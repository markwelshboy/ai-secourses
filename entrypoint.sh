#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Minimal fallbacks (overridden by /workspace/pod-runtime/helpers.sh if present)
# -----------------------------------------------------------------------------

print_info() { printf "[entrypoint.sh] INFO: %s\n" "$*"; }
print_warn() { printf "[entrypoint.sh] WARN: %s\n" "$*"; }
print_err()  { printf "[entrypoint.sh] ERR : %s\n" "$*"; }

clone_or_update() {
  local url="$1" dir="$2" name
  name="$(basename "$dir")"
  if [ -d "${dir}/.git" ]; then
    log "Updating ${name} in ${dir}..."
    git -C "${dir}" pull --rebase --autostash || \
      log "Warning: git pull failed for ${name}; continuing with existing checkout."
  else
    log "Cloning ${name} from ${url} into ${dir}..."
    rm -rf "${dir}"
    git clone --depth 1 "${url}" "${dir}"
  fi
}

# ----- Health check -----
health() {
  local name="$1" port="$2" gvar="$3" out="$4" cache="$5"
  local t=0

  until curl -fsS "http://127.0.0.1:${port}" >/dev/null 2>&1; do
    sleep 2
    t=$((t + 2))
    if [ "${t}" -ge 60 ]; then
      echo "WARN: ${name} on ${port} not HTTP 200 after 60s. Check logs: ${COMFY_LOGS}/comfyui-${port}.log"
      exit 1
    fi
  done

  echo "🚀 ${name} is UP on :${port} (Runtime Options: ${SAGE_ATTENTION} CUDA_VISIBLE_DEVICES=${gvar})"
  echo "       Output: ${out}"
  echo "   Temp/Cache: ${cache}"
  echo "       Log(s): ${COMFY_LOGS}/comfyui-${port}.log"
  echo ""
}

# ----- Start one Comfy session in tmux -----
start_one() {
  local sess="$1" port="$2" gvar="$3" out="$4" cache="$5"

  mkdir -p "${out}" "${cache}"

  tmux new-session -d -s "${sess}" \
    "CUDA_VISIBLE_DEVICES=${gvar} PYTHONUNBUFFERED=1 \
     python \"${COMFY_HOME}/main.py\" --listen ${COMFY_LISTEN} --port ${port} \
       ${SAGE_ATTENTION} \
       --output-directory \"${out}\" --temp-directory \"${cache}\" \
       >> \"${COMFY_LOGS}/comfyui-${port}.log\" 2>&1" \
    || echo "WARN: tmux session ${sess} may already exist; skipping creation"

  # Run health in a subshell so its exit doesn't kill the main script; we just log.
  ( health "${sess}" "${port}" "${gvar}" "${out}" "${cache}" ) || true
}

# -----------------------------------------------------------------------------
# SwarmUI workspace links
# -----------------------------------------------------------------------------
ensure_swarmui_workspace_links() {
  : "${POD_RUNTIME_DIR:=/workspace/pod-runtime}"
  local src_dir="${POD_RUNTIME_DIR}/secourses/swarmui"
  local ws="/workspace"

  [[ -d "${src_dir}" ]] || return 0

  section "SwarmUI workspace link setup"

  if [[ -d "${src_dir}/utilities" ]]; then
    if [[ -e "${ws}/utilities" && ! -L "${ws}/utilities" ]]; then
      print_warn "${ws}/utilities exists and is not a symlink; leaving it alone."
    else
      ln -sfn "${src_dir}/utilities" "${ws}/utilities"
      print_info "Linked: ${ws}/utilities -> ${src_dir}/utilities"
    fi
  else
    print_warn "No utilities dir found at: ${src_dir}/utilities"
  fi

  if [[ -f "${src_dir}/Amazing_SwarmUI_Presets_v39.json" ]]; then
    local target="${ws}/Amazing_SwarmUI_Presets_v39.json"
    if [[ -e "${target}" && ! -L "${target}" ]]; then
      print_warn "${target} exists and is not a symlink; leaving it alone."
    else
      ln -sfn "${src_dir}/Amazing_SwarmUI_Presets_v39.json" "${target}"
      print_info "Linked: ${target} -> ${src_dir}/Amazing_SwarmUI_Presets_v39.json"
    fi
  else
    print_warn "No presets file found at: ${src_dir}/Amazing_SwarmUI_Presets_v39.json"
  fi
}

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
: "${COMFY_HOME:=/workspace/ComfyUI}"
: "${COMFY_LOGS:=/workspace/logs}"
: "${COMFY_DOWNLOADS:=/workspace/downloads}"

: "${COMFY_VENV:=/workspace/ComfyUI/venv}"
: "${COMFY_LISTEN:=0.0.0.0}"
: "${COMFY_PORT:=3000}"
: "${ENABLE_SAGE:=true}"
: "${RUNTIME_ENSURE_INSTALL:=false}"

: "${SWARMUI_ENABLE:=false}"
: "${SWARMUI_DOWNLOADER_ENABLE:=false}"
: "${SWARMUI_LAUNCHER:=${POD_RUNTIME_DIR}/secourses/swarmui/start_swarmui_tmux.sh}"
: "${SWARMUI_DOWNLOADER_LAUNCHER:=${POD_RUNTIME_DIR}/secourses/swarmui/start_downloader_tmux.sh}"

# -----------------------------------------------------------------------------
# pod-runtime locations
# -----------------------------------------------------------------------------
: "${POD_RUNTIME_REPO_URL:=https://github.com/markwelshboy/pod-runtime.git}"
: "${POD_RUNTIME_DIR:=/workspace/pod-runtime}"
: "${POD_RUNTIME_ENV:=${POD_RUNTIME_DIR}/.env}"
: "${POD_RUNTIME_HELPERS:=${POD_RUNTIME_DIR}/helpers.sh}"

# -----------------------------------------------------------------------------
# Workspace "drop zone"
# -----------------------------------------------------------------------------
mkdir -p /workspace
mkdir -p ${COMFY_LOGS} ${COMFY_DOWNLOADS}

# -----------------------------------------------------------------------------
# Pull POD Runtime Repo
# -----------------------------------------------------------------------------

clone_or_update "${POD_RUNTIME_REPO_URL}" "${POD_RUNTIME_DIR}"

if [[ ! -f "$POD_RUNTIME_ENV" ]]; then
  echo "[fatal] Environment file not found at: $POD_RUNTIME_ENV" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$POD_RUNTIME_ENV"

if [[ ! -f "$POD_RUNTIME_HELPERS" ]]; then
  echo "[fatal] helpers.sh not found at: $POD_RUNTIME_HELPERS" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$POD_RUNTIME_HELPERS"

#------------------------------------------------------------------------
section 0 "Prepare Session Logging"
#----------------------------------------------
# 0) Create startup log
#----------------------------------------------

STARTUP_LOG="/workspace/startup.log"

# Duplicate all further stdout/stderr to both Vast log and a file
exec > >(tee -a "$STARTUP_LOG") 2>&1

echo "[bootstrap] Logging to: ${STARTUP_LOG}"

# -----------------------------------------------------------------------------
# Startup
# -----------------------------------------------------------------------------
section 1 "Container startup"
#----------------------------------------------
print_info "Workspace dropzone  : /workspace (logs=${COMFY_LOGS}, downloads=${COMFY_DOWNLOADS})"
print_info "POD_RUNTIME_DIR     : ${POD_RUNTIME_DIR}"

# Ensure ComfyUI exists
if [[ ! -d "${COMFY_HOME}" ]]; then
  print_warn "ComfyUI not found at ${COMFY_HOME}."
  if [[ "${RUNTIME_ENSURE_INSTALL,,}" == "true" ]]; then
    /opt/install_secourses_comfyui.sh
  else
    print_err "Image was expected to be build-baked. Exiting."
    exit 1
  fi
fi

ensure_comfy_dirs

on_start_comfy_banner

#------------------------------------------------------------------------
section 2 "SSH"
#----------------------------------------------
# Configure SSH using SSH* environment 
#   variables
#----------------------------------------------

setup_ssh

#------------------------------------------------------------------------
section 3 "Setting up SwarmUI workspace links"
#----------------------------------------------

ensure_swarmui_workspace_links || true

#------------------------------------------------------------------------
section 4 "(Optional) Auto-launch SwarmUI tmux"
#----------------------------------------------

# Auto-launch SwarmUI tmux (optional)
if [[ "${SWARMUI_ENABLE,,}" == "true" ]]; then
  if [[ -x "${SWARMUI_LAUNCHER}" ]]; then
    "${SWARMUI_LAUNCHER}" || print_warn "SwarmUI launcher failed (non-fatal)."
  else
    print_warn "SWARMUI_ENABLE=true but launcher not found/executable: ${SWARMUI_LAUNCHER}"
  fi
else
  print_info "SWARMUI_ENABLE not set to true; skipping SwarmUI launch."
fi

#------------------------------------------------------------------------
section 5 "(Optional) Auto-launch Downloader tmux"
#----------------------------------------------

# Auto-launch downloader tmux (optional)
if [[ "${SWARMUI_DOWNLOADER_ENABLE,,}" == "true" ]]; then
  if [[ -x "${SWARMUI_DOWNLOADER_LAUNCHER}" ]]; then
    "${SWARMUI_DOWNLOADER_LAUNCHER}" || print_warn "Downloader launcher failed (non-fatal)."
  else
    print_warn "SWARMUI_DOWNLOADER_ENABLE=true but launcher not found/executable: ${SWARMUI_DOWNLOADER_LAUNCHER}"
  fi
else
  print_info "SWARMUI_DOWNLOADER_ENABLE not set to true; skipping SwarmUI downloader launch."
fi

#------------------------------------------------------------------------
section 6 "Run ComfyUI"
#----------------------------------------------

# shellcheck disable=SC1090
source "${COMFY_VENV}/bin/activate"

print_info "Launching ComfyUI (tmux - comfy-${COMFY_PORT})"

# ----- Optional SAGE attention flag -----
SAGE_ATTENTION=$({ [[ "${ENABLE_SAGE:-true}" == "true" ]] && printf '%s' --use-sage-attention; } || true)

cd "${COMFY_HOME}"

# ----- Primary / default session -----
mkdir -p "output" "cache"

start_one comfy-${COMFY_PORT} ${COMFY_PORT} 0 "output" "cache"

echo ""
echo "Bootstrap complete. Bootstrap log: ${STARTUP_LOG}"
echo "General ComfyUI logs: ${COMFY_LOGS}"
echo ""

echo "=== Bootstrap done: $(date) ==="

sleep infinity
#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Minimal fallbacks (overridden by /workspace/pod-runtime/helpers.sh if present)
# -----------------------------------------------------------------------------
section() {
  local msg="${1:-}"
  printf "\n================================================================================\n"
  printf "=== %s\n" "${msg}"
  printf "================================================================================\n"
}
print_info() { printf "INFO: %s\n" "$*"; }
print_warn() { printf "WARN: %s\n" "$*"; }
print_err()  { printf "ERR : %s\n" "$*"; }

# -----------------------------------------------------------------------------
# Workspace "drop zone"
# -----------------------------------------------------------------------------
mkdir -p /workspace
mkdir -p /workspace/logs /workspace/downloads

# -----------------------------------------------------------------------------
# pod-runtime locations (your layout)
# -----------------------------------------------------------------------------
: "${POD_RUNTIME_DIR:=/workspace/pod-runtime}"
: "${POD_RUNTIME_ENV:=${POD_RUNTIME_DIR}/.env}"
: "${POD_RUNTIME_HELPERS:=${POD_RUNTIME_DIR}/helpers.sh}"

# Optional legacy support
LEGACY_ENV="/workspace/.env"
LEGACY_HELPERS="/workspace/helpers.sh"

# Load env first, then helpers
if [[ -f "${POD_RUNTIME_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${POD_RUNTIME_ENV}" || true
elif [[ -f "${LEGACY_ENV}" ]]; then
  # shellcheck disable=SC1091
  source "${LEGACY_ENV}" || true
fi

if [[ -f "${POD_RUNTIME_HELPERS}" ]]; then
  # shellcheck disable=SC1090
  source "${POD_RUNTIME_HELPERS}" || true
elif [[ -f "${LEGACY_HELPERS}" ]]; then
  # shellcheck disable=SC1091
  source "${LEGACY_HELPERS}" || true
fi

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
# Startup
# -----------------------------------------------------------------------------
section "Container startup"
print_info "Workspace dropzone  : /workspace (logs=/workspace/logs, downloads=/workspace/downloads)"
print_info "POD_RUNTIME_DIR     : ${POD_RUNTIME_DIR}"

ensure_swarmui_workspace_links || true

# Ensure ComfyUI exists
if [[ ! -d "${COMFY_HOME}" ]]; then
  print_warn "ComfyUI not found at ${COMFY_HOME}."
  if [[ "${RUNTIME_ENSURE_INSTALL,,}" == "true" ]]; then
    section "Runtime ensure install"
    /opt/install_secourses_comfyui.sh
  else
    print_err "Image was expected to be build-baked. Exiting."
    exit 1
  fi
fi

# Auto-launch SwarmUI tmux (optional)
if [[ "${SWARMUI_ENABLE,,}" == "true" ]]; then
  if [[ -x "${SWARMUI_LAUNCHER}" ]]; then
    section "Auto-launch SwarmUI"
    "${SWARMUI_LAUNCHER}" || print_warn "SwarmUI launcher failed (non-fatal)."
  else
    print_warn "SWARMUI_ENABLE=true but launcher not found/executable: ${SWARMUI_LAUNCHER}"
  fi
fi

# Auto-launch downloader tmux (optional)
if [[ "${SWARMUI_DOWNLOADER_ENABLE,,}" == "true" ]]; then
  if [[ -x "${SWARMUI_DOWNLOADER_LAUNCHER}" ]]; then
    section "Auto-launch SwarmUI Downloader"
    "${SWARMUI_DOWNLOADER_LAUNCHER}" || print_warn "Downloader launcher failed (non-fatal)."
  else
    print_warn "SWARMUI_DOWNLOADER_ENABLE=true but launcher not found/executable: ${SWARMUI_DOWNLOADER_LAUNCHER}"
  fi
fi

# Launch ComfyUI in foreground (container stays alive)
# shellcheck disable=SC1090
source "${COMFY_VENV}/bin/activate"

sage_flag=""
case "${ENABLE_SAGE,,}" in
  1|true|yes|y|on) sage_flag="--use-sage-attention" ;;
esac

section "Launching ComfyUI (foreground)"
print_info "Listen : ${COMFY_LISTEN}"
print_info "Port   : ${COMFY_PORT}"
print_info "Sage   : ${ENABLE_SAGE}"

cd "${COMFY_HOME}"
exec python main.py --listen "${COMFY_LISTEN}" --port "${COMFY_PORT}" ${sage_flag}

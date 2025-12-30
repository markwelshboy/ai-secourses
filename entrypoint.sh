#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Minimal entrypoint:
# - ensures /workspace exists
# - clones/updates pod-runtime
# - execs role launcher (comfy|musubi), or auto-detects
# -----------------------------------------------------------------------------

: "${WORKSPACE:=/workspace}"

: "${POD_RUNTIME_REPO_URL:=https://github.com/markwelshboy/pod-runtime.git}"
: "${POD_RUNTIME_DIR:=${WORKSPACE}/pod-runtime}"
: "${POD_RUNTIME_ENV:=${POD_RUNTIME_DIR}/.env}"

: "${AI_SECOURSES_ROLE:=auto}"   # comfy | musubi | auto

mkdir -p "${WORKSPACE}"

print() { printf "[entrypoint] %s\n" "$*"; }
warn()  { printf "[entrypoint] WARN: %s\n" "$*" >&2; }
err()   { printf "[entrypoint] ERR : %s\n" "$*" >&2; }

clone_or_update() {
  local url="$1" dir="$2"
  if [[ -d "${dir}/.git" ]]; then
    print "Updating $(basename "$dir") in ${dir}..."
    git -C "${dir}" pull --rebase --autostash || warn "git pull failed; continuing with existing checkout"
  else
    print "Cloning $(basename "$dir") from ${url} into ${dir}..."
    rm -rf "${dir}"
    git clone --depth 1 "${url}" "${dir}"
  fi
}

# Must have git
command -v git >/dev/null 2>&1 || { err "git not found in image"; exit 1; }

clone_or_update "${POD_RUNTIME_REPO_URL}" "${POD_RUNTIME_DIR}"

if [[ ! -f "${POD_RUNTIME_ENV}" ]]; then
  err "Missing ${POD_RUNTIME_ENV}"
  err "pod-runtime cloned to ${POD_RUNTIME_DIR} but .env is absent."
  exit 1
fi

# shellcheck source=/dev/null
source "${POD_RUNTIME_ENV}"

# Provide simple auto-detect if role=auto.
# (We do not source big helpers here; that's the role script’s job.)
detect_role() {
  local comfy_home="${COMFY_HOME:-/workspace/ComfyUI}"
  local comfy_venv="${COMFY_VENV:-/workspace/ComfyUI/venv}"
  local musubi_dir="${MUSUBI_TRAINER_DIR:-/workspace/SECourses_Musubi_Trainer}"
  local musubi_venv="${MUSUBI_VENV:-${musubi_dir}/venv}"

  if [[ -f "${comfy_home}/main.py" && -x "${comfy_venv}/bin/python" ]]; then
    echo "comfy"; return 0
  fi
  if [[ -f "${musubi_dir}/gui.py" && -x "${musubi_venv}/bin/python" ]]; then
    echo "musubi"; return 0
  fi
  echo "unknown"; return 0
}

role="${AI_SECOURSES_ROLE,,}"
if [[ "${role}" == "auto" ]]; then
  role="$(detect_role)"
fi

case "${role}" in
  comfy)
    exec "${POD_RUNTIME_DIR}/secourses/start.comfy.sh"
    ;;
  musubi)
    exec "${POD_RUNTIME_DIR}/secourses/start.musubi.sh"
    ;;
  *)
    err "Could not determine AI_SECOURSES_ROLE (got: ${AI_SECOURSES_ROLE}) and auto-detect failed."
    err "Inventory:"
    ls -la /workspace || true
    err "Hint: set AI_SECOURSES_ROLE=comfy or AI_SECOURSES_ROLE=musubi"
    exit 1
    ;;
esac

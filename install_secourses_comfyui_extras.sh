#!/usr/bin/env bash
set -euo pipefail

print_info() { printf "[comfyui-extras] INFO: %s\n" "$*"; }
print_warn() { printf "[comfyui-extras] WARN: %s\n" "$*"; }
print_err()  { printf "[comfyui-extras] ERR : %s\n" "$*"; }

: "${COMFY_VENV:=/workspace/ComfyUI/venv}"
: "${SHARED_REQ:=/opt/requirements.shared.txt}"

COMFY_PY="${COMFY_VENV}/bin/python"
COMFY_UV="${COMFY_VENV}/bin/uv"

[[ -x "${COMFY_PY}" ]] || { print_err "Missing venv python: ${COMFY_PY}"; exit 1; }
[[ -x "${COMFY_UV}" ]] || {
  print_warn "uv missing in venv; installing it into venv..."
  "${COMFY_PY}" -m pip install -U uv
}
[[ -x "${COMFY_UV}" ]] || { print_err "uv still missing in venv at: ${COMFY_UV}"; exit 1; }

if [[ ! -f "${SHARED_REQ}" ]]; then
  print_warn "Shared requirements not found at ${SHARED_REQ}; nothing to do."
  exit 0
fi

# uv config (cache mounted by Dockerfile)
: "${UV_CACHE_DIR:=/root/.cache/uv}"
export UV_CACHE_DIR
mkdir -p "${UV_CACHE_DIR}"
export UV_SKIP_WHEEL_FILENAME_CHECK="${UV_SKIP_WHEEL_FILENAME_CHECK:-1}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

# Make venv detectable for uv 0.9.x
export VIRTUAL_ENV="${COMFY_VENV}"
export PATH="${COMFY_VENV}/bin:${PATH}"

print_info "Installing shared requirements into Comfy venv: ${SHARED_REQ}"
"${COMFY_UV}" pip install -r "${SHARED_REQ}"

print_info "ComfyUI EXTRAS install complete."

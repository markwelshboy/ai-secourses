#!/usr/bin/env bash
set -euo pipefail

print_info() { printf "[swarmui-install] INFO: %s\n" "$*"; }
print_warn() { printf "[swarmui-install] WARN: %s\n" "$*"; }
print_err()  { printf "[swarmui-install] ERR : %s\n" "$*"; }

# -----------------------------------------------------------------------------
# Defaults / toggles
# -----------------------------------------------------------------------------
: "${WORKSPACE:=/workspace}"
: "${SWARMUI_HOME:=/workspace/SwarmUI}"

# Repo lock (normally passed via build args)
: "${SWARMUI_REPO:=https://github.com/mcmonkeyprojects/SwarmUI}"
: "${SWARMUI_REF:=master}"

# Optional DLNodes dependency used by SwarmUI backend
: "${INSTALL_SWARM_DLNODES:=true}"
: "${DLNODE_CONTROLNET_AUX_REPO:=https://github.com/Fannovel16/comfyui_controlnet_aux}"
: "${DLNODE_CONTROLNET_AUX_REF:=main}"

# Cloudflared
: "${INSTALL_CLOUDFLARED:=true}"
: "${CLOUDFLARED_PATH:=/usr/local/bin/cloudflared}"

# Dotnet install location (avoid ~/.dotnet bloat)
: "${DOTNET_INSTALL_DIR:=/opt/dotnet}"
: "${DOTNET_CHANNEL:=8.0}"

# Cleanup knobs
: "${STRIP_GIT:=true}"
: "${CLEAN_BUILD_TRASH:=true}"

bool() { case "${1,,}" in 1|true|yes|y|on) return 0 ;; *) return 1 ;; esac; }

git_clone_at_ref() {
  local repo="$1" ref="$2" dest="$3"
  if [[ ! -d "${dest}/.git" ]]; then
    git clone --depth 1 "${repo}" "${dest}"
  fi
  (
    cd "${dest}"
    git fetch --depth 1 origin "${ref}" >/dev/null 2>&1 || true
    git checkout -f "${ref}" >/dev/null 2>&1 || git checkout -f "origin/${ref}" >/dev/null 2>&1 || true
    git reset --hard >/dev/null 2>&1 || true
    git clean -fd >/dev/null 2>&1 || true
  )
}

trace_sizes() {
  print_info "SIZE TRACE (best-effort): /tmp /workspace /opt/dotnet"
  du -sh /tmp "${WORKSPACE}" "${DOTNET_INSTALL_DIR}" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------
print_info "Installing SwarmUI into ${SWARMUI_HOME}"
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

git_clone_at_ref "${SWARMUI_REPO}" "${SWARMUI_REF}" "${SWARMUI_HOME}"

# Install dotnet 8 (runtime + sdk) into /opt/dotnet
print_info "Installing dotnet ${DOTNET_CHANNEL} into ${DOTNET_INSTALL_DIR}"
mkdir -p "${DOTNET_INSTALL_DIR}"
export DOTNET_INSTALL_DIR
export DOTNET_ROOT="${DOTNET_INSTALL_DIR}"
export PATH="${DOTNET_INSTALL_DIR}:${DOTNET_INSTALL_DIR}/tools:${PATH}"

DOTNET_SCRIPT="${SWARMUI_HOME}/launchtools/dotnet-install.sh"
mkdir -p "${SWARMUI_HOME}/launchtools"
curl -fsSL "https://dot.net/v1/dotnet-install.sh" -o "${DOTNET_SCRIPT}"
chmod +x "${DOTNET_SCRIPT}"

# aspnetcore runtime + SDK (matches instructions)
"${DOTNET_SCRIPT}" --channel "${DOTNET_CHANNEL}" --runtime aspnetcore --install-dir "${DOTNET_INSTALL_DIR}"
"${DOTNET_SCRIPT}" --channel "${DOTNET_CHANNEL}" --install-dir "${DOTNET_INSTALL_DIR}"

dotnet --info >/dev/null 2>&1 || { print_err "dotnet install appears to have failed"; exit 1; }

# cloudflared (optional). Many bases already include it; we ensure presence.
if bool "${INSTALL_CLOUDFLARED}"; then
  if [[ -x "${CLOUDFLARED_PATH}" ]]; then
    print_info "cloudflared already present at ${CLOUDFLARED_PATH}"
  else
    print_info "Installing cloudflared to ${CLOUDFLARED_PATH}"
    # Official cloudflared Linux amd64 binary
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o "${CLOUDFLARED_PATH}"
    chmod +x "${CLOUDFLARED_PATH}"
  fi
fi

# DLNodes (optional): comfyui_controlnet_aux into SwarmUI backend DLNodes path
if bool "${INSTALL_SWARM_DLNODES}"; then
  DLN_BASE="${SWARMUI_HOME}/src/BuiltinExtensions/ComfyUIBackend/DLNodes"
  mkdir -p "${DLN_BASE}"
  print_info "Installing DLNode comfyui_controlnet_aux into ${DLN_BASE}"
  git_clone_at_ref "${DLNODE_CONTROLNET_AUX_REPO}" "${DLNODE_CONTROLNET_AUX_REF}" "${DLN_BASE}/comfyui_controlnet_aux"
fi

print_info "After installs (before cleanup):"
trace_sizes

print_info "Reducing image size..."
if bool "${CLEAN_BUILD_TRASH}"; then
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
fi

if bool "${STRIP_GIT}"; then
  find "${WORKSPACE}" -type d -name ".git" -prune -exec rm -rf {} + 2>/dev/null || true
fi

print_info "After cleanup:"
trace_sizes

print_info "SwarmUI install complete."

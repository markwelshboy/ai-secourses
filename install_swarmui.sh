#!/usr/bin/env bash
set -euo pipefail

# Layout / toggles
: "${WORKSPACE_HOME:=/workspace}"
: "${SWARMUI_HOME:=/workspace/SwarmUI}"

# Cleanup knobs (keep defaults ON for smaller images)
: "${STRIP_GIT:=true}"
: "${CLEAN_PIP_CACHE:=true}"
: "${CLEAN_BUILD_TRASH:=true}"

print_info() { printf "[musubi-install] INFO: %s\n" "$*"; }
print_warn() { printf "[musubi-install] WARN: %s\n" "$*"; }
print_err()  { printf "[musubi-install] ERR : %s\n" "$*"; }

uv_install() {
  # uv_install <args...>
  if "${MUSUBI_UV}" pip --python "${MUSUBI_PY}" install "$@"; then
    return 0
  fi
  print_warn "uv install failed; falling back to pip: $*"
  "${MUSUBI_PY}" -m pip install "$@"
}

bool() { case "${1,,}" in 1|true|yes|y|on) return 0 ;; *) return 1 ;; esac; }

section() {
  printf "\n================================================================================\n"
  printf "=== %s\n" "${1:-}"
  printf "================================================================================\n"
}

mkdir -p ${WORKSPACE_HOME}
cd ${WORKSPACE_HOME}

# ---- ffmpeg / ffprobe ----
# (exact file from instructions; safe if missing)
rm -f ffmpeg-N-118385-g0225fe857d-linux64-gpl.tar.xz || true
wget -q https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2025-01-31-12-58/ffmpeg-N-118385-g0225fe857d-linux64-gpl.tar.xz
tar xvf ffmpeg-N-118385-g0225fe857d-linux64-gpl.tar.xz --no-same-owner
mv ffmpeg-N-118385-g0225fe857d-linux64-gpl/bin/ffmpeg /usr/local/bin/
mv ffmpeg-N-118385-g0225fe857d-linux64-gpl/bin/ffprobe /usr/local/bin/
chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe
rm -rf ffmpeg-N-118385-g0225fe857d-linux64-gpl* || true

# ---- cloudflared ----
rm -f cloudflared-linux-amd64.deb || true
wget -q https://github.com/cloudflare/cloudflared/releases/download/2025.7.0/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb
rm -f cloudflared-linux-amd64.deb

# ---- SwarmUI core ----
rm -rf "${SWARMUI_HOME}" || true
git clone --depth 1 https://github.com/mcmonkeyprojects/SwarmUI "${SWARMUI_HOME}"

# ---- DLNodes (inside SwarmUI) ----
git clone --depth 1 https://github.com/Fannovel16/ComfyUI-Frame-Interpolation \
  "${SWARMUI_HOME}/src/BuiltinExtensions/ComfyUIBackend/DLNodes/ComfyUI-Frame-Interpolation"

git clone --depth 1 https://github.com/welltop-cn/ComfyUI-TeaCache \
  "${SWARMUI_HOME}/src/BuiltinExtensions/ComfyUIBackend/DLNodes/ComfyUI-TeaCache"

git clone --depth 1 https://github.com/Fannovel16/comfyui_controlnet_aux \
  "${SWARMUI_HOME}/src/BuiltinExtensions/ComfyUIBackend/DLNodes/comfyui_controlnet_aux"

# ---- dotnet 8 ----
cd "${SWARMUI_HOME}/launchtools"
wget -q https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh --channel 8.0 --runtime aspnetcore
./dotnet-install.sh --channel 8.0

print_info "[size] /workspace:"; du -sh /workspace/* 2>/dev/null || true
print_info "[size] /tmp:"; du -sh /tmp 2>/dev/null || true
print_info "[size] /root caches:"; du -sh /root/.cache 2>/dev/null || true
print_info "[size] /root/.nuget:"; du -sh /root/.nuget 2>/dev/null || true
print_info "[size] /usr/share/dotnet:"; du -sh /usr/share/dotnet 2>/dev/null || true

# -----------------------------------------------------------------------------
# Cleanup to reduce layer size (must happen in this same RUN layer)
# -----------------------------------------------------------------------------
print_info "Reducing image size..."

if bool "${CLEAN_PIP_CACHE}"; then
  rm -rf /root/.cache/pip /root/.cache/uv || true
  rm -rf /tmp/uv-cache /tmp/pip-cache || true
fi

if bool "${CLEAN_BUILD_TRASH}"; then
  find /workspace -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf /tmp/* /var/tmp/* || true
fi

if bool "${STRIP_GIT}"; then
  find /workspace -type d -name ".git" -prune -exec rm -rf {} + 2>/dev/null || true
fi

print_info "SwarmUI install complete"

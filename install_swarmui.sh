#!/usr/bin/env bash
set -euo pipefail

# Layout / toggles
: "${WORKSPACE_HOME:=/workspace}"
: "${SWARMUI_HOME:=/workspace/SwarmUI}"

section() {
  printf "\n================================================================================\n"
  printf "=== %s\n" "${1:-}"
  printf "================================================================================\n"
}

section "Installing SwarmUI (SECourses)"

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

section "SwarmUI install complete"

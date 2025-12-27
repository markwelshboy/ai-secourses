# syntax=docker/dockerfile:1.6
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

# ----------------------------
# Build-time version locks (these SHOULD affect caching)
# ----------------------------

# Core repos/refs
ARG COMFY_REPO="https://github.com/comfyanonymous/ComfyUI"
ARG COMFY_REF="master"

ARG NODE_MANAGER_REPO="https://github.com/ltdrdata/ComfyUI-Manager"
ARG NODE_MANAGER_REF="main"

ARG NODE_GGUF_REPO="https://github.com/city96/ComfyUI-GGUF"
ARG NODE_GGUF_REF="main"

ARG NODE_RES4LYF_REPO="https://github.com/ClownsharkBatwing/RES4LYF"
ARG NODE_RES4LYF_REF="main"

ARG NODE_IPADAPTER_REPO="https://github.com/cubiq/ComfyUI_IPAdapter_plus"
ARG NODE_IPADAPTER_REF="main"

ARG NODE_REACTOR_REPO="https://github.com/Gourieff/ComfyUI-ReActor"
ARG NODE_REACTOR_REF="main"

ARG NODE_IMPACT_REPO="https://github.com/ltdrdata/ComfyUI-Impact-Pack"
ARG NODE_IMPACT_REF="main"

# Torch install lock (mirrors script behavior, but configurable)
ARG TORCH_VERSION="2.8.0"
ARG TORCH_INDEX_URL="https://download.pytorch.org/whl/cu129"

# Wheel overrides (lock these URLs)
ARG WHEEL_FLASH_ATTN_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp310-cp310-linux_x86_64.whl"
ARG WHEEL_XFORMERS_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-linux_x86_64.whl"
ARG WHEEL_SAGEATTN_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0.post4-cp39-abi3-linux_x86_64.whl"
ARG WHEEL_INSIGHTFACE_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp310-cp310-linux_x86_64.whl"

# ----------------------------
# Runtime env toggles (Vast.ai)
# ----------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/workspace \
    UV_SKIP_WHEEL_FILENAME_CHECK=1 \
    UV_LINK_MODE=copy \
    # reduce build-time cache explosion
    UV_CACHE_DIR=/tmp/uv-cache \
    PIP_CACHE_DIR=/tmp/pip-cache \
    PIP_NO_CACHE_DIR=1 \
    COMFY_HOME=/workspace/ComfyUI \
    COMFY_VENV=/workspace/ComfyUI/venv \
    COMFY_LISTEN=0.0.0.0 \
    COMFY_PORT=3000 \
    INSTALL_IPADAPTER=false \
    INSTALL_REACTOR=false \
    INSTALL_IMPACT=false \
    RUNTIME_ENSURE_INSTALL=false \
    ENABLE_SAGE=true \
    # SwarmUI runtime toggles (used by entrypoint.sh)
    SWARMUI_ENABLE=true \
    SWARMUI_DOWNLOADER_ENABLE=true \
    SWARMUI_PORT=7861

# ---- OS deps (minimal; base already has most) ----
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl wget \
      git git-lfs \
      tmux jq unzip gawk coreutils \
      net-tools rsync ncurses-base bash-completion less nano \
      ninja-build aria2 vim \
      psmisc \
      python3.10-venv python3.10-dev \
      build-essential pkg-config \
      libgl1 libglib2.0-0 \
      gcc g++ cmake \
      openssh-server && \
    mkdir -p /run/sshd && \
    git lfs install --system && \
    ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure uv is present
RUN python -m pip install -U pip wheel setuptools uv

# Volume-style workspace layout (even without an actual mount)
RUN mkdir -p /workspace

# Shared requirements
COPY requirements.txt /opt/requirements.shared.txt
COPY requirements_trainer.txt /opt/requirements.musubi_trainer.txt

# Scripts
COPY install_secourses_comfyui.sh /opt/install_secourses_comfyui.sh
COPY install_swarmui.sh           /opt/install_swarmui.sh
COPY install_musubi_trainer.sh    /opt/install_musubi_trainer.sh

RUN chmod +x /opt/install_secourses_comfyui.sh /opt/install_swarmui.sh /opt/install_musubi_trainer.sh

# ----------------------------
# Build-time install: ComfyUI
# ----------------------------
RUN \
  COMFY_REPO="${COMFY_REPO}" COMFY_REF="${COMFY_REF}" \
  NODE_MANAGER_REPO="${NODE_MANAGER_REPO}" NODE_MANAGER_REF="${NODE_MANAGER_REF}" \
  NODE_GGUF_REPO="${NODE_GGUF_REPO}" NODE_GGUF_REF="${NODE_GGUF_REF}" \
  NODE_RES4LYF_REPO="${NODE_RES4LYF_REPO}" NODE_RES4LYF_REF="${NODE_RES4LYF_REF}" \
  NODE_IPADAPTER_REPO="${NODE_IPADAPTER_REPO}" NODE_IPADAPTER_REF="${NODE_IPADAPTER_REF}" \
  NODE_REACTOR_REPO="${NODE_REACTOR_REPO}" NODE_REACTOR_REF="${NODE_REACTOR_REF}" \
  NODE_IMPACT_REPO="${NODE_IMPACT_REPO}" NODE_IMPACT_REF="${NODE_IMPACT_REF}" \
  TORCH_VERSION="${TORCH_VERSION}" TORCH_INDEX_URL="${TORCH_INDEX_URL}" \
  WHEEL_FLASH_ATTN_URL="${WHEEL_FLASH_ATTN_URL}" \
  WHEEL_XFORMERS_URL="${WHEEL_XFORMERS_URL}" \
  WHEEL_SAGEATTN_URL="${WHEEL_SAGEATTN_URL}" \
  WHEEL_INSIGHTFACE_URL="${WHEEL_INSIGHTFACE_URL}" \
  /opt/install_secourses_comfyui.sh

# ----------------------------
# Build-time install: SwarmUI
# ----------------------------
RUN /opt/install_swarmui.sh

# ----------------------------
# Build-time install: Musubi Trainer
# ----------------------------
RUN /opt/install_musubi_trainer.sh

# Runtime scripts
COPY entrypoint.sh  /opt/entrypoint.sh
COPY healthcheck.sh /opt/healthcheck.sh
RUN chmod +x /opt/entrypoint.sh /opt/healthcheck.sh

WORKDIR /workspace/ComfyUI

# Healthcheck: checks ComfyUI, and optionally SwarmUI/downloader based on env toggles
HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD /opt/healthcheck.sh || exit 1

# Expose for documentation (Vast uses its own port mapping)
EXPOSE 3000 7861

# ----------------------------
# Image metadata (declare LAST so changing these args doesn't bust build cache)
# ----------------------------
ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"
ARG IMAGE_VERSION="0.1.0"

LABEL org.opencontainers.image.title="SECourses (build-baked /workspace layout)" \
      org.opencontainers.image.description="ComfyUI + SwarmUI + Musubi Trainer image based on SECourses RunPod instructions; all components installed at build time into /workspace; Vast-friendly env toggles." \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="SECourses Patreon and GitHub Repository"

ENTRYPOINT ["/opt/entrypoint.sh"]

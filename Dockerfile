# syntax=docker/dockerfile:1.6

# =============================================================================
# BASE (shared): OS deps + uv + /workspace layout + shared requirement files
# =============================================================================
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04 AS base

# ----------------------------
# Runtime env defaults (safe)
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
    ENABLE_SAGE=false \
    SWARMUI_ENABLE=false \
    SWARMUI_DOWNLOADER_ENABLE=false \
    SWARMUI_PORT=7861

# ---- OS deps ----
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

# Ensure uv is present (system-level; installers can still choose venv-local uv)
RUN python -m pip install -U pip wheel setuptools uv

# Volume-style workspace layout (even without an actual mount)
RUN mkdir -p /workspace

# =============================================================================
# COMFY target: ComfyUI + SwarmUI (+ runtime scripts)
# =============================================================================
FROM base AS comfy

# ----------------------------
# Build-time version locks (affect comfy caching)
# ----------------------------
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

ARG TORCH_VERSION="2.8.0"
ARG TORCH_INDEX_URL="https://download.pytorch.org/whl/cu129"

ARG WHEEL_FLASH_ATTN_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/flash_attn-2.8.2-cp310-cp310-linux_x86_64.whl"
ARG WHEEL_XFORMERS_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/xformers-0.0.33+c159edc0.d20250906-cp39-abi3-linux_x86_64.whl"
ARG WHEEL_SAGEATTN_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/sageattention-2.2.0.post4-cp39-abi3-linux_x86_64.whl"
ARG WHEEL_INSIGHTFACE_URL="https://huggingface.co/MonsterMMORPG/Wan_GGUF/resolve/main/insightface-0.7.3-cp310-cp310-linux_x86_64.whl"

# Shared requirement files
COPY requirements.txt         /opt/requirements.shared.txt

# Installer scripts only needed for comfy image
COPY install_secourses_comfyui.sh /opt/install_secourses_comfyui.sh
COPY install_swarmui.sh           /opt/install_swarmui.sh
RUN chmod +x /opt/install_secourses_comfyui.sh /opt/install_swarmui.sh

# Build-time install: ComfyUI
RUN --mount=type=cache,target=/root/.cache/uv \
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

# Build-time install: SwarmUI
RUN --mount=type=cache,target=/root/.cache/uv \
    /opt/install_swarmui.sh

# Runtime scripts for comfy image
COPY entrypoint.sh  /opt/entrypoint.sh
COPY healthcheck.sh /opt/healthcheck.sh
RUN chmod +x /opt/entrypoint.sh /opt/healthcheck.sh

WORKDIR /workspace/ComfyUI

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD /opt/healthcheck.sh || exit 1

EXPOSE 3000 7861 7862

# ---- Image metadata LAST (won't bust heavy caches) ----
ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"
ARG IMAGE_VERSION="0.1.0"

LABEL org.opencontainers.image.title="SECourses Comfy+Swarm (build-baked /workspace)" \
      org.opencontainers.image.description="ComfyUI + SwarmUI; all installed at build time into /workspace." \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

ENTRYPOINT ["/opt/entrypoint.sh"]


# =============================================================================
# MUSUBI target: Musubi Trainer/Tuner only (+ its own runtime scripts if desired)
# =============================================================================
FROM base AS musubi

# Requirement files
COPY requirements_trainer.txt /opt/requirements.musubi_trainer.txt

# Musubi installer only needed for musubi image
COPY install_musubi_trainer.sh /opt/install_musubi_trainer.sh
RUN chmod +x /opt/install_musubi_trainer.sh

RUN --mount=type=cache,target=/root/.cache/uv \
    /opt/install_musubi_trainer.sh

# Optional: you can reuse the same entrypoint/healthcheck, or have musubi-specific ones
COPY entrypoint.sh  /opt/entrypoint.sh
COPY healthcheck.sh /opt/healthcheck.sh
RUN chmod +x /opt/entrypoint.sh /opt/healthcheck.sh

WORKDIR /workspace

HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD /opt/healthcheck.sh || exit 1

EXPOSE 7863 7864

# ---- Image metadata LAST (won't bust heavy caches) ----
ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"
ARG IMAGE_VERSION="0.1.0"

LABEL org.opencontainers.image.title="SECourses Musubi (build-baked /workspace)" \
      org.opencontainers.image.description="Musubi Trainer/Tuner; installed at build time into /workspace." \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

ENTRYPOINT ["/opt/entrypoint.sh"]

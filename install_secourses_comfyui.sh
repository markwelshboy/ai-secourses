#!/usr/bin/env bash
set -euo pipefail

print_info() { printf "[comfyui-install] INFO: %s\n" "$*"; }
print_warn() { printf "[comfyui-install] WARN: %s\n" "$*"; }
print_err()  { printf "[comfyui-install] ERR : %s\n" "$*"; }

# -----------------------------------------------------------------------------
# Defaults / toggles
# -----------------------------------------------------------------------------
: "${WORKSPACE:=/workspace}"
: "${HF_HOME:=/workspace}"
: "${COMFY_HOME:=/workspace/ComfyUI}"
: "${COMFY_VENV:=/workspace/ComfyUI/venv}"

: "${INSTALL_IPADAPTER:=false}"
: "${INSTALL_REACTOR:=false}"
: "${INSTALL_IMPACT:=false}"
: "${INSTALL_SWARM_EXTRANODES:=true}"

# Cleanup knobs (keep defaults ON for smaller images)
: "${STRIP_GIT:=true}"
: "${CLEAN_PIP_CACHE:=true}"
: "${CLEAN_BUILD_TRASH:=true}"

# Shared reqs file baked into image
: "${SHARED_REQ:=/opt/requirements.shared.txt}"

# -----------------------------------------------------------------------------
# Repos / locks (normally injected via Docker build args)
# -----------------------------------------------------------------------------
: "${COMFY_REPO:=https://github.com/comfyanonymous/ComfyUI}"
: "${COMFY_REF:=master}"

: "${NODE_MANAGER_REPO:=https://github.com/ltdrdata/ComfyUI-Manager}"
: "${NODE_MANAGER_REF:=main}"

: "${NODE_GGUF_REPO:=https://github.com/city96/ComfyUI-GGUF}"
: "${NODE_GGUF_REF:=main}"

: "${NODE_RES4LYF_REPO:=https://github.com/ClownsharkBatwing/RES4LYF}"
: "${NODE_RES4LYF_REF:=main}"

: "${NODE_IPADAPTER_REPO:=https://github.com/cubiq/ComfyUI_IPAdapter_plus}"
: "${NODE_IPADAPTER_REF:=main}"

: "${NODE_REACTOR_REPO:=https://github.com/Gourieff/ComfyUI-ReActor}"
: "${NODE_REACTOR_REF:=main}"

: "${NODE_IMPACT_REPO:=https://github.com/ltdrdata/ComfyUI-Impact-Pack}"
: "${NODE_IMPACT_REF:=main}"

: "${TORCH_VERSION:=2.8.0}"
: "${TORCH_INDEX_URL:=https://download.pytorch.org/whl/cu129}"

: "${WHEEL_FLASH_ATTN_URL:?missing WHEEL_FLASH_ATTN_URL}"
: "${WHEEL_XFORMERS_URL:?missing WHEEL_XFORMERS_URL}"
: "${WHEEL_SAGEATTN_URL:?missing WHEEL_SAGEATTN_URL}"
: "${WHEEL_INSIGHTFACE_URL:?missing WHEEL_INSIGHTFACE_URL}"

# SwarmUI repo lock (for ExtraNodes sparse checkout)
: "${SWARMUI_REPO:=https://github.com/mcmonkeyprojects/SwarmUI}"
: "${SWARMUI_REF:=master}"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
bool() { case "${1,,}" in 1|true|yes|y|on) return 0 ;; *) return 1 ;; esac; }

guard_venv_python() {
  local py="$1" expected_prefix="$2"
  if [[ ! -x "$py" ]]; then
    print_err "Python not executable: $py"
    exit 1
  fi
  local exe
  exe="$("$py" - <<'PY'
import sys
print(sys.executable)
PY
)"
  print_info "Using python: ${exe}"
  if [[ "$exe" != "${expected_prefix}/bin/python"* ]]; then
    print_err "Guardrail tripped: python is not from expected venv (${expected_prefix}). Got: ${exe}"
    exit 1
  fi
}

trace_sizes() {
  print_info "SIZE TRACE (best-effort): /tmp /root/.cache /workspace /usr/local dist-packages"
  du -sh /tmp /root/.cache "${WORKSPACE}" /usr/local/lib/python3.10/dist-packages 2>/dev/null || true
  du -sh "${COMFY_VENV}" 2>/dev/null || true
}

git_clone_at_ref() {
  # git_clone_at_ref <repo> <ref> <dest>
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

big_warn() {
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!! WARNING: $*"
  echo "!!! Build will CONTINUE, but functionality may be missing."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
}

# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------
print_info "Installing ComfyUI into /workspace (baked into image)."
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

# --- Clone ComfyUI ---
git_clone_at_ref "${COMFY_REPO}" "${COMFY_REF}" "${COMFY_HOME}"

# --- Create venv (idempotent) ---
mkdir -p "${COMFY_VENV}"
python -m venv "${COMFY_VENV}"

COMFY_PY="${COMFY_VENV}/bin/python"
COMFY_PIP="${COMFY_VENV}/bin/pip"

# Guardrail: ensure python is venv python
guard_venv_python "${COMFY_PY}" "${COMFY_VENV}"

# --- Install pip tooling + uv (into venv) ---
print_info "Bootstrapping pip/uv inside Comfy venv..."
"${COMFY_PY}" -m pip install -U pip wheel setuptools
"${COMFY_PY}" -m pip install -U uv

COMFY_UV="${COMFY_VENV}/bin/uv"
if [[ ! -x "${COMFY_UV}" ]]; then
  print_err "uv not found in venv at: ${COMFY_UV}"
  exit 1
fi

# Constrain uv cache (so it doesn't explode in layer)
: "${UV_CACHE_DIR:=/tmp/uv-cache}"
export UV_CACHE_DIR
mkdir -p "${UV_CACHE_DIR}"

export UV_SKIP_WHEEL_FILENAME_CHECK="${UV_SKIP_WHEEL_FILENAME_CHECK:-1}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

# --- Torch (locked) ---
print_info "Installing torch==${TORCH_VERSION} from ${TORCH_INDEX_URL} into Comfy venv..."
"${COMFY_UV}" pip install "torch==${TORCH_VERSION}" torchvision torchaudio --index-url "${TORCH_INDEX_URL}"

# --- Custom nodes ---
cd "${COMFY_HOME}/custom_nodes"
git_clone_at_ref "${NODE_MANAGER_REPO}" "${NODE_MANAGER_REF}" "ComfyUI-Manager"
git_clone_at_ref "${NODE_GGUF_REPO}"    "${NODE_GGUF_REF}"    "ComfyUI-GGUF"
git_clone_at_ref "${NODE_RES4LYF_REPO}" "${NODE_RES4LYF_REF}" "RES4LYF"

if bool "${INSTALL_IPADAPTER}"; then
  git_clone_at_ref "${NODE_IPADAPTER_REPO}" "${NODE_IPADAPTER_REF}" "ComfyUI_IPAdapter_plus"
fi
if bool "${INSTALL_REACTOR}"; then
  git_clone_at_ref "${NODE_REACTOR_REPO}" "${NODE_REACTOR_REF}" "ComfyUI-ReActor"
fi
if bool "${INSTALL_IMPACT}"; then
  git_clone_at_ref "${NODE_IMPACT_REPO}" "${NODE_IMPACT_REF}" "ComfyUI-Impact-Pack"
fi

# --- Per-node requirements (install into venv) ---
print_info "Installing custom node requirements into Comfy venv..."
( cd ComfyUI-Manager && "${COMFY_UV}" pip install -r requirements.txt )
( cd ComfyUI-GGUF    && "${COMFY_UV}" pip install -r requirements.txt )
( cd RES4LYF         && "${COMFY_UV}" pip install -r requirements.txt )

if bool "${INSTALL_REACTOR}"; then
  ( cd ComfyUI-ReActor && "${COMFY_PY}" install.py || true )
  ( cd ComfyUI-ReActor && "${COMFY_UV}" pip install -r requirements.txt )
fi
if bool "${INSTALL_IMPACT}"; then
  ( cd ComfyUI-Impact-Pack && "${COMFY_PY}" install.py || true )
  ( cd ComfyUI-Impact-Pack && "${COMFY_UV}" pip install -r requirements.txt )
fi

# --- ComfyUI core requirements ---
cd "${COMFY_HOME}"
print_info "Installing ComfyUI requirements into venv..."
"${COMFY_UV}" pip install -r requirements.txt

# --- Wheel overrides (locked URLs) ---
print_info "Installing wheel overrides into venv..."
"${COMFY_PIP}" uninstall -y xformers >/dev/null 2>&1 || true
"${COMFY_UV}" pip install "${WHEEL_FLASH_ATTN_URL}"
"${COMFY_UV}" pip install "${WHEEL_XFORMERS_URL}"
"${COMFY_UV}" pip install "${WHEEL_SAGEATTN_URL}"
"${COMFY_UV}" pip install "${WHEEL_INSIGHTFACE_URL}"

# --- Shared requirements ---
if [[ -f "${SHARED_REQ}" ]]; then
  print_info "Installing shared requirements into venv: ${SHARED_REQ}"
  "${COMFY_UV}" pip install -r "${SHARED_REQ}"
else
  big_warn "Shared requirements file not found at ${SHARED_REQ} (skipping)."
fi

# -----------------------------------------------------------------------------
# SwarmUI ExtraNodes -> ComfyUI/custom_nodes (best-effort, non-fatal)
# -----------------------------------------------------------------------------
if bool "${INSTALL_SWARM_EXTRANODES}"; then
  print_info "Installing SwarmUI ExtraNodes into ComfyUI/custom_nodes (best-effort)..."
  cd "${COMFY_HOME}/custom_nodes"
  rm -rf SwarmComfyCommon SwarmComfyExtra SwarmUI_tmp || true

  git clone --depth 1 --filter=blob:none --sparse "${SWARMUI_REPO}" SwarmUI_tmp
  cd SwarmUI_tmp
  git fetch --depth 1 origin "${SWARMUI_REF}" >/dev/null 2>&1 || true
  git checkout -f "${SWARMUI_REF}" >/dev/null 2>&1 || git checkout -f "origin/${SWARMUI_REF}" >/dev/null 2>&1 || true

  EX_BASE="src/BuiltinExtensions/ComfyUIBackend/ExtraNodes"

  find_dir_under_base() {
    local base="$1" name="$2"
    git ls-tree -r -d --name-only HEAD "${base}" 2>/dev/null \
      | awk -v n="${name}" -F/ '$NF==n {print $0; exit}'
  }

  sparse_copy_dir() {
    local rel="$1" dest="$2"
    git sparse-checkout add "${rel}" >/dev/null 2>&1 || true
    if [[ -d "${rel}" ]]; then
      cp -r "${rel}" "../${dest}"
      print_info "Copied ${dest} from ${rel}"
      return 0
    fi
    return 1
  }

  copied_any=false

  common_path="$(find_dir_under_base "${EX_BASE}" "SwarmComfyCommon" || true)"
  if [[ -n "${common_path}" ]]; then
    if sparse_copy_dir "${common_path}" "SwarmComfyCommon"; then
      copied_any=true
    else
      big_warn "Found SwarmComfyCommon at '${common_path}' but failed to copy."
    fi
  else
    big_warn "SwarmComfyCommon not found under '${EX_BASE}'."
  fi

  extra_path="$(find_dir_under_base "${EX_BASE}" "SwarmComfyExtra" || true)"
  if [[ -n "${extra_path}" ]]; then
    if sparse_copy_dir "${extra_path}" "SwarmComfyExtra"; then
      copied_any=true
    else
      big_warn "Found SwarmComfyExtra at '${extra_path}' but failed to copy."
    fi
  else
    big_warn "SwarmComfyExtra not found under '${EX_BASE}'."
  fi

  cd ..
  rm -rf SwarmUI_tmp

  if [[ -d SwarmComfyCommon ]] && [[ ! -f SwarmComfyCommon/SwarmKSampler.py ]]; then
    big_warn "SwarmComfyCommon copied but SwarmKSampler.py not found (layout changed?)."
  fi
  if [[ "${copied_any}" != "true" ]]; then
    big_warn "No SwarmUI ExtraNodes directories were copied into ComfyUI/custom_nodes."
  fi
fi

# -----------------------------------------------------------------------------
# Cleanup (same RUN layer)
# -----------------------------------------------------------------------------
print_info "After installs (before cleanup):"
trace_sizes

print_info "Reducing image size..."
if bool "${CLEAN_PIP_CACHE}"; then
  rm -rf /root/.cache/pip 2>/dev/null || true
  # If /root/.cache/uv is a buildkit cache mount, rm may fail with "busy" — ignore.
  rm -rf /root/.cache/uv 2>/dev/null || true
  rm -rf /tmp/uv-cache /tmp/pip-cache 2>/dev/null || true
fi

if bool "${CLEAN_BUILD_TRASH}"; then
  find "${WORKSPACE}" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf /var/tmp/* 2>/dev/null || true
  rm -rf /tmp/* 2>/dev/null || true
fi

if bool "${STRIP_GIT}"; then
  find "${WORKSPACE}" -type d -name ".git" -prune -exec rm -rf {} + 2>/dev/null || true
fi

print_info "After cleanup:"
trace_sizes

print_info "ComfyUI install complete."

#!/usr/bin/env bash
set -euo pipefail

print_info() { printf "[comfyui-install] INFO: %s\n" "$*"; }
print_warn() { printf "[comfyui-install] WARN: %s\n" "$*"; }
print_err()  { printf "[comfyui-install] ERR : %s\n" "$*"; }

# Layout / toggles
: "${WORKSPACE_HOME:=/workspace}"
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

SHARED_REQ="/opt/requirements.shared.txt"

# Repos/refs (locked via build args)
: "${COMFY_REPO:=https://github.com/comfyanonymous/ComfyUI}"
: "${COMFY_REF:=master}"

: "${NODE_MANAGER_REPO:=https://github.com/ltdrdata/ComfyUI-Manager}"
: "${NODE_MANAGER_REF:=main}"
: "${NODE_QUANTOPS_REPO:=https://github.com/silveroxides/ComfyUI-QuantOps}"
: "${NODE_QUANTOPS_REF:=main}"
: "${NODE_GGUF_REPO:=https://github.com/city96/ComfyUI-GGUF}"
: "${NODE_GGUF_REF:=main}"
: "${NODE_RES4LYF_REPO:=https://github.com/ClownsharkBatwing/RES4LYF}"
: "${NODE_RES4LYF_REF:=main}"
: "${NODE_IPADAPTER_REPO:=https://github.com/cubiq/ComfyUI_IPAdapter_plus}"
: "${NODE_IPADAPTER_REF:=main}"
: "${NODE_REACTOR_REPO:=https://github.com/Gourieff/ComfyUI-ReActor}"
: "${NODE_REACTOR_REF:=main}"
: "${NODE_IMPACT_REPO:=https://github.com/ltdrdata/ComfyUI-Impact-Pack}"
: "${NODE_IMPACT_REF:=Main}"

: "${TORCH_VERSION:=2.8.0}"
: "${TORCH_INDEX_URL:=https://download.pytorch.org/whl/cu129}"

: "${WHEEL_FLASH_ATTN_URL:?missing}"
: "${WHEEL_XFORMERS_URL:?missing}"
: "${WHEEL_SAGEATTN_URL:?missing}"
: "${WHEEL_INSIGHTFACE_URL:?missing}"

: "${SWARMUI_REPO:=https://github.com/mcmonkeyprojects/SwarmUI}"
: "${SWARMUI_REF:=master}"

bool() { case "${1,,}" in 1|true|yes|y|on) return 0 ;; *) return 1 ;; esac; }

git_clone_at_ref() {
  # git_clone_at_ref <repo> <ref> <dest>
  local repo="$1" ref="$2" dest="$3"
  if [[ ! -d "${dest}/.git" ]]; then
    git clone --depth 1 "${repo}" "${dest}"
  fi
  (
    cd "${dest}"
    git fetch --depth 1 origin "${ref}" || true
    git checkout -f "${ref}" || git checkout -f "origin/${ref}" || true
    git reset --hard
    git clean -fd
  )
}

big_warn() {
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!! WARNING: $*"
  echo "!!! Build will CONTINUE, but features may be missing."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""
}

echo "[install] Installing into /workspace layout (baked into image)."
mkdir -p /workspace
cd /workspace

# --- ComfyUI ---
git_clone_at_ref "${COMFY_REPO}" "${COMFY_REF}" "${COMFY_HOME}"

cd "${COMFY_HOME}"

# --- venv ---
if [[ ! -d "${COMFY_VENV}" ]]; then
  python -m venv "${COMFY_VENV}"
fi
# shellcheck disable=SC1090
source "${COMFY_VENV}/bin/activate"
python -m pip install -U pip
python -m pip install -U uv

# --- torch (locked) ---
print_info "Installing torch ${TORCH_VERSION} from ${TORCH_INDEX_URL}"
uv pip install "torch==${TORCH_VERSION}" torchvision torchaudio --index-url "${TORCH_INDEX_URL}"

cd custom_nodes

# --- core nodes ---
git_clone_at_ref "${NODE_MANAGER_REPO}"  "${NODE_MANAGER_REF}"  "ComfyUI-Manager"
git_clone_at_ref "${NODE_QUANTOPS_REPO}" "${NODE_QUANTOPS_REF}" "ComfyUI-QuantOps"
git_clone_at_ref "${NODE_GGUF_REPO}"     "${NODE_GGUF_REF}"     "ComfyUI-GGUF"
git_clone_at_ref "${NODE_RES4LYF_REPO}"  "${NODE_RES4LYF_REF}"  "RES4LYF"

# --- optional nodes ---
if bool "${INSTALL_IPADAPTER}"; then
  git_clone_at_ref "${NODE_IPADAPTER_REPO}" "${NODE_IPADAPTER_REF}" "ComfyUI_IPAdapter_plus"
fi
if bool "${INSTALL_REACTOR}"; then
  git_clone_at_ref "${NODE_REACTOR_REPO}" "${NODE_REACTOR_REF}" "ComfyUI-ReActor"
fi
if bool "${INSTALL_IMPACT}"; then
  git_clone_at_ref "${NODE_IMPACT_REPO}" "${NODE_IMPACT_REF}" "ComfyUI-Impact-Pack"
fi

# --- per-node installs ---
( cd ComfyUI-Manager && uv pip install -r requirements.txt )
( cd ComfyUI-QuantOps && uv pip install -r requirements.txt )
( cd ComfyUI-GGUF && uv pip install -r requirements.txt )
( cd RES4LYF && uv pip install -r requirements.txt )

if bool "${INSTALL_REACTOR}"; then
  ( cd ComfyUI-ReActor && python install.py && uv pip install -r requirements.txt )
fi
if bool "${INSTALL_IMPACT}"; then
  ( cd ComfyUI-Impact-Pack && python install.py && uv pip install -r requirements.txt )
fi

cd "${COMFY_HOME}"

# --- ComfyUI requirements ---
uv pip install -r requirements.txt

# --- wheel overrides (locked URLs) ---
pip uninstall -y xformers || true
uv pip install "${WHEEL_FLASH_ATTN_URL}"
uv pip install "${WHEEL_XFORMERS_URL}"
uv pip install "${WHEEL_SAGEATTN_URL}"
uv pip install "${WHEEL_INSIGHTFACE_URL}"

uv pip install deepspeed

cd ${WORKSPACE_HOME}

# --- shared requirements (SECourses file) ---
uv pip install -r "${SHARED_REQ}"

# -----------------------------------------------------------------------------
# SwarmUI ExtraNodes -> ComfyUI custom_nodes (best-effort, non-fatal)
#
# We need these directories:
#   src/BuiltinExtensions/ComfyUIBackend/ExtraNodes/SwarmComfyCommon
#   src/BuiltinExtensions/ComfyUIBackend/ExtraNodes/SwarmComfyExtra
# (SwarmKSampler.py is inside SwarmComfyCommon)
# -----------------------------------------------------------------------------
if bool "${INSTALL_SWARM_EXTRANODES:-true}"; then
  print_info "Installing SwarmUI ExtraNodes (SwarmComfyCommon + SwarmComfyExtra; non-fatal)"

  cd "${COMFY_HOME}/custom_nodes"
  rm -rf SwarmComfyCommon SwarmComfyExtra SwarmUI_tmp || true

  # shallow clone + sparse to reduce weight
  git clone --depth 1 --filter=blob:none --sparse "${SWARMUI_REPO}" SwarmUI_tmp
  cd SwarmUI_tmp

  # try to checkout requested ref (branch/tag/commit)
  git fetch --depth 1 origin "${SWARMUI_REF}" >/dev/null 2>&1 || true
  git checkout -f "${SWARMUI_REF}" >/dev/null 2>&1 || git checkout -f "origin/${SWARMUI_REF}" >/dev/null 2>&1 || true

  EX_BASE="src/BuiltinExtensions/ComfyUIBackend/ExtraNodes"

  # Find the first directory named <name> anywhere under EX_BASE
  find_dir_under_base() {
    local base="$1" name="$2"
    git ls-tree -r -d --name-only HEAD "${base}" 2>/dev/null \
      | awk -v n="${name}" -F/ '$NF==n {print $0; exit}'
  }

  copy_one_extranode_dir() {
    local name="$1" dest="$2"
    local rel
    rel="$(find_dir_under_base "${EX_BASE}" "${name}" || true)"
    if [[ -z "${rel}" ]]; then
      big_warn "${name} not found under ${EX_BASE}"
      return 1
    fi

    # Only checkout exactly the needed subtree
    git sparse-checkout set "${rel}" >/dev/null 2>&1 || true

    if [[ -d "${rel}" ]]; then
      cp -r "${rel}" "../${dest}"
      print_info "Copied ${dest} from ${rel}"
      return 0
    fi

    big_warn "Found ${name} at '${rel}' but directory not present after sparse checkout"
    return 1
  }

  ok_common=false
  ok_extra=false

  if copy_one_extranode_dir "SwarmComfyCommon" "SwarmComfyCommon"; then ok_common=true; fi
  if copy_one_extranode_dir "SwarmComfyExtra"  "SwarmComfyExtra";  then ok_extra=true;  fi

  cd ..
  rm -rf SwarmUI_tmp

  # sanity checks
  if [[ "${ok_common}" == "true" ]]; then
    if [[ -f SwarmComfyCommon/SwarmKSampler.py ]]; then
      print_info "OK: SwarmKSampler.py present under SwarmComfyCommon"
    else
      big_warn "SwarmComfyCommon copied, but SwarmKSampler.py not found inside it (layout changed?)"
    fi
  fi

  if [[ "${ok_common}" != "true" && "${ok_extra}" != "true" ]]; then
    big_warn "Neither SwarmComfyCommon nor SwarmComfyExtra were copied into ComfyUI/custom_nodes."
  fi
fi

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

print_info "Done."

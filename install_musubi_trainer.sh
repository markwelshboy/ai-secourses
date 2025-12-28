#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Cleanup knobs (keep defaults ON for smaller images)
# -----------------------------------------------------------------------------
: "${STRIP_GIT:=true}"
: "${CLEAN_PIP_CACHE:=true}"
: "${CLEAN_BUILD_TRASH:=true}"
: "${RECREATE_VENV:=false}"    # set true if you want a fresh venv every build

: "${WORKSPACE:=/workspace}"
: "${HF_HOME:=/workspace}"

: "${MUSUBI_TRAINER_REPO:=https://github.com/FurkanGozukara/SECourses_Musubi_Trainer}"
: "${MUSUBI_TRAINER_DIR:=${WORKSPACE}/SECourses_Musubi_Trainer}"
: "${MUSUBI_TUNER_REPO:=https://github.com/kohya-ss/musubi-tuner}"
: "${MUSUBI_TUNER_DIR:=${MUSUBI_TRAINER_DIR}/musubi-tuner}"

: "${MUSUBI_VENV:=${MUSUBI_TRAINER_DIR}/venv}"
: "${MUSUBI_REQ:=/opt/requirements.musubi_trainer.txt}"

MUSUBI_PY="${MUSUBI_VENV}/bin/python"
MUSUBI_UV="${MUSUBI_VENV}/bin/uv"
MUSUBI_PIP="${MUSUBI_VENV}/bin/pip"

print_info() { printf "[musubi-install] INFO: %s\n" "$*"; }
print_warn() { printf "[musubi-install] WARN: %s\n" "$*"; }
print_err()  { printf "[musubi-install] ERR : %s\n" "$*"; }

uv_install() {
  # uv_install <pip args...>
  # Try uv first; if uv can't find the venv, fall tells you why and uses pip.
  if "${MUSUBI_UV}" pip install "$@"; then
    return 0
  fi
  print_warn "uv install failed; falling back to pip: $*"
  "${MUSUBI_PY}" -m pip install "$@"
}

bool() { case "${1,,}" in 1|true|yes|y|on) return 0 ;; *) return 1 ;; esac; }

# -----------------------------------------------------------------------------
# Helpers: tracing sizes to find bloat
# -----------------------------------------------------------------------------
trace_sizes() {
  print_info "SIZE TRACE: /tmp /root/.cache /workspace venvs /usr/local site-packages"
  du -sh \
    /tmp \
    /root/.cache \
    "${WORKSPACE}" \
    "${WORKSPACE}/ComfyUI/venv" \
    "${MUSUBI_VENV}" \
    /usr/local/lib/python3.10/dist-packages \
    2>/dev/null || true
}

# -----------------------------------------------------------------------------
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

print_info "Before install:"
trace_sizes

# -----------------------------------------------------------------------------
# Clone/update trainer
# -----------------------------------------------------------------------------
if [[ -d "${MUSUBI_TRAINER_DIR}/.git" ]]; then
  print_info "Updating trainer repo..."
  git -C "${MUSUBI_TRAINER_DIR}" pull --rebase --autostash || true
else
  print_info "Cloning trainer repo..."
  git clone --depth 1 "${MUSUBI_TRAINER_REPO}" "${MUSUBI_TRAINER_DIR}"
fi

# -----------------------------------------------------------------------------
# Clone/update musubi-tuner
# -----------------------------------------------------------------------------
if [[ -d "${MUSUBI_TUNER_DIR}/.git" ]]; then
  print_info "Updating musubi-tuner repo..."
  git -C "${MUSUBI_TUNER_DIR}" pull --rebase --autostash || true
else
  print_info "Cloning musubi-tuner repo..."
  git clone --depth 1 "${MUSUBI_TUNER_REPO}" "${MUSUBI_TUNER_DIR}"
fi

# -----------------------------------------------------------------------------
# Venv (optionally reuse to avoid churn)
# -----------------------------------------------------------------------------
if bool "${RECREATE_VENV}"; then
  print_warn "RECREATE_VENV=true: removing existing venv (if present)"
  rm -rf "${MUSUBI_VENV}" || true
fi

if [[ ! -d "${MUSUBI_VENV}" ]]; then
  print_info "Creating venv: ${MUSUBI_VENV}"
  python -m venv "${MUSUBI_VENV}"
else
  print_info "Reusing existing venv: ${MUSUBI_VENV}"
fi

# Make absolutely sure we install *into this venv*
"${MUSUBI_PY}" -m pip install -U pip wheel setuptools
"${MUSUBI_PIP}" install -U uv

if [[ ! -f "${MUSUBI_REQ}" ]]; then
  print_err "Requirements file not found at ${MUSUBI_REQ}"
  exit 1
fi

# -----------------------------------------------------------------------------
# UV behavior + cache placement
# -----------------------------------------------------------------------------

python -m venv "${MUSUBI_VENV}"

# Activate (good for lots of tools) + force env vars for uv detection
# shellcheck disable=SC1090
source "${MUSUBI_VENV}/bin/activate"
export VIRTUAL_ENV="${MUSUBI_VENV}"
export PATH="${MUSUBI_VENV}/bin:${PATH}"

export UV_SKIP_WHEEL_FILENAME_CHECK=1
export UV_LINK_MODE=copy

"${MUSUBI_PY}" -m pip install -U pip wheel setuptools
"${MUSUBI_PY}" -m pip install -U uv

uv_install -r "${MUSUBI_REQ}"
uv_install -e "${MUSUBI_TUNER_DIR}"

print_info "After installs (before cleanup):"
trace_sizes

# -----------------------------------------------------------------------------
# Cleanup (must happen in this same RUN layer)
# -----------------------------------------------------------------------------
print_info "Reducing image size..."

if bool "${CLEAN_PIP_CACHE}"; then
  rm -rf /root/.cache/pip /root/.cache/uv || true
  rm -rf /tmp/uv-cache /tmp/pip-cache || true
fi

if bool "${CLEAN_BUILD_TRASH}"; then
  find "${WORKSPACE}" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf /tmp/* /var/tmp/* || true
fi

if bool "${STRIP_GIT}"; then
  find "${WORKSPACE}" -type d -name ".git" -prune -exec rm -rf {} + 2>/dev/null || true
fi

print_info "After cleanup:"
trace_sizes

print_info "Install complete."

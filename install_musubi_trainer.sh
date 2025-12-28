#!/usr/bin/env bash
set -euo pipefail

print_info() { printf "[musubi-install] INFO: %s\n" "$*"; }
print_warn() { printf "[musubi-install] WARN: %s\n" "$*"; }
print_err()  { printf "[musubi-install] ERR : %s\n" "$*"; }

# -----------------------------------------------------------------------------
# Defaults / toggles
# -----------------------------------------------------------------------------
: "${WORKSPACE:=/workspace}"
: "${HF_HOME:=/workspace}"

# Cleanup knobs (default ON)
: "${STRIP_GIT:=true}"
: "${CLEAN_PIP_CACHE:=true}"
: "${CLEAN_BUILD_TRASH:=true}"

# Repos / dirs
: "${MUSUBI_TRAINER_REPO:=https://github.com/FurkanGozukara/SECourses_Musubi_Trainer}"
: "${MUSUBI_TRAINER_DIR:=${WORKSPACE}/SECourses_Musubi_Trainer}"
: "${MUSUBI_TUNER_REPO:=https://github.com/kohya-ss/musubi-tuner}"
: "${MUSUBI_TUNER_DIR:=${MUSUBI_TRAINER_DIR}/musubi-tuner}"

: "${MUSUBI_VENV:=${MUSUBI_TRAINER_DIR}/venv}"
: "${MUSUBI_REQ:=/opt/requirements.musubi_trainer.txt}"

# Constrain uv cache
: "${UV_CACHE_DIR:=/tmp/uv-cache}"

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
  du -sh "${MUSUBI_VENV}" 2>/dev/null || true
}

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

# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------
print_info "Installing Musubi Trainer/Tuner into ${MUSUBI_TRAINER_DIR}"
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

if [[ ! -f "${MUSUBI_REQ}" ]]; then
  print_err "Requirements file not found at ${MUSUBI_REQ}"
  exit 1
fi

# Clone trainer + tuner
if [[ -d "${MUSUBI_TRAINER_DIR}/.git" ]]; then
  git -C "${MUSUBI_TRAINER_DIR}" pull --rebase --autostash || true
else
  git clone --depth 1 "${MUSUBI_TRAINER_REPO}" "${MUSUBI_TRAINER_DIR}"
fi

if [[ -d "${MUSUBI_TUNER_DIR}/.git" ]]; then
  git -C "${MUSUBI_TUNER_DIR}" pull --rebase --autostash || true
else
  git clone --depth 1 "${MUSUBI_TUNER_REPO}" "${MUSUBI_TUNER_DIR}"
fi

# Create venv (idempotent)
python -m venv "${MUSUBI_VENV}"

MUSUBI_PY="${MUSUBI_VENV}/bin/python"
MUSUBI_PIP="${MUSUBI_VENV}/bin/pip"

guard_venv_python "${MUSUBI_PY}" "${MUSUBI_VENV}"

# Install pip tooling + uv into venv
print_info "Bootstrapping pip/uv inside Musubi venv..."
"${MUSUBI_PY}" -m pip install -U pip wheel setuptools
"${MUSUBI_PY}" -m pip install -U uv

MUSUBI_UV="${MUSUBI_VENV}/bin/uv"
if [[ ! -x "${MUSUBI_UV}" ]]; then
  print_err "uv not found in venv at: ${MUSUBI_UV}"
  exit 1
fi

# Configure uv (avoid cache explosion)
export UV_SKIP_WHEEL_FILENAME_CHECK="${UV_SKIP_WHEEL_FILENAME_CHECK:-1}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export UV_CACHE_DIR
mkdir -p "${UV_CACHE_DIR}"

print_info "Installing requirements into Musubi venv with venv-local uv..."
"${MUSUBI_UV}" pip install -r "${MUSUBI_REQ}"

print_info "Installing musubi-tuner editable into Musubi venv..."
"${MUSUBI_UV}" pip install -e "${MUSUBI_TUNER_DIR}"

print_info "After installs (before cleanup):"
trace_sizes

# -----------------------------------------------------------------------------
# Cleanup (same RUN layer)
# -----------------------------------------------------------------------------
print_info "Reducing image size..."
if bool "${CLEAN_PIP_CACHE}"; then
  rm -rf /root/.cache/pip 2>/dev/null || true
  # If /root/.cache/uv is a buildkit cache mount, rm may fail with "busy" — ignore.
  rm -rf /root/.cache/uv 2>/dev/null || true
  rm -rf /tmp/uv-cache /tmp/pip-cache 2>/dev/null || true
fi

if bool "${CLEAN_BUILD_TRASH}"; then
  find "${WORKSPACE}" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
fi

if bool "${STRIP_GIT}"; then
  find "${WORKSPACE}" -type d -name ".git" -prune -exec rm -rf {} + 2>/dev/null || true
fi

print_info "After cleanup:"
trace_sizes

print_info "Musubi Trainer/Tuner install complete."

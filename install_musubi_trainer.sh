#!/usr/bin/env bash
set -euo pipefail

print_info() { printf "[musubi-install] INFO: %s\n" "$*"; }
print_warn() { printf "[musubi-install] WARN: %s\n" "$*"; }
print_err()  { printf "[musubi-install] ERR : %s\n" "$*"; }

: "${WORKSPACE:=/workspace}"
: "${HF_HOME:=/workspace}"

: "${STRIP_GIT:=true}"
: "${CLEAN_PIP_CACHE:=true}"
: "${CLEAN_BUILD_TRASH:=true}"
: "${FAIL_IF_GLOBAL_SITEPACKAGES_GROWS:=true}"

: "${MUSUBI_TRAINER_REPO:=https://github.com/FurkanGozukara/SECourses_Musubi_Trainer}"
: "${MUSUBI_TRAINER_DIR:=${WORKSPACE}/SECourses_Musubi_Trainer}"
: "${MUSUBI_TUNER_REPO:=https://github.com/kohya-ss/musubi-tuner}"
: "${MUSUBI_TUNER_DIR:=${MUSUBI_TRAINER_DIR}/musubi-tuner}"

: "${MUSUBI_VENV:=${MUSUBI_TRAINER_DIR}/venv}"
: "${MUSUBI_REQ:=/opt/requirements.musubi_trainer.txt}"

: "${UV_CACHE_DIR:=/tmp/uv-cache}"
: "${PIP_CACHE_DIR:=/tmp/pip-cache}"

bool() { case "${1,,}" in 1|true|yes|y|on) return 0 ;; *) return 1 ;; esac; }

trace_sizes() {
  print_info "SIZE TRACE (best-effort): /tmp /root/.cache /workspace /usr/local dist-packages"
  du -sh /tmp /root/.cache "${WORKSPACE}" /usr/local/lib/python3.10/dist-packages 2>/dev/null || true
  du -sh "${MUSUBI_VENV}" 2>/dev/null || true
}

global_site_bytes() {
  du -sb /usr/local/lib/python3.10/dist-packages 2>/dev/null | awk '{print $1}' || true
}

guard_venv_python() {
  local py="$1" expected_prefix="$2"
  [[ -x "$py" ]] || { print_err "Python not executable: $py"; exit 1; }
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

print_info "Installing Musubi Trainer/Tuner into ${MUSUBI_TRAINER_DIR}"
mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

[[ -f "${MUSUBI_REQ}" ]] || { print_err "Requirements file not found at ${MUSUBI_REQ}"; exit 1; }

before_global="$(global_site_bytes)"
print_info "Global dist-packages bytes (before): ${before_global:-unknown}"

# Clone trainer
if [[ -d "${MUSUBI_TRAINER_DIR}/.git" ]]; then
  git -C "${MUSUBI_TRAINER_DIR}" pull --rebase --autostash || true
else
  git clone --depth 1 "${MUSUBI_TRAINER_REPO}" "${MUSUBI_TRAINER_DIR}"
fi

# Clone musubi-tuner
if [[ -d "${MUSUBI_TUNER_DIR}/.git" ]]; then
  git -C "${MUSUBI_TUNER_DIR}" pull --rebase --autostash || true
else
  mkdir -p "$(dirname "${MUSUBI_TUNER_DIR}")"
  git clone --depth 1 "${MUSUBI_TUNER_REPO}" "${MUSUBI_TUNER_DIR}"
fi

# Ensure uv exists (DON'T upgrade every build; just ensure present)
if ! command -v uv >/dev/null 2>&1; then
  print_info "uv not found; installing system uv..."
  python -m pip install -U uv
else
  print_info "uv present: $(uv --version 2>/dev/null || true)"
fi

# Create venv via uv (so uv recognizes it)
print_info "Creating Musubi venv via 'uv venv' at: ${MUSUBI_VENV}"
uv venv "${MUSUBI_VENV}"

MUSUBI_PY="${MUSUBI_VENV}/bin/python"
guard_venv_python "${MUSUBI_PY}" "${MUSUBI_VENV}"

# Make uv pip target THIS venv (critical for uv 0.9.x)
export VIRTUAL_ENV="${MUSUBI_VENV}"
export PATH="${MUSUBI_VENV}/bin:${PATH}"

# Configure uv cache (kept under /tmp to avoid layer bloat; can be buildkit mounted)
export UV_SKIP_WHEEL_FILENAME_CHECK="${UV_SKIP_WHEEL_FILENAME_CHECK:-1}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"
export UV_CACHE_DIR
mkdir -p "${UV_CACHE_DIR}" "${PIP_CACHE_DIR}"

print_info "Installing requirements into Musubi venv (uv pip)..."
uv pip install -r "${MUSUBI_REQ}"

print_info "Installing musubi-tuner editable into Musubi venv..."
uv pip install -e "${MUSUBI_TUNER_DIR}"

print_info "After installs (before cleanup):"
trace_sizes

after_global="$(global_site_bytes)"
print_info "Global dist-packages bytes (after): ${after_global:-unknown}"
if bool "${FAIL_IF_GLOBAL_SITEPACKAGES_GROWS}"; then
  if [[ -n "${before_global}" && -n "${after_global}" && "${after_global}" -gt "${before_global}" ]]; then
    print_err "Leak detected: /usr/local/.../dist-packages grew (before=${before_global} after=${after_global})."
    print_err "This indicates a system install occurred (bad)."
    exit 1
  fi
fi

print_info "Reducing image size..."

if bool "${CLEAN_PIP_CACHE}"; then
  rm -rf /root/.cache/pip 2>/dev/null || true
  rm -rf /root/.cache/uv 2>/dev/null || true  # may be a buildkit mount; ignore failures
  rm -rf "${UV_CACHE_DIR}" "${PIP_CACHE_DIR}" 2>/dev/null || true
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

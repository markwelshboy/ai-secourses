#!/usr/bin/env bash
set -euo pipefail

# Cleanup knobs (keep defaults ON for smaller images)
: "${STRIP_GIT:=true}"
: "${CLEAN_PIP_CACHE:=true}"
: "${CLEAN_BUILD_TRASH:=true}"

: "${WORKSPACE:=/workspace}"
: "${HF_HOME:=/workspace}"

: "${MUSUBI_TRAINER_REPO:=https://github.com/FurkanGozukara/SECourses_Musubi_Trainer}"
: "${MUSUBI_TRAINER_DIR:=${WORKSPACE}/SECourses_Musubi_Trainer}"
: "${MUSUBI_TUNER_REPO:=https://github.com/kohya-ss/musubi-tuner}"
: "${MUSUBI_TUNER_DIR:=${MUSUBI_TRAINER_DIR}/musubi-tuner}"

: "${MUSUBI_VENV:=${MUSUBI_TRAINER_DIR}/venv}"
: "${MUSUBI_REQ:=/opt/requirements.musubi_trainer.txt}"   # you can COPY this into the image or keep it in pod-runtime

mkdir -p "${WORKSPACE}"
cd "${WORKSPACE}"

# Clone/update trainer
if [[ -d "${MUSUBI_TRAINER_DIR}/.git" ]]; then
  git -C "${MUSUBI_TRAINER_DIR}" pull --rebase --autostash || true
else
  git clone --depth 1 "${MUSUBI_TRAINER_REPO}" "${MUSUBI_TRAINER_DIR}"
fi

# Clone/update musubi-tuner
if [[ -d "${MUSUBI_TUNER_DIR}/.git" ]]; then
  git -C "${MUSUBI_TUNER_DIR}" pull --rebase --autostash || true
else
  git clone --depth 1 "${MUSUBI_TUNER_REPO}" "${MUSUBI_TUNER_DIR}"
fi

# Venv
python -m venv "${MUSUBI_VENV}"
# shellcheck disable=SC1090
source "${MUSUBI_VENV}/bin/activate"

python -m pip install -U pip wheel setuptools
python -m pip install -U uv

# Install requirements into THIS venv
if [[ ! -f "${MUSUBI_REQ}" ]]; then
  echo "[musubi-trainer] FATAL: Requirements file not found at ${MUSUBI_REQ}" >&2
  exit 1
fi

export UV_SKIP_WHEEL_FILENAME_CHECK=1
export UV_LINK_MODE=copy

# Avoid uv cache explosion
export UV_CACHE_DIR=/tmp/uv-cache
mkdir -p "${UV_CACHE_DIR}"

uv pip install -r "${MUSUBI_REQ}"

# Install musubi-tuner editable
cd "${MUSUBI_TUNER_DIR}"
uv pip install -e .

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

echo "[musubi-trainer] Install complete."

#!/usr/bin/env bash
set -euo pipefail

: "${WORKSPACE:=/workspace}"
: "${HF_HOME:=/workspace}"

: "${MUSUBI_TRAINER_REPO:=https://github.com/FurkanGozukara/SECourses_Musubi_Trainer}"
: "${MUSUBI_TRAINER_DIR:=${WORKSPACE}/Musubi_Trainer}"
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

echo "[musubi-trainer] Install complete."

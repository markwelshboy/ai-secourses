#!/usr/bin/env bash
set -euo pipefail

log()  { printf "[entrypoint] %s\n" "$*"; }
warn() { printf "[entrypoint] WARN: %s\n" "$*" >&2; }
die()  { printf "[entrypoint] FATAL: %s\n" "$*" >&2; exit 1; }

: "${WORKSPACE:=/workspace}"
: "${POD_RUNTIME_REPO_URL:=https://github.com/markwelshboy/pod-runtime.git}"
: "${POD_RUNTIME_DIR:=${WORKSPACE}/pod-runtime}"
: "${POD_RUNTIME_REF:=}"  # optional branch/tag/commit
: "${POD_RUNTIME_ENV:=${POD_RUNTIME_DIR}/.env}"
: "${POD_RUNTIME_HELPERS:=${POD_RUNTIME_DIR}/helpers.sh}"
: "${POD_RUNTIME_START:=${POD_RUNTIME_DIR}/start.secourses.sh}"

mkdir -p "${WORKSPACE}"

command -v git >/dev/null 2>&1 || die "git not found in image"

clone_or_update() {
  local url="$1" dir="$2" ref="${3:-}"

  if [[ -d "${dir}/.git" ]]; then
    log "Updating pod-runtime in ${dir}..."
    ( git -C "${dir}" fetch --all --prune ) || true

    if [[ -z "${ref}" ]]; then
      ( git -C "${dir}" pull --rebase --autostash ) || warn "git pull failed; continuing with existing checkout"
    fi
  else
    log "Cloning pod-runtime from ${url} into ${dir}..."
    rm -rf "${dir}"
    git clone --depth 1 "${url}" "${dir}"
  fi

  if [[ -n "${ref}" ]]; then
    log "Checking out POD_RUNTIME_REF=${ref}"
    ( cd "${dir}" && git fetch --depth 1 origin "${ref}" >/dev/null 2>&1 ) || true
    ( cd "${dir}" && git checkout -f "${ref}" >/dev/null 2>&1 ) || \
    ( cd "${dir}" && git checkout -f "origin/${ref}" >/dev/null 2>&1 ) || \
      warn "checkout of ${ref} failed; continuing with current checkout"
  fi
}

clone_or_update "${POD_RUNTIME_REPO_URL}" "${POD_RUNTIME_DIR}" "${POD_RUNTIME_REF}"

# Optional: source .env (lets it set variables used by start script)
if [[ -f "${POD_RUNTIME_ENV}" ]]; then
  log "Sourcing ${POD_RUNTIME_ENV}"
  # shellcheck disable=SC1090
  source "${POD_RUNTIME_ENV}"
else
  warn ".env not found at ${POD_RUNTIME_ENV} (continuing)"
fi

[[ -f "${POD_RUNTIME_START}" ]] || die "Start script not found: ${POD_RUNTIME_START}"
chmod +x "${POD_RUNTIME_START}" || true

log "Exec: ${POD_RUNTIME_START}"
exec "${POD_RUNTIME_START}"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [options]

Defaults:
  repo:   markwelshboy/ai-secourses
  tag:    latest
  push:   true

Options:
  --repo <name>         Image repo (default: markwelshboy/ai-secourses)
  --tag <tag>           Tag (default: latest)
  --platform <plat>     Platform (default: linux/amd64)
  --push | --no-push    Push to registry (default: --push)
  --no-cache            Disable build cache
  --prune               Run safe-ish prune before build (builder/container/image)
  --prune-hard          Run aggressive prune (docker system prune -af)
  --build-date <str>    BUILD_DATE build-arg (default: now UTC)
  --vcs-ref <str>       VCS_REF build-arg (default: git sha or 'unknown')
  --version <str>       IMAGE_VERSION build-arg (default: 0.1.0)
EOF
}

REPO="markwelshboy/ai-secourses"
TAG="latest"
PLATFORM="linux/amd64"
PUSH="true"
NO_CACHE="false"
PRUNE="false"
PRUNE_HARD="false"

BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
VCS_REF="unknown"
IMAGE_VERSION="0.1.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --push) PUSH="true"; shift ;;
    --no-push) PUSH="false"; shift ;;
    --no-cache) NO_CACHE="true"; shift ;;
    --prune) PRUNE="true"; shift ;;
    --prune-hard) PRUNE_HARD="true"; shift ;;
    --build-date) BUILD_DATE="$2"; shift 2 ;;
    --vcs-ref) VCS_REF="$2"; shift 2 ;;
    --version) IMAGE_VERSION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

# Try to auto-fill VCS_REF from git if available and not explicitly set
if [[ "${VCS_REF}" == "unknown" ]]; then
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VCS_REF="$(git rev-parse --short HEAD)"
  fi
fi

IMG="${REPO}:${TAG}"

echo "== Build settings =="
echo "Image      : ${IMG}"
echo "Platform   : ${PLATFORM}"
echo "Push       : ${PUSH}"
echo "No-cache   : ${NO_CACHE}"
echo "Build date : ${BUILD_DATE}"
echo "VCS ref    : ${VCS_REF}"
echo "Version    : ${IMAGE_VERSION}"
echo ""

if [[ "${PRUNE_HARD}" == "true" ]]; then
  echo "== Aggressive prune (docker system prune -af) =="
  sudo docker system prune -af
elif [[ "${PRUNE}" == "true" ]]; then
  echo "== Safe-ish prune (builder/container/image) =="
  sudo docker container prune -f || true
  sudo docker image prune -f || true
  sudo docker builder prune -f || true
fi

echo "== Disk usage (before) =="
sudo docker system df || true
df -h || true
echo ""

# Ensure buildx builder exists & is selected
if ! sudo docker buildx inspect >/dev/null 2>&1; then
  sudo docker buildx create --use --name default >/dev/null
fi

BUILD_ARGS=(
  "--build-arg" "BUILD_DATE=${BUILD_DATE}"
  "--build-arg" "VCS_REF=${VCS_REF}"
  "--build-arg" "IMAGE_VERSION=${IMAGE_VERSION}"
)

CACHE_ARGS=()
if [[ "${NO_CACHE}" == "true" ]]; then
  CACHE_ARGS+=(--no-cache)
fi

PUSH_ARGS=()
if [[ "${PUSH}" == "true" ]]; then
  PUSH_ARGS+=(--push)
else
  PUSH_ARGS+=(--load)
fi

# BuildKit on; buildx by default uses it
echo "== Building =="
set -x
sudo docker buildx build \
  --platform "${PLATFORM}" \
  -t "${IMG}" \
  "${PUSH_ARGS[@]}" \
  "${CACHE_ARGS[@]}" \
  "${BUILD_ARGS[@]}" \
  .
set +x

echo ""
echo "== Done =="
echo "Built: ${IMG}"
if [[ "${PUSH}" == "true" ]]; then
  echo "Pushed: ${IMG}"
else
  echo "Loaded locally: ${IMG}"
fi

echo ""
echo "== Disk usage (after) =="
sudo docker system df || true
df -h || true

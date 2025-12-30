#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# build.sh — buildx builder with prune knobs for:
#   - markwelshboy/ai-secourses-comfy:latest
#   - markwelshboy/ai-secourses-musubi:latest
#
# Usage:
#   ./build.sh                 # builds & pushes both (default)
#   ./build.sh --all
#   ./build.sh --comfy
#   ./build.sh --musubi
#
# Options:
#   --no-push              Do not push (default: push)
#   --load                 Load into local docker (implies --no-push)
#   --platform <plats>     Default: linux/amd64
#   --no-cache             Disable build cache
#   --prune                Safe-ish prune before build
#   --prune-hard           Aggressive prune before build (docker system prune -af)
#
# Tagging:
#   --tag comfy:<tag>      Override comfy tag (default: latest)
#   --tag musubi:<tag>     Override musubi tag (default: latest)
#
# Metadata:
#   --image-version <v>    Default: 0.1.0
#   --build-date <iso>     Default: now (UTC)
#   --vcs-ref <sha>        Default: git rev-parse --short HEAD or "unknown"
#
# Pass-through build args:
#   --build-arg KEY=VALUE  Repeatable. Passed to docker buildx build.
# -----------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--all|--comfy|--musubi] [options]

Targets:
  --all        Build both (default)
  --comfy      Build Comfy target only
  --musubi     Build Musubi target only

Options:
  --no-push              Do not push (default is push)
  --load                 Load into local docker (implies --no-push)
  --platform <plats>     Default: linux/amd64 (e.g. linux/amd64,linux/arm64)
  --no-cache             Disable build cache
  --prune                Safe-ish prune (container/image/builder)
  --prune-hard           Aggressive prune (docker system prune -af)

Tagging:
  --tag comfy:<tag>      Override comfy tag (default: latest)
  --tag musubi:<tag>     Override musubi tag (default: latest)

Metadata:
  --image-version <v>    Default: 0.1.0
  --build-date <iso>     Default: now UTC if omitted
  --vcs-ref <sha>        Default: git rev-parse --short HEAD or "unknown"

Pass-through:
  --build-arg KEY=VALUE  Repeatable.

Examples:
  ./build.sh
  ./build.sh --comfy --no-push
  ./build.sh --musubi --tag musubi:dev --load
  ./build.sh --all --platform linux/amd64,linux/arm64 --prune
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Targets
DO_COMFY=false
DO_MUSUBI=false
DO_ALL=true

# Build behavior
PUSH=true
LOAD=false
PLATFORM="linux/amd64"
NO_CACHE=false
PRUNE=false
PRUNE_HARD=false

# Images/tags
COMFY_IMAGE="markwelshboy/ai-secourses-comfy"
MUSUBI_IMAGE="markwelshboy/ai-secourses-musubi"
COMFY_TAG="latest"
MUSUBI_TAG="latest"

# Metadata
IMAGE_VERSION="0.1.0"
BUILD_DATE=""
VCS_REF=""

# Extra args
EXTRA_BUILD_ARGS=()

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      DO_ALL=true; DO_COMFY=false; DO_MUSUBI=false
      shift
      ;;
    --comfy)
      DO_ALL=false; DO_COMFY=true
      shift
      ;;
    --musubi)
      DO_ALL=false; DO_MUSUBI=true
      shift
      ;;
    --no-push)
      PUSH=false
      shift
      ;;
    --load)
      LOAD=true
      PUSH=false
      shift
      ;;
    --platform)
      [[ -n "${2:-}" ]] || die "--platform requires a value"
      PLATFORM="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    --prune)
      PRUNE=true
      shift
      ;;
    --prune-hard)
      PRUNE_HARD=true
      shift
      ;;
    --tag)
      [[ -n "${2:-}" ]] || die "--tag requires a value like comfy:dev"
      case "$2" in
        comfy:*)
          COMFY_TAG="${2#comfy:}"
          ;;
        musubi:*)
          MUSUBI_TAG="${2#musubi:}"
          ;;
        *)
          die "--tag must be 'comfy:<tag>' or 'musubi:<tag>'"
          ;;
      esac
      shift 2
      ;;
    --image-version)
      [[ -n "${2:-}" ]] || die "--image-version requires a value"
      IMAGE_VERSION="$2"
      shift 2
      ;;
    --build-date)
      [[ -n "${2:-}" ]] || die "--build-date requires a value"
      BUILD_DATE="$2"
      shift 2
      ;;
    --vcs-ref)
      [[ -n "${2:-}" ]] || die "--vcs-ref requires a value"
      VCS_REF="$2"
      shift 2
      ;;
    --build-arg)
      [[ -n "${2:-}" ]] || die "--build-arg requires KEY=VALUE"
      EXTRA_BUILD_ARGS+=(--build-arg "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac
done

# Select targets
if $DO_ALL; then
  DO_COMFY=true
  DO_MUSUBI=true
fi

have_cmd docker || die "docker not found"
sudo docker buildx version >/dev/null 2>&1 || die "docker buildx not available"

# Metadata defaults
if [[ -z "${BUILD_DATE}" ]]; then
  BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
if [[ -z "${VCS_REF}" ]]; then
  if have_cmd git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  else
    VCS_REF="unknown"
  fi
fi

echo "== Build settings =="
echo "Targets     : $($DO_COMFY && echo -n "comfy " ; $DO_MUSUBI && echo -n "musubi " ; echo)"
echo "Platform    : ${PLATFORM}"
echo "Push        : ${PUSH}"
echo "Load        : ${LOAD}"
echo "No-cache    : ${NO_CACHE}"
echo "Prune       : ${PRUNE}"
echo "Prune-hard  : ${PRUNE_HARD}"
echo "Build date  : ${BUILD_DATE}"
echo "VCS ref     : ${VCS_REF}"
echo "Version     : ${IMAGE_VERSION}"
echo "Comfy image : ${COMFY_IMAGE}:${COMFY_TAG}"
echo "Musubi image: ${MUSUBI_IMAGE}:${MUSUBI_TAG}"
echo ""

# Prune logic (optional)
if $PRUNE_HARD; then
  echo "== Aggressive prune (docker system prune -af) =="
  sudo docker system prune -af || true
elif $PRUNE; then
  echo "== Safe-ish prune (container/image/builder) =="
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

common_buildx_args=(
  --platform "${PLATFORM}"
  --build-arg "BUILD_DATE=${BUILD_DATE}"
  --build-arg "VCS_REF=${VCS_REF}"
  --build-arg "IMAGE_VERSION=${IMAGE_VERSION}"
)

if $NO_CACHE; then
  common_buildx_args+=(--no-cache)
fi

if $PUSH; then
  common_buildx_args+=(--push)
elif $LOAD; then
  common_buildx_args+=(--load)
else
  # if neither push nor load, default to load to make it useful locally
  common_buildx_args+=(--load)
fi

build_target() {
  local target="$1" image="$2" tag="$3"

  echo ""
  echo "================================================================================"
  echo "== Building target: ${target}"
  echo "== Image: ${image}:${tag}"
  echo "================================================================================"
  echo ""

  sudo docker buildx build \
    --target "${target}" \
    -t "${image}:${tag}" \
    "${common_buildx_args[@]}" \
    "${EXTRA_BUILD_ARGS[@]}" \
    .
}

if $DO_COMFY; then
  build_target "comfy" "${COMFY_IMAGE}" "${COMFY_TAG}"
fi

if $DO_MUSUBI; then
  build_target "musubi" "${MUSUBI_IMAGE}" "${MUSUBI_TAG}"
fi

echo ""
echo "== Done =="
if $PUSH; then
  $DO_COMFY  && echo "Pushed: ${COMFY_IMAGE}:${COMFY_TAG}"  || true
  $DO_MUSUBI && echo "Pushed: ${MUSUBI_IMAGE}:${MUSUBI_TAG}" || true
else
  $DO_COMFY  && echo "Built (local): ${COMFY_IMAGE}:${COMFY_TAG}"  || true
  $DO_MUSUBI && echo "Built (local): ${MUSUBI_IMAGE}:${MUSUBI_TAG}" || true
fi

echo ""
echo "== Disk usage (after) =="
sudo docker system df || true
df -h || true

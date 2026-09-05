#!/bin/bash
# Build and push JupyterLab Docker images for multiple architectures
#
# Usage:
#   ./build.sh              # Build and push multi-arch
#   ./build.sh --local      # Build locally only (single architecture, no push)
#   ./build.sh --no-cache   # Build from scratch without cache

set -e

# Configuration
REGISTRY="docker.io/dawsonlp"
IMAGE_NAME="jupyterlab"
BUILDER="${BUILDER:-cloud-dawsonlp-arm64}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# Version definition
PYTHON_VERSION="3.14"
BUILD_DATE="20260905"

# Parse arguments
LOCAL_ONLY=false
NO_CACHE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_ONLY=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

EXTRA_ARGS=()
if [ "$NO_CACHE" = true ]; then
    EXTRA_ARGS+=(--no-cache --pull)
fi

# Main build logic
cd "$(dirname "$0")"

echo "=========================================="
echo "JupyterLab Data Science Docker Image Builder"
echo "=========================================="
echo "Registry: $REGISTRY"
echo "Image: $IMAGE_NAME"
echo "Python Version: $PYTHON_VERSION"
echo "Builder: $BUILDER"
echo "Platforms: $PLATFORMS"
echo "Local only: $LOCAL_ONLY"
echo "No cache: $NO_CACHE"
echo ""

TAGS=(
    "${REGISTRY}/${IMAGE_NAME}:latest"
    "${REGISTRY}/${IMAGE_NAME}:${PYTHON_VERSION}"
    "${REGISTRY}/${IMAGE_NAME}:${PYTHON_VERSION}-${BUILD_DATE}"
)

TAG_ARGS=()
for tag in "${TAGS[@]}"; do
    TAG_ARGS+=(-t "$tag")
done

if [ "$LOCAL_ONLY" = true ]; then
    echo "Building locally (single architecture)..."
    docker build \
        "${EXTRA_ARGS[@]}" \
        "${TAG_ARGS[@]}" \
        .
else
    echo "Building multi-arch and pushing to registry..."
    docker buildx use "$BUILDER"
    docker buildx build \
        --builder "$BUILDER" \
        --platform "$PLATFORMS" \
        "${EXTRA_ARGS[@]}" \
        "${TAG_ARGS[@]}" \
        --push \
        .
fi

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "Available images:"
if [ "$LOCAL_ONLY" = true ]; then
    docker images | grep "${IMAGE_NAME}" | head -5
else
    for tag in "${TAGS[@]}"; do
        echo "  $tag"
    done
fi


#!/bin/bash
# Build and push PostgreSQL Batteries-Included Docker images
#
# Usage:
#   ./build.sh              # Build and push
#   ./build.sh --local      # Build locally only (no push)
#   ./build.sh --no-cache   # Build from scratch without cache

set -e

# Configuration
REGISTRY="docker.io/dawsonlp"
IMAGE_NAME="postgres-batteries-inc"
BUILDER="${BUILDER:-cloud-dawsonlp-arm64}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# Version - PostgreSQL stable release and matching major line
PG_VERSION="18.6"
PG_MAJOR="${PG_VERSION%%.*}"

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
echo "PostgreSQL Batteries-Included Builder"
echo "=========================================="
echo "Registry: $REGISTRY"
echo "Image: $IMAGE_NAME"
echo "PostgreSQL Version: $PG_VERSION"
echo "PostgreSQL Major: $PG_MAJOR"
echo "Platforms: $PLATFORMS"
echo "Local only: $LOCAL_ONLY"
echo "No cache: $NO_CACHE"
echo ""

if [ "$LOCAL_ONLY" = true ]; then
    echo "Building locally (single architecture)..."
    docker build \
        "${EXTRA_ARGS[@]}" \
        --build-arg PG_VERSION="$PG_VERSION" \
        --build-arg PG_MAJOR="$PG_MAJOR" \
        -t "${REGISTRY}/${IMAGE_NAME}:latest" \
        -t "${REGISTRY}/${IMAGE_NAME}:${PG_VERSION}" \
        -t "${REGISTRY}/${IMAGE_NAME}:${PG_MAJOR}" \
        .
else
    echo "Building multi-arch and pushing to registry..."
    docker buildx use "$BUILDER"
    docker buildx build \
        --builder "$BUILDER" \
        --platform "$PLATFORMS" \
        "${EXTRA_ARGS[@]}" \
        --build-arg PG_VERSION="$PG_VERSION" \
        --build-arg PG_MAJOR="$PG_MAJOR" \
        -t "${REGISTRY}/${IMAGE_NAME}:latest" \
        -t "${REGISTRY}/${IMAGE_NAME}:${PG_VERSION}" \
        -t "${REGISTRY}/${IMAGE_NAME}:${PG_MAJOR}" \
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
    echo "  ${REGISTRY}/${IMAGE_NAME}:latest  (PostgreSQL $PG_VERSION)"
    echo "  ${REGISTRY}/${IMAGE_NAME}:${PG_VERSION}"
    echo "  ${REGISTRY}/${IMAGE_NAME}:${PG_MAJOR}"
fi

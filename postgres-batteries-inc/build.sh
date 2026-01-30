#!/bin/bash
# Build and push PostgreSQL Batteries-Included Docker images
#
# Usage:
#   ./build.sh              # Build and push
#   ./build.sh --local      # Build locally only (no push)

set -e

# Configuration
REGISTRY="docker.io/dawsonlp"
IMAGE_NAME="postgres-batteries-inc"
BUILDER="cloud-dawsonlp-arm64"
PLATFORMS="linux/amd64,linux/arm64"

# Version - PostgreSQL major version
PG_VERSION="18"

# Parse arguments
LOCAL_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_ONLY=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Main build logic
cd "$(dirname "$0")"

echo "=========================================="
echo "PostgreSQL Batteries-Included Builder"
echo "=========================================="
echo "Registry: $REGISTRY"
echo "Image: $IMAGE_NAME"
echo "PostgreSQL Version: $PG_VERSION"
echo "Platforms: $PLATFORMS"
echo "Local only: $LOCAL_ONLY"
echo ""

TAGS="${REGISTRY}/${IMAGE_NAME}:latest -t ${REGISTRY}/${IMAGE_NAME}:${PG_VERSION}"

if [ "$LOCAL_ONLY" = true ]; then
    echo "Building locally (single architecture)..."
    docker build \
        --build-arg PG_MAJOR="$PG_VERSION" \
        -t "${REGISTRY}/${IMAGE_NAME}:latest" \
        -t "${REGISTRY}/${IMAGE_NAME}:${PG_VERSION}" \
        .
else
    echo "Building multi-arch and pushing to registry..."
    docker buildx use "$BUILDER"
    docker buildx build \
        --builder "$BUILDER" \
        --platform "$PLATFORMS" \
        --build-arg PG_MAJOR="$PG_VERSION" \
        -t "${REGISTRY}/${IMAGE_NAME}:latest" \
        -t "${REGISTRY}/${IMAGE_NAME}:${PG_VERSION}" \
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
fi
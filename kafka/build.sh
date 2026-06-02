#!/bin/bash
# Build and push Kafka Docker images for multiple versions and architectures
#
# Usage:
#   ./build.sh              # Build and push all versions
#   ./build.sh --local      # Build locally only (no push)
#   ./build.sh 4.3.0        # Build specific version only
#
# Versions:
#   4.3.0     - Stable release (tagged as :latest and :4.3.0)

set -e

# Configuration
REGISTRY="docker.io/dawsonlp"
IMAGE_NAME="kafka"
BUILDER="${BUILDER:-cloud-dawsonlp-arm64}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# Version definitions
STABLE_VERSION="4.3.0"

# Parse arguments
LOCAL_ONLY=false
SPECIFIC_VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL_ONLY=true
            shift
            ;;
        *)
            SPECIFIC_VERSION="$1"
            shift
            ;;
    esac
done

# Function to build a specific version
build_version() {
    local version=$1
    local tags=$2
    
    echo ""
    echo "=========================================="
    echo "Building Kafka version: $version"
    echo "Tags: $tags"
    echo "=========================================="
    
    # Construct tag arguments
    local tag_args=""
    for tag in $tags; do
        tag_args="$tag_args -t ${REGISTRY}/${IMAGE_NAME}:${tag}"
    done
    
    if [ "$LOCAL_ONLY" = true ]; then
        echo "Building locally (single architecture)..."
        docker build \
            --build-arg KAFKA_VERSION="$version" \
            $tag_args \
            .
    else
        echo "Building multi-arch and pushing to registry..."
        docker buildx use "$BUILDER"
        docker buildx build \
            --builder "$BUILDER" \
            --platform "$PLATFORMS" \
            --build-arg KAFKA_VERSION="$version" \
            $tag_args \
            --push \
            .
    fi
    
    echo "✓ Completed: $version"
}

# Main build logic
cd "$(dirname "$0")"

echo "Kafka Docker Image Builder"
echo "Registry: $REGISTRY"
echo "Builder: $BUILDER"
echo "Platforms: $PLATFORMS"
echo "Local only: $LOCAL_ONLY"

if [ -n "$SPECIFIC_VERSION" ]; then
    # Build specific version
    if [ "$SPECIFIC_VERSION" = "$STABLE_VERSION" ]; then
        build_version "$STABLE_VERSION" "latest $STABLE_VERSION"
    else
        build_version "$SPECIFIC_VERSION" "$SPECIFIC_VERSION"
    fi
else
    # Build stable version (tagged as latest and version number)
    build_version "$STABLE_VERSION" "latest $STABLE_VERSION"
fi

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "Available images:"
if [ "$LOCAL_ONLY" = true ]; then
    docker images | grep "${IMAGE_NAME}" | head -10
else
    echo "  ${REGISTRY}/${IMAGE_NAME}:latest     (Kafka $STABLE_VERSION)"
    echo "  ${REGISTRY}/${IMAGE_NAME}:$STABLE_VERSION"
fi

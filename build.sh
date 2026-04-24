#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE_NAME="unbound-custom"
TAG="${1:-latest}"

echo "Building ${IMAGE_NAME}:${TAG}..."
docker build -t "${IMAGE_NAME}:${TAG}" "${PROJECT_DIR}"

echo "Image built: ${IMAGE_NAME}:${TAG}"
echo ""
echo "To push to registry:"
echo "  docker tag ${IMAGE_NAME}:${TAG} <registry>/<repo>:${TAG}"
echo "  docker push <registry>/<repo>:${TAG}"

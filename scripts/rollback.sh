#!/bin/bash
# =============================================================
# Rollback Script
# Reverts production to a previously deployed image version.
#
# Usage:
#   export DOCKER_USERNAME=psourabh311
#   bash rollback.sh <git-sha>
#
# Example:
#   bash rollback.sh abc1234
# =============================================================

set -e

DOCKER_USERNAME="${DOCKER_USERNAME:-myusername}"
ROLLBACK_TAG="${1:-latest}"
IMAGE_NAME="${DOCKER_USERNAME}/flask-cicd-app"
ROLLBACK_IMAGE="${IMAGE_NAME}:${ROLLBACK_TAG}"

echo "============================================"
echo "ROLLBACK INITIATED"
echo "Target image: ${ROLLBACK_IMAGE}"
echo "============================================"

docker pull "${ROLLBACK_IMAGE}"

BLUE_RUNNING=$(docker ps --filter "name=flask-blue" --filter "status=running" -q)
GREEN_RUNNING=$(docker ps --filter "name=flask-green" --filter "status=running" -q)

if [ -n "$BLUE_RUNNING" ]; then
    ROLLBACK_CONTAINER="flask-green"
    ROLLBACK_PORT=5001
    OLD_CONTAINER="flask-blue"
else
    ROLLBACK_CONTAINER="flask-blue"
    ROLLBACK_PORT=5000
    OLD_CONTAINER="flask-green"
fi

docker rm -f "${ROLLBACK_CONTAINER}" 2>/dev/null || true

echo "Starting rollback container on port ${ROLLBACK_PORT}..."
docker run -d \
    --name "${ROLLBACK_CONTAINER}" \
    --restart unless-stopped \
    -p "${ROLLBACK_PORT}:5000" \
    -e "APP_VERSION=${ROLLBACK_TAG}" \
    "${ROLLBACK_IMAGE}"

echo "Verifying rollback container health..."
sleep 5
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:${ROLLBACK_PORT}/health")

if [ "$HTTP_STATUS" != "200" ]; then
    echo "ERROR: Rollback container failed health check."
    docker rm -f "${ROLLBACK_CONTAINER}"
    exit 1
fi

sudo sed -i "s/server 127\.0\.0\.1:[0-9]*/server 127.0.0.1:${ROLLBACK_PORT}/" \
    /etc/nginx/sites-available/flask-app
sudo nginx -t
sudo systemctl reload nginx

docker stop "${OLD_CONTAINER}" 2>/dev/null || true
docker rm "${OLD_CONTAINER}" 2>/dev/null || true

echo "============================================"
echo "ROLLBACK SUCCESSFUL"
echo "Running: ${ROLLBACK_IMAGE}"
echo "============================================"

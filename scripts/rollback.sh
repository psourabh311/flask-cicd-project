#!/bin/bash
# =============================================================
# Rollback Script
# Use karo jab deployment fail ho ya production me issue aaye
# Usage: bash rollback.sh <previous-image-tag>
# Example: bash rollback.sh abc1234
# =============================================================

set -e

DOCKER_USERNAME="${DOCKER_USERNAME:-myusername}"
ROLLBACK_TAG="${1:-latest}"    # Argument se tag lo, default latest
IMAGE_NAME="${DOCKER_USERNAME}/flask-cicd-app"
ROLLBACK_IMAGE="${IMAGE_NAME}:${ROLLBACK_TAG}"

echo "============================================"
echo "ROLLBACK INITIATED"
echo "Rolling back to: ${ROLLBACK_IMAGE}"
echo "============================================"

# Rollback image pull karo
echo "Pulling rollback image..."
docker pull "${ROLLBACK_IMAGE}"

# Current running container dhundo
BLUE_RUNNING=$(docker ps --filter "name=flask-blue" --filter "status=running" -q)
GREEN_RUNNING=$(docker ps --filter "name=flask-green" --filter "status=running" -q)

# Rollback container naam aur port decide karo
if [ -n "$BLUE_RUNNING" ]; then
    ROLLBACK_CONTAINER="flask-green"
    ROLLBACK_PORT=5001
    OLD_CONTAINER="flask-blue"
    OLD_PORT=5000
else
    ROLLBACK_CONTAINER="flask-blue"
    ROLLBACK_PORT=5000
    OLD_CONTAINER="flask-green"
    OLD_PORT=5001
fi

# Purana rollback container hatao agar hai
docker rm -f "${ROLLBACK_CONTAINER}" 2>/dev/null || true

# Rollback container start karo
echo "Starting rollback container on port ${ROLLBACK_PORT}..."
docker run -d \
    --name "${ROLLBACK_CONTAINER}" \
    --restart unless-stopped \
    -p "${ROLLBACK_PORT}:5000" \
    -e "APP_VERSION=${ROLLBACK_TAG}" \
    "${ROLLBACK_IMAGE}"

# Health check
echo "Checking rollback container health..."
sleep 5
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:${ROLLBACK_PORT}/health")

if [ "$HTTP_STATUS" != "200" ]; then
    echo "ERROR: Rollback container is not healthy!"
    docker rm -f "${ROLLBACK_CONTAINER}"
    exit 1
fi

# Nginx switch karo
sudo sed -i "s/server 127.0.0.1:[0-9]*/server 127.0.0.1:${ROLLBACK_PORT}/" \
    /etc/nginx/sites-available/flask-app
sudo nginx -t
sudo systemctl reload nginx

# Broken container hatao
docker stop "${OLD_CONTAINER}" 2>/dev/null || true
docker rm "${OLD_CONTAINER}" 2>/dev/null || true

echo "============================================"
echo "ROLLBACK SUCCESSFUL!"
echo "Now running: ${ROLLBACK_IMAGE}"
echo "============================================"

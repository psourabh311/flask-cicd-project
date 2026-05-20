#!/bin/bash
# =============================================================
# Zero-Downtime Deployment Script
# Strategy: Blue-Green on a single EC2 instance
#
# Flow:
# 1. Detect which container is currently active (blue=5000 / green=5001)
# 2. Start the new container on the alternate port
# 3. Poll /health until the new container is ready
# 4. Update Nginx upstream to point to the new port
# 5. Stop and remove the old container
# =============================================================

# Exit immediately if any command fails.
# Without this, a failed health check would not stop the script,
# and Nginx could switch traffic to a broken container.
set -e

# If the script exits due to set -e, print a failure message.
# The old container remains running — no downtime occurs.
trap 'echo "DEPLOYMENT FAILED. Old container is still running. No downtime occurred."; exit 1' ERR

# Configuration
IMAGE_NAME="${DOCKER_USERNAME:-myusername}/flask-cicd-app"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

BLUE_PORT=5000
GREEN_PORT=5001
NGINX_CONF="/etc/nginx/sites-available/flask-app"

echo "============================================"
echo "Starting Zero-Downtime Deployment"
echo "Image: ${FULL_IMAGE}"
echo "============================================"

# Detect which container is currently active
BLUE_RUNNING=$(docker ps --filter "name=flask-blue" --filter "status=running" -q)
GREEN_RUNNING=$(docker ps --filter "name=flask-green" --filter "status=running" -q)

if [ -n "$BLUE_RUNNING" ]; then
    CURRENT_COLOR="blue"
    CURRENT_PORT=$BLUE_PORT
    NEW_COLOR="green"
    NEW_PORT=$GREEN_PORT
    CURRENT_CONTAINER="flask-blue"
    NEW_CONTAINER="flask-green"
elif [ -n "$GREEN_RUNNING" ]; then
    CURRENT_COLOR="green"
    CURRENT_PORT=$GREEN_PORT
    NEW_COLOR="blue"
    NEW_PORT=$BLUE_PORT
    CURRENT_CONTAINER="flask-green"
    NEW_CONTAINER="flask-blue"
else
    echo "No existing container found — this is the first deployment."
    CURRENT_COLOR="none"
    NEW_COLOR="blue"
    NEW_PORT=$BLUE_PORT
    NEW_CONTAINER="flask-blue"
    CURRENT_CONTAINER=""
fi

echo "Active: ${CURRENT_COLOR} | Deploying to: ${NEW_COLOR} (port ${NEW_PORT})"

# Pull the latest image from Docker Hub
echo "Pulling image: ${FULL_IMAGE}"
docker pull "${FULL_IMAGE}"

# Remove any stopped container with the same name
if docker ps -a --filter "name=${NEW_CONTAINER}" -q | grep -q .; then
    echo "Removing stopped container: ${NEW_CONTAINER}"
    docker rm -f "${NEW_CONTAINER}" || true
fi

# Start the new container on the alternate port
echo "Starting container: ${NEW_CONTAINER} on port ${NEW_PORT}"
docker run -d \
    --name "${NEW_CONTAINER}" \
    --restart unless-stopped \
    -p "${NEW_PORT}:5000" \
    -e "APP_VERSION=${IMAGE_TAG}" \
    "${FULL_IMAGE}"

# Poll /health until the new container is ready
# This is the core of zero-downtime — Nginx is not switched until
# the new container confirms it is ready to serve traffic.
echo "Waiting for new container to pass health check..."
MAX_RETRIES=30
RETRY_INTERVAL=2
RETRIES=0

until curl -sf "http://localhost:${NEW_PORT}/health" > /dev/null 2>&1; do
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "ERROR: Health check failed after ${MAX_RETRIES} attempts."
        echo "Removing unhealthy container: ${NEW_CONTAINER}"
        docker rm -f "${NEW_CONTAINER}"
        echo "Old container (${CURRENT_CONTAINER}) is still serving traffic."
        exit 1
    fi
    echo "Attempt ${RETRIES}/${MAX_RETRIES} — retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

echo "New container is healthy."

# Switch Nginx upstream to the new port
# nginx reload is graceful — in-flight requests are completed before switching
echo "Switching Nginx traffic to port ${NEW_PORT}..."
sudo sed -i "s/server 127\.0\.0\.1:[0-9]*/server 127.0.0.1:${NEW_PORT}/" "${NGINX_CONF}"
sudo nginx -t
sudo systemctl reload nginx
echo "Nginx switched to port ${NEW_PORT}."

# Stop and remove the old container
if [ -n "$CURRENT_CONTAINER" ] && [ "$CURRENT_COLOR" != "none" ]; then
    echo "Stopping old container: ${CURRENT_CONTAINER}"
    docker stop "${CURRENT_CONTAINER}"
    docker rm "${CURRENT_CONTAINER}"
fi

# Remove unused images to free disk space
echo "Pruning unused Docker images..."
docker image prune -f

echo "============================================"
echo "DEPLOYMENT SUCCESSFUL"
echo "Active container : ${NEW_CONTAINER}"
echo "Port             : ${NEW_PORT}"
echo "Image            : ${FULL_IMAGE}"
echo "============================================"

curl -s "http://localhost:${NEW_PORT}/version"
echo ""

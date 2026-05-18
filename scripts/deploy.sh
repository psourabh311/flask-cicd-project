#!/bin/bash
# =============================================================
# Zero-Downtime Deployment Script
# Strategy: Blue-Green on single EC2
# 
# Kaise kaam karta hai:
# 1. Pata karo kaunsa container chal raha hai (blue=5000 ya green=5001)
# 2. Doosre port pe naya container start karo
# 3. Health check karo — ready hone ka wait karo
# 4. Nginx config update karo naye port pe
# 5. Purana container band karo
# =============================================================

# set -e: Koi bhi command fail hote hi script band ho jaaye
# Bina iske agar health check fail ho toh script aage badhti rehti
# aur broken container pe traffic switch ho jaata — DANGEROUS
set -e

# trap: Agar script kisi bhi wajah se fail ho (set -e ki wajah se)
# toh ye cleanup function chalega
# Ye ensure karta hai ki failure pe purana container band nahi hoga
trap 'echo "DEPLOYMENT FAILED! Old container still running. No downtime occurred."; exit 1' ERR

# ============================================================
# CONFIGURATION — Ye values GitHub Actions se environment
# variables ke through aayengi
# ============================================================
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

# ============================================================
# STEP 1: Kaunsa container currently chal raha hai?
# ============================================================
# docker ps se check karo kaunsa container active hai
BLUE_RUNNING=$(docker ps --filter "name=flask-blue" --filter "status=running" -q)
GREEN_RUNNING=$(docker ps --filter "name=flask-green" --filter "status=running" -q)

if [ -n "$BLUE_RUNNING" ]; then
    # Blue chal raha hai, toh green pe deploy karenge
    CURRENT_COLOR="blue"
    CURRENT_PORT=$BLUE_PORT
    NEW_COLOR="green"
    NEW_PORT=$GREEN_PORT
    CURRENT_CONTAINER="flask-blue"
    NEW_CONTAINER="flask-green"
elif [ -n "$GREEN_RUNNING" ]; then
    # Green chal raha hai, toh blue pe deploy karenge
    CURRENT_COLOR="green"
    CURRENT_PORT=$GREEN_PORT
    NEW_COLOR="blue"
    NEW_PORT=$BLUE_PORT
    CURRENT_CONTAINER="flask-green"
    NEW_CONTAINER="flask-blue"
else
    # Pehli baar deploy ho raha hai — koi container nahi chal raha
    echo "First deployment — no existing container found"
    CURRENT_COLOR="none"
    NEW_COLOR="blue"
    NEW_PORT=$BLUE_PORT
    NEW_CONTAINER="flask-blue"
    CURRENT_CONTAINER=""
fi

echo "Current: ${CURRENT_COLOR} | Deploying to: ${NEW_COLOR} (port ${NEW_PORT})"

# ============================================================
# STEP 2: Latest image pull karo Docker Hub se
# ============================================================
echo "Pulling latest image: ${FULL_IMAGE}"
docker pull "${FULL_IMAGE}"

# ============================================================
# STEP 3: Agar purana same-name container hai toh hatao
# (stopped state me ho sakta hai)
# ============================================================
if docker ps -a --filter "name=${NEW_CONTAINER}" -q | grep -q .; then
    echo "Removing old stopped container: ${NEW_CONTAINER}"
    docker rm -f "${NEW_CONTAINER}" || true
fi

# ============================================================
# STEP 4: Naya container start karo NEW_PORT pe
# ============================================================
echo "Starting new container: ${NEW_CONTAINER} on port ${NEW_PORT}"
docker run -d \
    --name "${NEW_CONTAINER}" \
    --restart unless-stopped \
    -p "${NEW_PORT}:5000" \
    -e "APP_VERSION=${IMAGE_TAG}" \
    "${FULL_IMAGE}"

# ============================================================
# STEP 5: Health check — container ready hone ka wait karo
# Ye SABSE IMPORTANT step hai zero-downtime ke liye
# ============================================================
echo "Waiting for new container to be healthy..."
MAX_RETRIES=30      # 30 baar try karo
RETRY_INTERVAL=2    # har 2 second me
RETRIES=0

until curl -sf "http://localhost:${NEW_PORT}/health" > /dev/null 2>&1; do
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "ERROR: Health check failed after ${MAX_RETRIES} attempts!"
        echo "New container is NOT healthy. Removing it..."
        docker rm -f "${NEW_CONTAINER}"
        echo "Old container (${CURRENT_CONTAINER}) is still running. No downtime!"
        exit 1  # trap chalega yahan
    fi
    echo "Health check attempt ${RETRIES}/${MAX_RETRIES} — waiting..."
    sleep $RETRY_INTERVAL
done

echo "New container is HEALTHY!"

# ============================================================
# STEP 6: Nginx config update karo — traffic switch karo
# sed command se port replace karo nginx config me
# ============================================================
echo "Switching Nginx traffic to port ${NEW_PORT}..."

# Nginx config me upstream port update karo
sudo sed -i "s/server 127.0.0.1:[0-9]*/server 127.0.0.1:${NEW_PORT}/" "${NGINX_CONF}"

# Nginx config test karo — galat config se Nginx crash ho sakta hai
sudo nginx -t

# Nginx reload karo — reload graceful hota hai, restart nahi
# Reload me existing connections drop nahi hote — TRUE zero downtime
sudo systemctl reload nginx

echo "Nginx switched to port ${NEW_PORT}"

# ============================================================
# STEP 7: Purana container band karo
# Ye tabhi hoga jab naya container healthy ho aur Nginx switch ho chuka ho
# ============================================================
if [ -n "$CURRENT_CONTAINER" ] && [ "$CURRENT_COLOR" != "none" ]; then
    echo "Stopping old container: ${CURRENT_CONTAINER}"
    docker stop "${CURRENT_CONTAINER}"
    docker rm "${CURRENT_CONTAINER}"
    echo "Old container removed"
fi

# ============================================================
# STEP 8: Purani images clean karo (disk space bachao)
# ============================================================
echo "Cleaning up old Docker images..."
docker image prune -f

echo "============================================"
echo "DEPLOYMENT SUCCESSFUL!"
echo "Active container: ${NEW_CONTAINER} on port ${NEW_PORT}"
echo "Image deployed: ${FULL_IMAGE}"
echo "============================================"

# Verify karo
curl -s "http://localhost:${NEW_PORT}/version"
echo ""

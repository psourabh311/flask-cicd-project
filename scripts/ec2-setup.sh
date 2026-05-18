#!/bin/bash
# =============================================================
# EC2 Initial Setup Script
# Ye script SIRF EK BAAR chalana hai — naya EC2 launch karne ke baad
# SSH karke manually run karo: bash ec2-setup.sh
# =============================================================

set -e

echo "============================================"
echo "EC2 Initial Setup for Flask CI/CD Project"
echo "============================================"

# ============================================================
# STEP 1: System update
# ============================================================
echo "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# ============================================================
# STEP 2: Docker install karo
# Official Docker repository se install karo — apt ka docker.io
# outdated hota hai
# ============================================================
echo "Installing Docker..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Docker ka official GPG key add karo
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Docker repository add karo
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# ubuntu user ko docker group me add karo (sudo ke bina docker chalane ke liye)
sudo usermod -aG docker ubuntu

# Docker service enable karo (reboot pe auto-start)
sudo systemctl enable docker
sudo systemctl start docker

echo "Docker installed: $(docker --version)"

# ============================================================
# STEP 3: Nginx install karo
# ============================================================
echo "Installing Nginx..."
sudo apt-get install -y nginx

# Nginx enable karo
sudo systemctl enable nginx
sudo systemctl start nginx

echo "Nginx installed: $(nginx -v 2>&1)"

# ============================================================
# STEP 4: Nginx config setup karo
# ============================================================
echo "Configuring Nginx..."

# Default Nginx site disable karo
sudo rm -f /etc/nginx/sites-enabled/default

# Flask app config create karo
sudo tee /etc/nginx/sites-available/flask-app > /dev/null << 'NGINX_CONF'
upstream flask_app {
    server 127.0.0.1:5000;
}

server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/flask_access.log;
    error_log /var/log/nginx/flask_error.log;

    client_max_body_size 10M;

    location / {
        proxy_pass http://flask_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        access_log off;
        proxy_pass http://flask_app;
        proxy_set_header Host $host;
    }
}
NGINX_CONF

# Config enable karo
sudo ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/

# Config test karo
sudo nginx -t

# Nginx reload karo
sudo systemctl reload nginx

echo "Nginx configured successfully"

# ============================================================
# STEP 5: deploy.sh EC2 pe copy karo aur executable banao
# GitHub Actions is script ko call karega
# ============================================================
echo "Setting up deploy script..."

# deploy.sh content yahan paste karo ya scp se copy karo
# GitHub Actions me ye script already /home/ubuntu/deploy.sh pe hogi
# (hum ise repo se copy karenge)

sudo chmod +x /home/ubuntu/deploy.sh 2>/dev/null || \
    echo "Note: Copy deploy.sh to /home/ubuntu/deploy.sh manually or via CI/CD"

# ============================================================
# STEP 6: Sudoers me nginx commands add karo
# deploy.sh ko nginx reload karne ke liye sudo chahiye
# Lekin GitHub Actions ubuntu user se SSH karta hai
# Ye config ubuntu user ko password ke bina nginx commands chalane deta hai
# ============================================================
echo "Configuring sudoers for nginx..."
echo "ubuntu ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /bin/systemctl reload nginx, /bin/systemctl restart nginx, /usr/bin/sed" | \
    sudo tee /etc/sudoers.d/nginx-deploy

sudo chmod 440 /etc/sudoers.d/nginx-deploy

# ============================================================
# STEP 7: UFW Firewall setup (optional but recommended)
# ============================================================
echo "Configuring firewall..."
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS (future use)
# sudo ufw enable        # Uncomment karo agar enable karna hai

echo "============================================"
echo "EC2 Setup Complete!"
echo "Next steps:"
echo "1. Copy deploy.sh to /home/ubuntu/deploy.sh"
echo "2. Add GitHub Secrets (DOCKER_USERNAME, DOCKER_PASSWORD, SSH_PRIVATE_KEY, EC2_HOST)"
echo "3. Push code to main branch"
echo "============================================"

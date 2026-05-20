#!/bin/bash
# =============================================================
# EC2 Initial Setup Script
# Run this once after launching a new EC2 instance.
# Installs Docker, Nginx, and configures the deployment environment.
#
# Usage:
#   scp -i key.pem ec2-setup.sh ubuntu@<EC2-IP>:~/
#   ssh -i key.pem ubuntu@<EC2-IP>
#   bash ec2-setup.sh
# =============================================================

set -e

echo "============================================"
echo "EC2 Initial Setup"
echo "============================================"

# System update
echo "Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install Docker from the official Docker repository
echo "Installing Docker..."
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker

echo "Docker installed: $(docker --version)"

# Install Nginx
echo "Installing Nginx..."
sudo apt-get install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

echo "Nginx installed: $(nginx -v 2>&1)"

# Configure Nginx reverse proxy
echo "Configuring Nginx..."
sudo rm -f /etc/nginx/sites-enabled/default

sudo tee /etc/nginx/sites-available/flask-app > /dev/null << 'NGINX_CONF'
upstream flask_app {
    server 127.0.0.1:5000;
}

server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/flask_access.log;
    error_log  /var/log/nginx/flask_error.log;

    client_max_body_size 10M;

    location / {
        proxy_pass         http://flask_app;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout    60s;
    }

    location /health {
        access_log off;
        proxy_pass       http://flask_app;
        proxy_set_header Host $host;
    }
}
NGINX_CONF

sudo ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

echo "Nginx configured."

# Allow the ubuntu user to reload Nginx without a password
# Required by deploy.sh which runs as ubuntu via SSH
echo "Configuring sudoers for Nginx reload..."
echo "ubuntu ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /bin/systemctl reload nginx, /bin/systemctl restart nginx, /usr/bin/sed" | \
    sudo tee /etc/sudoers.d/nginx-deploy
sudo chmod 440 /etc/sudoers.d/nginx-deploy

# Make deploy.sh executable if it was already copied
chmod +x /home/ubuntu/deploy.sh 2>/dev/null || true

# Firewall rules
echo "Configuring firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

echo "============================================"
echo "Setup complete."
echo ""
echo "Next steps:"
echo "  1. Ensure deploy.sh is at /home/ubuntu/deploy.sh"
echo "  2. Add GitHub Secrets: DOCKER_USERNAME, DOCKER_PASSWORD,"
echo "     SSH_PRIVATE_KEY, EC2_HOST"
echo "  3. Push to main branch to trigger the pipeline"
echo "============================================"

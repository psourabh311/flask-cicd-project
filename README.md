# Flask CI/CD Project — Production-Ready Pipeline

## Architecture
```
GitHub Push → GitHub Actions CI/CD → Docker Hub → EC2 (Nginx → Gunicorn → Flask)
```

## Zero-Downtime Strategy
Blue-Green deployment on single EC2:
1. New container starts on alternate port
2. Health check passes
3. Nginx switches traffic
4. Old container stops

## GitHub Secrets Required
| Secret | Value |
|--------|-------|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub password or access token |
| `SSH_PRIVATE_KEY` | Contents of EC2 .pem file |
| `EC2_HOST` | EC2 public IP address |

## Setup Steps

### 1. Local Development
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app/app.py
```

### 2. Docker Local Test
```bash
docker build -t flask-cicd-app:local .
docker run -p 5000:5000 flask-cicd-app:local
curl http://localhost:5000/health
```

### 3. EC2 Setup (One-time)
```bash
# EC2 pe SSH karo
ssh -i your-key.pem ubuntu@<EC2-IP>

# Setup script copy karo aur chalao
scp -i your-key.pem scripts/ec2-setup.sh ubuntu@<EC2-IP>:~/
scp -i your-key.pem scripts/deploy.sh ubuntu@<EC2-IP>:~/
bash ec2-setup.sh
```

### 4. GitHub Secrets Add Karo
GitHub repo → Settings → Secrets and variables → Actions → New repository secret

### 5. Deploy
```bash
git push origin main
# GitHub Actions automatically deploy karega
```

## Rollback
```bash
# EC2 pe SSH karo
export DOCKER_USERNAME=your-dockerhub-username
bash rollback.sh <previous-git-sha>
```

## Endpoints
- `GET /` — App status
- `GET /health` — Health check (200 = healthy)
- `GET /version` — Deployed version

## EC2 Security Group Rules
| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP only | SSH |
| 80 | TCP | 0.0.0.0/0 | HTTP |
| 443 | TCP | 0.0.0.0/0 | HTTPS (future) |

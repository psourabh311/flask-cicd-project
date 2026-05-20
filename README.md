# Flask CI/CD Pipeline — Production Deployment on AWS EC2

A production-grade CI/CD pipeline that automatically tests, builds, and deploys a containerized Flask application to AWS EC2 with zero downtime on every push to the main branch.

## Architecture

```
GitHub Push → GitHub Actions (CI/CD) → Docker Hub → AWS EC2 (Nginx → Gunicorn → Flask)
```

## Zero-Downtime Strategy

Blue-Green deployment on a single EC2 instance:

1. New container starts on the alternate port (5000 or 5001)
2. `deploy.sh` polls `/health` until the container is ready
3. Nginx upstream is updated — traffic switches instantly
4. Old container is stopped

No requests are dropped during deployment.

## Project Structure

```
flask-cicd-project/
├── app/
│   ├── app.py               # Flask application
│   ├── __init__.py
│   └── tests/
│       └── test_app.py      # Pytest test suite
├── nginx/
│   └── nginx.conf           # Reverse proxy configuration
├── scripts/
│   ├── deploy.sh            # Zero-downtime deployment script
│   ├── rollback.sh          # Rollback to a previous image version
│   ├── ec2-setup.sh         # One-time EC2 provisioning script
│   └── flask-app.service    # Systemd service definition
├── .github/
│   └── workflows/
│       └── deploy.yml       # GitHub Actions CI/CD pipeline
├── Dockerfile               # Multi-stage Docker build
├── .dockerignore
└── requirements.txt
```

## GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub access token |
| `SSH_PRIVATE_KEY` | Private key for EC2 SSH access |
| `EC2_HOST` | EC2 public IP address |

## Setup

### 1. Local Development

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app/app.py
```

### 2. Local Docker Test

```bash
docker build -t flask-cicd-app:local .
docker run -p 5000:5000 flask-cicd-app:local
curl http://localhost:5000/health
```

### 3. EC2 Setup (one-time)

```bash
scp -i your-key.pem scripts/ec2-setup.sh ubuntu@<EC2-IP>:~/
scp -i your-key.pem scripts/deploy.sh ubuntu@<EC2-IP>:~/
ssh -i your-key.pem ubuntu@<EC2-IP>
bash ec2-setup.sh
```

### 4. Add GitHub Secrets

GitHub repo → Settings → Secrets and variables → Actions

### 5. Deploy

```bash
git push origin main
```

GitHub Actions handles the rest automatically.

## Rollback

```bash
ssh -i your-key.pem ubuntu@<EC2-IP>
export DOCKER_USERNAME=your-dockerhub-username
bash rollback.sh <git-sha>
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | Application status |
| `GET /health` | Health check — returns 200 when ready |
| `GET /version` | Returns the deployed git SHA |

## EC2 Security Group

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH access |
| 80 | TCP | 0.0.0.0/0 | HTTP traffic |
| 443 | TCP | 0.0.0.0/0 | HTTPS (future) |

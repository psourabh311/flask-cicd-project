import os
import logging
from flask import Flask, jsonify

# Configure structured logging for production
# Logs are consumed by Docker and forwarded to CloudWatch or any log aggregator
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# APP_VERSION is injected as an environment variable during deployment
# The CI/CD pipeline sets this to the git commit SHA
# This allows verifying exactly which commit is running in production
APP_VERSION = os.environ.get('APP_VERSION', 'v1.0.0')


@app.route('/')
def home():
    logger.info("Home endpoint called")
    return jsonify({
        'message': 'Flask CI/CD App is running! - Deployed via GitHub Actions',
        'version': APP_VERSION,
        'status': 'success'
    }), 200


@app.route('/health')
def health():
    # Health check endpoint — critical for zero-downtime deployment
    #
    # How it is used in the deployment flow:
    # 1. New container starts on an alternate port
    # 2. deploy.sh polls this endpoint every 2 seconds
    # 3. Only after receiving HTTP 200 does Nginx switch traffic
    # 4. Old container is stopped after the switch
    #
    # This guarantees no traffic is sent to a container that is not ready
    logger.info("Health check called")
    return jsonify({
        'status': 'healthy',
        'version': APP_VERSION
    }), 200


@app.route('/version')
def version():
    # Used to verify which version is live after a deployment
    # curl http://<server>/version returns the deployed git SHA
    return jsonify({'version': APP_VERSION}), 200


if __name__ == '__main__':
    # host='0.0.0.0' is required inside Docker
    # Without it the app binds to 127.0.0.1 which is only reachable
    # inside the container — port mapping would not work
    app.run(host='0.0.0.0', port=5000, debug=False)

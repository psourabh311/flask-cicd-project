import os
import logging
from flask import Flask, jsonify

# Logging setup — production me logs structured hone chahiye
# Ye logs Docker ke through CloudWatch ya any log aggregator me jaate hain
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# APP_VERSION env variable se aata hai
# CI/CD pipeline me hum git commit SHA inject karenge yahan
# Isse pata chalega ki exactly kaunsa commit deploy hua hai
APP_VERSION = os.environ.get('APP_VERSION', 'v1.0.0')


@app.route('/')
def home():
    logger.info("Home endpoint hit")
    return jsonify({
        'message': 'Hello Sourabh! Your Flask CI/CD App is running! - Deployed via GitHub Actions 🚀',
        'version': APP_VERSION,
        'status': 'success'
    }), 200


@app.route('/health')
def health():
    # YE ENDPOINT SABSE IMPORTANT HAI
    # Zero-downtime deployment me kya hota hai:
    # 1. Naya container start karo
    # 2. /health ko curl karo — agar 200 aaya toh container ready hai
    # 3. Tabhi Nginx ka traffic naye container pe switch karo
    # 4. Purana container band karo
    # Agar /health nahi hota toh hume pata nahi chalta container ready hai ya nahi
    # Users ko errors milte jab tak container fully start nahi hota
    logger.info("Health check hit")
    return jsonify({
        'status': 'healthy',
        'version': APP_VERSION
    }), 200


@app.route('/version')
def version():
    # Deployment ke baad verify karne ke liye
    # curl http://your-server/version se pata chalega kaunsa version live hai
    return jsonify({'version': APP_VERSION}), 200


if __name__ == '__main__':
    # host='0.0.0.0' — Docker ke liye ZAROORI hai
    # Agar '127.0.0.1' diya toh container ke bahar se access nahi hoga
    # kyunki Docker container ka apna network namespace hota hai
    app.run(host='0.0.0.0', port=5000, debug=False)

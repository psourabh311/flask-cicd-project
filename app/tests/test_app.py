import sys
import os
import pytest

# app directory ko path me add karo
# GitHub Actions me working directory project root hoti hai
# isliye 'app' folder directly importable hona chahiye
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# app.py file se 'app' variable (Flask instance) import karo
# 'app.app' = app folder ka app.py file ka app variable
from app import app as flask_app


@pytest.fixture
def client():
    """Har test ke liye ek fresh test client milega"""
    flask_app.config['TESTING'] = True
    with flask_app.test_client() as client:
        yield client


def test_home_endpoint(client):
    response = client.get('/')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'success'
    assert 'version' in data


def test_health_endpoint(client):
    response = client.get('/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'healthy'


def test_version_endpoint(client):
    response = client.get('/version')
    assert response.status_code == 200
    data = response.get_json()
    assert 'version' in data

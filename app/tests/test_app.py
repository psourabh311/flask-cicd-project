import sys
import os
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app import app as flask_app


@pytest.fixture
def client():
    """Provide a test client for each test case."""
    flask_app.config['TESTING'] = True
    with flask_app.test_client() as client:
        yield client


def test_home_endpoint(client):
    """Verify home endpoint returns 200 with expected JSON structure."""
    response = client.get('/')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'success'
    assert 'version' in data


def test_health_endpoint(client):
    """
    Verify health endpoint returns 200 with healthy status.
    This test is critical — if it fails, the CI pipeline blocks deployment.
    The deploy.sh script relies on this endpoint for zero-downtime switching.
    """
    response = client.get('/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'healthy'


def test_version_endpoint(client):
    """Verify version endpoint returns the version field."""
    response = client.get('/version')
    assert response.status_code == 200
    data = response.get_json()
    assert 'version' in data

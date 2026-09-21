import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.config import settings

# Initialize the automated test client runner mapped to our app engine
client = TestClient(app)

# -------------------------------------------------------------------------
# SECURITY GATE TEST SUITE
# -------------------------------------------------------------------------

def test_endpoint_denies_access_without_security_token():
    """
    ARRANGE / ACT: Fire a request with missing authorization headers.
    """
    response = client.post("/api/v1/transform", json={})
    
    # ASSERT: The security guard must drop the traffic with an explicit 401
    assert response.status_code == 401
    assert response.json()["detail"] == "Access Denied: Invalid Security Credentials."


def test_endpoint_denies_access_with_incorrect_security_token():
    """
    ARRANGE / ACT: Fire a request with an invalid malformed header key token.
    """
    headers = {"X-EAI-TOKEN": "WRONG-TOKEN-123"}
    response = client.post("/api/v1/transform", headers=headers, json={})
    
    # ASSERT: Connection must be blocked
    assert response.status_code == 401


# -------------------------------------------------------------------------
# VALIDATION & SCHEMA CORE CONTRACT TEST SUITE
# -------------------------------------------------------------------------

def test_endpoint_accepts_and_processes_valid_telemetry_payload():
    """
    ARRANGE: Construct a perfectly valid mock JSON transaction payload.
    """
    headers = {"X-EAI-TOKEN": settings.API_SECURITY_TOKEN}
    valid_payload = {
        "meter_id": "MTR-2026-TEST",
        "grid_zone": "WEST-ZONE-ALPHA",
        "readings": [
            {"timestamp": "2026-07-28T12:00:00Z", "kwh_value": 10.50, "voltage": 220.0},
            {"timestamp": "2026-07-28T12:15:00Z", "kwh_value": 15.50, "voltage": 218.5}
        ]
    }

    # ACT: Dispatch the payload across our simulated network interface
    response = client.post("/api/v1/transform", headers=headers, json=valid_payload)

    # ASSERT: Must return a 200 OK along with your computed business analytics summary
    assert response.status_code == 200
    data = response.json()
    assert data["metadata"]["processed_asset"] == "MTR-2026-TEST"
    assert data["analytics_summary"]["cumulative_kwh"] == 26.0
    assert data["analytics_summary"]["average_load_per_interval"] == 13.0


def test_endpoint_rejects_payload_violating_numerical_business_constraints():
    """
    ARRANGE: Construct a broken payload that violates the positive consumption rule (gt=0.0).
    """
    headers = {"X-EAI-TOKEN": settings.API_SECURITY_TOKEN}
    invalid_payload = {
        "meter_id": "MTR-2026-TEST",
        "grid_zone": "WEST-ZONE-ALPHA",
        "readings": [
            {"timestamp": "2026-07-28T12:00:00Z", "kwh_value": -5.0, "voltage": 220.0} # Violating field
        ]
    }

    # ACT: Send data into the validation gate
    response = client.post("/api/v1/transform", headers=headers, json=invalid_payload)

    # ASSERT: The Pydantic contract layer must block execution with a 422 error
    assert response.status_code == 422

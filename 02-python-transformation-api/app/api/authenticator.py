import logging
from fastapi import HTTPException, Security, status
from fastapi.security.api_key import APIKeyHeader
from app.config import settings

# Configure structured logging for the API module
logger = logging.getLogger(__name__)

# Declare the specific header key name the system will look for in network packets
API_KEY_NAME = "X-EAI-TOKEN"
api_key_header_guard = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

# -------------------------------------------------------------------------
# SECURITY INTERCEPTOR FUNCTION
# -------------------------------------------------------------------------
def authenticate_request(api_key: str = Security(api_key_header_guard)):
    """
    Validates inbound network header keys against our centralized secure token contract.
    """
    if api_key == settings.API_SECURITY_TOKEN:
        return api_key
    logger.warning("Security Breach Attempt: Unauthorized connection dropped due to missing or invalid token credentials.")
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Access Denied: Invalid Security Credentials."
    )


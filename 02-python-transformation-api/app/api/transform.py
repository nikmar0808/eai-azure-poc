import logging
from fastapi import APIRouter, Depends, HTTPException, Header, Security, status
from fastapi.security.api_key import APIKeyHeader
from sqlalchemy.orm import Session
import dateutil.parser

# --- DATABASE INFRASTRUCTURE IMPORTS ---
from app.database.connection import get_db_session
from app.database.models import SmartMeterIntervalRecord
from app.schemas.meter import SmartMeterPayload as SmartMeterPayloadSchema
from app.config import settings

# Configure structured logging for the API module
logger = logging.getLogger(__name__)

# Declare the specific header key name the system will look for in network packets
API_KEY_NAME = "X-EAI-TOKEN"
api_key_header_guard = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

# FastAPI is built natively on top of the OpenAPI Specification (formerly known as Swagger).
# Because we explicitly declared our data contracts using Pydantic and type hints,
# the FastAPI engine dynamically analyzes your code structure at startup.
# It maps out your routers, types, and constraints, compiles them into a standardized JSON configuration file behind the scenes, and
# hosts an embedded web page to read that file.
# APIRouter acts like a mini-ESB router that attaches to the main engine later
# Instead of cluttering your main application file, an APIRouter lets you build isolated groups of endpoints.
# The prefix="/api/v1" means every endpoint inside this file will automatically start with /api/v1 (e.g., /api/v1/transform).
# This is how professional developers version their APIs so they don't break older client integrations when upgrading software.
router = APIRouter(prefix="/api/v1", tags=["Ingestion & Transformation"])

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

# -------------------------------------------------------------------------
# SECURED INGESTION ROUTE
# -------------------------------------------------------------------------
# The @ symbol is called a Decorator. Think of it as wrapping a specific function with extra powers.
# Here, it tells FastAPI: "Listen for incoming HTTP POST requests hitting the /transform path, and
# route that network traffic directly into the function below."
@router.post("/transform", status_code=status.HTTP_200_OK)
# This is the critical link. By typing the incoming payload variable as your Pydantic SmartMeterPayload class,
# FastAPI automatically performs three background steps the moment a request hits the server:
# 1. It captures the raw incoming JSON text stream over the network.
# 2. It parses that text and validates it against every single rule we set up in meter.py
# (like checking if types match and numbers are positive).
# 3. If valid, it hands your function a clean, fully populated Python object ready for use.
# If invalid, it completely drops the connection and generates that detailed error report you saw in Swagger.
async def validate_and_transform_payload(
    payload: SmartMeterPayloadSchema,                 # This MUST match your Pydantic Schema model type
    authenticated: str = Depends(authenticate_request),
    db: Session = Depends(get_db_session)
):
    try:
        # 1. Loop and stage using 'record' to prevent shadowing 'payload'
        for record in payload.readings:
            db_record = SmartMeterIntervalRecord(
                meter_id=payload.meter_id,
                grid_zone=payload.grid_zone,
                timestamp=record.timestamp,
                kwh_value=record.kwh_value,
                voltage=record.voltage
            )
            db.add(db_record)
        
        # 2. Physically flush and write the transactions to the PostgreSQL container
        db.commit() 
        
        # 3. Calculate metrics using a clean list comprehension name 'item'
        total_intervals = len(payload.readings)
        total_kwh = sum(item.kwh_value for item in payload.readings)
        
        return {
            "message": "Payload schema validated and saved successfully to grid warehouse",
            "metadata": {
                "processed_asset": payload.meter_id,
                "regional_zone": payload.grid_zone,
                "intervals_saved": total_intervals
            },
            "analytics_summary": {
                "cumulative_kwh": total_kwh,
                "average_load_per_interval": (total_kwh / total_intervals) if total_intervals > 0 else 0.0
            }
        }
    except Exception as e:
        db.rollback()
        logger.error(f"Data tier exception encountered: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Database persistent write failure: {str(e)}"
        )

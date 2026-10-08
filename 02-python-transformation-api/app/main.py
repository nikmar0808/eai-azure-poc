import os
if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor
    configure_azure_monitor()
    from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
    SQLAlchemyInstrumentor().instrument()

import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api.transform import router as transform_router
from app.api.readings import router as readings_router

from app.config import settings

# --- DATABASE ENGINE IMPORTS ---
from app.database.connection import engine
from app.database.models import Base

# Force table generation inside the PostgreSQL container at system startup
Base.metadata.create_all(bind=engine)

# Configure unified structured logging for the application lifecycle
LOG_FORMAT = "%(asctime)s - %(levelname)s - [%(name)s] - %(message)s"
LOG_LEVEL = getattr(logging, os.getenv("LOG_LEVEL", "INFO").upper(), logging.INFO)

root_logger = logging.getLogger()
root_logger.setLevel(LOG_LEVEL)
# basicConfig() silently does nothing when the root logger already has a handler, and the tracing
# library may add one first. A console handler is therefore added explicitly if none exists.
if not any(type(h) is logging.StreamHandler for h in root_logger.handlers):
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(logging.Formatter(LOG_FORMAT))
    root_logger.addHandler(console_handler)

logger = logging.getLogger(__name__)

# --- LIFESPAN EVENT HANDLER ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Triggers an audit log entry on system initialization to verify configuration states.
    Replaces the deprecated @app.on_event("startup") pattern.
    """
    logger.info("Initializing Enterprise Transformation Service Core...")
    logger.info(f"Target Configuration Locked -> Title: {settings.APP_TITLE} | Version: {settings.APP_VERSION}")
    
    yield  # The application serves requests while frozen here
    
    # Optional: Place any shutdown/cleanup logic (e.g., closing DB pools) here
    logger.info("Shutting down Enterprise Transformation Service Core...")

# Initialize the core FastAPI Application Engine using centralized configuration settings
app = FastAPI(
    title=settings.APP_TITLE,
    description="High-speed ingestion and validation engine for grid smart-meter telemetry.",
    version=settings.APP_VERSION,
    lifespan=lifespan  # Register the lifespan context manager
)

# Base health-check endpoint
@app.get("/")
def read_root():
    return {
        "status": "operational",
        "engine": "FastAPI",
        "version": settings.APP_VERSION
    }
# health-check for the database
@app.get("/health")
def health_check():
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        db_status = "UP"
    except Exception:
        db_status = "DOWN"

    overall_status = "UP" if db_status == "UP" else "DOWN"
    status_code = 200 if db_status == "UP" else 503
    return JSONResponse(
        status_code=status_code,
        content={"status": overall_status, "database": db_status},
    )

# Register the decoupled enterprise ingestion routers
app.include_router(transform_router)
app.include_router(readings_router)
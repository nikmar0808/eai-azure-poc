import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.api.transform import router as transform_router
from app.config import settings

# --- DATABASE ENGINE IMPORTS ---
from app.database.connection import engine
from app.database.models import Base

# Force table generation inside the PostgreSQL container at system startup
Base.metadata.create_all(bind=engine)

# Configure unified structured logging for the application lifecycle
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - [%(name)s] - %(message)s"
)
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

# Register the decoupled enterprise ingestion routers
app.include_router(transform_router)

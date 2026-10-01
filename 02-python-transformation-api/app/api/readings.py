import logging
from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database.connection import get_db_session
from app.database.models import SmartMeterIntervalRecord
from app.api.authenticator import authenticate_request

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1", tags=["Readings"])

@router.get("/meters/{meter_id}/readings")
def get_recent_readings(
    meter_id: str,
    limit: int = Query(default=20, ge=1, le=100),
    authenticated: str = Depends(authenticate_request),
    db: Session = Depends(get_db_session),
):
    stmt = (
        select(SmartMeterIntervalRecord)
        .where(SmartMeterIntervalRecord.meter_id == meter_id)
        .order_by(SmartMeterIntervalRecord.timestamp.desc())
        .limit(limit)
    )
    rows = db.execute(stmt).scalars().all()

    return {
        "meter_id": meter_id,
        "count": len(rows),
        "readings": [
            {
                "timestamp": row.timestamp.isoformat(),
                "kwh_value": row.kwh_value,
                "voltage": row.voltage,
            }
            for row in rows
        ],
    }

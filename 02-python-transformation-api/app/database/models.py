from sqlalchemy import Column, Integer, String, Float, DateTime
from app.database.connection import Base
import datetime
# zoneinfo import ZoneInfo  --is available in Python 3.9 and later. If you're using an earlier version, you can use the backports.zoneinfo package.

class SmartMeterIntervalRecord(Base):
    """
    Relational schema map representing our persistent system of record.
    """
    __tablename__ = "smart_meter_intervals"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    meter_id = Column(String(20), index=True, nullable=False)
    grid_zone = Column(String(50), nullable=False)
    timestamp = Column(DateTime, nullable=False)
    kwh_value = Column(Float, nullable=False)
    voltage = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


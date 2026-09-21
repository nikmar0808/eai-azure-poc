import logging
import os
import xml.etree.ElementTree as ET
from pydantic import ValidationError
from app.schemas.meter import SmartMeterPayload, MeterReading

# Configure structured logging for the core service module
logger = logging.getLogger(__name__)

class LegacyXMLTransformer:
    """
    Translates legacy XML telemetry payloads into schema-validated JSON/Python data structures.
    """
    
    def __init__(self, file_path: str):
        self.file_path = file_path

    def execute_transformation(self) -> SmartMeterPayload:
        """
        Parses raw text files from disk, remaps legacy tags, and pushes data through Pydantic contracts.
        """
        # Architectural Guard: Verify file existence before running heavy parsing routines
        if not os.path.exists(self.file_path):
            logger.error(f"File ingestion failure: Path target not found at {self.file_path}")
            raise FileNotFoundError(f"Missing resource: {self.file_path}")

        try:
            logger.info(f"Initializing parsing routine for XML source: {self.file_path}")
            
            # Step 1: Read and parse the XML file into an in-memory element tree
            tree = ET.parse(self.file_path)
            root = tree.getroot()

            # Step 2: Extract Root Level Legacy Meta-Data Tag Values
            meter_id = root.find("AssetMetadataCode").text
            grid_zone = root.find("OperationalZone").text

            logger.info(f"Successfully isolated telemetry header metadata for Asset: {meter_id}")

            # Step 3: Loop through nested array collections and map metrics
            parsed_readings = []
            readings_node = root.find("IntervalReadings")
            
            for reading_element in readings_node.findall("Reading"):
                raw_time = reading_element.find("TimePoint").text
                raw_kwh = float(reading_element.find("KwhValue").text)
                
                # Handle optional fields safely
                voltage_node = reading_element.find("VoltageCheck")
                raw_voltage = float(voltage_node.text) if voltage_node is not None else None

                # Construct an individual MeterReading instance
                reading_record = MeterReading(
                    timestamp=raw_time,
                    kwh_value=raw_kwh,
                    voltage=raw_voltage
                )
                parsed_readings.append(reading_record)

            # Step 4: Assemble the complete structural boundary payload contract
            final_payload = SmartMeterPayload(
                meter_id=meter_id,
                grid_zone=grid_zone,
                readings=parsed_readings
            )

            logger.info("Successfully executed data transformation lifecycle. Structure matches contract boundaries.")
            return final_payload

        except ET.ParseError as xml_err:
            logger.error(f"Fatal XML structural malformation intercepted: {str(xml_err)}")
            raise ValueError(f"Invalid XML document formatting: {str(xml_err)}")
            
        except ValidationError as pydantic_err:
            logger.error(f"Inbound business data constraint violation caught during translation: {pydantic_err.json()}")
            raise

        except Exception as err:
            logger.error(f"Unexpected enterprise integration mapping breakdown error: {str(err)}")
            raise

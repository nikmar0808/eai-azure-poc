# C4 — Level 2: Container

Shows the two independently deployable units inside the system boundary
from Level 1, and how they talk to each other. "Container" here is the
C4 sense (a separately runnable unit) - not specific to Docker.

```mermaid
C4Container
    title Container — Smart Meter Ingestion System

    Person(operator, "Operator / Client")

    Container_Boundary(eai, "Smart Meter Ingestion System") {
        Container(gateway, "java-gateway", "Spring Boot", "Validates and forwards requests; port 8081, public")
        Container(validator, "python-validator", "FastAPI", "Applies stricter validation, transforms, persists; port 8082, internal-only")
    }
    
    ContainerDb_Ext(postgres, "PostgreSQL", "smart_meter_warehouse")

    Rel(operator, gateway, "POST /api/v1/ingest/bulk", "HTTPS/JSON")
    Rel(gateway, validator, "POST /api/v1/transform", "HTTP, header X-EAI-Token")
    Rel(validator, postgres, "Writes SmartMeterIntervalRecord rows", "SQL")
```
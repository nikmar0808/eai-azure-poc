# C4 — Level 1: System Context

Shows the Smart Meter Ingestion system as a single box, and who or what
outside it depends on it or is depended on by it. No internal structure
is shown at this level — that is Level 2, below.

```mermaid
C4Context
    title System Context — Smart Meter Ingestion

    Person(operator, "Operator / Client", "Sends meter readings via HTTP")

    System(eai, "Smart Meter Ingestion System", "Validates, transforms and stores smart-meter telemetry")

    SystemDb_Ext(postgres, "PostgreSQL", "Stores validated readings. External to this system's own deployment unit.")

    Rel(operator, eai, "POSTs readings to", "HTTPS/JSON")
    Rel(eai, postgres, "Writes validated readings to", "SQL")
```

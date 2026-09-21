import time
import random
import datetime
import concurrent.futures
import json
import httpx

# Target Configuration - Points directly to the exposed Java Inbound Gateway
TARGET_INGEST_URL = "http://https://wu7br131a6.execute-api.ap-south-1.amazonaws.com/api/v1/ingest/bulk" # For local testing, ensure the Java gateway is running and accessible
# TARGET_INGEST_URL = "http://localhost:8081/api/v1/ingest/bulk" # For using API Gateway URL, uncomment this line and comment the above line

# Stress Test Parameters
TOTAL_METERS = 50          # Number of unique industrial assets simulated
READINGS_PER_BATCH = 10    # Collection readings per array envelope 
CONCURRENT_THREADS = 8     # Concurrent execution network dispatch pumps

def generate_mock_payload(meter_id: int) -> dict:
    """Constructs syntactically valid grid telemetry matrices matching contract rules."""
    zones = ["ZONE-NORTH", "ZONE-SOUTH", "ZONE-EAST", "ZONE-WEST"]
    current_time = datetime.datetime.now(datetime.timezone.utc)
    
    readings = []
    for i in range(READINGS_PER_BATCH):
        # Create incremental back-dated historical intervals
        interval_time = current_time - datetime.timedelta(minutes=15 * i)
        readings.append({
            "timestamp": interval_time.isoformat(timespec='seconds').replace("+00:00", "Z"),
            "kwh_value": round(random.uniform(5.5, 85.3), 2),
            "voltage": round(random.uniform(220.0, 240.0), 1)
        })
        
    return {
        "meter_id": f"MTR-SIM-{meter_id:05d}",
        "grid_zone": random.choice(zones),
        "readings": readings
    }

def dispatch_payload(meter_id: int) -> tuple[int, float]:
    """Pumps a data transaction packet through the Java gate and tracks latency."""
    payload = generate_mock_payload(meter_id)
    
    # We do NOT pass the header key here because the Java gateway acts as the public proxy!
    # Java automatically attaches the internal token before downstream routing.
    headers = {"Content-Type": "application/json"}
    
    start_time = time.perf_counter()
    try:
        # Use a synchronous HTTP client wrapper to hit the endpoint
        with httpx.Client(timeout=10.0) as client:
            response = client.post(TARGET_INGEST_URL, json=payload, headers=headers)
            latency = time.perf_counter() - start_time
            return response.status_code, latency
    except Exception as e:
        latency = time.perf_counter() - start_time
        return 503, latency  # Transport pipe connection failure placeholder

def run_stress_test():
    """Manages thread allocations and prints out grid processing statistics."""
    print("=" * 70)
    print("STARTING ENTERPRISE CORE INTEGRATION PIPELINE LOAD SIMULATION")
    print(f"Target Gateway: {TARGET_INGEST_URL}")
    print(f"Total Transactions Staged: {TOTAL_METERS}")
    print(f"Total Telemetry Intervals Flooded: {TOTAL_METERS * READINGS_PER_BATCH}")
    print(f"Concurrent Worker Pipelines Active: {CONCURRENT_THREADS}")
    print("=" * 70)
    
    success_count = 0
    failure_count = 0
    latencies = []
    
    start_wall_time = time.perf_counter()
    
    # Fire the concurrent thread pool executor
    with concurrent.futures.ThreadPoolExecutor(max_workers=CONCURRENT_THREADS) as executor:
        # Map out tasks to threads
        futures = {executor.submit(dispatch_payload, m_id): m_id for m_id in range(1, TOTAL_METERS + 1)}
        
        for future in concurrent.futures.as_completed(futures):
            meter_id = futures[future]
            try:
                status_code, latency = future.result()
                latencies.append(latency)
                
                if status_code == 200:
                    success_count += 1
                    print(f"[SUCCESS] Asset MTR-SIM-{meter_id:05d} cleared pipeline in {latency:.3f}s")
                else:
                    failure_count += 1
                    print(f"[FAILURE] Asset MTR-SIM-{meter_id:05d} dropped carrying code {status_code}")
            except Exception as exc:
                print(f"[CRITICAL] Simulation Thread crashed for asset context {meter_id}: {exc}")
                failure_count += 1

    total_wall_time = time.perf_counter() - start_wall_time
    avg_latency = sum(latencies) / len(latencies) if latencies else 0
    throughput = (TOTAL_METERS * READINGS_PER_BATCH) / total_wall_time
    
    print("=" * 70)
    print("SIMULATION STATISTICS RESULTS SUMMARY")
    print("=" * 70)
    print(f"Total Execution Wall Clock Duration : {total_wall_time:.2f} seconds")
    print(f"Successful Transaction Transmissions: {success_count}/{TOTAL_METERS} ({(success_count/TOTAL_METERS)*100:.1f}%)")
    print(f"Failed Transaction Transmissions    : {failure_count}/{TOTAL_METERS}")
    print(f"Mean Round-Trip Latency per Batch   : {avg_latency:.3f} seconds")
    print(f"Pipeline Ingestion Throughput Velocity: {throughput:.1f} intervals/sec")
    print("=" * 70)

if __name__ == "__main__":
    run_stress_test()

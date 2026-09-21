# Optimize for production deployment of a Python application using pip and a lightweight Python runtime. 
# This Dockerfile employs a multi-stage build to separate the compilation and runtime environments, 
# using pip for dependency management and a lightweight Python runtime for executing the application. 
# The final image is based on a lightweight Python slim image, and it runs the application as a non-root user to enhance security. 
# Notice the use of caching strategies for pip dependencies and the isolation of the build artifacts to minimize the final image size. 
# Also notice the use of FROM ... AS ... multi-stage build. 

# Step 1: Use a lightweight official Python 3.14 base runtime image 
FROM python:3.14-slim AS builder 

# Step 2: Establish system operational paths inside the container 
WORKDIR /build 

# Step 3: Inject system optimization flags to bypass overhead and freezing 
ENV PYTHONDONTWRITEBYTECODE=1 
ENV PYTHONUNBUFFERED=1 

# Step 4: Isolate dependency layer installation for fast rebuild caching 
COPY requirements.txt . 

RUN pip install --no-cache-dir --upgrade pip && \ 
    pip install --no-cache-dir --user -r requirements.txt 

FROM python:3.14-slim AS runner

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 
ENV PYTHONUNBUFFERED=1 
ENV PATH=/home/appuser/.local/bin:$PATH 

RUN groupadd -r appgroup && useradd -r -g appgroup -m appuser 

# This will now succeed because /root/.local exists in the builder stage
COPY --from=builder /root/.local /home/appuser/.local 

# Step 5: Transfer the functional enterprise application logic into the box 
# Only what runtime needs — not tests/, not test_data/, not this Dockerfile. 
COPY app ./app 

RUN chown -R appuser:appgroup /app /home/appuser/.local 

USER appuser 

# Step 6: Expose the operational engine network gateway port 
EXPOSE 8082 

# Step 7: Launch the concurrent asynchronous Uvicorn execution loop 
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8082"]

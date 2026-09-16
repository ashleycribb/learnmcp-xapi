FROM python:3.12-slim

# Set environment defaults
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency specifications and install
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY . .

# Expose HTTP port (Cloud Run sets PORT env var)
EXPOSE 8080

# Command to start the FastMCP HTTP/SSE server with uvicorn
CMD ["sh", "-c", "uvicorn learnmcp_xapi.main:app --host 0.0.0.0 --port ${PORT:-8080}"]

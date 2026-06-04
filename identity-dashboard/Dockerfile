# ================================================================
# Dockerfile — gidas-identity
# Multi-stage build: builder (dependencies) → runtime
# ================================================================

# Stage 1: Builder — install Python dependencies
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.12-slim

# Create non-root user
RUN groupadd -r appuser \
    && useradd -r -g appuser -d /app -s /sbin/nologin appuser \
    && mkdir -p /app \
    && chown appuser:appuser /app

# Copy Python dependencies from builder
COPY --from=builder /root/.local /home/appuser/.local

# Install SOPS CLI for secrets decryption
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && curl -LO https://github.com/getsops/sops/releases/download/v3.10.2/sops-v3.10.2.linux.amd64 \
    && mv sops-v3.10.2.linux.amd64 /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy application code
COPY app/ /app/app/
COPY requirements.txt /app/

WORKDIR /app
USER appuser

ENV \
    PATH="/home/appuser/.local/bin:${PATH}" \
    PYTHONPATH="/app:${PYTHONPATH}" \
    PYTHONUNBUFFERED=1

ENTRYPOINT ["python", "-m", "app"]

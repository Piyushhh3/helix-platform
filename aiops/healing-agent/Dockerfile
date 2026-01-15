# ============================================================================
# HEALING AGENT - MULTI-STAGE DOCKERFILE
# ============================================================================

FROM python:3.11-slim as builder

WORKDIR /build

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ============================================================================
# RUNTIME STAGE
# ============================================================================
FROM python:3.11-slim

# Create non-root user
RUN useradd -m -u 1000 agent && \
    mkdir -p /app && \
    chown -R agent:agent /app

WORKDIR /app

# Copy dependencies from builder
COPY --from=builder --chown=agent:agent /root/.local /home/agent/.local

# Copy application code
COPY --chown=agent:agent src/ ./src/
COPY --chown=agent:agent config/ ./config/

# Set Python path
ENV PYTHONPATH=/app/src
ENV PATH=/home/agent/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1

USER agent

EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:5000/health')"

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "src.main:app"]

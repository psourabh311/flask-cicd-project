# =============================================================
# Multi-Stage Dockerfile
# Stage 1 (builder): installs dependencies
# Stage 2 (runtime): copies only what is needed to run the app
# Result: final image is ~150MB instead of ~800MB
# =============================================================

# Stage 1 — Builder
# This stage is discarded after the build. It exists only to
# install packages so that build tools and pip cache do not
# end up in the final image.
FROM python:3.11-slim AS builder

WORKDIR /app

# Copy requirements first to leverage Docker layer caching.
# If requirements.txt has not changed, pip install is skipped
# on subsequent builds — significantly faster CI builds.
COPY requirements.txt .

RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Stage 2 — Runtime (final image)
# Only the installed packages and application code are copied here.
# Build tools, pip cache, and compiler dependencies are excluded.
FROM python:3.11-slim AS runtime

# Run as a non-root user — security best practice.
# If the container is compromised, the attacker does not get root.
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy installed Python packages from the builder stage
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/gunicorn

# Copy application source code
COPY app/ .

# Transfer ownership to the non-root user
RUN chown -R appuser:appuser /app

USER appuser

# EXPOSE is documentation — it does not publish the port.
# The actual port mapping is done with docker run -p.
EXPOSE 5000

# Docker-native health check
# --interval=30s  : check every 30 seconds
# --timeout=10s   : fail if no response within 10 seconds
# --start-period=5s: allow 5 seconds for the app to start
# --retries=3     : mark container unhealthy after 3 failures
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')" || exit 1

# Start Gunicorn with 2 workers — appropriate for t2.micro
# -w 2              : 2 worker processes
# -b 0.0.0.0:5000   : bind to all interfaces on port 5000
# --access-logfile - : write access logs to stdout (captured by Docker)
# --error-logfile -  : write error logs to stderr (captured by Docker)
# app:app           : module 'app', Flask instance variable 'app'
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "--access-logfile", "-", "--error-logfile", "-", "app:app"]

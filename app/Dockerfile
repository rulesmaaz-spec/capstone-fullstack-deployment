# ==========================================
# STAGE 1: Builder (Compiles dependencies)
# ==========================================
FROM python:3.11-slim AS builder

WORKDIR /app
# Install system dependencies needed for psycopg2
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
# Install packages into a local directory
RUN pip install --user --no-cache-dir -r requirements.txt

# ==========================================
# STAGE 2: Runtime (The final small image)
# ==========================================
FROM python:3.11-slim

# Install only the runtime library for Postgres
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for security
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /home/appuser
# Copy the installed packages from the builder stage
COPY --from=builder /root/.local /home/appuser/.local
# Copy the app code
COPY app.py .

# Change ownership and switch to non-root user
RUN chown -R appuser:appgroup /home/appuser
USER appuser

# Make sure Python finds the local packages
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

EXPOSE 5000

# Use Gunicorn instead of the Flask dev server
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]

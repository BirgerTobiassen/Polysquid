FROM ubuntu:24.04

# Set working directory
WORKDIR /app

# Install Python 3.12 and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3-pip \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

# Copy application
COPY app.py .
COPY templates/ templates/

# Run the app as a non-root user.
RUN useradd --create-home --shell /usr/sbin/nologin appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:5000/health || exit 1

# Expose port
EXPOSE 5000

# Run the Flask app
CMD ["python3", "app.py"]

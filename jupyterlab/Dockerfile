# JupyterLab Data Science Environment
# Multi-architecture support (arm64 + amd64)
#
# Includes: Full data science stack with LangChain, PyTorch, and database connectivity
#
# Tags:
#   dawsonlp/jupyterlab:latest - Latest Python 3.14
#   dawsonlp/jupyterlab:3.14   - Python 3.14 specific

FROM python:3.14-slim

LABEL org.opencontainers.image.title="JupyterLab Data Science" \
      org.opencontainers.image.description="JupyterLab with data science, ML, LangChain, and database tools" \
      org.opencontainers.image.authors="dawsonlp" \
      org.opencontainers.image.source="https://github.com/dawsonlp/docker_images" \
      org.opencontainers.image.version="3.14-20260316" \
      org.opencontainers.image.created="2026-03-16T16:22:25Z"

# Prevent Python from writing pyc files and buffering stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for JupyterLab
RUN useradd -m -s /bin/bash jupyter && \
    mkdir -p /notebooks && \
    chown -R jupyter:jupyter /notebooks

# Install Python packages
COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip && \
    pip install -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Create JupyterLab settings for continuous completion
RUN mkdir -p /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/completer-extension && \
    echo '{"showCompletionSuggestionsWhileTyping": true, "autoCompletion": true}' > \
    /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/completer-extension/plugin.jupyterlab-settings && \
    chown -R jupyter:jupyter /home/jupyter/.jupyter

# Switch to non-root user
USER jupyter
WORKDIR /notebooks

# Expose JupyterLab port
EXPOSE 8888

# Volume for notebooks
VOLUME ["/notebooks"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8888/api || exit 1

# Start JupyterLab
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--NotebookApp.token=''", "--NotebookApp.password=''"]
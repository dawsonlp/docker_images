# JupyterLab Data Science Environment
# Multi-architecture support (arm64 + amd64)
#
# Includes: Full data science stack with LangChain, PyTorch, and database connectivity
#
# Tags:
#   dawsonlp/jupyterlab:latest - Latest Python 3.14
#   dawsonlp/jupyterlab:3.14   - Python 3.14 specific

ARG PYTHON_VERSION=3.14
ARG UV_VERSION=0.11.16

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM python:${PYTHON_VERSION}-slim

ARG PYTHON_VERSION

LABEL org.opencontainers.image.title="JupyterLab Data Science" \
      org.opencontainers.image.description="JupyterLab with data science, ML, LangChain, and database tools" \
      org.opencontainers.image.authors="dawsonlp" \
      org.opencontainers.image.source="https://github.com/dawsonlp/docker_images" \
      org.opencontainers.image.version="${PYTHON_VERSION}-20260602" \
      org.opencontainers.image.created="2026-06-02T00:00:00Z"

COPY --from=uv /uv /uvx /bin/

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    UV_COMPILE_BYTECODE=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    PATH="/opt/venv/bin:$PATH" \
    SHELL=/bin/bash \
    TERM=xterm-256color \
    JUPYTER_ENABLE_LAB=yes

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash-completion \
    build-essential \
    curl \
    fonts-dejavu \
    fonts-liberation \
    git \
    graphviz \
    less \
    libgl1 \
    libglib2.0-0 \
    libpq-dev \
    locales \
    nano \
    postgresql-client \
    procps \
    tini \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for JupyterLab
RUN useradd -m -s /bin/bash jupyter && \
    mkdir -p /notebooks /opt/venv && \
    chown -R jupyter:jupyter /notebooks /opt/venv

WORKDIR /opt/jupyterlab

# Install Python packages from the uv lockfile
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project && \
    python -m ipykernel install --sys-prefix --name python3 --display-name "Python 3.14" && \
    python -m bash_kernel.install --sys-prefix

# Configure shell, JupyterLab terminals, widgets, and notebook display defaults
COPY config/ /tmp/jupyter-config/
RUN mkdir -p \
        /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/completer-extension \
        /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/apputils-extension \
        /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/terminal-extension \
        /home/jupyter/.ipython/profile_default/startup \
        /home/jupyter/.config/matplotlib && \
    cp /tmp/jupyter-config/jupyter_lab_config.py /home/jupyter/.jupyter/jupyter_lab_config.py && \
    cp /tmp/jupyter-config/completer.jupyterlab-settings /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/completer-extension/plugin.jupyterlab-settings && \
    cp /tmp/jupyter-config/theme.jupyterlab-settings /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/apputils-extension/themes.jupyterlab-settings && \
    cp /tmp/jupyter-config/terminal.jupyterlab-settings /home/jupyter/.jupyter/lab/user-settings/@jupyterlab/terminal-extension/plugin.jupyterlab-settings && \
    cp /tmp/jupyter-config/ipython_startup.py /home/jupyter/.ipython/profile_default/startup/00-defaults.py && \
    cp /tmp/jupyter-config/matplotlibrc /home/jupyter/.config/matplotlib/matplotlibrc && \
    cp /tmp/jupyter-config/bashrc /home/jupyter/.bashrc && \
    rm -rf /tmp/jupyter-config && \
    chown -R jupyter:jupyter /home/jupyter/.jupyter /home/jupyter/.ipython /home/jupyter/.config /home/jupyter/.bashrc

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
ENTRYPOINT ["tini", "--"]
CMD ["jupyter", "lab"]

# =============================================================================
# GoodWorkflows base image
# =============================================================================
# A lightweight, extensible base with R, Python (via uv), uvr, and Rust pre-installed.
# Consumers can quickly spin up venvs with `uv` (Python) or install R packages
# without rebuilding the whole image.
#
# Build:
#   docker build -t ghcr.io/gwmcelfresh/goodworkflows:latest .
#
# Extend (example):
#   FROM ghcr.io/gwmcelfresh/goodworkflows:latest
#   RUN uv pip install --system scanpy anndata
#   RUN Rscript -e "install.packages('Seurat', repos='https://cloud.r-project.org')"
# =============================================================================

FROM ubuntu:22.04 AS base

LABEL org.opencontainers.image.source="https://github.com/GWMcElfresh/GoodWorkflows"
LABEL org.opencontainers.image.description="Base image with R, Python (uv), uvr, and Rust for quick reproducible workflows"

# Versions — override at build time with --build-arg
ARG UV_PYTHON_VERSION=3.12
ARG R_VERSION=""
ARG RUST_VERSION=stable

ENV DEBIAN_FRONTEND=noninteractive

# ---- system dependencies ----------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        gnupg \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libfreetype6-dev \
        libtiff5-dev \
        libjpeg-dev \
        libpng-dev \
        pkg-config \
        wget \
    && rm -rf /var/lib/apt/lists/*

# ---- Python (system 3.10) + uv -----------------------------------------------
# Ubuntu 22.04 ships Python 3.10. Keep it as system default so apt tooling stays
# compatible. Install newer runtimes per-project via `uv python install`.
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-dev \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
ENV UV_SYSTEM_PYTHON=1

# Pre-cache one uv-managed Python for common workflows (not the system default).
ARG UV_PYTHON_VERSION
RUN uv python install "${UV_PYTHON_VERSION}"

# ---- R -----------------------------------------------------------------------
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
        | gpg --dearmor -o /etc/apt/keyrings/cran.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu $(. /etc/os-release && echo ${VERSION_CODENAME})-cran40/" \
        > /etc/apt/sources.list.d/cran-r.list \
    && apt-get update \
    && if [ -n "$R_VERSION" ]; then \
        apt-get install -y --no-install-recommends \
            r-base-core=${R_VERSION}* r-base-dev=${R_VERSION}*; \
    else \
        apt-get install -y --no-install-recommends r-base r-base-dev; \
    fi \
    && rm -rf /var/lib/apt/lists/*

# ---- uvr (R package manager CLI) ---------------------------------------------
ARG TARGETARCH
RUN if [ "${TARGETARCH}" = "arm64" ]; then UVR_ARCH="aarch64-unknown-linux-gnu"; else UVR_ARCH="x86_64-unknown-linux-gnu"; fi \
    && curl -fsSL "https://github.com/nbafrank/uvr/releases/latest/download/uvr-${UVR_ARCH}.tar.gz" \
        | tar -xz -C /usr/local/bin uvr \
    && chmod +x /usr/local/bin/uvr

# ---- Rust via rustup ---------------------------------------------------------
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH="/usr/local/cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain ${RUST_VERSION} --profile minimal \
    && rustup component add rustfmt clippy \
    && chmod -R a+w ${CARGO_HOME} ${RUSTUP_HOME}

# ---- final setup -------------------------------------------------------------
WORKDIR /workspace

# Smoke-test: make sure all runtimes are functional
ARG UV_PYTHON_VERSION
RUN python3 --version \
    && uv --version \
    && uv python find "${UV_PYTHON_VERSION}" \
    && uvr --version \
    && R --version | head -n1 \
    && rustc --version \
    && cargo --version

CMD ["/bin/bash"]

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
ARG PYTHON_VERSION=3.12
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
        software-properties-common \
        wget \
    && rm -rf /var/lib/apt/lists/*

# ---- Python via deadsnakes + uv ---------------------------------------------
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xBA6932366A755776" \
        | gpg --dearmor -o /etc/apt/keyrings/deadsnakes.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/deadsnakes.gpg] http://ppa.launchpad.net/deadsnakes/ppa/ubuntu $(. /etc/os-release && echo ${VERSION_CODENAME}) main" \
        > /etc/apt/sources.list.d/deadsnakes-ppa.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-dev \
        python${PYTHON_VERSION}-venv \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && update-alternatives --install /usr/bin/python  python  /usr/bin/python${PYTHON_VERSION} 1

# Install uv (fast Python package manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
ENV UV_SYSTEM_PYTHON=1

# ---- R -----------------------------------------------------------------------
RUN wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
        | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc \
    && add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" \
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

# Smoke-test: make sure all three runtimes are functional
RUN python3 --version \
    && uv --version \
    && uvr --version \
    && R --version | head -n1 \
    && rustc --version \
    && cargo --version

CMD ["/bin/bash"]

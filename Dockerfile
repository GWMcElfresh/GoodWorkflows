# =============================================================================
# GoodWorkflows base image
# =============================================================================
# A lightweight, extensible base with R, Python (via uv), and Rust pre-installed.
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
LABEL org.opencontainers.image.description="Base image with R, Python (uv), and Rust for quick venv-based workflows"

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
RUN add-apt-repository -y ppa:deadsnakes/ppa \
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
    && R --version | head -n1 \
    && rustc --version \
    && cargo --version

CMD ["/bin/bash"]

# =============================================================================
# GoodWorkflows base / dependency image (dockerDependencies multi-stage)
# =============================================================================
# Stages:
#   foundation — heavy runtimes (Ubuntu 3.10, uv, R, uvr, Rust)
#   deps       — cached dependency layer (monthly base-deps + incremental hash)
#   runtime    — published ghcr.io/gwmcelfresh/goodworkflows:latest on main
#
# CI uses GWMcElfresh/dockerDependencies reusable workflows:
#   build-base-image.yml  → ghcr.io/<repo>/base-deps:YYYY-MM
#   docker-cache.yml      → ghcr.io/<repo>/deps:<hash-YYYY-MM>, tests, :latest
# =============================================================================

# Must be declared before the first FROM so BuildKit can resolve `FROM ${BASE_IMAGE}`.
ARG BASE_IMAGE=foundation

FROM ubuntu:22.04 AS foundation

LABEL org.opencontainers.image.source="https://github.com/GWMcElfresh/GoodWorkflows"
LABEL org.opencontainers.image.description="Base image with R, Python (uv), uvr, and Rust for quick reproducible workflows"

ARG PYTHON_VERSION=3.12
ARG R_VERSION=""
ARG RUST_VERSION=stable

ENV DEBIAN_FRONTEND=noninteractive

# ---- system dependencies ----------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        gfortran \
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
        libhdf5-dev \
        libnetcdf-dev \
        libgsl-dev \
        libgit2-dev \
        libglpk-dev \
        libuv1-dev \
        pandoc \
        pkg-config \
        wget \
    && rm -rf /var/lib/apt/lists/*

# ---- Python (system 3.10) + uv -----------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-dev \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
ENV UV_SYSTEM_PYTHON=1

ARG PYTHON_VERSION
RUN uv python install "${PYTHON_VERSION}"

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

# ---- deps (cached dependency layer) ------------------------------------------
# Default BASE_IMAGE=foundation for full builds. docker-cache passes a monthly
# base-deps image with SKIP_BASE_DEPS=true for fast incremental rebuilds.
FROM ${BASE_IMAGE} AS deps

ARG SKIP_BASE_DEPS=false
ARG PYTHON_VERSION=3.12

RUN if [ "${SKIP_BASE_DEPS}" = "true" ]; then \
        echo "Using pre-built base-deps image"; \
    else \
        echo "Building deps layer from foundation"; \
    fi \
    && python3 --version \
    && uv --version \
    && uv python find "${PYTHON_VERSION}" \
    && uvr --version \
    && R --version | head -n1 \
    && rustc --version \
    && cargo --version

# ---- pre-install R packages (batch_effect_assessments + uvr workflows) ------
ENV R_LIBS_SITE=/usr/local/lib/R/site-library \
    UVR_INSTALL_SYSREQS=1

RUN mkdir -p "${R_LIBS_SITE}" \
    && R --quiet -e " \
        options(repos = c(CRAN = 'https://cloud.r-project.org')); \
        pkgs <- c('Rcpp', 'jsonlite', 'tidyverse', 'Seurat'); \
        install.packages( \
            pkgs, \
            lib = Sys.getenv('R_LIBS_SITE'), \
            Ncpus = max(1L, parallel::detectCores() - 1L), \
            dependencies = TRUE \
        ); \
        missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]; \
        if (length(missing)) stop('Missing R packages: ', paste(missing, collapse = ', ')); \
        cat('R site-library OK\n') \
    "

ENV R_LIBS="${R_LIBS_SITE}:${R_LIBS}"

# ---- runtime (published :latest on main) -------------------------------------
FROM deps AS runtime

WORKDIR /workspace
CMD ["/bin/bash"]

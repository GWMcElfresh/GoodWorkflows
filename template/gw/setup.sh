#!/usr/bin/env bash
# setup.sh — Bootstrap GoodWorkflows on Bazzite (or any Fedora-based Linux)
#
# USAGE:
#   cd template/gw
#   bash setup.sh
#
# This script:
#   1. Installs Nextflow (if missing)
#   2. Verifies Podman is installed and rootless
#   3. Verifies NVIDIA GPU passthrough works (--privileged required on Bazzite)
#   4. Pulls all required container images
#   5. Creates the runs/ directory for per-run isolation
#
# Requires: curl, podman, nvidia drivers
# System deps: java-25-openjdk, libcurl-devel, libuv, cmake, openssl-devel, libxml2-devel
# No sudo required if Podman rootless + NVIDIA CDI are already configured.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo " GoodWorkflows — Bazzite Setup"
echo "=========================================="

# --- Detect PIPELINE_ROOT ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ ! -f "${PIPELINE_ROOT}/main.nf" ]]; then
    echo -e "${RED}ERROR: Could not locate main.nf. Expected at: ${PIPELINE_ROOT}/main.nf${NC}"
    echo "Make sure you're running this from template/gw/ inside the GoodWorkflows repo."
    exit 1
fi
echo -e "${GREEN}Pipeline root: ${PIPELINE_ROOT}${NC}"

# --- 1. Check system dependencies ---
echo ""
echo "--- Checking system dependencies ---"

MISSING_DEPS=()

# Check Java (required by Nextflow)
if command -v java &>/dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1)
    echo -e "${GREEN}Java found: ${JAVA_VERSION}${NC}"
else
    MISSING_DEPS+=("java-25-openjdk")
fi

# Check other build/runtime dependencies
for dep in libcurl-devel libuv cmake openssl-devel libxml2-devel; do
    if rpm -q "${dep}" &>/dev/null; then
        echo -e "${GREEN}Found: ${dep}${NC}"
    else
        MISSING_DEPS+=("${dep}")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${YELLOW}The following system packages are missing:${NC}"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - ${dep}"
    done
    echo ""
    echo "Install them all at once with:"
    echo -e "  ${GREEN}sudo rpm-ostree install ${MISSING_DEPS[*]}${NC}"
    echo ""
    echo "NOTE: rpm-ostree installs require a reboot to take effect."
    echo "After reboot, re-run this script to continue."
    exit 1
fi

# --- 2. Install Nextflow ---
echo ""
echo "--- Checking Nextflow ---"
if command -v nextflow &>/dev/null; then
    echo -e "${GREEN}Nextflow found: $(nextflow -version 2>&1 | head -1)${NC}"
else
    echo -e "${YELLOW}Nextflow not found. Installing to ~/bin/nextflow...${NC}"
    mkdir -p "${HOME}/bin"
    curl -s https://get.nextflow.io | bash
    mv nextflow "${HOME}/bin/nextflow"
    chmod +x "${HOME}/bin/nextflow"

    # Add ~/bin to PATH for this session
    export PATH="${HOME}/bin:${PATH}"

    # Suggest adding to shell profile
    if ! grep -q 'export PATH.*~/bin' "${HOME}/.bashrc" 2>/dev/null; then
        echo 'export PATH="${HOME}/bin:${PATH}"' >> "${HOME}/.bashrc"
        echo -e "${YELLOW}Added ~/bin to PATH in ~/.bashrc. Restart your shell or run: source ~/.bashrc${NC}"
    fi

    echo -e "${GREEN}Nextflow installed: $(nextflow -version 2>&1 | head -1)${NC}"
fi

# --- 3. Verify Podman ---
echo ""
echo "--- Checking Podman ---"
if command -v podman &>/dev/null; then
    PODMAN_VERSION=$(podman --version 2>&1)
    echo -e "${GREEN}Podman found: ${PODMAN_VERSION}${NC}"
else
    echo -e "${RED}ERROR: Podman is not installed.${NC}"
    echo "On Bazzite, Podman should be pre-installed. If not, run:"
    echo "  rpm-ostree install podman"
    exit 1
fi

# Check rootless mode
if podman info 2>/dev/null | grep -q 'rootless: true'; then
    echo -e "${GREEN}Podman is running rootless (recommended).${NC}"
else
    echo -e "${YELLOW}WARNING: Podman is not in rootless mode. Rootless is recommended.${NC}"
fi

# --- 4. Verify NVIDIA GPU passthrough ---
echo ""
echo "--- Checking NVIDIA GPU passthrough ---"
GPU_TEST_IMAGE="docker.io/nvidia/cuda:12.0.1-base-ubuntu22.04"

# Pull the test image first (don't fail if it's already cached)
echo "Pulling CUDA test image (one-time)..."
podman pull "${GPU_TEST_IMAGE}" 2>/dev/null || {
    echo -e "${YELLOW}WARNING: Could not pull ${GPU_TEST_IMAGE}. GPU verification skipped.${NC}"
    echo "You can still run CPU-only workflows (ingest_export, ingest_tabulate)."
}

if podman image exists "${GPU_TEST_IMAGE}" 2>/dev/null; then
    echo "Testing GPU passthrough with --privileged..."
    GPU_OUTPUT=$(podman run --rm --privileged --gpus all "${GPU_TEST_IMAGE}" nvidia-smi 2>&1) || true
    if echo "${GPU_OUTPUT}" | grep -qE "NVIDIA-SMI|GeForce"; then
        echo -e "${GREEN}GPU passthrough works!${NC}"
        echo "${GPU_OUTPUT}" | grep -E "NVIDIA-SMI|GeForce"
    else
        echo -e "${RED}ERROR: GPU passthrough failed.${NC}"
        echo "On Bazzite, this usually means nvidia-container-toolkit CDI is not configured."
        echo "Try:"
        echo "  1. Verify nvidia drivers: nvidia-smi"
        echo "  2. Check CDI config: ls /etc/cdi/nvidia.yaml"
        echo "  3. If missing: sudo rpm-ostree install nvidia-container-toolkit"
        echo ""
        echo "You can still run CPU-only workflows (ingest_export, ingest_tabulate)."
    fi
else
    echo -e "${YELLOW}GPU test image not available. Skipping GPU verification.${NC}"
fi

# --- 5. Pull container images ---
echo ""
echo "--- Pulling container images ---"

IMAGES=(
    "ghcr.io/bimberlabinternal/rdiscvr:latest"
    "ghcr.io/bimberlabinternal/cellmembrane:latest"
    "ghcr.io/gwmcelfresh/scmodal:sha-83cc3f1"
)

for img in "${IMAGES[@]}"; do
    echo "Pulling: ${img}"
    if podman pull "${img}"; then
        echo -e "${GREEN}  OK: ${img}${NC}"
    else
        echo -e "${RED}  FAILED: ${img}${NC}"
        echo "  Check that the image is public and the registry is reachable."
    fi
done

# --- 6. Create runs/ directory ---
echo ""
echo "--- Creating runs/ directory ---"
RUNS_DIR="${SCRIPT_DIR}/runs"
mkdir -p "${RUNS_DIR}"
echo -e "${GREEN}Created: ${RUNS_DIR}${NC}"

# --- Summary ---
echo ""
echo "=========================================="
echo " Setup Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Download test data:"
echo "     bash fetch_example_data.sh"
echo ""
echo "  2. Run a workflow:"
echo "     bash run.sh --workflow ingest_export"
echo "     bash run.sh --workflow integration"
echo ""
echo "  Outputs land in: template/gw/runs/<timestamp>/outputs/"
echo "=========================================="
# syntax=docker/dockerfile:1
# PodmanWrapper – rootless Podman + podman-compose on Rocky Linux 9
# Designed for HPC / SLURM single-node workflows.
FROM rockylinux:9

LABEL org.opencontainers.image.title="PodmanWrapper" \
      org.opencontainers.image.description="Rootless Podman + podman-compose wrapper for HPC/SLURM" \
      org.opencontainers.image.source="https://github.com/GWMcElfresh/PodmanWrapper" \
      org.opencontainers.image.licenses="MIT"

# ---------------------------------------------------------------------------- #
# System packages
# Replace Rocky Linux 9 minimal coreutils-single and util-linux-core with full 
# versions
# ---------------------------------------------------------------------------- #
RUN dnf -y update && \
    dnf -y install --allowerasing \
        podman \
        fuse-overlayfs \
        slirp4netns \
        python3 \
        python3-pip \
        bash \
        coreutils \
        git \
        shadow-utils \
        util-linux \
    && dnf clean all

# ---------------------------------------------------------------------------- #
# podman-compose (latest from PyPI)
# ---------------------------------------------------------------------------- #
RUN pip3 install --no-cache-dir podman-compose

# ---------------------------------------------------------------------------- #
# Rootless Podman – subuid / subgid
# Assumptions:
#   • On the host the HPC user already has /etc/subuid and /etc/subgid entries.
#   • When this container is run rootless on the host those mappings are
#     inherited automatically.
#   • Inside the image we create a generic "hpcuser" (uid 1000) so the image
#     itself can also be used standalone with --userns=keep-id or similar.
# ---------------------------------------------------------------------------- #
RUN useradd -m -u 1000 -s /bin/bash hpcuser && \
    echo "hpcuser:100000:65536" >> /etc/subuid && \
    echo "hpcuser:100000:65536" >> /etc/subgid

# ---------------------------------------------------------------------------- #
# Podman storage configuration for rootless overlayfs
#
# graphRoot and runRoot are set explicitly under /tmp so that the inner Podman
# (launched by podman-compose) always uses local node storage, never an NFS
# or Lustre filesystem that doesn't support overlayfs mounts.
# These values are also overridable at runtime via CONTAINERS_GRAPHROOT and
# CONTAINERS_RUNROOT environment variables (set by run-compose).
# ---------------------------------------------------------------------------- #
RUN mkdir -p /home/hpcuser/.config/containers && \
    printf '[storage]\ndriver = "overlay"\ngraphRoot = "/tmp/podman-inner/storage"\nrunRoot = "/tmp/podman-inner/run"\n\n[storage.options.overlay]\nmount_program = "/usr/bin/fuse-overlayfs"\n' \
        > /home/hpcuser/.config/containers/storage.conf && \
    chown -R hpcuser:hpcuser /home/hpcuser/.config

# ---------------------------------------------------------------------------- #
# Wrapper entrypoint
# ---------------------------------------------------------------------------- #
COPY run-compose /usr/local/bin/run-compose
RUN chmod +x /usr/local/bin/run-compose

WORKDIR /workspace

USER hpcuser

# XDG_RUNTIME_DIR is expected to be set by the caller (SLURM script or podman
# run -e flag).  We provide a safe fallback for standalone/local use.
ENV XDG_RUNTIME_DIR=/tmp/runtime-1000 \
    HOME=/home/hpcuser

ENTRYPOINT ["/usr/local/bin/run-compose"]

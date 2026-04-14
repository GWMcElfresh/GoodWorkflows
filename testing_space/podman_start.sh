#!/usr/bin/env bash


podman machine init
podman machine set --memory 12288 podman-machine-default && \
podman machine start podman-machine-default 

#podman system info 2>/dev/null | grep -E 'memTotal|memFree'

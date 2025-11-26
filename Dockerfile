FROM nvcr.io/nvidia/l4t-cuda:12.2.2-devel-arm64-ubuntu22.04 AS base

ARG OLLAMA_VERSION=0.13.0
ARG JETPACK_VERSION_MAJOR=6
ARG IS_SBSA=False
ARG CUDA_VERSION_MAJOR=12

ENV OLLAMA_VERSION=${OLLAMA_VERSION} \
    OLLAMA_HOST=0.0.0.0 \
    OLLAMA_LOGS=/data/logs/ollama.log \
    OLLAMA_MODELS=/data/models/ollama/models \
    OLLAMA_HOME=/opt/ollama \
    CUDA_VERSION_MAJOR=${CUDA_VERSION_MAJOR} \
    JETPACK_VERSION_MAJOR=${JETPACK_VERSION_MAJOR}

# Copy start script
COPY start_ollama /start_ollama
RUN chmod +x /start_ollama

# Install wget and other required tools
RUN apt-get update && apt-get install -y wget ca-certificates && rm -rf /var/lib/apt/lists/*

# Set environment variable for ollama release URL
ENV OLLAMA_RELEASE_URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}"

# Download and install base ollama binary
RUN set -e \
    && echo "Downloading ollama ${OLLAMA_VERSION}" \
    && mkdir -p /tmp/ollama && cd /tmp/ollama \
    && wget $WGET_FLAGS "${OLLAMA_RELEASE_URL}/ollama-linux-arm64.tgz" \
    && tar -xzvf ollama-linux-arm64.tgz -C /usr/local \
    && rm ollama-linux-arm64.tgz \
    && cd / && rm -rf /tmp/ollama

# Download and install JetPack-specific ollama libraries
RUN set -e \
    && mkdir -p /tmp/ollama && cd /tmp/ollama \
    && wget $WGET_FLAGS "${OLLAMA_RELEASE_URL}/ollama-linux-arm64-jetpack${JETPACK_VERSION_MAJOR}.tgz" \
    && tar -xzvf ollama-linux-arm64-jetpack${JETPACK_VERSION_MAJOR}.tgz -C /usr/local \
    && rm ollama-linux-arm64-jetpack${JETPACK_VERSION_MAJOR}.tgz \
    && cd / && rm -rf /tmp/ollama

# Install Python ollama package
RUN set -e \
    && . /opt/venv/bin/activate \
    && uv pip install ollama

# Create symbolic links
RUN ln -s /usr/local/bin/ollama /usr/bin/ollama || true \
    && ln -s /usr/bin/python3 /usr/bin/python || true

CMD /start_ollama && /bin/bash

EXPOSE 11434
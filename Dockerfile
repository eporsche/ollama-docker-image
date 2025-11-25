# Complete standalone Dockerfile for Ollama on Jetson
# This Dockerfile consolidates all dependencies from jetson-containers:
# ubuntu → build-essential → cuda → cudastack → cmake → python → go → ollama

# ============================================================================
# BASE: Ubuntu 22.04
# ============================================================================
FROM ubuntu:22.04 AS base

# ============================================================================
# LAYER 1: build-essential
# Installs compilers, build tools & configures locale
# ============================================================================
FROM base AS build-essential

ENV DEBIAN_FRONTEND=noninteractive \
    LANGUAGE=en_US:en \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    WGET_FLAGS="--quiet --show-progress --progress=bar:force:noscroll --no-check-certificate --timeout=60 --tries=3 --retry-connrefused --retry-on-host-error --retry-on-http-error=500,502,503,504"

RUN set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        locales \
        locales-all \
        tzdata \
    && locale-gen en_US $LANG \
    && update-locale LC_ALL=$LC_ALL LANG=$LANG \
    && locale \
    \
    && apt-get install -y --no-install-recommends \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        lsb-release \
        pkg-config \
        gnupg \
        git \
        git-lfs \
        gdb \
        wget \
        curl \
        nano \
        zip \
        unzip \
        libnuma-dev \
        libibverbs-dev \
        time \
        sshpass \
        ssh-client \
        binutils \
        xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && gcc --version \
    && g++ --version

# ============================================================================
# LAYER 2: CUDA Toolkit
# Installs NVIDIA CUDA 12.9 for Jetson (arm64 tegra)
# ============================================================================
FROM build-essential AS cuda

ARG CUDA_URL=https://developer.download.nvidia.com/compute/cuda/12.9.1/local_installers/cuda-tegra-repo-ubuntu2204-12-9-local_12.9.1-1_arm64.deb \
    CUDA_DEB=cuda-tegra-repo-ubuntu2204-12-9-local \
    CUDA_PACKAGES="cuda-toolkit*" \
    CUDA_ARCH_LIST=87 \
    CUDA_ARCH=tegra-aarch64 \
    CUDA_INSTALLED_VERSION=129 \
    IS_SBSA=False \
    DISTRO=ubuntu2204

COPY scripts/install_cuda.sh /tmp/cuda/install.sh
RUN /tmp/cuda/install.sh

ENV CUDA_HOME="/usr/local/cuda"
ENV NVCC_PATH="$CUDA_HOME/bin/nvcc"

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    CUDAARCHS=${CUDA_ARCH_LIST} \
    CUDA_ARCHITECTURES=${CUDA_ARCH_LIST} \
    CUDA_INSTALLED_VERSION=${CUDA_VERSION} \
    CUDA_HOME="/usr/local/cuda" \
    CUDNN_LIB_PATH="/usr/lib/aarch64-linux-gnu" \
    CUDNN_LIB_INCLUDE_PATH="/usr/include" \
    CMAKE_CUDA_COMPILER=${NVCC_PATH} \
    CUDA_NVCC_EXECUTABLE=${NVCC_PATH} \
    CUDACXX=${NVCC_PATH} \
    TORCH_NVCC_FLAGS="-Xfatbin -compress-all" \
    CUDA_BIN_PATH="${CUDA_HOME}/bin" \
    CUDA_TOOLKIT_ROOT_DIR="${CUDA_HOME}" \
    LD_LIBRARY_PATH="${CUDA_HOME}/compat:${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}" \
    LDFLAGS="-L/usr/local/cuda/lib64 ${LDFLAGS}" \
    DEBIAN_FRONTEND=noninteractive

ENV PATH="${PATH}:${CUDA_HOME}/bin" \
    LIBRARY_PATH=${LIBRARY_PATH:+${LIBRARY_PATH}:}/usr/local/cuda/lib64/stubs \
    LDFLAGS="${LDFLAGS:+${LDFLAGS} }-L/usr/local/cuda/lib64/stubs -Wl,-rpath,/usr/local/cuda/lib64" \
    CPLUS_INCLUDE_PATH=/usr/local/cuda/include/cccl${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}} \
    C_INCLUDE_PATH=/usr/local/cuda/include/cccl${C_INCLUDE_PATH:+:${C_INCLUDE_PATH}}

WORKDIR /

# ============================================================================
# LAYER 3: cuDNN (part of cudastack)
# Installs cuDNN for deep learning acceleration
# ============================================================================
FROM cuda AS cudastack

ARG CUDNN_VERSION=9.15.0 \
    CUDNN_URL=https://developer.download.nvidia.com/compute/cudnn/9.15.0/local_installers/cudnn-local-tegra-repo-ubuntu2204-9.15.0_1.0-1_arm64.deb \
    CUDNN_DEB=cudnn-local-tegra-repo-ubuntu2204-9.15.0 \
    CUDNN_PACKAGES="libcudnn9-cuda-12 libcudnn9-dev-cuda-12 libcudnn9-samples" \
    DISTRO=ubuntu2204

COPY scripts/install_cudnn.sh /tmp/cudnn/install.sh
RUN /tmp/cudnn/install.sh

# ============================================================================
# LAYER 4: CMake
# Upgrades CMake via Kitware's apt repo
# ============================================================================
FROM cudastack AS cmake

RUN set -ex \
    && wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/kitware.list >/dev/null \
    && apt-get update \
    && rm /usr/share/keyrings/kitware-archive-keyring.gpg \
    && apt-get install -y --no-install-recommends kitware-archive-keyring \
    && apt-cache policy cmake \
    && apt-get install -y --no-install-recommends cmake \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && cmake --version

# ============================================================================
# LAYER 5: Python
# Installs Python 3.12 via uv in a virtual environment
# ============================================================================
FROM cmake AS python

ARG PYTHON_VERSION=3.12
ARG PYTHON_FREE_THREADING=0

ENV PYTHON_VERSION=${PYTHON_VERSION} \
    PYTHON_FREE_THREADING=${PYTHON_FREE_THREADING} \
    PYTHONFAULTHANDLER=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONIOENCODING=utf-8 \
    PYTHONHASHSEED=random \
    PIP_NO_CACHE_DIR=true \
    PIP_CACHE_PURGE=true \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    PIP_WHEEL_DIR=/opt/wheels \
    PIP_VERBOSE=1 \
    TWINE_NON_INTERACTIVE=1 \
    PATH=/opt/venv/bin:$PATH \
    UV_PYTHON=/opt/venv/bin/python

# Use bash for consistent shell behavior with pipefail support
SHELL ["/bin/bash", "-c"]

# Install system dependencies for Python installation
RUN set -eux \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Download and install uv package manager (uses pipefail for curl|sh safety)
RUN set -euxo pipefail \
    && curl -fsSL https://astral.sh/uv/install.sh | sh \
    && if [ -f "${HOME}/.local/bin/uv" ]; then \
         install -m 0755 "${HOME}/.local/bin/uv" /usr/local/bin/uv; \
       fi \
    && uv --version

# Determine Python version (with free-threading support if enabled)
RUN set -eux \
    && PYTHON_INSTALL_VERSION="${PYTHON_VERSION}" \
    && if [ "${PYTHON_FREE_THREADING}" = "1" ]; then \
         PYTHON_INSTALL_VERSION="${PYTHON_VERSION}t"; \
         echo "🔓 FREE-THREADED (NO-GIL) BUILD ENABLED"; \
       fi \
    && echo "Installing Python ${PYTHON_INSTALL_VERSION}" \
    && uv python install "${PYTHON_INSTALL_VERSION}"

# Create Python virtual environment
RUN set -eux \
    && PYTHON_INSTALL_VERSION="${PYTHON_VERSION}" \
    && if [ "${PYTHON_FREE_THREADING}" = "1" ]; then \
         PYTHON_INSTALL_VERSION="${PYTHON_VERSION}t"; \
       fi \
    && PY_BIN="$(uv python find "${PYTHON_INSTALL_VERSION}")" \
    && uv venv --python "${PY_BIN}" --system-site-packages /opt/venv \
    && . /opt/venv/bin/activate \
    && which python \
    && python --version

# Install core Python packages
RUN set -eux \
    && . /opt/venv/bin/activate \
    && uv pip install --upgrade pip pkginfo \
    && uv pip install --no-binary :all: psutil

# Install Python build and development packages
RUN set -eux \
    && . /opt/venv/bin/activate \
    && uv pip install --upgrade \
         setuptools \
         packaging \
         Cython \
         wheel \
         uv \
         nvidia-ml-py \
         twine

# Create symlinks and verify installation
RUN set -eux \
    && ln -sf /opt/venv/bin/python /usr/local/bin/python3 \
    && which python3 \
    && python3 --version

# Set PYTHON_GIL=0 for free-threaded builds
RUN if [ "${PYTHON_FREE_THREADING}" = "1" ]; then \
      echo "export PYTHON_GIL=0" >> /etc/bash.bashrc; \
    fi

# ============================================================================
# LAYER 6: NumPy and HuggingFace Hub
# Installs Python dependencies for ML
# ============================================================================
FROM python AS python-ml

RUN . /opt/venv/bin/activate \
    && uv pip install --upgrade numpy huggingface_hub

# ============================================================================
# LAYER 7: Go
# Installs Go compiler needed to build ollama
# ============================================================================
FROM python-ml AS golang

ARG GOLANG_VERSION="1.22.7"

RUN curl -fsSL https://go.dev/dl/go${GOLANG_VERSION}.linux-arm64.tar.gz -o /tmp/go.tgz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm /tmp/go.tgz

ENV PATH="/usr/local/go/bin:${PATH}" \
    GOPATH="/root/go"

RUN go version

# ============================================================================
# LAYER 8: Ollama
# Installs ollama binary and sets up the server
# ============================================================================
FROM golang AS ollama

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
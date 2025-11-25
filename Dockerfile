ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG OLLAMA_VERSION \
    JETPACK_VERSION_MAJOR \
    CUDA_VERSION_MAJOR

ENV OLLAMA_VERSION=${OLLAMA_VERSION} \
    OLLAMA_HOST=0.0.0.0 \
    OLLAMA_LOGS=/data/logs/ollama.log \
    OLLAMA_MODELS=/data/models/ollama/models \
    OLLAMA_HOME=/opt/ollama \
    CUDA_VERSION_MAJOR=${CUDA_VERSION_MAJOR}

COPY start_ollama /
COPY scripts/ /tmp

RUN apt-get update && \
    apt-get install -y wget curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN ln -s /root/.local/bin/uv /usr/local/bin/uv

RUN /tmp/install.sh

CMD /start_ollama && /bin/bash

EXPOSE 11434
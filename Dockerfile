FROM mambaorg/micromamba:2.3.2-ubuntu22.04

LABEL org.opencontainers.image.title="pathseq-t2t" \
      org.opencontainers.image.description="Host-subtraction and microbial profiling pipeline" \
      org.opencontainers.image.version="0.3.0"

# Install as root, then switch back to mambaorg default user
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      procps \
    && rm -rf /var/lib/apt/lists/*

# Copy conda environment definitions
COPY envs/ /opt/envs/

# Build each conda environment
# micromamba is on PATH as the standard entrypoint tool
RUN micromamba create -y -f /opt/envs/main.yml     && \
    micromamba create -y -f /opt/envs/metaphlan.yml && \
    micromamba create -y -f /opt/envs/checkm2.yml   && \
    micromamba create -y -f /opt/envs/checkv.yml    && \
    micromamba create -y -f /opt/envs/gtdbtk.yml    && \
    micromamba clean -afy

# Install pathseq-t2t
COPY src/pathseq-t2t  /usr/local/bin/pathseq-t2t
COPY src/commands/    /opt/pathseq-t2t/src/commands/
COPY lib/             /opt/pathseq-t2t/lib/
COPY scripts/         /opt/pathseq-t2t/scripts/
RUN chmod +x /usr/local/bin/pathseq-t2t && \
    ln -sf /opt/pathseq-t2t /opt/pathseq-t2t/src

# Wrapper scripts: redirect isolated-env tools to their env binaries.
# This keeps pathseq-t2t unaware of conda environments.
RUN for bin in metaphlan bowtie2; do \
      printf '#!/bin/sh\nexec /opt/conda/envs/metaphlan/bin/%s "$@"\n' "$bin" \
        > /usr/local/bin/$bin && chmod +x /usr/local/bin/$bin; \
    done && \
    printf '#!/bin/sh\nexec /opt/conda/envs/checkm2/bin/checkm2 "$@"\n' \
      > /usr/local/bin/checkm2 && chmod +x /usr/local/bin/checkm2 && \
    printf '#!/bin/sh\nexec /opt/conda/envs/checkv/bin/checkv "$@"\n' \
      > /usr/local/bin/checkv && chmod +x /usr/local/bin/checkv && \
    for bin in gtdbtk pplacer fastani; do \
      printf '#!/bin/sh\nexec /opt/conda/envs/gtdbtk/bin/%s "$@"\n' "$bin" \
        > /usr/local/bin/$bin && chmod +x /usr/local/bin/$bin; \
    done

# Add main env binaries to PATH
ENV PATH="/opt/conda/envs/main/bin:${PATH}" \
    SCRIPT_DIR="/opt/pathseq-t2t/src"

# Smoke test
RUN pathseq-t2t --version

WORKDIR /data
CMD ["pathseq-t2t", "--help"]

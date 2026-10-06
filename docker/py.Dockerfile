FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends time procps build-essential libfftw3-dev \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
# harmonypy 2.1.0 is the C++ rewrite; 2.0.2 was 18x to 21x slower on the same input
RUN uv pip install --system scanpy==1.12.4 harmonypy==2.1.0 leidenalg igraph openTSNE "dask[array]" distributed

COPY docker/monitor.sh docker/entrypoint.sh /bench/
ENTRYPOINT ["/bench/entrypoint.sh"]

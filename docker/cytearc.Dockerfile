# CyteArc needs Python 3.13, so it does not share the Scanpy image
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends time procps build-essential \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
RUN uv pip install --system "cytearc[extra]==1.3.0"

COPY docker/monitor.sh docker/entrypoint.sh /bench/
ENTRYPOINT ["/bench/entrypoint.sh"]

# bixverse Python bindings over the same bixverse-rs crates as the R package.
# PyPI has no aarch64 Linux wheels, so both build from the committed trees
# (commits in vendor/SHAS):
#   git -C <bixverse-rs> archive --format=tar.gz --prefix=bixverse-rs/ -o $PWD/vendor/bixverse-rs.tar.gz <branch>
#   git -C <manifolds-rs> archive --format=tar.gz --prefix=manifolds-rs/ -o $PWD/vendor/manifolds-rs.tar.gz <branch>
#   docker build -f docker/bixverse-py.Dockerfile -t scbench-bixverse-py .
FROM python:3.12-slim

# cmake for the static HDF5 build
RUN apt-get update && apt-get install -y --no-install-recommends time procps build-essential cmake curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal

COPY vendor/bixverse-rs.tar.gz vendor/manifolds-rs.tar.gz /tmp/
RUN cd /tmp && tar xzf bixverse-rs.tar.gz && tar xzf manifolds-rs.tar.gz \
    && uv pip install --system /tmp/manifolds-rs/python \
    && uv pip install --system "/tmp/bixverse-rs/python[embed]" \
    && python -c 'from importlib.metadata import version as v; assert v("bixverse") == "0.3.1" and v("manifolds-rs") == "0.6.1"' \
    && rm -rf /tmp/bixverse-rs* /tmp/manifolds-rs* /opt/cargo/registry

COPY docker/monitor.sh docker/entrypoint.sh /bench/
ENTRYPOINT ["/bench/entrypoint.sh"]

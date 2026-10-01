FROM rocker/r-ver:4.6.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake curl git libhdf5-dev libglpk-dev libxml2-dev libssl-dev \
    libcurl4-openssl-dev libfftw3-dev libgsl-dev libpng-dev time procps \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal

# FIt-SNE binary for Seurat's tsne.method = "FIt-SNE"
RUN git clone --depth 1 https://github.com/KlugerLab/FIt-SNE /opt/FIt-SNE \
    && cd /opt/FIt-SNE && mkdir -p bin \
    && g++ -std=c++11 -O3 src/sptree.cpp src/tsne.cpp src/nbodyfft.cpp \
       -o bin/fast_tsne -pthread -lfftw3 -lm

RUN Rscript -e 'install.packages(c("remotes", "BiocManager", "data.table", "Seurat", "harmony", "leidenbase"), Ncpus = 8)'
RUN Rscript -e 'remotes::install_github("bnprks/BPCells/r", upgrade = "never")'
RUN apt-get update && apt-get install -y --no-install-recommends libbz2-dev liblzma-dev libzstd-dev \
    && rm -rf /var/lib/apt/lists/*
RUN Rscript -e 'BiocManager::install(c("scrapper", "rhdf5"), ask = FALSE, update = FALSE, Ncpus = 8)'
RUN Rscript -e 'install.packages(c("manifoldsR", "bixverse"), repos = c("https://gregorlueg.r-universe.dev", getOption("repos")), type = "source", Ncpus = 8); stopifnot(packageVersion("bixverse") >= "0.5.5")'

COPY docker/monitor.sh docker/entrypoint.sh /bench/
ENTRYPOINT ["/bench/entrypoint.sh"]

# OSCA: Bioconductor's HDF5-backed out-of-core path
RUN Rscript -e 'BiocManager::install(c("SingleCellExperiment", "HDF5Array", "DelayedArray", "scuttle", "scran", "scater", "BiocSingular", "bluster", "BiocParallel", "beachmat.hdf5"), ask = FALSE, update = FALSE, Ncpus = 8)'

# scbench-r plus bixverse 0.8.4 and manifoldsR from local checkouts, until they
# are on r-universe. bixverse patches bixverse-r to a pushed bixverse-rs branch,
# so cargo fetches that itself. Pack without build artefacts first (commits in
# vendor/SHAS):
#   COPYFILE_DISABLE=1 tar czf vendor/<pkg>.tar.gz --exclude target --exclude .git --exclude '*.o' --exclude '*.so' -C <parent> <pkg>
#   for bixverse and manifoldsR
#   docker build -f docker/r-local.Dockerfile -t scbench-r:local .
#   R_IMAGE=scbench-r:local scripts/run.sh bixverse <dataset>
FROM scbench-r
# manifoldsR ships its vendored crates as .tar.xz
RUN apt-get update && apt-get install -y --no-install-recommends xz-utils \
    && rm -rf /var/lib/apt/lists/*
COPY vendor/bixverse.tar.gz vendor/manifoldsR.tar.gz /tmp/
RUN cd /tmp && for p in bixverse manifoldsR; do tar xzf $p.tar.gz; done \
    && Rscript -e 'install.packages(c("/tmp/manifoldsR", "/tmp/bixverse"), repos = NULL, type = "source", Ncpus = 8); stopifnot(packageVersion("bixverse") >= "0.8.4", packageVersion("manifoldsR") >= "0.5.0")' \
    && rm -rf /tmp/bixverse* /tmp/manifoldsR*

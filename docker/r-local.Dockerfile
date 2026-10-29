# scbench-r plus bixverse and manifoldsR from local checkouts, until they are on
# r-universe. Both patch their crates to pushed bixverse-rs / manifolds-rs
# branches, so cargo fetches those itself; NOT_CRAN=true keeps manifoldsR off
# its offline vendored build. Pack without build artefacts or vendored crates
# first (commits in vendor/SHAS):
#   COPYFILE_DISABLE=1 tar czf vendor/<pkg>.tar.gz --exclude target --exclude .git --exclude '*.o' --exclude '*.so' --exclude src/vendor --exclude src/.cargo --exclude src/rust/vendor.tar.xz -C <parent> <pkg>
#   for bixverse and manifoldsR
#   docker build -f docker/r-local.Dockerfile -t scbench-r:local .
#   R_IMAGE=scbench-r:local scripts/run.sh bixverse <dataset>
FROM scbench-r
COPY vendor/bixverse.tar.gz vendor/manifoldsR.tar.gz /tmp/
RUN cd /tmp && for p in bixverse manifoldsR; do tar xzf $p.tar.gz; done \
    && NOT_CRAN=true Rscript -e 'install.packages(c("/tmp/manifoldsR", "/tmp/bixverse"), repos = NULL, type = "source", Ncpus = 8); stopifnot(packageVersion("bixverse") >= "0.8.4", packageVersion("manifoldsR") >= "0.6.0")' \
    && rm -rf /tmp/bixverse* /tmp/manifoldsR*

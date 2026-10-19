# scbench-r plus bixverse 0.8.0 and manifoldsR from local checkouts, until they
# are on r-universe. bixverse patches bixverse-r to a local bixverse-rs path, so
# that checkout comes along and the path is pointed at it. Pack without build
# artefacts first (commits in vendor/SHAS):
#   COPYFILE_DISABLE=1 tar czf vendor/<pkg>.tar.gz --exclude target --exclude .git --exclude '*.o' --exclude '*.so' -C <parent> <pkg>
#   for bixverse, bixverse-rs and manifoldsR
#   docker build -f docker/r-local.Dockerfile -t scbench-r:local .
#   R_IMAGE=scbench-r:local scripts/run.sh bixverse <dataset>
FROM scbench-r
COPY vendor/bixverse.tar.gz vendor/bixverse-rs.tar.gz vendor/manifoldsR.tar.gz /tmp/
RUN cd /tmp && for p in bixverse bixverse-rs manifoldsR; do tar xzf $p.tar.gz; done \
    && sed -i 's#path = "[^"]*/bixverse-rs/#path = "/tmp/bixverse-rs/#' bixverse/src/rust/Cargo.toml \
    && Rscript -e 'install.packages(c("/tmp/manifoldsR", "/tmp/bixverse"), repos = NULL, type = "source", Ncpus = 8); stopifnot(packageVersion("bixverse") >= "0.8.0", packageVersion("manifoldsR") >= "0.5.0")' \
    && rm -rf /tmp/bixverse* /tmp/manifoldsR*

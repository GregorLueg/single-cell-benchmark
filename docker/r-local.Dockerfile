# scbench-r plus bixverse from a local checkout, until it is on r-universe.
# Its crates come from crates.io; NOT_CRAN=true keeps it off the offline
# vendored build. Pack the committed tree first (commit in vendor/SHAS):
#   git -C <bixverse> archive --format=tar.gz --prefix=bixverse/ -o $PWD/vendor/bixverse.tar.gz <branch>
#   docker build -f docker/r-local.Dockerfile -t scbench-r:local .
#   R_IMAGE=scbench-r:local scripts/run.sh bixverse <dataset>
FROM scbench-r
COPY vendor/bixverse.tar.gz /tmp/
RUN cd /tmp && tar xzf bixverse.tar.gz \
    && NOT_CRAN=true Rscript -e 'install.packages("/tmp/bixverse", repos = NULL, type = "source", Ncpus = 8); stopifnot(packageVersion("bixverse") >= "0.9.0")' \
    && rm -rf /tmp/bixverse*

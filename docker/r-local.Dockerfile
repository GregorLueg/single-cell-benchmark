# TODO: drop once bixverse 0.6.0 is on r-universe; scbench-r then installs it.
# The bixverse rows of the simulation runs used this image: scbench-r plus
# bixverse 0.6.0 from a local checkout (bixverse-rs from the release-0.6.0
# branch on GitHub). Pack the checkout without build artefacts first:
#   COPYFILE_DISABLE=1 tar czf vendor/bixverse.tar.gz --exclude target --exclude '*.o' --exclude '*.so' -C <parent> bixverse
#   docker build -f docker/r-local.Dockerfile -t scbench-r:local .
#   R_IMAGE=scbench-r:local scripts/run.sh bixverse <dataset>
FROM scbench-r
COPY vendor/bixverse.tar.gz /tmp/
RUN cd /tmp && tar xzf bixverse.tar.gz \
    && Rscript -e 'install.packages("/tmp/bixverse", repos = NULL, type = "source", Ncpus = 8); stopifnot(packageVersion("bixverse") >= "0.6.0")' \
    && rm -rf /tmp/bixverse*

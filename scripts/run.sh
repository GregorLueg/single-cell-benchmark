#!/usr/bin/env bash
# Usage: [COLD=1|0] [INPUT=mtx|h5ad|dask] [BIX_KNN=kmknn] [BIX_TSNE_KNN=nndescent] [TAG=suffix] [STEP_TIMEOUT=2700] [R_IMAGE=scbench-r] scripts/run.sh <tool> <dataset>
#   tool: scanpy | cytearc | brisc | bixverse_py | seurat_bpcells | seurat_standard | scrapper | bixverse
# WARM=1 reconnects to the on-disk data the last cold run left in the scratch
# volume (bixverse | seurat_bpcells | cytearc only), so run the cold run first.
# Container is capped like a MacBook Air: 8 cores, 24 GB RAM plus swap.
# A run is killed when no step has finished for STEP_TIMEOUT seconds.
set -euo pipefail
tool="$1"; dataset="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
mem="${MEM:-24g}"; memswap="${MEMSWAP:-32g}"
warm="${WARM:-0}"; suffix=""; [ "$warm" = 1 ] && suffix="_warm"
out="$root/results/$dataset/$tool${suffix}${TAG:+_$TAG}"
rm -rf "$out"; mkdir -p "$out"

case "$tool" in
  scanpy) image=scbench-py; cmd=(python /bench/pipelines/scanpy_pipeline.py /data /out) ;;
  brisc)  image=scbench-brisc; cmd=(python /bench/pipelines/brisc_pipeline.py /data /out) ;;
  bixverse_py) image=scbench-bixverse-py; cmd=(python /bench/pipelines/bixverse_pipeline.py /data /out /scratch) ;;
  cytearc)
    image=scbench-cytearc; script=cytearc_pipeline.py; [ "$warm" = 1 ] && script=cytearc_warm.py
    cmd=(python "/bench/pipelines/$script" /data /out /scratch) ;;
  *)      image="${R_IMAGE:-scbench-r}";  cmd=(Rscript "/bench/pipelines/${tool}${suffix}.R" /data /out /scratch) ;;
esac

# on-disk scratch lives in a volume inside the VM, not a slow bind mount
if [ "$warm" != 1 ]; then
  docker volume rm -f scbench-scratch > /dev/null
  docker volume create scbench-scratch > /dev/null
fi

docker rm -f scbench-run > /dev/null 2>&1 || true

# cold read: empty the macOS file cache under the bind mount (COLD=0 skips it).
# Dropping the VM's page cache had no measurable effect. Needs a sudoers entry:
#   <user> ALL=(root) NOPASSWD: /usr/sbin/purge
if [ "${COLD:-1}" = 1 ]; then
  sudo -n /usr/sbin/purge || { echo "purge failed: add the sudoers entry or set COLD=0" >&2; exit 1; }
fi

# watchdog: steps.csv gains a line per finished step, so its mtime is the end
# of the last step (or the pipeline start)
step_timeout="${STEP_TIMEOUT:-2700}"
(
  start=$(date +%s)
  while sleep 10; do
    last=$(date -r "$out/steps.csv" +%s 2> /dev/null || echo "$start")
    if [ $(( $(date +%s) - last )) -gt "$step_timeout" ]; then
      touch "$out/TIMEOUT"
      docker kill scbench-run > /dev/null 2>&1
      break
    fi
  done
) &
watchdog=$!

status=0
docker run --rm --name scbench-run --cpus=8 --memory="$mem" --memory-swap="$memswap" --shm-size="${SHM:-64m}" \
  -e LOAD_ONLY="${LOAD_ONLY:-0}" -e OMP_NUM_THREADS=8 -e OPENBLAS_NUM_THREADS=8 -e RAYON_NUM_THREADS=8 -e INPUT="${INPUT:-mtx}" -e CHUNK="${CHUNK:-50000}" -e BIX_CSC_GB="${BIX_CSC_GB:-8}" -e BIX_KNN="${BIX_KNN:-nndescent}" -e BIX_TSNE_KNN="${BIX_TSNE_KNN:-kmknn}" -e BRISC_HOGWILD="${BRISC_HOGWILD:-0}" -e DGE_METHOD="${DGE_METHOD:-}" \
  -v "$root/data/$dataset:/data:ro" \
  -v "$out:/out" \
  -v "$root/pipelines:/bench/pipelines:ro" \
  -v scbench-scratch:/scratch \
  "$image" /out "${cmd[@]}" || status=$?
kill "$watchdog" 2> /dev/null || true
# what the tool left on disk (bixverse's store, BPCells' matrix dirs); input data excluded
docker run --rm -v scbench-scratch:/s --entrypoint du "$image" -sk /s 2> /dev/null | cut -f1 > "$out/scratch_kb" || true
# docker kill, or an OOM kill of the whole container, takes the entrypoint
# with it, so it never writes the exit line
if [ -f "$out/TIMEOUT" ]; then
  echo "exit=124" >> "$out/log.txt"
elif ! grep -q "^exit=" "$out/log.txt"; then
  echo "exit=$status" >> "$out/log.txt"
fi
exit "$status"

#!/usr/bin/env bash
# Usage: [BIX_KNN=nndescent] [BIX_TSNE_KNN=nndescent] [TAG=suffix] scripts/run.sh <tool> <dataset>
#   tool: scanpy | seurat_bpcells | seurat_standard | scrapper | bixverse
# Container is capped like a MacBook Air: 8 cores, 24 GB RAM plus swap.
set -euo pipefail
tool="$1"; dataset="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
mem="${MEM:-24g}"; memswap="${MEMSWAP:-32g}"
out="$root/results/$dataset/$tool${TAG:+_$TAG}"
rm -rf "$out"; mkdir -p "$out"

case "$tool" in
  scanpy) image=scbench-py; cmd=(python /bench/pipelines/scanpy_pipeline.py /data /out) ;;
  *)      image=scbench-r;  cmd=(Rscript "/bench/pipelines/${tool}.R" /data /out /scratch) ;;
esac

# on-disk scratch lives in a volume inside the VM, not a slow bind mount
docker volume rm -f scbench-scratch > /dev/null
docker volume create scbench-scratch > /dev/null

docker run --rm --cpus=8 --memory="$mem" --memory-swap="$memswap" \
  -e OMP_NUM_THREADS=8 -e OPENBLAS_NUM_THREADS=8 -e RAYON_NUM_THREADS=8 -e BIX_KNN="${BIX_KNN:-kmknn}" -e BIX_TSNE_KNN="${BIX_TSNE_KNN:-kmknn}" \
  -v "$root/data/$dataset:/data:ro" \
  -v "$out:/out" \
  -v "$root/pipelines:/bench/pipelines:ro" \
  -v scbench-scratch:/scratch \
  "$image" /out "${cmd[@]}"

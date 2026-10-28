#!/usr/bin/env bash
# Usage: [BACKEND=wgpu|mlx|cpu] [BIX_KNN=nndescent] [BIX_TSNE_KNN=kmknn] scripts/run_native.sh <dataset>
# Runs bixverse on the host: bixverse_gpu.R on Metal via wgpu or, with
# BACKEND=mlx, MLX (needs bixverse.gpu built against mlx-c); BACKEND=cpu runs
# the Docker CPU pipeline bixverse.R natively, the control for the GPU rows.
# No memory cap on macOS. RSS of the R process is sampled once a second instead
# of cgroup anon memory; it includes resident file-mapped pages, so the tables
# take the peak footprint that /usr/bin/time -l reports instead.
set -uo pipefail
dataset="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
backend="${BACKEND:-wgpu}"
case "$backend" in
  mlx) run=bixverse_mlx; script=bixverse_gpu.R ;;
  cpu) run=bixverse_native; script=bixverse.R ;;
  *)   run=bixverse_gpu; script=bixverse_gpu.R ;;
esac
out="$root/results/$dataset/$run"
scratch="$root/scratch_native"
rm -rf "$out" "$scratch"; mkdir -p "$out" "$scratch"

BACKEND="$backend" BIX_CSC_GB="${BIX_CSC_GB:-8}" BIX_KNN="${BIX_KNN:-kmknn}" BIX_TSNE_KNN="${BIX_TSNE_KNN:-kmknn}" \
  R_LIBS="$root/rlib" RAYON_NUM_THREADS=8 OMP_NUM_THREADS=8 OPENBLAS_NUM_THREADS=8 BENCH_DIR="$root" /usr/bin/time -l \
  Rscript "$root/pipelines/$script" "$root/data/$dataset" "$out" "$scratch" \
  > "$out/log.txt" 2>&1 &
pid=$!
echo "t,anon_bytes,file_bytes,swap_bytes" > "$out/mem.csv"
while kill -0 "$pid" 2> /dev/null; do
  rss=$(ps -o rss= -p "$(pgrep -P "$pid" -n R 2>/dev/null || echo "$pid")" 2>/dev/null | tr -d ' ')
  echo "$(python3 -c 'import time; print(time.time())'),$(( ${rss:-0} * 1024 )),0,0" >> "$out/mem.csv"
  sleep 1
done
wait "$pid"; status=$?
echo "exit=$status" >> "$out/log.txt"
du -sk "$scratch" | cut -f1 > "$out/scratch_kb"
rm -rf "$scratch"

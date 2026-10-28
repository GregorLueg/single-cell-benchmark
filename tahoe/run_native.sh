#!/usr/bin/env bash
# Usage: [DATA=dir] [BACKEND=mlx|wgpu] [WALL=18000] tahoe/run_native.sh
# bixverse.gpu on the host (Docker has no Metal), same steps and defaults as
# tahoe/run.sh. No memory cap on macOS. Samples once a second: RSS of the R
# process (includes resident file-mapped pages, so the tables take the peak
# footprint from /usr/bin/time -l), and system-wide swap used above its value at
# the start plus pages swapped out since, which only mean something on a quiet
# machine.
set -uo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
data="${DATA:-$HOME/Desktop/tahoe100m_h5ad}"
dataset="${DATASET:-tahoe}"
backend="${BACKEND:-mlx}"
out="$root/results/$dataset/bixverse_$backend${TAG:+_$TAG}"
scratch="$root/scratch_native"
rm -rf "$out" "$scratch"; mkdir -p "$out" "$scratch"

swap_mb() { sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/'; }
swapouts() { vm_stat | awk '/Swapouts/ {gsub("\\.", "", $2); print $2}'; }
swap0=$(swap_mb); outs0=$(swapouts)

BACKEND="$backend" BENCH_DIR="$root" BIX_CSC_GB="${BIX_CSC_GB:-24}" MIN_CELLS="${MIN_CELLS:-9000}" \
  MT_MAX="${MT_MAX:-15}" TRUTH_COL="${TRUTH_COL:-cell_line}" BATCH_COL="${BATCH_COL:-plate}" \
  DGE_COL="${DGE_COL:-drug}" DGE_CTRL="${DGE_CTRL:-DMSO_TF}" DGE_CASE="${DGE_CASE:-Gemcitabine}" GENE_COL="${GENE_COL:-}" \
  RAYON_NUM_THREADS=8 OMP_NUM_THREADS=8 OPENBLAS_NUM_THREADS=8 /usr/bin/time -l \
  Rscript "$root/pipelines/bixverse_gpu.R" "$data" "$out" "$scratch" \
  > "$out/log.txt" 2>&1 &
pid=$!
wall="${WALL:-18000}"; start=$(date +%s)
echo "t,anon_bytes,file_bytes,swap_bytes,swapouts" > "$out/mem.csv"
while kill -0 "$pid" 2> /dev/null; do
  rss=$(ps -o rss= -p "$(pgrep -P "$pid" -n R 2>/dev/null || echo "$pid")" 2>/dev/null | tr -d ' ')
  swap=$(awk -v a="$(swap_mb)" -v b="$swap0" 'BEGIN { d = (a - b) * 1048576; print (d > 0 ? int(d) : 0) }')
  echo "$(date +%s),$(( ${rss:-0} * 1024 )),0,$swap,$(( $(swapouts) - outs0 ))" >> "$out/mem.csv"
  if [ $(( $(date +%s) - start )) -gt "$wall" ]; then touch "$out/TIMEOUT"; pkill -P "$pid"; kill "$pid"; fi
  sleep 1
done
wait "$pid"; status=$?
echo "exit=$status" >> "$out/log.txt"
du -sk "$scratch" | cut -f1 > "$out/scratch_kb"
rm -rf "$scratch"

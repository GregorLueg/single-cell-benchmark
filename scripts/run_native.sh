#!/usr/bin/env bash
# Usage: scripts/run_native.sh <dataset>
# Runs bixverse_gpu.R on the host (Metal). No memory cap on macOS; RSS of the
# R process is sampled once a second instead of cgroup anon memory, and it
# includes resident file-mapped pages.
set -uo pipefail
dataset="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/results/$dataset/bixverse_gpu"
scratch="$root/scratch_native"
rm -rf "$out" "$scratch"; mkdir -p "$out" "$scratch"

BIX_CSC_GB="${BIX_CSC_GB:-8}" R_LIBS="$root/rlib" RAYON_NUM_THREADS=8 BENCH_DIR="$root" /usr/bin/time -l \
  Rscript "$root/pipelines/bixverse_gpu.R" "$root/data/$dataset" "$out" "$scratch" \
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

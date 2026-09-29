#!/usr/bin/env bash
# Usage: entrypoint.sh <out_dir> <command...>
set -u
out="$1"; shift
mkdir -p "$out"
/bench/monitor.sh "$out/mem.csv" &
mon=$!
/usr/bin/time -v "$@" > "$out/log.txt" 2>&1
status=$?
kill "$mon"
echo "exit=$status" >> "$out/log.txt"
exit "$status"

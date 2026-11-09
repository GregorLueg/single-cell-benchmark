#!/usr/bin/env bash
# Samples container memory from cgroup v2 once a second. anon is the figure
# that matters; file is reclaimable page cache and inflates for streaming tools.
out="$1"
echo "t,anon_bytes,file_bytes,swap_bytes,shmem_bytes,file_mapped_bytes" > "$out"
while true; do
  anon=$(awk '$1=="anon"{print $2}' /sys/fs/cgroup/memory.stat)
  file=$(awk '$1=="file"{print $2}' /sys/fs/cgroup/memory.stat)
  shmem=$(awk '$1=="shmem"{print $2}' /sys/fs/cgroup/memory.stat)
  mapped=$(awk '$1=="file_mapped"{print $2}' /sys/fs/cgroup/memory.stat)
  swap=$(cat /sys/fs/cgroup/memory.swap.current 2>/dev/null || echo 0)
  echo "$(date +%s.%N),$anon,$file,$swap,$shmem,$mapped" >> "$out"
  sleep 1
done

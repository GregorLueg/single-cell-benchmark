#!/usr/bin/env bash
# Same-input Harmony benchmark: 3 reps per implementation and size, one process each
cd "$(dirname "$0")/../.."
B=scripts/harmony_bench
R=results/harmony_bench
PY=${HARMONYPY_PYTHON:-$B/.venv/bin/python}
echo "size,impl,rep,seconds,max_rss_bytes" > $R/runs.csv
for ds in splat_100k splat_1m; do
  in=$R/input_$ds.csv
  for impl in none_r none_py v1 v2 v2_b05 gpu mlx harmonypy; do
    for rep in 1 2 3; do
      out=$R/$ds/$impl/rep$rep
      mkdir -p "$(dirname "$out")"
      case $impl in
        none_r) cmd=(Rscript $B/run_bix.R "$in" none "$out") ;;
        none_py) cmd=($PY $B/run_py.py "$in" none "$out") ;;
        harmonypy) cmd=($PY $B/run_py.py "$in" harmonypy "$out") ;;
        *) cmd=(Rscript $B/run_bix.R "$in" "$impl" "$out") ;;
      esac
      /usr/bin/time -l "${cmd[@]}" 2> "$out.log"
      rss=$(grep "maximum resident set size" "$out.log" | awk '{print $1}')
      echo "$ds,$impl,$rep,$(cat "$out.time" 2>/dev/null),$rss" >> $R/runs.csv
    done
  done
  echo "$(date +%H:%M) $ds done"
done

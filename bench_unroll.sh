#!/usr/bin/env bash
# Build and time each bench/ program with and without Shoggoth's scalar loop
# unroller (`SHOGGOTH_DISABLE=unroll`).
#
# Usage:
#   ./bench_unroll.sh                         # native backend, -d:release, 3 runs
#   BACKEND=c ./bench_unroll.sh               # C backend
#   OPT_FLAGS="-d:danger" RUNS=5 ./bench_unroll.sh
#   BENCHES="matmul rex_perf nifbench" ./bench_unroll.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
NIMONY="${NIMONY:-$ROOT/bin/nimony}"
BACKEND="${BACKEND:-n}"
OPT_FLAGS="${OPT_FLAGS:--d:release}"
RUNS="${RUNS:-3}"
OUT_DIR="${OUT_DIR:-/tmp/bench_unroll_${BACKEND}}"
BENCHES="${BENCHES:-matmul raytracer nifbench rex_perf alloc_bench gcbench}"

if [[ ! -x "$NIMONY" ]]; then
  echo "error: $NIMONY not found; build with './bin/hastur build nimony'" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

text_bytes() {
  size -A "$1" 2>/dev/null | awk '$1 == ".text" { print $2; found = 1 } END { if (!found) print 0 }'
}

best_ms() {
  local bin="$1" best="" i t0 t1 ms
  for ((i = 1; i <= RUNS; i++)); do
    t0=$(date +%s%N)
    "$bin" > "$OUT_DIR/last.out"
    t1=$(date +%s%N)
    ms=$(( (t1 - t0) / 1000000 ))
    if [[ -z "$best" || "$ms" -lt "$best" ]]; then
      best="$ms"
    fi
  done
  echo "$best"
}

echo "Backend: $BACKEND | Flags: $OPT_FLAGS | Runs: $RUNS | Out: $OUT_DIR"
echo

summary=()
for name in $BENCHES; do
  src="$ROOT/bench/${name}.nim"
  bin_off="$OUT_DIR/${name}_off"
  bin_on="$OUT_DIR/${name}_on"

  echo "=== Building $name ==="
  rm -rf "$OUT_DIR/cache_off_${name}" "$OUT_DIR/cache_on_${name}"
  # shellcheck disable=SC2086
  SHOGGOTH_DISABLE=unroll "$NIMONY" "$BACKEND" $OPT_FLAGS \
    --nimcache:"$OUT_DIR/cache_off_${name}" -o:"$bin_off" "$src" >/dev/null
  # shellcheck disable=SC2086
  "$NIMONY" "$BACKEND" $OPT_FLAGS \
    --nimcache:"$OUT_DIR/cache_on_${name}" -o:"$bin_on" "$src" >/dev/null

  txt_off=$(text_bytes "$bin_off")
  txt_on=$(text_bytes "$bin_on")

  echo "--- Running $name (unroll OFF, $RUNS runs) ---"
  ms_off=$(best_ms "$bin_off")
  cat "$OUT_DIR/last.out"

  echo "--- Running $name (unroll ON, $RUNS runs) ---"
  ms_on=$(best_ms "$bin_on")
  cat "$OUT_DIR/last.out"

  ratio=$(awk -v a="$ms_off" -v b="$ms_on" 'BEGIN { if (b > 0) printf "%.3fx", a / b; else print "n/a" }')
  summary+=("$(printf "%-12s  .text: %7d -> %7d (%+6d)   best_ms: %6d -> %6d  (%s)" \
    "$name" "$txt_off" "$txt_on" "$((txt_on - txt_off))" "$ms_off" "$ms_on" "$ratio")")
  echo
done

echo "=== Summary (best of $RUNS runs, $BACKEND $OPT_FLAGS) ==="
printf '%s\n' "${summary[@]}"

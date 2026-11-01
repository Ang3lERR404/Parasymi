#!/bin/sh
#! bench.sh <label> <aa> [game flags]: one benchmark run of the release build (build it first:
#! `zig build -Drelease=true`) with antialias <aa> (off|fxaa|msaa4|msaa8), vsync off, at
#! --tod=0.45; prints each pass's GPU ms over 0.1 and the frame's total. The game logs its
#! eased per-pass times as it closes (engine render/renderer.zig `logTimes`), so give it
#! flags that end the run, e.g. `--demo --inspect=player --shots=2 --orbit=8`.
#! The gardener's options.cfg is backed up and put back after. Run from anywhere.
# where the repository is, from this script's own place
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo" || exit 1
# the gardener's options, whose antialias is switched for the run
cfg="$LOCALAPPDATA/Parasymi/options.cfg"
label=$1; aa=$2; shift 2
cp "$cfg" "$cfg.benchbak"
sed -i "s/^antialias = .*/antialias = $aa/" "$cfg"
out=$(timeout 200 zig-out/bin/Parasymi.exe --novsync --tod=0.45 "$@" 2>&1 | grep "info: gpu ")
mv "$cfg.benchbak" "$cfg"
rm -rf shots
echo "== $label aa=$aa $(echo "$out" | grep 'gpu total' | sed 's/.*gpu //')"
echo "$out" | grep -v "gpu total" | sed 's/.*gpu //' | awk '$2>0.1{printf "  %-16s %6.2f\n",$1,$2}'

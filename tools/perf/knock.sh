#!/bin/sh
#! knock.sh <label> <file> <old> <new> [bench flags]: a knock-out. Swaps the one place
#! <old> appears in <file> (a shader, usually) for <new>, builds release, benches it
#! (bench.sh, msaa8, `--demo --inspect=player --shots=2 --orbit=8` unless flags are given)
#! and puts the file back as it was, whatever happened. What a piece costs is the base
#! time less the time without it. Never commit a knocked-out file; check `git status`.
# where the repository is, and this script's own folder
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo" || exit 1
label=$1; file=$2; old=$3; new=$4; shift 4
[ $# -eq 0 ] && set -- --demo --inspect=player --shots=2 --orbit=8
# the file as it was, kept beside it while knocked out
bak=$(mktemp)
cp "$file" "$bak"
if python -I "$here/swap.py" "$file" "$old" "$new"; then
  zig build -Drelease=true 2>&1 | head -5
  sh "$here/bench.sh" "$label" msaa8 "$@"
fi
cp "$bak" "$file"
rm -f "$bak"

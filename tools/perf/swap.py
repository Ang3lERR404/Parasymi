"""swap.py <file> <old> <new>: replaces the one place <old> appears in <file> with <new>
(fails, touching nothing, unless it appears exactly once); keeps LF line endings. Used by
knock.sh. From Git Bash, an argument starting with / is rewritten as a Windows path:
start <old>/<new> with something else (a space), or call it from a script file."""
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, newline='').read()
n = s.count(old)
if n != 1:
    print(f"swap: {n} matches for {old!r} in {path}")
    sys.exit(1)
open(path, 'w', newline='').write(s.replace(old, new))

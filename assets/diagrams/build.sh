#!/bin/bash
# Regenerates the README diagrams. Needs python3 and inkscape.
set -euo pipefail
cd "$(dirname "$0")"
python3 gen.py
for f in arch flow; do for th in light dark; do
  inkscape "src-$f-$th.svg" --export-text-to-path --export-plain-svg --export-filename="$f-$th.svg" 2>/dev/null
  rm "src-$f-$th.svg"
done; done

#!/usr/bin/env bash
# Checks rules/*.txt against tests/examples/*.txt and tests/clean.txt.
#   - every line in tests/examples/<rule>.txt must match rules/<rule>.txt
#   - no line in tests/clean.txt may match any rule
#   - every rule file must have an examples file
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
strip() { grep -vE '^[[:space:]]*(#|$)' "$1" || true; }
fail=0

for rule in "$root"/rules/*.txt; do
  name="$(basename "$rule" .txt)"
  ex="$root/tests/examples/$name.txt"
  if [[ ! -f "$ex" ]]; then echo "FAIL $name: missing tests/examples/$name.txt"; fail=1; continue; fi
  if ! grep -qvE '^[[:space:]]*(#|$)' "$rule"; then echo "FAIL $name: rule file has no patterns"; fail=1; fi
  while IFS= read -r line; do
    if ! grep -qiE -f <(strip "$rule") <<< "$line"; then echo "FAIL $name: not matched: $line"; fail=1; fi
  done < <(strip "$ex")
done

all="$(for r in "$root"/rules/*.txt; do strip "$r"; done)"
while IFS= read -r line; do
  if grep -qiE -f <(printf '%s\n' "$all") <<< "$line"; then echo "FAIL clean: false positive: $line"; fail=1; fi
done < <(strip "$root/tests/clean.txt")

(( fail )) && exit 1
echo "OK: $(ls "$root"/rules/*.txt | wc -l) rule sets"

#!/usr/bin/env bash
# Scans commit messages and PR text for AI-agent marketing/attribution lines.
#
# Rules are plain text files: one case-insensitive extended regex per line,
# '#' comments and blank lines ignored. The rule name is the file's basename.
set -euo pipefail

for bin in jq gh grep base64; do
  command -v "$bin" >/dev/null || { echo "::error::$bin is required but not installed"; exit 1; }
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
builtin_dir="$root/rules"
workspace="${GITHUB_WORKSPACE:-$PWD}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/rules" "$work/texts"

# Splits a comma/space/newline separated list into one item per line.
split_list() { tr ', ' '\n\n' <<< "${1:-}" | sed '/^$/d'; }
strip() { grep -vE '^[[:space:]]*(#|$)' || true; }
# Escapes text for a workflow command message.
esc() { local s="${1//%/%25}"; s="${s//$'\r'/%0D}"; printf '%s' "${s//$'\n'/%0A}"; }

# ---------------------------------------------------------------- rules
selected="$(split_list "${INPUT_RULES:-all}")"
excluded="$(split_list "${INPUT_EXCLUDE_RULES:-}")"
case "$selected" in
  all)  selected="$(cd "$builtin_dir" && ls *.txt | sed 's/\.txt$//')" ;;
  none) selected="" ;;
esac
while IFS= read -r r; do
  [[ -n "$r" ]] || continue
  grep -qxF "$r" <<< "$excluded" && continue
  [[ -f "$builtin_dir/$r.txt" ]] || {
    echo "::error::Unknown built-in rule '$r'. Available: $(cd "$builtin_dir" && ls *.txt | sed 's/\.txt$//' | paste -sd, -)"
    exit 1
  }
  strip < "$builtin_dir/$r.txt" > "$work/rules/$r"
done <<< "$selected"

# Custom rule files from the calling repo (paths relative to the workspace).
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  [[ "$f" = /* ]] || f="$workspace/$f"
  [[ -f "$f" ]] || { echo "::error::Rule file not found: $f (did you run actions/checkout?)"; exit 1; }
  name="$(basename "$f")"; name="${name%.*}"
  strip < "$f" >> "$work/rules/$name"
done <<< "$(printf '%s\n' "${INPUT_RULE_FILES:-}" | sed '/^[[:space:]]*$/d')"

printf '%s\n' "${INPUT_EXTRA_PATTERNS:-}" | strip > "$work/rules/custom"
printf '%s\n' "${INPUT_ALLOW_PATTERNS:-}" | strip > "$work/allow"

find "$work/rules" -type f -empty -delete
if [[ -z "$(ls -A "$work/rules")" ]]; then
  echo "::warning::No rules enabled; nothing to check."
  { echo "found=false"; echo "count=0"; echo "matches=[]"; } >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi
echo "Rules: $(ls "$work/rules" | paste -sd, -)"

# -------------------------------------------------------------- sources
sources="$(split_list "${INPUT_SOURCES:-commits,pr-title,pr-body}")"
has() { grep -qxF "$1" <<< "$sources"; }
event="${GITHUB_EVENT_PATH:-}"
is_pr=false
[[ "${GITHUB_EVENT_NAME:-}" == pull_request || "${GITHUB_EVENT_NAME:-}" == pull_request_target ]] && is_pr=true

n=0
add() { # add <source> <ref> <text>
  n=$((n + 1))
  printf '%s\t%s\n' "$1" "$2" > "$work/texts/$n.meta"
  printf '%s\n' "$3" > "$work/texts/$n.txt"
}

if $is_pr; then
  has pr-title && add pr-title "#$(jq -r '.pull_request.number' "$event")" "$(jq -r '.pull_request.title // ""' "$event")"
  has pr-body  && add pr-body  "#$(jq -r '.pull_request.number' "$event")" "$(jq -r '.pull_request.body // ""' "$event")"
fi

if has commits; then
  rows=""
  if $is_pr; then
    url="$(jq -r '.pull_request.commits_url' "$event")"
    # Captured first so an API failure fails the job instead of silently passing.
    rows="$(gh api --paginate "$url" --jq '.[] | [.sha, (.commit.message | @base64)] | @tsv')"
  elif [[ -n "$event" && -f "$event" ]]; then
    rows="$(jq -r '(.commits // [])[] | [.id, (.message | @base64)] | @tsv' "$event")"
  fi
  while IFS=$'\t' read -r sha msg; do
    [[ -n "$sha" ]] || continue
    add commit "$sha" "$(printf '%s' "$msg" | base64 -d)"
  done <<< "$rows"
fi

# ----------------------------------------------------------------- scan
lvl=error; [[ "${INPUT_FAIL:-true}" == "true" ]] || lvl=warning
: > "$work/matches.jsonl"
for ((i = 1; i <= n; i++)); do
  IFS=$'\t' read -r src ref < "$work/texts/$i.meta"
  txt="$work/texts/$i.txt"
  # "<line>\t<rule>\t<text>" for each matching line, first rule wins.
  for rule in "$work"/rules/*; do
    grep -inE -f "$rule" "$txt" | sed "s/^\([0-9]*\):/\1\t$(basename "$rule")\t/" || true
  done | sort -t$'\t' -k1,1n -s | awk -F'\t' '!seen[$1]++' > "$work/hits"
  while IFS=$'\t' read -r line rule text; do
    [[ -n "$line" ]] || continue
    if [[ -s "$work/allow" ]] && grep -qiE -f "$work/allow" <<< "$text"; then continue; fi
    label="$src"; [[ "$src" == commit ]] && label="commit ${ref:0:7}"
    echo "::${lvl} title=$(esc "Agent marketing in $label ($rule)")::$(esc "line $line: $text")"
    jq -nc --arg source "$src" --arg ref "$ref" --argjson line "$line" --arg rule "$rule" --arg text "$text" \
      '{source: $source, ref: $ref, line: $line, rule: $rule, text: $text}' >> "$work/matches.jsonl"
  done < "$work/hits"
done

count="$(wc -l < "$work/matches.jsonl" | tr -d ' ')"
found=false; [[ "$count" -gt 0 ]] && found=true
{
  echo "found=$found"
  echo "count=$count"
  echo "matches=$(jq -sc . "$work/matches.jsonl")"
} >> "${GITHUB_OUTPUT:-/dev/null}"

echo "Checked $n item(s); $count match(es)."
if $found && [[ "${INPUT_FAIL:-true}" == "true" ]]; then
  echo "${INPUT_FAILURE_MESSAGE:-Remove AI-agent attribution/marketing lines (reword commits with 'git rebase -i', edit the PR title/description).}"
  exit 1
fi

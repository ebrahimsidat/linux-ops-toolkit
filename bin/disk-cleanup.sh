#!/usr/bin/env bash
# disk-cleanup.sh - reclaim space safely. Dry run by default; nothing is removed without --apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: disk-cleanup.sh [options] DIR [DIR...]

Find and optionally delete old files under the given directories.

Options:
  -d, --days N          Only files not modified in the last N days (default: 14)
  -p, --pattern GLOB    File name pattern, repeatable (default: *.log.* *.gz *.tmp core.*)
  -m, --min-size SIZE   Only files at least this size, find(1) syntax, e.g. 10M (default: none)
      --journal SIZE    Also vacuum the systemd journal down to SIZE, e.g. 500M (needs --apply)
      --apply           Delete files. Without it, only report what would be removed.
  -h, --help            Show this help

Exit codes: 0 success, 3 usage or safety error.
USAGE
}

days=14
min_size=""
journal_size=""
apply=0
patterns=()
dirs=()

while (($#)); do
  case "$1" in
    -d | --days)
      days="${2:-}"
      shift 2
      ;;
    -p | --pattern)
      patterns+=("${2:-}")
      shift 2
      ;;
    -m | --min-size)
      min_size="${2:-}"
      shift 2
      ;;
    --journal)
      journal_size="${2:-}"
      shift 2
      ;;
    --apply)
      apply=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      dirs+=("$@")
      break
      ;;
    -*)
      usage >&2
      die "unknown option: $1"
      ;;
    *)
      dirs+=("$1")
      shift
      ;;
  esac
done

is_positive_int "$days" || die "--days must be a positive integer"
[[ -z "$min_size" || "$min_size" =~ ^[0-9]+[kMG]?$ ]] || die "--min-size must look like 512k, 10M or 1G"
((${#dirs[@]})) || {
  usage >&2
  die "at least one directory is required"
}
((${#patterns[@]})) || patterns=('*.log.*' '*.gz' '*.tmp' 'core.*')

for dir in "${dirs[@]}"; do
  [[ -d "$dir" ]] || die "not a directory: $dir"
  is_protected_path "$dir" && die "refusing to clean a top-level system directory: $dir"
done

# Build: ( -name p1 -o -name p2 ... )
name_expr=("(")
for i in "${!patterns[@]}"; do
  ((i > 0)) && name_expr+=(-o)
  name_expr+=(-name "${patterns[$i]}")
done
name_expr+=(")")

size_expr=()
[[ -n "$min_size" ]] && size_expr=(-size "+${min_size}")

total_bytes=0
total_files=0
mode="DRY RUN"
((apply)) && mode="APPLY"
log INFO "mode=${mode} days=${days} patterns=${patterns[*]}"

for dir in "${dirs[@]}"; do
  while IFS= read -r -d '' entry; do
    size="${entry%%$'\t'*}"
    file="${entry#*$'\t'}"
    total_bytes=$((total_bytes + size))
    total_files=$((total_files + 1))
    if ((apply)); then
      rm -f -- "$file"
      printf 'deleted\t%s\t%s\n' "$(human_bytes "$size")" "$file"
    else
      printf 'would delete\t%s\t%s\n' "$(human_bytes "$size")" "$file"
    fi
  done < <(find "$dir" -xdev -type f "${name_expr[@]}" -mtime "+$((days - 1))" "${size_expr[@]}" -printf '%s\t%p\0')
done

if [[ -n "$journal_size" ]]; then
  if ((apply)) && have journalctl; then
    journalctl --vacuum-size="$journal_size"
  else
    log INFO "journal vacuum to ${journal_size} skipped (dry run or journalctl unavailable)"
  fi
fi

verb="reclaimable"
((apply)) && verb="reclaimed"
printf 'SUMMARY: %d files, %s %s\n' "$total_files" "$(human_bytes "$total_bytes")" "$verb"

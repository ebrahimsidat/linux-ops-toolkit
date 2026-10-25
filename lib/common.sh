#!/usr/bin/env bash
# Shared helpers for linux-ops-toolkit. Source this file; do not execute it.

# Exit codes shared by every tool (Nagios-compatible where it matters).
# shellcheck disable=SC2034  # consumed by the scripts that source this file
readonly EXIT_OK=0
readonly EXIT_WARNING=1
readonly EXIT_CRITICAL=2
readonly EXIT_UNKNOWN=3

LOT_QUIET="${LOT_QUIET:-0}"

log() {
  # log LEVEL MESSAGE... -> timestamped line on stderr
  local level="$1"
  shift
  [[ "$LOT_QUIET" == "1" && "$level" == "INFO" ]] && return 0
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" >&2
}

die() {
  log ERROR "$*"
  exit "$EXIT_UNKNOWN"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    have "$cmd" || die "required command not found: $cmd"
  done
}

human_bytes() {
  # human_bytes 1536 -> 1.5K
  local bytes="${1:-0}"
  awk -v b="$bytes" 'BEGIN {
    split("B K M G T P", u, " ");
    i = 1;
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d%s\n", b, u[i]; else printf "%.1f%s\n", b, u[i];
  }'
}

is_positive_int() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && (( 10#$1 > 0 ))
}

# Directories that cleanup tools must never operate on directly.
is_protected_path() {
  local path
  path="$(realpath -m -- "$1")"
  case "$path" in
    / | /bin | /boot | /dev | /etc | /home | /lib | /lib64 | /opt | /proc | /root | /run | /sbin | /srv | /sys | /usr | /var)
      return 0
      ;;
  esac
  return 1
}

#!/usr/bin/env bash
# check-certs.sh - TLS certificate expiry check for endpoints and PEM files, with Nagios exit codes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: check-certs.sh [options] TARGET [TARGET...]

TARGET is host:port (checked over TLS with SNI) or a path to a PEM certificate file.

Options:
  -w, --warning DAYS    Warning when a certificate expires within DAYS (default: 30)
  -c, --critical DAYS   Critical when a certificate expires within DAYS (default: 14)
  -f, --file LIST       Read targets from LIST, one per line ('#' comments allowed)
  -t, --timeout SEC     Connection timeout per endpoint (default: 10)
  -h, --help            Show this help

Exit codes: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN (the worst result across all targets).
USAGE
}

warn_days=30
crit_days=14
timeout_s=10
targets=()

while (($#)); do
  case "$1" in
    -w | --warning)
      warn_days="${2:-}"
      shift 2
      ;;
    -c | --critical)
      crit_days="${2:-}"
      shift 2
      ;;
    -t | --timeout)
      timeout_s="${2:-}"
      shift 2
      ;;
    -f | --file)
      [[ -r "${2:-}" ]] || die "cannot read target list: ${2:-}"
      while IFS= read -r line; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [[ -n "$line" ]] && targets+=("$line")
      done <"$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      die "unknown option: $1"
      ;;
    *)
      targets+=("$1")
      shift
      ;;
  esac
done

is_positive_int "$warn_days" || die "--warning must be a positive integer"
is_positive_int "$crit_days" || die "--critical must be a positive integer"
is_positive_int "$timeout_s" || die "--timeout must be a positive integer"
((crit_days <= warn_days)) || die "--critical must not exceed --warning"
((${#targets[@]})) || {
  usage >&2
  die "at least one target is required"
}
require_cmd openssl

# Print the leaf certificate (PEM) for a target, or fail.
fetch_cert() {
  local target="$1"
  if [[ -f "$target" ]]; then
    openssl x509 -in "$target" 2>/dev/null
    return
  fi
  local host="${target%:*}" port="${target##*:}"
  [[ "$target" == *:* && "$port" =~ ^[0-9]+$ ]] || return 1
  timeout "$timeout_s" openssl s_client -connect "${host}:${port}" -servername "$host" </dev/null 2>/dev/null |
    openssl x509 2>/dev/null
}

worst=$EXIT_OK
now=$(date +%s)

for target in "${targets[@]}"; do
  if ! pem="$(fetch_cert "$target")" || [[ -z "$pem" ]]; then
    printf 'UNKNOWN  %s: unable to read certificate\n' "$target"
    ((worst < EXIT_UNKNOWN)) && worst=$EXIT_UNKNOWN
    continue
  fi
  end_raw="$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)"
  subject="$(openssl x509 -noout -subject -nameopt RFC2253 <<<"$pem" | sed 's/^subject=//')"
  end_epoch="$(date -d "$end_raw" +%s)"
  days_left=$(((end_epoch - now) / 86400))

  if ((end_epoch <= now)); then
    status="CRITICAL"
    code=$EXIT_CRITICAL
    detail="expired ${end_raw}"
  elif ((days_left < crit_days)); then
    status="CRITICAL"
    code=$EXIT_CRITICAL
    detail="expires in ${days_left} days (${end_raw})"
  elif ((days_left < warn_days)); then
    status="WARNING"
    code=$EXIT_WARNING
    detail="expires in ${days_left} days (${end_raw})"
  else
    status="OK"
    code=$EXIT_OK
    detail="${days_left} days left (${end_raw})"
  fi
  printf '%-8s %s: %s [%s]\n' "$status" "$target" "$detail" "$subject"

  # UNKNOWN (3) must not mask CRITICAL (2), so rank explicitly.
  if ((worst == EXIT_UNKNOWN)); then
    ((code == EXIT_CRITICAL)) && worst=$EXIT_CRITICAL
  elif ((code == EXIT_CRITICAL)) || ((code > worst)); then
    worst=$code
  fi
done

exit "$worst"

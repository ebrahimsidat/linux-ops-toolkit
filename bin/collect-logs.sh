#!/usr/bin/env bash
# collect-logs.sh - gather a diagnostic bundle for a support case or post-incident review.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: collect-logs.sh [options]

Create a compressed bundle with system information, the journal, selected log files and a
triage report. Every file is listed in a SHA-256 manifest so the bundle can be verified.

Options:
  -s, --since HOURS     Journal window in hours (default: 24)
  -o, --output-dir DIR  Where to write the bundle (default: /tmp)
  -u, --unit UNIT       Include the journal of a systemd unit, repeatable
  -f, --file PATH       Include an extra log file, repeatable
      --redact          Mask IPv4 addresses and e-mail addresses in collected text
  -h, --help            Show this help
USAGE
}

since=24
outdir="/tmp"
redact=0
units=()
extra_files=()

while (($#)); do
  case "$1" in
    -s | --since)
      since="${2:-}"
      shift 2
      ;;
    -o | --output-dir)
      outdir="${2:-}"
      shift 2
      ;;
    -u | --unit)
      units+=("${2:-}")
      shift 2
      ;;
    -f | --file)
      extra_files+=("${2:-}")
      shift 2
      ;;
    --redact)
      redact=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown option: $1"
      ;;
  esac
done

is_positive_int "$since" || die "--since must be a positive integer"
[[ -d "$outdir" && -w "$outdir" ]] || die "output directory is not writable: $outdir"
require_cmd tar sha256sum

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
host="$(hostname -s 2>/dev/null || cat /proc/sys/kernel/hostname)"
name="diag-${host}-${stamp}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bundle="${work}/${name}"
mkdir -p "${bundle}/system" "${bundle}/logs" "${bundle}/journal"

capture() {
  # capture FILE CMD... -> run CMD, save stdout+stderr, never fail the bundle
  local file="$1"
  shift
  "$@" >"$file" 2>&1 || true
}

log INFO "collecting system information"
capture "${bundle}/system/uname.txt" uname -a
capture "${bundle}/system/uptime.txt" uptime
capture "${bundle}/system/df.txt" df -hPT
capture "${bundle}/system/df-inodes.txt" df -hiP
capture "${bundle}/system/free.txt" free -h
capture "${bundle}/system/ps.txt" ps auxww --sort=-pcpu
capture "${bundle}/system/mounts.txt" cat /proc/mounts
[[ -r /etc/os-release ]] && cp /etc/os-release "${bundle}/system/os-release.txt"
have ip && capture "${bundle}/system/ip-addr.txt" ip -br addr
have ss && capture "${bundle}/system/sockets.txt" ss -tulpn
have lsblk && capture "${bundle}/system/lsblk.txt" lsblk -f
have rpm && capture "${bundle}/system/packages.txt" rpm -qa --last
have dpkg-query && capture "${bundle}/system/packages.txt" dpkg-query -W
have systemctl && capture "${bundle}/system/failed-units.txt" systemctl list-units --failed --no-pager

LOT_QUIET=1 capture "${bundle}/triage.txt" bash "${SCRIPT_DIR}/triage.sh"

if have journalctl; then
  log INFO "exporting journal for the last ${since}h"
  capture "${bundle}/journal/system.log" journalctl --since "-${since}h" --no-pager -o short-iso
  capture "${bundle}/journal/kernel.log" journalctl -k --since "-${since}h" --no-pager -o short-iso
  for unit in "${units[@]}"; do
    capture "${bundle}/journal/${unit//\//_}.log" journalctl -u "$unit" --since "-${since}h" --no-pager -o short-iso
  done
fi

for f in /var/log/messages /var/log/syslog /var/log/secure /var/log/auth.log /var/log/dnf.log /var/log/yum.log "${extra_files[@]}"; do
  [[ -f "$f" && -r "$f" ]] || continue
  tail -n 20000 -- "$f" >"${bundle}/logs/$(basename -- "$f")"
done

if ((redact)); then
  log INFO "redacting IPv4 and e-mail addresses"
  find "$bundle" -type f -name '*.txt' -o -type f -name '*.log' -o -type f -name 'messages' -o -type f -name 'syslog' -o -type f -name 'secure' |
    while IFS= read -r f; do
      sed -E -i \
        -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/x.x.x.x/g' \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<redacted-email>/g' \
        "$f"
    done
fi

(cd "$bundle" && find . -type f -print0 | sort -z | xargs -0 sha256sum >"${work}/manifest.tmp")
mv "${work}/manifest.tmp" "${bundle}/MANIFEST.sha256"

archive="${outdir%/}/${name}.tar.gz"
tar -C "$work" -czf "$archive" "$name"
chmod 600 "$archive"
log INFO "bundle written"
printf '%s\n' "$archive"

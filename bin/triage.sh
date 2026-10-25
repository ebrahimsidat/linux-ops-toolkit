#!/usr/bin/env bash
# triage.sh - first-five-minutes incident snapshot of a Linux host.
# Read-only: it inspects the system and never changes it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: triage.sh [options]

Collect a point-in-time health snapshot: load, memory, disks, inodes, top processes,
failed services, kernel errors, OOM kills and listening sockets.

Options:
  -o, --output FILE      Also write the report to FILE
  -n, --top N            Number of processes to list (default: 10)
      --disk-warn PCT    Flag file systems at or above PCT% used (default: 85)
  -h, --help             Show this help

Exit codes: 0 no findings, 1 findings that need attention, 3 usage error.
USAGE
}

output=""
top_n=10
disk_warn=85

while (($#)); do
  case "$1" in
    -o | --output)
      output="${2:-}"
      shift 2
      ;;
    -n | --top)
      top_n="${2:-}"
      shift 2
      ;;
    --disk-warn)
      disk_warn="${2:-}"
      shift 2
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

is_positive_int "$top_n" || die "--top must be a positive integer"
if ! is_positive_int "$disk_warn" || ((disk_warn > 100)); then
  die "--disk-warn must be 1-100"
fi

findings=()

section() {
  printf '\n===== %s =====\n' "$1"
}

finding() {
  findings+=("$1")
}

report() {
  section "HOST"
  printf 'hostname: %s\n' "$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname)"
  printf 'kernel:   %s\n' "$(uname -sr)"
  [[ -r /etc/os-release ]] && printf 'os:       %s\n' "$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")"
  printf 'time:     %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'uptime:   %s\n' "$(uptime -p 2>/dev/null || uptime)"

  section "LOAD AND CPU"
  local cpus load1
  cpus="$(nproc 2>/dev/null || echo 1)"
  read -r load1 _ </proc/loadavg
  printf 'cpus: %s  loadavg: %s\n' "$cpus" "$(cut -d' ' -f1-3 /proc/loadavg)"
  if awk -v l="$load1" -v c="$cpus" 'BEGIN { exit !(l > c * 2) }'; then
    finding "1-minute load ${load1} is more than twice the CPU count (${cpus})"
  fi

  section "MEMORY"
  free -h 2>/dev/null || head -5 /proc/meminfo
  local avail_pct
  avail_pct="$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END { if (t) printf "%d", a * 100 / t }' /proc/meminfo)"
  if [[ -n "$avail_pct" ]] && ((avail_pct < 10)); then
    finding "only ${avail_pct}% of memory is available"
  fi

  section "FILE SYSTEMS (usage)"
  df -hPT -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null || df -hP
  local fs pct mount
  while read -r fs pct mount; do
    pct="${pct%\%}"
    [[ "$pct" =~ ^[0-9]+$ ]] || continue
    ((pct >= disk_warn)) && finding "file system ${mount} (${fs}) is ${pct}% full"
  done < <(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null | awk 'NR > 1 { print $1, $5, $6 }')

  section "FILE SYSTEMS (inodes)"
  df -hiP -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null || echo "inode usage unavailable"
  while read -r fs pct mount; do
    pct="${pct%\%}"
    [[ "$pct" =~ ^[0-9]+$ ]] || continue
    ((pct >= disk_warn)) && finding "file system ${mount} (${fs}) has used ${pct}% of its inodes"
  done < <(df -iP -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null | awk 'NR > 1 { print $1, $5, $6 }')

  section "TOP ${top_n} PROCESSES BY CPU"
  ps -eo pid,user,pcpu,pmem,etime,comm --sort=-pcpu 2>/dev/null | head -n "$((top_n + 1))"

  section "TOP ${top_n} PROCESSES BY MEMORY"
  ps -eo pid,user,pmem,rss,etime,comm --sort=-rss 2>/dev/null | head -n "$((top_n + 1))"

  section "FAILED SERVICES"
  if have systemctl && systemctl list-units --failed --no-legend --plain >/dev/null 2>&1; then
    local failed
    failed="$(systemctl list-units --failed --no-legend --plain 2>/dev/null | awk '{print $1}')"
    if [[ -n "$failed" ]]; then
      printf '%s\n' "$failed"
      finding "failed systemd units: $(tr '\n' ' ' <<<"$failed")"
    else
      echo "none"
    fi
  else
    echo "systemd not available"
  fi

  section "KERNEL ERRORS (last hour)"
  local kerr=""
  if have journalctl; then
    kerr="$(journalctl -k -p err --since '-1h' --no-pager -q 2>/dev/null | tail -n 20)"
  elif have dmesg; then
    kerr="$(dmesg --level=err,crit,alert,emerg 2>/dev/null | tail -n 20)"
  fi
  if [[ -n "$kerr" ]]; then
    printf '%s\n' "$kerr"
  else
    echo "none found (or not permitted)"
  fi

  section "OOM KILLS"
  local ooms=""
  if have journalctl; then
    ooms="$(journalctl -k --since '-24h' --no-pager -q 2>/dev/null | grep -i 'out of memory: killed process' | tail -n 10)"
  fi
  if [[ -n "$ooms" ]]; then
    printf '%s\n' "$ooms"
    finding "the kernel OOM killer ran in the last 24 hours"
  else
    echo "none in the last 24 hours (or not permitted)"
  fi

  section "LISTENING SOCKETS"
  if have ss; then
    ss -tulnH 2>/dev/null | awk '{ print $1, $5 }' | sort -u
  else
    echo "ss not available"
  fi

  section "FINDINGS"
  if ((${#findings[@]})); then
    printf -- '- %s\n' "${findings[@]}"
  else
    echo "no issues detected"
  fi
}

if [[ -n "$output" ]]; then
  report | tee "$output"
else
  report
fi

((${#findings[@]})) && exit "$EXIT_WARNING"
exit "$EXIT_OK"

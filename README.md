# linux-ops-toolkit

[![CI](https://github.com/ebrahimsidat/linux-ops-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/ebrahimsidat/linux-ops-toolkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Small, dependable Bash tools for Linux operations and incident response. Each tool does one job, is safe by default,
has a `--help`, returns meaningful exit codes, and is covered by automated tests on **Ubuntu, Rocky Linux 8 and Rocky
Linux 9** (RHEL-compatible).

| Tool | What it does | Safe by default |
| --- | --- | --- |
| `triage.sh` | First-five-minutes health snapshot: load, memory, disk and inode usage, top processes, failed units, kernel errors, OOM kills, listening sockets, and a list of findings | Read-only |
| `collect-logs.sh` | Builds a `.tar.gz` diagnostic bundle for a vendor case or post-incident review, with a SHA-256 manifest and optional redaction of IP and e-mail addresses | Writes only its bundle, mode `0600` |
| `disk-cleanup.sh` | Finds old rotated logs, archives, temp files and core dumps, and optionally vacuums the journal | Dry run unless `--apply`; refuses `/`, `/etc`, `/var` and other top-level system directories |
| `check-certs.sh` | Checks TLS certificate expiry for `host:port` endpoints or PEM files | Read-only; Nagios/Icinga exit codes |

## Install

```bash
git clone https://github.com/ebrahimsidat/linux-ops-toolkit.git
cd linux-ops-toolkit
sudo make install            # installs ops-triage, ops-collect-logs, ops-disk-cleanup, ops-check-certs
```

Or run in place with `bash bin/<tool>.sh`. Requirements: Bash 4.4+, coreutils, findutils, procps, and `openssl` for
certificate checks. `systemctl`, `journalctl` and `ss` are used when present.

## Usage

```bash
# Incident triage, saved for the ticket. Exit 1 means there are findings to look at.
ops-triage --output /tmp/triage-$(hostname -s).txt

# Diagnostic bundle covering the last 6 hours, including an application unit, with addresses masked
sudo ops-collect-logs --since 6 --unit myapp.service --redact --output-dir /var/tmp

# See what would be removed, then remove it
ops-disk-cleanup --days 14 /var/log/myapp /srv/app/tmp
ops-disk-cleanup --days 14 --apply /var/log/myapp /srv/app/tmp

# Certificate expiry across an inventory, suitable for a Nagios/Icinga/Zabbix check or cron
ops-check-certs --warning 30 --critical 14 --file /etc/ops/tls-endpoints.txt
```

Sample output:

```text
$ ops-check-certs portal.example.com:443 /etc/pki/tls/certs/api.pem
OK       portal.example.com:443: 74 days left (Jan  7 23:59:59 2027 GMT) [CN=portal.example.com]
WARNING  /etc/pki/tls/certs/api.pem: expires in 21 days (Nov 15 12:00:00 2026 GMT) [CN=api.internal]
$ echo $?
1
```

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | OK / no findings |
| 1 | Warning / findings that need attention |
| 2 | Critical (`check-certs.sh`) |
| 3 | Unknown, usage or safety error |

## Engineering standards

- `set -euo pipefail`, quoted expansions, NUL-delimited file handling (names with spaces and newlines are safe).
- ShellCheck-clean with no blanket suppressions.
- 25 [bats](https://github.com/bats-core/bats-core) tests, including destructive paths that run only against temporary
  directories.
- CI runs ShellCheck, then the test suite on Ubuntu and in Rocky Linux 8 and 9 containers, and verifies `make install`.

See [docs/runbook.md](docs/runbook.md) for how the tools fit into an incident.

## License

[MIT](LICENSE) © 2026 Ebrahim Sidat

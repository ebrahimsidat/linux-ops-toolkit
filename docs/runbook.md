# Using the toolkit during an incident

## 1. Triage (minutes 0–5)

```bash
ops-triage --output /tmp/triage.txt
```

Read the **FINDINGS** section first. Common findings and next steps:

| Finding | Next step |
| --- | --- |
| File system nearly full | `du -xh --max-depth=2 <mount> \| sort -h \| tail`, then `ops-disk-cleanup` (dry run first) |
| Inodes nearly exhausted | Look for directories with very many small files: `find <mount> -xdev -type d -size +1M` |
| Load more than twice the CPU count | Check the CPU and memory process lists, then `vmstat 1 5` for I/O wait |
| Low available memory or OOM kills | Identify the process in the OOM section; check its limits and recent deployments |
| Failed systemd units | `systemctl status <unit>` and `journalctl -u <unit> -b` |

Attach `/tmp/triage.txt` to the incident ticket.

## 2. Stabilise

Reclaim space safely when a disk is full:

```bash
ops-disk-cleanup --days 7 /var/log/myapp                 # review the list
ops-disk-cleanup --days 7 --apply /var/log/myapp         # then apply
sudo ops-disk-cleanup --days 7 --journal 500M --apply /var/log/myapp
```

The tool never deletes without `--apply`, never crosses file system boundaries, and refuses top-level system
directories.

## 3. Collect evidence

```bash
sudo ops-collect-logs --since 4 --unit myapp.service --redact --output-dir /var/tmp
```

Before attaching the bundle to a vendor case, verify it:

```bash
mkdir /tmp/check && tar -C /tmp/check -xzf /var/tmp/diag-*.tar.gz
(cd /tmp/check/diag-* && sha256sum -c MANIFEST.sha256)
```

`--redact` masks IPv4 and e-mail addresses. Review the bundle for other sensitive data (host names, user names)
before sharing it outside your organisation.

## 4. Prevent recurrence

Schedule certificate checks so expiry never causes an outage:

```cron
# /etc/cron.d/check-certs: daily at 07:15, mail on WARNING or CRITICAL
15 7 * * * root out=$(/usr/local/bin/ops-check-certs --file /etc/ops/tls-endpoints.txt) || echo "$out" | mail -s "TLS expiry warning" ops@example.com
```

Or call `ops-check-certs` directly as a Nagios, Icinga or Zabbix external check.

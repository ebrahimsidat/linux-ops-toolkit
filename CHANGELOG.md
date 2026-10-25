# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-25

### Added

- triage.sh: read-only incident snapshot with findings and exit code
- collect-logs.sh: diagnostic bundle with SHA-256 manifest and optional redaction
- disk-cleanup.sh: dry-run-by-default cleanup with system-directory guard rails
- check-certs.sh: TLS certificate expiry check with Nagios exit codes
- make install and uninstall targets
- CI: ShellCheck and bats on Ubuntu, Rocky Linux 8 and Rocky Linux 9

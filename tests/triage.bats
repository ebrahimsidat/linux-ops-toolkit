#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  load test_helper
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

@test "report contains every section" {
  run bash "$BIN/triage.sh" --top 3
  [ "$status" -le 1 ]
  for s in HOST "LOAD AND CPU" MEMORY "FILE SYSTEMS (usage)" "FILE SYSTEMS (inodes)" \
    "PROCESSES BY CPU" "PROCESSES BY MEMORY" "FAILED SERVICES" "KERNEL ERRORS" "OOM KILLS" \
    "LISTENING SOCKETS" FINDINGS; do
    [[ "$output" == *"$s"* ]]
  done
}

@test "a 1% disk threshold always produces a finding and exit 1" {
  run bash "$BIN/triage.sh" --disk-warn 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"% full"* ]]
}

@test "--output writes the same report to a file" {
  run bash "$BIN/triage.sh" --output "$WORK/report.txt"
  [ -s "$WORK/report.txt" ]
  grep -q "===== FINDINGS =====" "$WORK/report.txt"
}

@test "invalid options are rejected" {
  run bash "$BIN/triage.sh" --disk-warn 150
  [ "$status" -eq 3 ]
  run bash "$BIN/triage.sh" --bogus
  [ "$status" -eq 3 ]
}

#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  load test_helper
  WORK="$(mktemp -d)"
  make_tree "$WORK"
}

teardown() {
  rm -rf "$WORK"
}

@test "dry run lists old matching files and deletes nothing" {
  run bash "$BIN/disk-cleanup.sh" --days 7 "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would delete"*"app.log.1"* ]]
  [[ "$output" == *"archive.gz"* ]]
  [[ "$output" == *"work.tmp"* ]]
  [[ "$output" == *"SUMMARY: 3 files"*"reclaimable"* ]]
  [ -f "$WORK/app.log.1" ]
  [ -f "$WORK/sub/archive.gz" ]
}

@test "recent files and non-matching names are never selected" {
  run bash "$BIN/disk-cleanup.sh" --days 7 "$WORK"
  [[ "$output" != *"app.log.2"* ]]
  [[ "$output" != *$'\t'"$WORK/app.log"$'\n'* ]]
}

@test "--apply deletes only the selected files" {
  run bash "$BIN/disk-cleanup.sh" --days 7 --apply "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUMMARY: 3 files"*"reclaimed"* ]]
  [ ! -e "$WORK/app.log.1" ]
  [ ! -e "$WORK/sub/archive.gz" ]
  [ ! -e "$WORK/sub/work.tmp" ]
  [ -f "$WORK/app.log" ]
  [ -f "$WORK/app.log.2" ]
}

@test "custom pattern narrows the selection" {
  run bash "$BIN/disk-cleanup.sh" --days 7 --pattern '*.gz' "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUMMARY: 1 files"* ]]
  [[ "$output" == *"archive.gz"* ]]
}

@test "file names with spaces are handled" {
  printf 'x\n' >"$WORK/old report.tmp"
  touch -d '30 days ago' "$WORK/old report.tmp"
  run bash "$BIN/disk-cleanup.sh" --days 7 --apply "$WORK"
  [ "$status" -eq 0 ]
  [ ! -e "$WORK/old report.tmp" ]
}

@test "refuses top-level system directories" {
  run bash "$BIN/disk-cleanup.sh" --days 7 /etc
  [ "$status" -eq 3 ]
  [[ "$output" == *"refusing"* ]]
}

@test "rejects a non-numeric --days" {
  run bash "$BIN/disk-cleanup.sh" --days soon "$WORK"
  [ "$status" -eq 3 ]
}

@test "requires a directory argument" {
  run bash "$BIN/disk-cleanup.sh"
  [ "$status" -eq 3 ]
}

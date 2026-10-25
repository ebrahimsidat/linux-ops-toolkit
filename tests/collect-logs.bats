#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  load test_helper
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

@test "creates a private bundle with a valid SHA-256 manifest" {
  run bash "$BIN/collect-logs.sh" --since 1 --output-dir "$WORK"
  [ "$status" -eq 0 ]
  archive="${lines[-1]}"
  [ -f "$archive" ]
  [ "$(stat -c %a "$archive")" = "600" ]
  mkdir "$WORK/x"
  tar -C "$WORK/x" -xzf "$archive"
  dir="$(find "$WORK/x" -mindepth 1 -maxdepth 1 -type d)"
  [ -f "$dir/triage.txt" ]
  [ -f "$dir/system/uname.txt" ]
  (cd "$dir" && sha256sum --quiet -c MANIFEST.sha256)
}

@test "extra files are included and redaction masks addresses" {
  printf 'login from 10.20.30.40 by ops@example.com\n' >"$WORK/app.log"
  run bash "$BIN/collect-logs.sh" --since 1 --output-dir "$WORK" --file "$WORK/app.log" --redact
  [ "$status" -eq 0 ]
  mkdir "$WORK/x"
  tar -C "$WORK/x" -xzf "${lines[-1]}"
  collected="$(find "$WORK/x" -name app.log)"
  grep -q 'x.x.x.x' "$collected"
  grep -q '<redacted-email>' "$collected"
  run ! grep -q '10.20.30.40' "$collected"
}

@test "unwritable output directory is rejected" {
  run bash "$BIN/collect-logs.sh" --output-dir /nonexistent
  [ "$status" -eq 3 ]
}

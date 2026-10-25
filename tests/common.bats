#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  load test_helper
  # shellcheck source=../lib/common.sh
  source "${REPO_ROOT}/lib/common.sh"
}

@test "human_bytes formats bytes, kibibytes and gibibytes" {
  [ "$(human_bytes 512)" = "512B" ]
  [ "$(human_bytes 1536)" = "1.5K" ]
  [ "$(human_bytes 1073741824)" = "1.0G" ]
}

@test "is_positive_int accepts positive integers only" {
  is_positive_int 7
  is_positive_int 010
  run ! is_positive_int 0
  run ! is_positive_int -3
  run ! is_positive_int abc
  run ! is_positive_int ""
}

@test "is_protected_path blocks top-level system directories" {
  is_protected_path /
  is_protected_path /etc
  is_protected_path /var/
  is_protected_path /usr/../etc
  run ! is_protected_path /var/log/myapp
  run ! is_protected_path /tmp/scratch
}

#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  load test_helper
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORK"
}

make_cert() {
  # make_cert NAME DAYS -> self-signed certificate valid for DAYS days
  openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=$1.example.test" \
    -keyout "$WORK/$1.key" -out "$WORK/$1.pem" -days "$2" >/dev/null 2>&1
}

@test "certificate with plenty of time left is OK" {
  make_cert healthy 365
  run bash "$BIN/check-certs.sh" "$WORK/healthy.pem"
  [ "$status" -eq 0 ]
  [[ "$output" == OK* ]]
  [[ "$output" == *"CN=healthy.example.test"* ]]
}

@test "certificate inside the warning window is WARNING" {
  make_cert soon 20
  run bash "$BIN/check-certs.sh" --warning 30 --critical 14 "$WORK/soon.pem"
  [ "$status" -eq 1 ]
  [[ "$output" == WARNING* ]]
}

@test "certificate inside the critical window is CRITICAL" {
  make_cert urgent 5
  run bash "$BIN/check-certs.sh" "$WORK/urgent.pem"
  [ "$status" -eq 2 ]
  [[ "$output" == CRITICAL* ]]
}

@test "worst status wins across several targets, and CRITICAL beats UNKNOWN" {
  make_cert healthy 365
  make_cert urgent 5
  run bash "$BIN/check-certs.sh" "$WORK/healthy.pem" "$WORK/missing.pem" "$WORK/urgent.pem"
  [ "$status" -eq 2 ]
  [[ "$output" == *"UNKNOWN"*"missing.pem"* ]]
}

@test "unreadable target alone is UNKNOWN" {
  run bash "$BIN/check-certs.sh" "$WORK/missing.pem"
  [ "$status" -eq 3 ]
}

@test "targets can be read from a list file with comments" {
  make_cert healthy 365
  printf '# inventory\n%s   # web cert\n\n' "$WORK/healthy.pem" >"$WORK/targets.txt"
  run bash "$BIN/check-certs.sh" --file "$WORK/targets.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == OK* ]]
}

@test "critical threshold above warning is rejected" {
  run bash "$BIN/check-certs.sh" --warning 10 --critical 20 "$WORK/any.pem"
  [ "$status" -eq 3 ]
}

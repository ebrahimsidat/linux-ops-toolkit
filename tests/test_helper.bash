# Shared setup for the bats suites.
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
BIN="${REPO_ROOT}/bin"
export LOT_QUIET=1

make_tree() {
  # make_tree DIR -> old and new files of several kinds
  local dir="$1"
  mkdir -p "$dir/sub"
  printf 'old log\n' >"$dir/app.log.1"
  printf 'old gz\n' >"$dir/sub/archive.gz"
  printf 'old tmp\n' >"$dir/sub/work.tmp"
  printf 'keep me\n' >"$dir/app.log"
  printf 'new rotated log\n' >"$dir/app.log.2"
  touch -d '30 days ago' "$dir/app.log.1" "$dir/sub/archive.gz" "$dir/sub/work.tmp" "$dir/app.log"
}

#!/usr/bin/env sh
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
RESET=$ROOT/scripts/reset-fresh-install.sh
TMP=${TMPDIR:-/tmp}/xymedia-reset-test.$$
mkdir -p "$TMP/bin" "$TMP/install/media" "$TMP/install/xiaoya" "$TMP/install/components"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
printf '%s\n' keep >"$TMP/install/media/keep.txt"
printf '%s\n' keep >"$TMP/install/xiaoya/keep.txt"
printf '%s\n' keep >"$TMP/install/components/keep.txt"
for item in compose.fuse.yaml config.yaml verify-release.sh; do printf '%s\n' "$item" >"$TMP/install/$item"; done

cat >"$TMP/bin/docker" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$*" >>"$XYMEDIA_DOCKER_LOG"
case "$*" in
  "ps -a "*)
    case "${XYMEDIA_FAKE_MODE:-managed}" in
      none) :;;
      foreign) printf 'c2\tapp-foreign\tcontainer\tUp\n';;
      *) printf 'c1\tapp\tcontainer\tUp\n';;
    esac
    ;;
  "volume ls "*)
    case "$*" in *'{{.ID}}'*) exit 42;; esac
    case "${XYMEDIA_FAKE_MODE:-managed}" in
      none|foreign) :;;
      *) printf 'v1\tdata\tvolume\t-\n';;
    esac
    ;;
  "network ls "*)
    case "${XYMEDIA_FAKE_MODE:-managed}" in
      none|foreign) :;;
      *) printf 'n1\tdefault\tnetwork\t-\n';;
    esac
    ;;
  "inspect "*)
    case "$4" in c1) printf '%s\n' xymedia_test;; c2) printf '%s\n' foreign;; v1|n1) printf '%s\n' xymedia_test;; esac
    ;;
  "stop c1") :;;
  "rm c1") :;;
  "volume rm v1") :;;
  "network rm n1") :;;
  *) exit 1;;
esac
EOF
chmod +x "$TMP/bin/docker"

run_reset() {
	printf '%s\n' "$1" "$2" >"$TMP/input"
	XYMEDIA_TEST_TTY="$TMP/input" XYMEDIA_DOCKER_LOG="$TMP/docker.log" PATH="$TMP/bin:$PATH" "$RESET" --install-dir "$TMP/install" --project xymedia_test >"$TMP/output" 2>&1
}

run_reset wrong n
test ! -e "$TMP/install/.env"
test ! -s "$TMP/docker.log" || exit 1

test_invalid_project() {
	value=$1
	: >"$TMP/docker.log"
	set +e
	XYMEDIA_TEST_TTY="$TMP/input" XYMEDIA_DOCKER_LOG="$TMP/docker.log" PATH="$TMP/bin:$PATH" "$RESET" --install-dir "$TMP/install" --project "$value" >"$TMP/output" 2>&1
	status=$?
	set -e
	test "$status" -eq 2
	test ! -s "$TMP/docker.log"
	test ! -e "$TMP/install/.xymedia-reset-backups"
}

for value in 'x space' 'x=other' Xymedia '' _project -project; do
	test_invalid_project "$value"
done
test_invalid_project '中文'
test_invalid_project "$(printf 'x\tbad')"
test_invalid_project "$(awk 'BEGIN { printf "x"; for (i = 1; i <= 63; i++) printf "a" }')"

# Existing installation can be reset after both Compose control files are gone.
run_reset 'RESET xymedia_test' y
test ! -e "$TMP/install/.env"
test ! -e "$TMP/install/compose.yaml"
test -f "$TMP/install/media/keep.txt"
test -f "$TMP/install/xiaoya/keep.txt"
test -f "$TMP/install/components/keep.txt"
test -d "$TMP/install/.xymedia-reset-backups"
test -f "$TMP/install/.xymedia-reset-backups"/*/config.yaml
grep -n 'stop c1' "$TMP/docker.log" >/dev/null
grep -n 'rm c1' "$TMP/docker.log" >/dev/null
grep -n 'volume rm v1' "$TMP/docker.log" >/dev/null
grep -n 'network rm n1' "$TMP/docker.log" >/dev/null
test "$(grep -n 'stop c1' "$TMP/docker.log" | cut -d: -f1)" -lt "$(grep -n 'rm c1' "$TMP/docker.log" | cut -d: -f1)"

# A foreign label returned by the fake daemon is rejected before deletion.
rm -rf "$TMP/install/.xymedia-reset-backups"
: >"$TMP/docker.log"
printf '%s\n' 'RESET xymedia_test' y >"$TMP/input"
set +e
XYMEDIA_TEST_TTY="$TMP/input" XYMEDIA_DOCKER_LOG="$TMP/docker.log" XYMEDIA_FAKE_MODE=foreign PATH="$TMP/bin:$PATH" "$RESET" --install-dir "$TMP/install" --project xymedia_test >"$TMP/output" 2>&1
status=$?
set -e
test "$status" -eq 2
test ! -e "$TMP/install/.xymedia-reset-backups"
if test -f "$TMP/install/.xymedia-reset-backups"/"*"/config.yaml; then exit 1; fi
if grep -q 'rm ' "$TMP/docker.log"; then exit 1; fi

# No matching resources still requires both confirmations and creates a backup.
rm -rf "$TMP/install/.xymedia-reset-backups"
printf '%s\n' reset-control >"$TMP/install/.env"
: >"$TMP/docker.log"
printf '%s\n' 'RESET xymedia_test' y >"$TMP/input"
XYMEDIA_TEST_TTY="$TMP/input" XYMEDIA_DOCKER_LOG="$TMP/docker.log" XYMEDIA_FAKE_MODE=none PATH="$TMP/bin:$PATH" "$RESET" --install-dir "$TMP/install" --project xymedia_test >"$TMP/output" 2>&1
test ! -e "$TMP/install/.env"
test -f "$TMP/install/.xymedia-reset-backups"/*/.env
if grep -q 'stop\| rm ' "$TMP/docker.log"; then exit 1; fi

# Cancellation after discovery performs no deletion or backup.
rm -rf "$TMP/install/.xymedia-reset-backups"
printf '%s\n' cancel >"$TMP/install/.env"
: >"$TMP/docker.log"
run_reset 'RESET xymedia_test' n
test -f "$TMP/install/.env"
test ! -e "$TMP/install/.xymedia-reset-backups"
if grep -q 'stop\| rm ' "$TMP/docker.log"; then exit 1; fi

printf '%s\n' 'reset tests: PASS'

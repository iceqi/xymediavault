#!/usr/bin/env sh
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
INSTALL=$ROOT/scripts/install.sh
TMP=${TMPDIR:-/tmp}/xymedia-installer-test.$$
mkdir -p "$TMP/bin"
trap 'rm -rf "$TMP"' 0 HUP INT TERM

cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
url=
destination=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) destination=$2; shift 2;;
    https://*) url=$1; shift;;
    *) shift;;
  esac
done
printf '%s\n' "$url" >"$XYMEDIA_TEST_URL_LOG"
case "$url" in
  https://raw.githubusercontent.com/iceqi/xymediavault/*/scripts/update-components.sh)
    printf '%s\n' '#!/usr/bin/env sh' 'printf "%s\\n" "$*" >>"$XYMEDIA_TEST_UPDATER_LOG"' 'case " $* " in *" --dry-run "*) exit 0;; esac' >"$destination";;
  https://raw.githubusercontent.com/iceqi/xymediavault/9fa0ed12a8547895f44ecea036bf5558053798c2/scripts/migrate-components-storage.sh)
    printf '%s\n' '#!/usr/bin/env sh' 'printf "%s\\n" "$*" >>"$XYMEDIA_TEST_MIGRATION_LOG"' 'if [ "${XYMEDIA_TEST_MIGRATION_FAIL:-0}" -eq 1 ] && case " $* " in *" --dry-run "*) true;; *) false;; esac; then exit 1; fi' 'case " $* " in *" --dry-run "*) exit 0;; esac' >"$destination";;
  *)
    printf '%s\n' '#!/usr/bin/env sh' 'printf "%s|%s|%s\\n" "$1" "$XYMEDIA_COMMAND" "$XYMEDIA_FUSE_MODE" >"$XYMEDIA_TEST_BOOTSTRAP_LOG"' >"$destination";;
esac
EOF
cat >"$TMP/bin/mktemp" <<'EOF'
#!/usr/bin/env sh
printf '%s/bootstrap.sh\n' "$XYMEDIA_TEST_TMP"
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/mktemp"

assert_forward() {
	expected_release=$1
	expected_url=$2
	test "$(tr -d '\n' <"$TMP/url.log")" = "$expected_url"
	test "$(cut -d'|' -f1 "$TMP/bootstrap.log")" = "$expected_release"
	test ! -e "$TMP/bootstrap.sh"
}

env -u XYMEDIA_RELEASE -u XYMEDIA_DOWNLOAD_PROXY \
	XYMEDIA_TEST_TTY="$TMP/missing-tty" XYMEDIA_TEST_URL_LOG="$TMP/url.log" XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
assert_forward v1.4.0 \
	'https://github.com/iceqi/xymediavault/releases/download/v1.4.0/bootstrap.sh'

printf '%s\n' 5 >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/bootstrap.log" "$TMP/updater.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
test ! -e "$TMP/url.log"
test ! -e "$TMP/updater.log"

printf '%s\n' 4 /srv/xymedia y >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/migration.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_MIGRATION_LOG="$TMP/migration.log" XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
test "$(tr -d '\n' <"$TMP/url.log")" = \
	'https://raw.githubusercontent.com/iceqi/xymediavault/9fa0ed12a8547895f44ecea036bf5558053798c2/scripts/migrate-components-storage.sh'
test "$(sed -n '1p' "$TMP/migration.log")" = '--install-dir /srv/xymedia --dry-run'
test "$(sed -n '2p' "$TMP/migration.log")" = '--install-dir /srv/xymedia --yes'
test ! -e "$TMP/bootstrap.sh"
if grep -q '/main/scripts/migrate-components-storage.sh' "$TMP/url.log"; then exit 1; fi

printf '%s\n' 4 '' n >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/migration.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_MIGRATION_LOG="$TMP/migration.log" XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
test "$(sed -n '1p' "$TMP/migration.log")" = '--install-dir /opt/xymedia --dry-run'
test "$(wc -l <"$TMP/migration.log")" -eq 1
test ! -e "$TMP/bootstrap.sh"

printf '%s\n' 4 /opt/xymedia y >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/migration.log"
set +e
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_MIGRATION_LOG="$TMP/migration.log" XYMEDIA_TEST_MIGRATION_FAIL=1 \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null 2>&1
migration_status=$?
set -e
test "$migration_status" -ne 0
test "$(wc -l <"$TMP/migration.log")" -eq 1
test ! -e "$TMP/bootstrap.sh"

printf '%s\n' 3 >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/bootstrap.log" "$TMP/updater.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
assert_forward v1.4.0 \
	'https://github.com/iceqi/xymediavault/releases/download/v1.4.0/bootstrap.sh'
test "$(cut -d'|' -f2 "$TMP/bootstrap.log")" = 'compose-only'
test ! -e "$TMP/updater.log"

printf '%s\n' 2 1 '' y >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/updater.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
test "$(tr -d '\n' <"$TMP/url.log")" = \
  'https://raw.githubusercontent.com/iceqi/xymediavault/21e99c95df0c800079fff327c5fcf78b05734612/scripts/update-components.sh'
test "$(sed -n '1p' "$TMP/updater.log")" = '--install-dir /opt/xymedia --component title --dry-run'
test "$(sed -n '2p' "$TMP/updater.log")" = '--install-dir /opt/xymedia --component title --yes'
if grep -q '/main/scripts/update-components.sh' "$TMP/url.log"; then exit 1; fi

printf '%s\n' 2 4 4 >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/updater.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
test ! -e "$TMP/url.log"
test ! -e "$TMP/updater.log"

printf '%s\n' 2 2 '' n >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/updater.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
test "$(sed -n '1p' "$TMP/updater.log")" = '--install-dir /opt/xymedia --component tmm --dry-run'
test "$(wc -l <"$TMP/updater.log")" -eq 1

printf '%s\n' bad 5 >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/updater.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >"$TMP/menu.out" 2>&1
test "$(grep -Fc '请选择 [1]：' "$TMP/menu.out")" -eq 2
test "$(grep -Fc '请输入 1、2、3、4 或 5。' "$TMP/menu.out")" -ge 1
test ! -e "$TMP/url.log"
test ! -e "$TMP/migration.log"

printf '%s\n' 1 >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/bootstrap.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
assert_forward v1.4.0 \
	'https://github.com/iceqi/xymediavault/releases/download/v1.4.0/bootstrap.sh'

: >"$TMP/tty-input"
rm -f "$TMP/url.log" "$TMP/bootstrap.log"
env -u XYMEDIA_RELEASE -u XYMEDIA_COMMAND \
	XYMEDIA_TEST_TTY="$TMP/tty-input" XYMEDIA_TEST_URL_LOG="$TMP/url.log" \
	XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" XYMEDIA_TEST_UPDATER_LOG="$TMP/updater.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
assert_forward v1.4.0 \
	'https://github.com/iceqi/xymediavault/releases/download/v1.4.0/bootstrap.sh'

grep -q 'XYMEDIA_FUSE_MODE=host-media' "$ROOT/docs/USAGE.md"
if grep -Eq 'XYMEDIA_FUSE_MODE=host([[:space:]`]|$)' "$ROOT/README.md" "$ROOT/docs/USAGE.md"; then
	exit 1
fi
compose_only_block=$(awk '
  /^```/ {
    if (in_fence) {
      if (block ~ /XYMEDIA_COMMAND=compose-only/) {
        printf "%s", block
        exit
      }
      in_fence=0
      block=""
    } else {
      in_fence=1
    }
    next
  }
  in_fence {
    block = block $0 "\n"
  }
' "$ROOT/README.md")
test -n "$compose_only_block"
printf '%s\n' "$compose_only_block" | grep -q 'XYMEDIA_COMMAND=compose-only'
if printf '%s\n' "$compose_only_block" | grep -q 'XYMEDIA_FUSE_MODE='; then
	exit 1
fi

env -u XYMEDIA_DOWNLOAD_PROXY XYMEDIA_RELEASE=v1.4.1 \
	XYMEDIA_TEST_URL_LOG="$TMP/url.log" XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null
assert_forward v1.4.1 \
	'https://github.com/iceqi/xymediavault/releases/download/v1.4.1/bootstrap.sh'

env -u XYMEDIA_RELEASE -u XYMEDIA_DOWNLOAD_PROXY -u XYMEDIA_TEST_TTY \
	XYMEDIA_TEST_URL_LOG="$TMP/url.log" XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" v1.4.2 >/dev/null
assert_forward v1.4.2 \
	'https://github.com/iceqi/xymediavault/releases/download/v1.4.2/bootstrap.sh'

XYMEDIA_RELEASE=v1.4.1 XYMEDIA_DOWNLOAD_PROXY='' \
	XYMEDIA_TEST_URL_LOG="$TMP/url.log" XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" v1.4.2 >/dev/null
assert_forward v1.4.2 \
	'https://github.com/iceqi/xymediavault/releases/download/v1.4.2/bootstrap.sh'

env -u XYMEDIA_RELEASE XYMEDIA_DOWNLOAD_PROXY=https://proxy.example/ \
	XYMEDIA_TEST_URL_LOG="$TMP/url.log" XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" \
	XYMEDIA_TEST_TMP="$TMP" PATH="$TMP/bin:$PATH" "$INSTALL" v1.4.1 >/dev/null
assert_forward v1.4.1 \
	'https://proxy.example/https://github.com/iceqi/xymediavault/releases/download/v1.4.1/bootstrap.sh'

set +e
PATH="$TMP/bin:$PATH" "$INSTALL" v1.4 >/dev/null 2>&1
test $? -eq 2
XYMEDIA_SKIP_SIGNATURE_VERIFY=1 PATH="$TMP/bin:$PATH" "$INSTALL" >/dev/null 2>&1
test $? -eq 2
"$INSTALL" v1.4.0 extra >/dev/null 2>&1
test $? -eq 2
set -e

printf '%s\n' 'installer tests: PASS'

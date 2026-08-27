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
printf '%s\n' '#!/usr/bin/env sh' 'printf "%s|%s\\n" "$1" "$XYMEDIA_FUSE_MODE" >"$XYMEDIA_TEST_BOOTSTRAP_LOG"' >"$destination"
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
	XYMEDIA_TEST_URL_LOG="$TMP/url.log" XYMEDIA_TEST_BOOTSTRAP_LOG="$TMP/bootstrap.log" \
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

env -u XYMEDIA_RELEASE -u XYMEDIA_DOWNLOAD_PROXY \
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

#!/usr/bin/env sh
set -eu
ROOT=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/../.." && pwd -P
)
INSTALL="$ROOT/scripts/install.sh"
TMP=${TMPDIR:-/tmp}/xymedia-installer-test.$$
mkdir -p "$TMP/bin" "$TMP/vault"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
cat >"$TMP/bin/docker" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  info) exit 0;;
  version) printf 'amd64\n';;
  compose) [ "${2:-}" = version ] && printf 'Docker Compose version v2\n' || exit 0;;
  container) [ "${2:-}" = inspect ] && exit 1;;
  inspect) exit 1;;
  *) exit 0;;
esac
EOF
chmod +x "$TMP/bin/docker"
PATH="$TMP/bin:$PATH"
cat >"$TMP/fake-legacy.sh" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s|%s|%s|%s\n' "$IMAGE" "$XYMEDIA_TMM_IMAGE" "${1:-}" "${XYMEDIA_NON_INTERACTIVE:-}" >"$FAKE_LEGACY_LOG"
mkdir -p "$1/data" "$1/components"
printf 'services:\n  xymediavault:\n    image: %s\n    environment:\n      XYMEDIA_COMPONENT_RUNTIME: "local"\n    ports:\n      - "19080:8080"\n      - "19081:8081"\n      - "19082:8082"\n    volumes:\n      - ./data:/app/data\n      - ./tmm:/app/tmm\n      - ./components:/app/components\n      - ./mnt:/mnt/xymediavault\n  xiaoya-alist:\n    image: xiaoyaliu/alist:latest\n    ports:\n      - "15678:80"\n      - "12345:2345"\n      - "12346:2346"\n    volumes:\n      - ./xiaoya:/data\n' "$IMAGE" >"$1/docker-compose.yml"
printf 'services:\n  xymediavault:\n    devices:\n      - /dev/fuse:/dev/fuse\n    cap_add:\n      - SYS_ADMIN\n    security_opt:\n      - apparmor:unconfined\n' >"$1/docker-compose.fuse.yml"
EOF
chmod +x "$TMP/fake-legacy.sh"
test "$($INSTALL help | grep -c 'vault install')" -eq 1
set +e
printf '' | "$INSTALL" >/dev/null 2>&1
test $? -eq 2
set -e
set +e
"$INSTALL" vault install --channel beta --dir "$TMP/nontty" >/dev/null 2>&1
test $? -eq 2
set -e
# shellcheck disable=SC1091
test "$(
	. "$ROOT/scripts/lib/common.sh"
	channel_image stable vault
)" = iceqi/xymediavault:latest
# shellcheck disable=SC1091
test "$(
	. "$ROOT/scripts/lib/common.sh"
	channel_image beta tmm
)" = iceqi/xymedia-tmm:beta
# shellcheck disable=SC1091
test "$(
	. "$ROOT/scripts/lib/common.sh"
	channel_image stable title
)" = iceqi/xymedia-title:stable
FAKE_LEGACY_LOG="$TMP/legacy.log" XYMEDIA_LEGACY_INSTALLER="$TMP/fake-legacy.sh" "$INSTALL" vault install --channel beta --dir "$TMP/vault" --non-interactive >/dev/null
test "$(cut -d'|' -f1 "$TMP/legacy.log")" = iceqi/xymediavault:beta
test "$(cut -d'|' -f2 "$TMP/legacy.log")" = iceqi/xymedia-tmm:beta
grep -q 'xiaoya-alist' "$TMP/vault/docker-compose.yml"
grep -q './components:/app/components' "$TMP/vault/docker-compose.yml"
test -d "$TMP/vault/components"
test "$(cat "$TMP/vault/.xymedia-channel")" = beta
mkdir "$TMP/menu"
(cd "$TMP/menu" && timeout 20 script -qec "printf '1\\n\\n0\\n' | env FAKE_LEGACY_LOG='$TMP/menu.log' XYMEDIA_LEGACY_INSTALLER='$TMP/fake-legacy.sh' $INSTALL menu" /dev/null)
test -s "$TMP/menu.log"
test "$(cut -d'|' -f1 "$TMP/menu.log")" = iceqi/xymediavault:latest
test "$(cut -d'|' -f2 "$TMP/menu.log")" = iceqi/xymedia-tmm:latest
test "$(cut -d'|' -f4 "$TMP/menu.log")" = false
lock="$TMP/lock"
mkdir "$lock"
printf '%s\n' "$$" >"$lock/pid"
if XYMEDIA_LOCK_DIR="$lock" "$INSTALL" status >/dev/null 2>&1; then :; fi
rm -rf "$lock"
mkdir "$lock"
printf '999999\n' >"$lock/pid"
XYMEDIA_LOCK_DIR="$lock" XYMEDIA_LEGACY_INSTALLER="$TMP/fake-legacy.sh" FAKE_LEGACY_LOG="$TMP/legacy.log" "$INSTALL" vault install --channel stable --dir "$TMP/vault2" --non-interactive >/dev/null 2>&1 || true
test -f "$TMP/vault2/docker-compose.yml"
XYMEDIA_INSTALL_DIR="$TMP/vault" "$INSTALL" status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["vault"] and d["title"]'
set +e
"$INSTALL" vault install --channel stable --dir "$TMP/vault" --non-interactive >/dev/null 2>&1
test $? -ne 0
set -e
BOOTSTRAP_INPUT="$TMP/bootstrap-input.sh"
BOOTSTRAP_ARCHIVE="$TMP/bootstrap.tar.gz"
cp "$INSTALL" "$BOOTSTRAP_INPUT"
tar -czf "$BOOTSTRAP_ARCHIVE" -C "$ROOT" --transform='s,^,xymediavault-beta/,' scripts/install.sh scripts/legacy-install.sh scripts/lib
test "$(XYMEDIA_INSTALLER_TESTING=1 XYMEDIA_INSTALLER_ARCHIVE_URL="file://$BOOTSTRAP_ARCHIVE" sh "$BOOTSTRAP_INPUT" help | grep -c 'vault install')" -eq 1
mkdir "$TMP/bootstrap-bin"
cat >"$TMP/bootstrap-bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
destination=
url=
while [ "$#" -gt 0 ]; do
	case "$1" in
	-o)
		destination=$2
		shift 2
		;;
	https://*) url=$1; shift ;;
	*) shift ;;
	esac
done
printf '%s\n' "$url" >"$BOOTSTRAP_URL_LOG"
cp "$BOOTSTRAP_ARCHIVE_SOURCE" "$destination"
EOF
chmod +x "$TMP/bootstrap-bin/curl"
test "$(PATH="$TMP/bootstrap-bin:$PATH" BOOTSTRAP_URL_LOG="$TMP/bootstrap-url.log" BOOTSTRAP_ARCHIVE_SOURCE="$BOOTSTRAP_ARCHIVE" XYMEDIA_INSTALLER_TESTING=1 sh "$BOOTSTRAP_INPUT" help | grep -c 'vault install')" -eq 1
test "$(cat "$TMP/bootstrap-url.log")" = 'https://gh-proxy.org/https://codeload.github.com/iceqi/xymediavault/tar.gz/refs/heads/beta'
set +e
printf '' | XYMEDIA_INSTALLER_TESTING=1 XYMEDIA_INSTALLER_ARCHIVE_URL="file://$BOOTSTRAP_ARCHIVE" sh "$BOOTSTRAP_INPUT" >/dev/null 2>&1
test $? -eq 2
set -e
set +e
XYMEDIA_INSTALLER_REF='../unsafe' XYMEDIA_INSTALLER_TESTING=1 XYMEDIA_INSTALLER_ARCHIVE_URL="file://$BOOTSTRAP_ARCHIVE" sh "$BOOTSTRAP_INPUT" help >/dev/null 2>&1
test $? -eq 1
set -e
printf '%s\n' 'installer tests: PASS'

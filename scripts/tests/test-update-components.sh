#!/usr/bin/env sh
set -eu
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
SCRIPT=$ROOT/scripts/update-components.sh
TMP=${TMPDIR:-/tmp}/xymedia-updater-test.$$
mkdir -p "$TMP/bin"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
printf '%s\n' 'XYMEDIA_APP_CONTAINER=fake-app' > "$TMP/.env"
REAL_JQ=$(command -v jq)

cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
out=; url=
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2;; https://*) url=$1; shift;; -H) shift 2;; *) shift;; esac; done
printf '%s\n' "$url" >> "$XYMEDIA_TEST_LOG"
case "$url" in
  https://api.github.com/repos/iceqi/xymedia-title/releases/tags/component-sha-007ed892afaf)
    printf '%s\n' '{"tag_name":"component-sha-007ed892afaf","assets":[{"id":101,"name":"xymedia-title-sha-007ed892afaf-linux-amd64.tar.zst"},{"id":102,"name":"xymedia-title-sha-007ed892afaf-linux-amd64.tar.zst.sha256"}]}' > "$out";;
  https://api.github.com/repos/iceqi/xymedia-title/releases/assets/101) cp "$XYMEDIA_TEST_ARCHIVE" "$out";;
  https://api.github.com/repos/iceqi/xymedia-title/releases/assets/102) printf '%s  archive\n' "$XYMEDIA_TEST_HASH" > "$out";;
  *) exit 1;;
esac
EOF
cat > "$TMP/bin/jq" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$*" >> "$XYMEDIA_JQ_LOG"
exec "$XYMEDIA_REAL_JQ" "$@"
EOF
cat > "$TMP/bin/zstd" <<'EOF'
#!/usr/bin/env sh
set -eu
case "$1" in -t) exit 0;; -dc) shift; cat "$1";; esac
EOF
cat > "$TMP/bin/tar" <<'EOF'
#!/usr/bin/env sh
set -eu
case "$1" in
  -xOf) shift 2; case "$1" in manifest.json) printf '%s' "$XYMEDIA_TEST_MANIFEST";; payload/title.bin) printf '%s' payload;; *) exit 1;; esac;;
  -tvf) printf '%s\n' '-rw-r--r-- manifest.json' '-rw-r--r-- payload/title.bin';;
  -tf) printf '%s\n' manifest.json payload/title.bin;;
esac
EOF
cat > "$TMP/bin/sha256sum" <<'EOF'
#!/usr/bin/env sh
set -eu
if [ "${1:-}" = -c ]; then read hash file; test "$hash" = "$XYMEDIA_TEST_HASH"; else printf '%s  %s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa "${2:-}"; fi
EOF
cat > "$TMP/bin/docker" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$*" >> "$XYMEDIA_DOCKER_LOG"
if [ "${XYMEDIA_FAIL_MUTATION:-false}" = true ] && [ "$1" = run ] && printf '%s' "$*" | grep -q '/stage'; then
  if [ -f "$XYMEDIA_DOCKER_RUN_MARKER" ]; then exit 1; fi
  touch "$XYMEDIA_DOCKER_RUN_MARKER"
fi
case "$1:$2" in
  inspect:-f) printf '%s\n' running;;
  inspect:*) printf '%s\n' '[{"Image":"img","State":{"Running":true},"Mounts":[{"Destination":"/app/components","Type":"volume","Name":"components"}]}]';;
  image:*) printf '%s\n' '[{"Architecture":"amd64"}]';;
esac
if [ "${XYMEDIA_FAIL_STOP:-false}" = true ] && [ "$1" = stop ]; then exit 1; fi
EOF
chmod +x "$TMP/bin"/*
export PATH="$TMP/bin:$PATH" XYMEDIA_REAL_JQ="$REAL_JQ" XYMEDIA_TEST_LOG="$TMP/curl.log" XYMEDIA_JQ_LOG="$TMP/jq.log" XYMEDIA_DOCKER_LOG="$TMP/docker.log"
export GH_TOKEN=test-token
touch "$TMP/docker.log"
export XYMEDIA_DOCKER_RUN_MARKER="$TMP/docker-run.marker"
export XYMEDIA_TEST_HASH=ea719e6a86907b44b79ab0dc5fef43e83adb89706bf50973d4b3353b168f0534
export XYMEDIA_TEST_ARCHIVE="$TMP/archive"
set_manifest() {
  XYMEDIA_TEST_MANIFEST=$(printf '%s' "$1")
  export XYMEDIA_TEST_MANIFEST
}
set_manifest '{"schema_version":1,"component":"title","release_version":"sha-007ed892afaf","platform":"linux/amd64","files":{"payload/title.bin":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
printf '%s' 'fake archive' > "$TMP/archive"

set +e
env -u GH_TOKEN -u GITHUB_TOKEN "$SCRIPT" --install-dir "$TMP" --component title --dry-run >/dev/null 2>&1
test $? -eq 2
set -e
test ! -s "$TMP/curl.log"

"$SCRIPT" --install-dir "$TMP" --component title --dry-run >/dev/null
grep -q '/releases/tags/component-sha-007ed892afaf$' "$TMP/curl.log"
grep -q '/releases/assets/101$' "$TMP/curl.log"
grep -q '/releases/assets/102$' "$TMP/curl.log"
test ! -s "$TMP/docker.log"
if grep -q 'test-token' "$TMP/curl.log" "$TMP/jq.log" "$TMP/docker.log"; then exit 1; fi

set_manifest '{"schema_version":1,"component":"title","release_version":"component-sha-007ed892afaf","platform":"linux/amd64","files":{"payload/title.bin":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
set +e
"$SCRIPT" --install-dir "$TMP" --component title --dry-run >/dev/null 2>&1
test $? -eq 2
set -e
test ! -s "$TMP/docker.log"

set_manifest '{"schema_version":1,"component":"title","release_version":"sha-007ed892afaf","platform":"linux/amd64","files":{"payload/title.bin":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
"$SCRIPT" --install-dir "$TMP" --component title >/dev/null 2>&1 || test $? -eq 1
if grep -Eq '^(stop|start|run) ' "$TMP/docker.log"; then exit 1; fi
export XYMEDIA_FAIL_STOP=true
set +e
rollback_output=$("$SCRIPT" --install-dir "$TMP" --component title --yes 2>&1)
rollback_status=$?
set -e
test "$rollback_status" -ne 0
printf '%s\n' "$rollback_output" | grep -qv 'unbound variable'
grep -q '^start fake-app$' "$TMP/docker.log"
unset XYMEDIA_FAIL_STOP
"$SCRIPT" --install-dir "$TMP" --component title --yes >/dev/null
grep -q '^run ' "$TMP/docker.log"
grep -q '^stop fake-app$' "$TMP/docker.log"
grep -q '^start fake-app$' "$TMP/docker.log"

rm -f "$TMP/docker.log" "$TMP/docker-run.marker"
export XYMEDIA_FAIL_MUTATION=true
set +e
mutation_output=$("$SCRIPT" --install-dir "$TMP" --component title --yes 2>&1)
mutation_status=$?
set -e
test "$mutation_status" -ne 0
printf '%s\n' "$mutation_output" | grep -qv 'unbound variable'
grep -q '^start fake-app$' "$TMP/docker.log"
if grep -q 'rm -f' "$TMP/docker.log"; then exit 1; fi
unset XYMEDIA_FAIL_MUTATION
printf '%s\n' 'update-components tests: PASS'

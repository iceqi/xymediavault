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
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2;; https://*) url=$1; shift;; -H) printf 'header:%s\n' "$2" >> "$XYMEDIA_TEST_LOG"; shift 2;; *) shift;; esac; done
printf '%s\n' "$url" >> "$XYMEDIA_TEST_LOG"
case "$url" in
  *https://github.com/iceqi/xymedia-components/releases/download/title-component-sha-ab7f33d6ede5/xymedia-title-sha-ab7f33d6ede5-linux-amd64.tar.zst) cp "$XYMEDIA_TEST_ARCHIVE" "$out";;
  *https://github.com/iceqi/xymedia-components/releases/download/title-component-sha-ab7f33d6ede5/xymedia-title-sha-ab7f33d6ede5-linux-amd64.tar.zst.sha256) printf '%s  archive\n' "$XYMEDIA_TEST_HASH" > "$out";;
  *https://github.com/iceqi/xymedia-components/releases/download/tmm-component-sha-a0206a51fd9e/xymedia-tmm-sha-a0206a51fd9e-linux-any.tar.zst) cp "$XYMEDIA_TEST_ARCHIVE" "$out";;
  *https://github.com/iceqi/xymedia-components/releases/download/tmm-component-sha-a0206a51fd9e/xymedia-tmm-sha-a0206a51fd9e-linux-any.tar.zst.sha256) printf '%s  archive\n' "$XYMEDIA_TEST_HASH" > "$out";;
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
printf '%s\n' "$*" >> "$XYMEDIA_ZSTD_LOG"
EOF
cat > "$TMP/bin/tar" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$*" >> "$XYMEDIA_TAR_LOG"
case "$1" in
  -xOf) shift 2; case "$1" in manifest.json) printf '%s' "$XYMEDIA_TEST_MANIFEST";; payload/title.bin|payload/tmm.bin) printf '%s' payload;; *) exit 1;; esac;;
  -xpf) shift 2; test "$1" = -C; mkdir -p "$2/payload"; printf '%s' payload > "$2/payload/$XYMEDIA_TEST_COMPONENT.bin";;
  -tvf) printf '%s\n' '-rw-r--r-- manifest.json' "-rw-r--r-- payload/$XYMEDIA_TEST_COMPONENT.bin";;
  -tf) printf '%s\n' manifest.json "payload/$XYMEDIA_TEST_COMPONENT.bin";;
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
  volume:inspect) printf '%s\n' '[{"Name":"components","Labels":{"com.docker.compose.project":"xymedia","com.docker.compose.volume":"components"}}]';;
  image:*) printf '%s\n' '[{"Architecture":"amd64"}]';;
esac
if [ "${XYMEDIA_FAIL_STOP:-false}" = true ] && [ "$1" = stop ]; then exit 1; fi
EOF
chmod +x "$TMP/bin"/*
export PATH="$TMP/bin:$PATH" XYMEDIA_REAL_JQ="$REAL_JQ" XYMEDIA_TEST_LOG="$TMP/curl.log" XYMEDIA_JQ_LOG="$TMP/jq.log" XYMEDIA_ZSTD_LOG="$TMP/zstd.log" XYMEDIA_TAR_LOG="$TMP/tar.log" XYMEDIA_DOCKER_LOG="$TMP/docker.log"
unset GH_TOKEN GITHUB_TOKEN
touch "$TMP/docker.log"
touch "$TMP/zstd.log" "$TMP/tar.log"
export XYMEDIA_DOCKER_RUN_MARKER="$TMP/docker-run.marker"
export XYMEDIA_TEST_HASH=201443ee5b61a447ed4edb551d23a57bde2f6bfb68520d2891c6cd66f0fb2b1f
export XYMEDIA_TEST_ARCHIVE="$TMP/archive"
export XYMEDIA_TEST_COMPONENT=title
set_manifest() {
  XYMEDIA_TEST_MANIFEST=$(printf '%s' "$1")
  export XYMEDIA_TEST_MANIFEST
}
set_manifest '{"schema_version":1,"component":"title","release_version":"sha-ab7f33d6ede5","platform":"linux/amd64","files":{"payload/title.bin":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
printf '%s' 'fake archive' > "$TMP/archive"

printf '%s\n' '{"title":{"repository":"iceqi/xymedia-components","tag":"component-sha-007ed892afaf","release_version":"sha-007ed892afaf","assets":{}},"tmm":{"repository":"iceqi/xymedia-components","tag":"tmm-component-sha-a0206a51fd9e","release_version":"sha-a0206a51fd9e","assets":{}}}' > "$TMP/legacy-lock.json"
set +e
"$SCRIPT" --install-dir "$TMP" --component title --dry-run --lock-file "$TMP/legacy-lock.json" >/dev/null 2>&1
test $? -eq 2
set -e

validation_output=$("$SCRIPT" --install-dir "$TMP" --component title --dry-run)
printf '%s\n' "$validation_output" | grep -q 'title 归档 checksum 校验中。'
printf '%s\n' "$validation_output" | grep -q 'title payload 校验完成。'
grep -q '/releases/download/title-component-sha-ab7f33d6ede5/xymedia-title-sha-ab7f33d6ede5-linux-amd64.tar.zst$' "$TMP/curl.log"
grep -q '/releases/download/title-component-sha-ab7f33d6ede5/xymedia-title-sha-ab7f33d6ede5-linux-amd64.tar.zst.sha256$' "$TMP/curl.log"
grep -q '^https://gh-proxy.org/https://github.com/iceqi/xymedia-components/releases/download/' "$TMP/curl.log"
test "$(grep -c -- '-xpf - -C' "$TMP/tar.log")" -eq 1
test "$(grep -c -- '-xOf - payload/' "$TMP/tar.log")" -eq 0
if grep -q 'api.github.com\|Authorization\|Bearer' "$TMP/curl.log"; then exit 1; fi
test ! -s "$TMP/docker.log"

export XYMEDIA_DOWNLOAD_PROXY=''
: > "$TMP/curl.log"
"$SCRIPT" --install-dir "$TMP" --component title --dry-run >/dev/null
grep -q '^https://github.com/iceqi/xymedia-components/releases/download/' "$TMP/curl.log"
unset XYMEDIA_DOWNLOAD_PROXY

export XYMEDIA_DOWNLOAD_PROXY=http://proxy.example
: > "$TMP/curl.log"
set +e
"$SCRIPT" --install-dir "$TMP" --component title --dry-run >/dev/null 2>&1
test $? -eq 2
set -e
test ! -s "$TMP/curl.log"
unset XYMEDIA_DOWNLOAD_PROXY

export XYMEDIA_TEST_COMPONENT=tmm XYMEDIA_TEST_HASH=57ee0cdf0cf2127678ab598dfb8e9047e6aa903443f8d616955533e6cca0cfea
set_manifest '{"schema_version":1,"component":"tmm","release_version":"sha-a0206a51fd9e","platform":"linux/any","files":{"payload/tmm.bin":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
"$SCRIPT" --install-dir "$TMP" --component tmm --dry-run >/dev/null
grep -q '/releases/download/tmm-component-sha-a0206a51fd9e/xymedia-tmm-sha-a0206a51fd9e-linux-any.tar.zst$' "$TMP/curl.log"
grep -q '/releases/download/tmm-component-sha-a0206a51fd9e/xymedia-tmm-sha-a0206a51fd9e-linux-any.tar.zst.sha256$' "$TMP/curl.log"

export XYMEDIA_TEST_COMPONENT=title XYMEDIA_TEST_HASH=201443ee5b61a447ed4edb551d23a57bde2f6bfb68520d2891c6cd66f0fb2b1f
set_manifest '{"schema_version":1,"component":"title","release_version":"wrong-version","platform":"linux/amd64","files":{"payload/title.bin":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
set +e
"$SCRIPT" --install-dir "$TMP" --component title --dry-run >/dev/null 2>&1
test $? -eq 2
set -e
test ! -s "$TMP/docker.log"

set_manifest '{"schema_version":1,"component":"title","release_version":"sha-ab7f33d6ede5","platform":"linux/amd64","files":{"payload/title.bin":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
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

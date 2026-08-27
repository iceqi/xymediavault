#!/usr/bin/env sh
set -eu
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
SCRIPT=$ROOT/scripts/migrate-components-storage.sh
TMP=${TMPDIR:-/tmp}/xymedia-migration-test.$$
mkdir -p "$TMP/bin" "$TMP/install"
trap 'rm -rf "$TMP"' 0 HUP INT TERM
printf '%s\n' 'XYMEDIA_APP_CONTAINER=fake-app' 'COMPOSE_PROJECT_NAME=xymedia' > "$TMP/install/.env"
printf '%s\n' 'services:' '  app:' '    volumes:' '      - components:/app/components' 'volumes:' '  components:' > "$TMP/install/compose.yaml"
cat > "$TMP/bin/docker" <<'EOF'
#!/usr/bin/env sh
set -eu
printf '%s\n' "$*" >> "$XYMEDIA_DOCKER_LOG"
state=${XYMEDIA_DOCKER_STATE:?}
case "$1:$2" in
  inspect:-f) if [ "${XYMEDIA_HEALTH_FAIL:-false}" = true ]; then printf '%s\n' unhealthy; else printf '%s\n' healthy; fi;;
  inspect:*) if [ -f "$state.bind" ]; then printf '%s\n' "[{\"State\":{\"Running\":true},\"Mounts\":[{\"Destination\":\"/app/components\",\"Type\":\"bind\",\"Source\":\"$XYMEDIA_COMPONENTS_DIR\"}]}]"; else printf '%s\n' '[{"State":{"Running":true},"Mounts":[{"Destination":"/app/components","Type":"volume","Name":"components"}]}]'; fi;;
  volume:inspect) printf '%s\n' '[{"Labels":{"com.docker.compose.project":"xymedia","com.docker.compose.volume":"components"}}]';;
  image:*) exit 0;;
  compose:*)
    case " $* " in *' config -q '*) exit 0;; esac
    if [ -f "$state.bind" ]; then rm -f "$state.bind"; else touch "$state.bind"; fi
    exit 0;;
  run:*)
    for arg in "$@"; do case "$arg" in type=bind,src=*,dst=/stage) stage=${arg#type=bind,src=}; stage=${stage%,dst=/stage}; touch "$stage/components-source.tar";; esac; done
    exit 0;;
esac
EOF
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$TMP/bin/sleep"
chmod +x "$TMP/bin/docker"
chmod +x "$TMP/bin/sleep"
export PATH="$TMP/bin:$PATH" XYMEDIA_DOCKER_LOG="$TMP/docker.log" XYMEDIA_DOCKER_STATE="$TMP/state" XYMEDIA_COMPONENTS_DIR="$TMP/install/components"
: > "$TMP/docker.log"
cp -p "$TMP/install/compose.yaml" "$TMP/compose.before"
set +e
"$SCRIPT" --install-dir "$TMP/install" --dry-run >"$TMP/dry.out" 2>&1
status=$?
set -e
test "$status" -eq 0
cmp -s "$TMP/compose.before" "$TMP/install/compose.yaml"
test ! -e "$TMP/install/components"
if grep -Eq 'stop|compose .*up' "$TMP/docker.log"; then exit 1; fi
mkdir "$TMP/install/components"
printf x > "$TMP/install/components/existing"
"$SCRIPT" --install-dir "$TMP/install" --dry-run >/dev/null
rm -f "$TMP/install/components/existing"
ln -s "$TMP/install" "$TMP/symlink-install"
set +e
"$SCRIPT" --install-dir "$TMP/symlink-install" --dry-run >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 2
set +e
"$SCRIPT" --install-dir "$TMP/install" >/dev/null 2>&1
status=$?
set -e
test "$status" -eq 2
rm -rf "$TMP/install/components" "$TMP/symlink-install"
rm -f "$TMP/docker.log" "$TMP/state.bind"
mkdir "$TMP/install/components"
XYMEDIA_HEALTH_FAIL=false "$SCRIPT" --install-dir "$TMP/install" --yes >/dev/null
test -f "$TMP/install/.xymedia-component-migrations"/*/components-source.tar
grep -q "      - \"\${XYMEDIA_INSTALL_DIR}/components:/app/components\"" "$TMP/install/compose.yaml"
grep -q 'compose.*up.*--no-deps app' "$TMP/docker.log"
if grep -q 'volume rm\|volume prune' "$TMP/docker.log"; then exit 1; fi

rm -rf "$TMP/install/.xymedia-component-migrations" "$TMP/install/components"
printf '%s\n' '      - components:/app/components' > "$TMP/install/compose.yaml.tmp"
mv "$TMP/install/compose.yaml.tmp" "$TMP/install/compose.yaml"
: > "$TMP/docker.log"
rm -f "$TMP/state.bind"
set +e
XYMEDIA_HEALTH_FAIL=true "$SCRIPT" --install-dir "$TMP/install" --yes >/dev/null 2>&1
status=$?
set -e
test "$status" -ne 0
grep -q '      - components:/app/components' "$TMP/install/compose.yaml"
grep -q 'compose.*up.*--no-deps app' "$TMP/docker.log"
grep -q '^stop fake-app$' "$TMP/docker.log"
test "$(grep -c 'compose.*up.*--no-deps app' "$TMP/docker.log")" -ge 2
if grep -q 'volume rm\|volume prune' "$TMP/docker.log"; then exit 1; fi
printf '%s\n' 'migration tests: PASS'

#!/usr/bin/env sh
XYMEDIA_INSTALLER_VERSION=${XYMEDIA_INSTALLER_VERSION:-beta}
VAULT_IMAGE_BASE=iceqi/xymediavault
is_tty() { [ -t 0 ] && [ -t 1 ]; }
log() { printf '[xymedia] %s\n' "$*"; }
die() {
	printf '[xymedia] ERROR: %s\n' "$*" >&2
	exit 1
}
die2() {
	printf '[xymedia] ERROR: %s\n' "$*" >&2
	exit 2
}
channel_image() { case "$1:$2" in stable:vault) printf '%s:latest' "$VAULT_IMAGE_BASE" ;; beta:vault) printf '%s:beta' "$VAULT_IMAGE_BASE" ;; *) return 1 ;; esac }
valid_channel() { [ "$1" = stable ] || [ "$1" = beta ]; }
docker_ready() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }
compose_cmd() { if docker compose version >/dev/null 2>&1; then printf 'docker compose'; elif command -v docker-compose >/dev/null 2>&1; then printf docker-compose; else return 1; fi; }
platform() {
	raw=$(docker version --format '{{.Server.Arch}}' 2>/dev/null || true)
	[ -n "$raw" ] || raw=$(uname -m)
	case "$raw" in amd64 | x86_64) printf linux/amd64 ;; arm64 | aarch64) printf linux/arm64 ;; arm | armv7 | armv7l | armhf) printf linux/arm/v7 ;; *) printf '%s' unknown ;; esac
}
lock_acquire() {
	lock=${XYMEDIA_LOCK_DIR:-${TMPDIR:-/tmp}/xymedia-installer.lock}
	pidfile=$lock/pid
	if ! mkdir "$lock" 2>/dev/null; then
		oldpid=$(cat "$pidfile" 2>/dev/null || true)
		case "$oldpid" in '' | *[!0-9]*) die "已有操作正在进行（锁：$lock）" ;; esac
		if kill -0 "$oldpid" 2>/dev/null; then die "已有操作正在进行（PID：$oldpid）"; fi
		rm -f "$pidfile"
		rmdir "$lock" 2>/dev/null || die "无法回收锁：$lock"
		mkdir "$lock" || die "无法创建锁：$lock"
	fi
	printf '%s\n' "$$" >"$pidfile"
	trap 'rm -f "$pidfile"; rmdir "$lock" 2>/dev/null || true' 0 HUP INT TERM
}
confirm() {
	[ "${1:-false}" = true ] && return 0
	printf '%s 输入 YES 确认：' "$2"
	IFS= read -r answer
	[ "$answer" = YES ]
}
install_dir() { printf '%s' "${XYMEDIA_INSTALL_DIR:-$(pwd -P)}"; }
safe_dir() {
	case "$1" in
	'' | / | */../* | ../* | */.. | ..) return 1 ;;
	esac
	printf '%s' "$1" | LC_ALL=C grep '[[:cntrl:]]' >/dev/null 2>&1 && return 1
	[ ! -L "$1" ] 2>/dev/null || return 1
	probe=$1
	while [ ! -e "$probe" ]; do
		case "$probe" in / | .) break ;; esac
		probe=$(dirname "$probe")
	done
	[ -d "$probe" ] || return 1
	while :; do
		[ ! -L "$probe" ] 2>/dev/null || return 1
		case "$probe" in / | .) break ;; esac
		probe=$(dirname "$probe")
	done
}
write_channel() { (
	umask 077
	printf '%s\n' "$2" >"$1/.xymedia-channel"
); }
read_channel() { [ -r "$1/.xymedia-channel" ] && tr -d '\r\n' <"$1/.xymedia-channel" || true; }
container_exists() { docker container inspect "$1" >/dev/null 2>&1; }
container_state() {
	state=$(docker inspect --format '{{if .State.Running}}running{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || true)
	[ -n "$state" ] || state=absent
	printf '%s' "$state"
}
json_quote() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/[[:cntrl:]]/ /g'; }
env_report() {
	printf 'OS: Linux\nArchitecture: %s\n' "$(platform)"
	docker_ready && printf 'Docker: available\n' || printf 'Docker: unavailable\n'
	compose_cmd >/dev/null 2>&1 && printf 'Compose: available\n' || printf 'Compose: unavailable\n'
	[ -c /dev/fuse ] && printf 'FUSE: available\n' || printf 'FUSE: unavailable\n'
	printf 'Docker endpoint: %s\n' "${DOCKER_HOST:-local/default}"
	printf 'Rootless: '
	docker info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -qi rootless && printf 'yes\n' || printf 'no/unknown\n'
	if command -v df >/dev/null 2>&1; then df -h . | awk 'NR==2 {print "Disk: " $4 " free"}'; fi
	if command -v free >/dev/null 2>&1; then free -h | awk 'NR==2 {print "Memory: " $7 " available"}'; fi
	for p in 18080 18081 18082 18083; do if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$p" 2>/dev/null | tail -n +2 | grep -q .; then printf 'Port %s: occupied\n' "$p"; else printf 'Port %s: available/unknown\n' "$p"; fi; done
	case "$(platform)" in linux/amd64 | linux/arm64) printf 'Title support: yes\n' ;; *) printf 'Title support: no\n' ;; esac
}
version_report() {
	dir=$(install_dir)
	printf 'Installer: %s\nVault channel: %s\n' "$XYMEDIA_INSTALLER_VERSION" "$(read_channel "$dir")"
	if container_exists xymediavault; then printf '%s: %s\n' xymediavault "$(container_state xymediavault) $(docker inspect --format '{{.Config.Image}} {{.Image}}' xymediavault 2>/dev/null || printf unknown)"; else printf '%s\n' 'xymediavault: not installed'; fi
}
status_report() {
	if [ "${1:-}" = --json ]; then
		dir=$(install_dir)
		v=$(read_channel "$dir")
		printf '{"installer":"%s","vault_channel":"%s","vault":{"status":"%s","image":"%s"}}\n' "$(json_quote "$XYMEDIA_INSTALLER_VERSION")" "$(json_quote "$v")" "$(container_state xymediavault)" "$(json_quote "$(container_image xymediavault)")"
		return 0
	fi
	if container_exists xymediavault; then docker inspect --format 'xymediavault: {{.State.Status}} ({{.Config.Image}})' xymediavault 2>/dev/null || true; else printf '%s\n' 'xymediavault: not installed'; fi
}
container_health() {
	name=$1
	health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || true)
	[ "$health" = healthy ] || [ "$health" = running ]
}
container_image() {
	image=$(docker inspect --format '{{.Config.Image}}' "$1" 2>/dev/null || true)
	[ -n "$image" ] || image=unknown
	printf '%s' "$image"
}
http_check() {
	url=$1
	command -v curl >/dev/null 2>&1 && curl -fsS --max-time 8 "$url" >/dev/null 2>&1
}

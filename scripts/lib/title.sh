#!/usr/bin/env sh
title_usage() { printf '%s\n' 'title install|check|upgrade'; }
title_name() { if [ "${XYMEDIA_INSTALLER_TESTING:-0}" = 1 ] && [ -n "${XYMEDIA_TITLE_CONTAINER:-}" ]; then printf '%s' "$XYMEDIA_TITLE_CONTAINER"; else printf '%s' xymedia-title-standalone; fi; }
title_port() { if [ "${XYMEDIA_INSTALLER_TESTING:-0}" = 1 ] && [ -n "${XYMEDIA_TITLE_PORT:-}" ]; then printf '%s' "$XYMEDIA_TITLE_PORT"; else printf '%s' "${TITLE_PORT:-18083}"; fi; }
title_network_args() { if [ "${XYMEDIA_INSTALLER_TESTING:-0}" = 1 ] && [ -n "${XYMEDIA_TITLE_NETWORK:-}" ]; then printf '%s\n' --network "$XYMEDIA_TITLE_NETWORK" --network-alias "$(title_name)"; elif docker network inspect xymedia-managed >/dev/null 2>&1; then printf '%s\n' --network xymedia-managed --network-alias xymedia-title-standalone; fi; }
owned_standalone() {
	n=$(title_name)
	[ "$(docker inspect --format '{{index .Config.Labels "io.xymedia.owner"}}' "$n" 2>/dev/null || true)" = xymedia-title-standalone ] && [ "$(docker inspect --format '{{index .Config.Labels "io.xymedia.installer"}}' "$n" 2>/dev/null || true)" = xymediavault-script ]
}
title_conflict() {
	container_exists xymedia-title && die2 '固定名称 xymedia-title 已存在，可能由 Vault 或 foreign 服务占用'
	n=$(title_name)
	if container_exists "$n" && ! owned_standalone; then die2 '独立 Title 容器名已被 foreign 容器占用'; fi
}
title_create() {
	ch=$1
	image=$(channel_image "$ch" title)
	n=$(title_name)
	p=$(title_port)
	set -- docker run -d --name "$n" --label io.xymedia.owner=xymedia-title-standalone --label io.xymedia.installer=xymediavault-script --label io.xymedia.service=xymedia-title --label io.xymedia.channel="$ch" --user 10001:10001 --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m,mode=1777 --tmpfs /dev/shm:rw,noexec,nosuid,size=64m,mode=1777 --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1536m --cpus 1 --restart unless-stopped -p "127.0.0.1:$p:8080"
	network_args=$(title_network_args)
	# Network options are generated internally as fixed words.
	# shellcheck disable=SC2086
	set -- "$@" $network_args
	"$@" "$image"
}
title_version() {
	n=$(title_name)
	docker exec "$n" python -c 'import json,urllib.request; d=json.load(urllib.request.urlopen("http://127.0.0.1:8080/version", timeout=5)); assert d.get("service")=="xymedia-title" and d.get("model")=="bert"; print(json.dumps(d,sort_keys=True))' 2>/dev/null
}
title_registry_state() {
	image=$(container_image "$(title_name)")
	[ "$image" != unknown ] || {
		printf UNKNOWN
		return
	}
	remote=$(docker manifest inspect "$image" 2>/dev/null || true)
	[ -n "$remote" ] || {
		printf UNKNOWN
		return
	}
	local_id=$(docker inspect --format '{{.Image}}' "$(title_name)" 2>/dev/null || true)
	pulled_id=$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)
	[ -n "$local_id" ] && [ "$local_id" = "$pulled_id" ] && printf current || printf outdated
}
title_health() {
	n=$(title_name)
	end=$(($(date +%s) + 180))
	while [ "$(date +%s)" -lt "$end" ]; do
		if docker exec "$n" python -c 'import urllib.request; r=urllib.request.urlopen("http://127.0.0.1:8080/healthz",timeout=3); raise SystemExit(0 if r.status == 200 else 1)' >/dev/null 2>&1 && title_version >/dev/null 2>&1; then return 0; fi
		sleep 2
	done
	return 1
}
title_install() {
	ch=stable
	yes=false
	while [ $# -gt 0 ]; do case "$1" in --channel)
		[ $# -ge 2 ] || die2 '--channel 需要参数'
		ch=$2
		shift 2
		;;
	--channel=*)
		ch=${1#--channel=}
		[ -n "$ch" ] || die2 '--channel 需要参数'
		shift
		;;
	--yes)
		yes=true
		shift
		;;
	*) die2 "未知参数：$1" ;; esac done
	valid_channel "$ch" || die2 'channel 必须是 stable 或 beta'
	[ "$(platform)" = linux/amd64 ] || [ "$(platform)" = linux/arm64 ] || die2 'Title 仅支持 amd64/arm64'
	title_conflict
	confirm "$yes" '安装独立 XyMedia Title。' || exit 1
	lock_acquire
	image=$(channel_image "$ch" title)
	docker pull "$image" || die 'Title 镜像拉取失败'
	title_create "$ch"
	if ! title_health; then
		docker rm -f "$(title_name)" >/dev/null 2>&1 || true
		die 'Title health/version 检查失败'
	fi
	log "Title $ch 已安装，URL：http://127.0.0.1:$(title_port)/healthz"
}
title_check() { if container_exists xymedia-title; then printf '%s\n' 'Title 由 Vault 托管，独立脚本不操作。'; elif container_exists "$(title_name)"; then
	owned_standalone || die2 '独立 Title 容器不是本脚本创建，拒绝操作'
	printf 'Title: %s channel=%s registry=%s version=' "$(container_state "$(title_name)")" "$(docker inspect --format '{{index .Config.Labels "io.xymedia.channel"}}' "$(title_name)")" "$(title_registry_state)"
	title_version 2>/dev/null || printf UNKNOWN
	printf '\n'
else printf '%s\n' 'Title: not installed'; fi; }
title_upgrade() {
	ch=
	yes=false
	n=$(title_name)
	while [ $# -gt 0 ]; do case "$1" in --channel)
		[ $# -ge 2 ] || die2 '--channel 需要参数'
		ch=$2
		shift 2
		;;
	--channel=*)
		ch=${1#--channel=}
		[ -n "$ch" ] || die2 '--channel 需要参数'
		shift
		;;
	--yes)
		yes=true
		shift
		;;
	*) die2 "未知参数：$1" ;; esac done
	container_exists "$n" || die2 '独立 Title 未安装'
	owned_standalone || die2 '独立 Title 不是本脚本所有'
	[ -n "$ch" ] || ch=$(docker inspect --format '{{index .Config.Labels "io.xymedia.channel"}}' "$n")
	valid_channel "$ch" || die2 'channel 无效'
	confirm "$yes" '升级独立 XyMedia Title。' || exit 1
	lock_acquire
	image=$(channel_image "$ch" title)
	docker pull "$image" || die '拉取失败，旧容器保持不变'
	backup="${n}.backup.$$"
	docker rename "$n" "$backup" || die '无法保存旧容器'
	old_running=$(docker inspect --format '{{.State.Running}}' "$backup")
	if [ "$old_running" = true ]; then docker stop "$backup" >/dev/null || {
		docker rename "$backup" "$n"
		die '无法停止旧容器'
	}; fi
	if ! title_create "$ch" || ! title_health; then
		docker rm -f "$n" >/dev/null 2>&1 || true
		docker rename "$backup" "$n" || true
		[ "$old_running" = true ] && docker start "$n" >/dev/null 2>&1 || true
		die '升级失败，已恢复旧容器'
	fi
	if ! docker rm -f "$backup" >/dev/null 2>&1; then
		docker rm -f "$n" >/dev/null 2>&1 || true
		docker rename "$backup" "$n" || true
		[ "$old_running" = true ] && docker start "$n" >/dev/null 2>&1 || true
		die '无法删除旧容器，已恢复旧容器'
	fi
	log "Title 已升级：$ch"
}
title_command() {
	cmd=${1:-}
	[ $# -gt 0 ] && shift
	case "$cmd" in install) title_install "$@" ;; check) title_check ;; upgrade) title_upgrade "$@" ;; *)
		title_usage
		exit 2
		;;
	esac
}
uninstall_service() {
	service=${1:-}
	[ $# -gt 0 ] && shift
	yes=false
	purge=false
	while [ $# -gt 0 ]; do case "$1" in --yes)
		yes=true
		shift
		;;
	--purge-data)
		purge=true
		shift
		;;
	*) die2 "未知参数：$1" ;; esac done
	case "$service" in title)
		n=$(title_name)
		container_exists xymedia-title && die2 '固定 xymedia-title 由 Vault/foreign 管理，拒绝删除'
		container_exists "$n" && ! owned_standalone && die2 'foreign Title 容器，拒绝删除'
		confirm "$yes" '卸载独立 XyMedia Title。' || exit 1
		lock_acquire
		docker rm -f "$n" >/dev/null 2>&1 || true
		[ "$purge" = true ] && log 'Title 无 volume，不删除模型数据'
		;;
	vault)
		confirm "$yes" '卸载 Vault，将停止并删除服务。' || exit 1
		lock_acquire
		d=$(install_dir)
		c=$(compose_cmd 2>/dev/null || true)
		[ -z "$c" ] || $c -f "$d/docker-compose.yml" down || true
		rm -f "$d/.xymedia-channel"
		[ "$purge" = true ] && rm -rf "$d/data" "$d/xiaoya" "$d/tmm"
		;;
	*) die2 'uninstall 目标必须是 vault 或 title' ;; esac
}

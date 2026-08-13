#!/usr/bin/env sh
vault_usage() { printf '%s\n' 'vault install|check|upgrade|switch'; }

vault_dir_from_args() {
	d=$(install_dir)
	while [ $# -gt 0 ]; do
		case "$1" in
		--dir)
			[ $# -ge 2 ] || die2 '--dir 需要参数'
			d=$2
			shift 2
			;;
		--dir=*)
			d=${1#--dir=}
			[ -n "$d" ] || die2 '--dir 需要参数'
			shift
			;;
		*) shift ;;
		esac
	done
	safe_dir "$d" || die '安装目录不安全'
	printf '%s' "$d"
}

vault_run_legacy() {
	ch=$1
	d=$2
	mode=$3
	noninteractive=${4:-false}
	assumeyes=${5:-false}
	image=$(channel_image "$ch" vault)
	tmm=$(channel_image "$ch" tmm)
	legacy=${XYMEDIA_LEGACY_INSTALLER:-$SCRIPT_DIR/legacy-install.sh}
	[ -r "$legacy" ] || die "缺少 legacy engine：$legacy"
	mkdir -p "$d"
	log "调用完整 Vault legacy engine（$mode，$ch）"
	(cd "$d" && IMAGE="$image" XYMEDIA_TMM_IMAGE="$tmm" XYMEDIA_NON_INTERACTIVE="$noninteractive" XYMEDIA_ASSUME_YES="$assumeyes" sh "$legacy" "$d")
}

vault_install() {
	ch=stable
	d=$(install_dir)
	noninteractive=false
	assumeyes=false
	while [ $# -gt 0 ]; do
		case "$1" in
		--channel)
			[ $# -ge 2 ] || die2 '--channel 需要参数'
			ch=$2
			shift 2
			;;
		--channel=*)
			ch=${1#--channel=}
			[ -n "$ch" ] || die2 '--channel 需要参数'
			shift
			;;
		stable | beta)
			ch=$1
			shift
			;;
		--dir)
			[ $# -ge 2 ] || die2 '--dir 需要参数'
			d=$2
			shift 2
			;;
		--dir=*)
			d=${1#--dir=}
			[ -n "$d" ] || die2 '--dir 需要参数'
			shift
			;;
		--non-interactive)
			noninteractive=true
			shift
			;;
		--yes)
			assumeyes=true
			shift
			;;
		*) die2 "未知 vault install 参数：$1" ;;
		esac
	done
	valid_channel "$ch" || die2 'channel 必须是 stable 或 beta'
	[ "$noninteractive" = true ] || [ "${MENU_INTERACTIVE:-false}" = true ] || is_tty || die2 '非交互安装必须指定 --non-interactive'
	safe_dir "$d" || die2 '安装目录不安全'
	[ ! -e "$d/docker-compose.yml" ] || die2 '已有安装，请使用 upgrade 或 switch'
	docker_ready || die 'Docker 不可用'
	lock_acquire
	vault_run_legacy "$ch" "$d" install "$noninteractive" "$assumeyes" || exit $?
	write_channel "$d" "$ch"
	log "Vault $ch 已安装：$d"
}

vault_check() {
	d=$(install_dir)
	while [ $# -gt 0 ]; do
		case "$1" in
		--dir)
			[ $# -ge 2 ] || die2 '--dir 需要参数'
			d=$2
			shift 2
			;;
		--dir=*)
			d=${1#--dir=}
			[ -n "$d" ] || die2 '--dir 需要参数'
			shift
			;;
		*) die2 "未知 vault check 参数：$1" ;;
		esac
	done
	if [ ! -f "$d/docker-compose.yml" ]; then
		printf '%s\n' 'Vault: not installed'
		return 0
	fi
	state=$(container_state xymediavault)
	printf 'Vault: %s (%s)\n' "$state" "$(read_channel "$d")"
}

vault_upgrade() {
	d=$(install_dir)
	ch=${XYMEDIA_CHANNEL:-$(read_channel "$d")}
	[ -n "$ch" ] || ch=stable
	yes=false
	while [ $# -gt 0 ]; do
		case "$1" in
		--channel)
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
		--dir)
			[ $# -ge 2 ] || die2 '--dir 需要参数'
			d=$2
			shift 2
			;;
		--dir=*)
			d=${1#--dir=}
			[ -n "$d" ] || die2 '--dir 需要参数'
			shift
			;;
		*) die2 "未知 vault upgrade 参数：$1" ;;
		esac
	done
	valid_channel "$ch" || die2 'channel 必须是 stable 或 beta'
	if [ "$yes" = true ]; then
		noninteractive=true
		assumeyes=true
	else
		is_tty || die2 '非交互升级必须指定 --yes'
		confirm false '升级 Vault 并备份/替换容器。' || exit 1
		noninteractive=false
		assumeyes=false
	fi
	safe_dir "$d" || die2 '安装目录不安全'
	[ -f "$d/docker-compose.yml" ] || die2 'Vault 未安装'
	lock_acquire
	vault_run_legacy "$ch" "$d" upgrade "$noninteractive" "$assumeyes" || exit $?
	write_channel "$d" "$ch"
	log "Vault 已升级：$ch"
}

vault_switch() {
	ch=
	yes=false
	d=$(install_dir)
	while [ $# -gt 0 ]; do
		case "$1" in
		--channel)
			[ $# -ge 2 ] || die2 '--channel 需要参数'
			ch=$2
			shift 2
			;;
		--channel=*)
			ch=${1#--channel=}
			[ -n "$ch" ] || die2 '--channel 需要参数'
			shift
			;;
		--dir)
			[ $# -ge 2 ] || die2 '--dir 需要参数'
			d=$2
			shift 2
			;;
		--dir=*)
			d=${1#--dir=}
			[ -n "$d" ] || die2 '--dir 需要参数'
			shift
			;;
		--yes)
			yes=true
			shift
			;;
		*) die2 "未知 vault switch 参数：$1" ;;
		esac
	done
	[ -n "$ch" ] || die2 'switch 需要 --channel'
	valid_channel "$ch" || die2 'channel 必须是 stable 或 beta'
	[ -f "$d/docker-compose.yml" ] || die2 'Vault 未安装'
	if [ "$ch" = beta ]; then confirm "$yes" '切换 Beta 将运行测试镜像。' || exit 1; fi
	if [ "$yes" = true ]; then
		vault_upgrade --channel "$ch" --dir "$d" --yes
	else
		is_tty || die2 '非交互切换必须指定 --yes'
		confirm false '切换 Vault 通道并备份/替换容器。' || exit 1
		vault_upgrade --channel "$ch" --dir "$d" --yes
	fi
}

vault_command() {
	cmd=${1:-}
	[ $# -gt 0 ] && shift
	case "$cmd" in
	install) vault_install "$@" ;; check) vault_check "$@" ;; upgrade) vault_upgrade "$@" ;; switch) vault_switch "$@" ;;
	*)
		vault_usage
		exit 2
		;;
	esac
}

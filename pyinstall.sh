#!/usr/bin/env bash
# lxspacepy：在主流 Linux 发行版上安全地编译和管理独立 Python 版本。

set -Eeuo pipefail
IFS=$'\n\t'

PROGRAM_NAME="lxspacepy"
INSTALL_ROOT="${LXSPACEPY_INSTALL_ROOT:-/usr/local/lxspacepy}"
VERSIONS_ROOT="$INSTALL_ROOT/versions"
BIN_DIR="${LXSPACEPY_BIN_DIR:-/usr/local/bin}"
MARKER_NAME=".lxspacepy-install"
BUILD_DIR=""
INSTALL_PREFIX=""

log() {
    printf '[%s] %s\n' "$PROGRAM_NAME" "$*"
}

warn() {
    printf '[%s] 警告：%s\n' "$PROGRAM_NAME" "$*" >&2
}

die() {
    printf '[%s] 错误：%s\n' "$PROGRAM_NAME" "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
用法：
  pyinstall.sh                         打开交互菜单
  pyinstall.sh list                    列出本工具管理的 Python
  pyinstall.sh verify VERSION          验证已安装的 Python
  pyinstall.sh install VERSION [选项]  编译安装 Python
  pyinstall.sh switch VERSION          切换默认 python 命令
  pyinstall.sh uninstall VERSION       卸载本工具安装的 Python

install 选项：
  --sha256 HEX           官方源码包的 SHA-256（推荐）
  --allow-unverified     明确允许不校验源码（不推荐）

uninstall 选项：
  --yes                  跳过交互确认

示例：
  sudo ./pyinstall.sh install 3.12.12 --sha256 <64位校验值>
  sudo ./pyinstall.sh switch 3.12.12
  sudo ./pyinstall.sh uninstall 3.12.12

环境变量：
  JOBS                   并行编译任务数，默认为 CPU 核数
EOF
}

cleanup() {
    local status=$?
    trap - EXIT

    if [[ -n "$BUILD_DIR" && -d "$BUILD_DIR" ]]; then
        rm -rf -- "$BUILD_DIR"
    fi

    if (( status != 0 )) && [[ -n "$INSTALL_PREFIX" && -d "$INSTALL_PREFIX" ]]; then
        warn "安装未完成，正在清理 $INSTALL_PREFIX"
        rm -rf -- "$INSTALL_PREFIX"
    fi

    exit "$status"
}

require_root() {
    (( EUID == 0 )) || die "此操作需要 root 权限，请使用 sudo。"
}

PACKAGE_MANAGER=""

require_platform() {
    if command -v apt-get >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
    elif command -v zypper >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; then
        PACKAGE_MANAGER="zypper"
    elif command -v apk >/dev/null 2>&1; then
        PACKAGE_MANAGER="apk"
    else
        die "不支持的系统。目前支持 apt、dnf/yum、pacman、zypper 和 apk。"
    fi
}

package_is_installed() {
    local package="$1"
    case "$PACKAGE_MANAGER" in
        apt)
            dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q '^install ok installed$'
            ;;
        dnf|yum|zypper)
            rpm -q "$package" >/dev/null 2>&1
            ;;
        pacman)
            pacman -Q "$package" >/dev/null 2>&1
            ;;
        apk)
            apk info -e "$package" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

is_valid_version() {
    [[ "${1:-}" =~ ^3\.[0-9]+\.[0-9]+$ ]]
}

is_valid_sha256() {
    [[ "${1:-}" =~ ^[[:xdigit:]]{64}$ ]]
}

major_minor() {
    local version="$1"
    local major minor
    IFS='.' read -r major minor _ <<< "$version"
    printf '%s.%s' "$major" "$minor"
}

prefix_for() {
    printf '%s/%s' "$VERSIONS_ROOT" "$1"
}

python_for() {
    local version="$1"
    local mm
    mm="$(major_minor "$version")"
    printf '%s/bin/python%s' "$(prefix_for "$version")" "$mm"
}

is_managed_install() {
    local version="$1"
    local prefix marker content
    prefix="$(prefix_for "$version")"
    marker="$prefix/$MARKER_NAME"

    [[ -d "$prefix" && -f "$marker" ]] || return 1
    content="$(<"$marker")"
    [[ "$content" == $'version='"$version"$'\nprefix='"$prefix" ]]
}

verify_install() {
    local version="$1"
    local python
    python="$(python_for "$version")"

    is_managed_install "$version" || return 1
    [[ -x "$python" ]] || return 1
    "$python" -c 'import bz2, ctypes, lzma, readline, sqlite3, ssl' >/dev/null 2>&1 || return 1
    "$python" -m pip --version >/dev/null 2>&1 || return 1
}

install_dependencies() {
    local packages=()
    local missing=()
    local package

    require_platform
    case "$PACKAGE_MANAGER" in
        apt)
            packages=(
                build-essential ca-certificates curl
                libbz2-dev libffi-dev libgdbm-dev libgdbm-compat-dev
                liblzma-dev libncurses-dev libreadline-dev libsqlite3-dev
                libssl-dev make pkg-config uuid-dev zlib1g-dev
            )
            ;;
        dnf|yum)
            packages=(
                gcc gcc-c++ make ca-certificates curl
                bzip2-devel libffi-devel gdbm-devel xz-devel ncurses-devel
                readline-devel sqlite-devel openssl-devel pkgconf-pkg-config
                libuuid-devel zlib-devel
            )
            ;;
        pacman)
            packages=(
                base-devel ca-certificates curl bzip2 libffi gdbm xz
                ncurses readline sqlite openssl pkgconf util-linux zlib
            )
            ;;
        zypper)
            packages=(
                gcc gcc-c++ make ca-certificates curl
                libbz2-devel libffi-devel gdbm-devel xz-devel ncurses-devel
                readline-devel sqlite3-devel libopenssl-devel pkg-config
                libuuid-devel zlib-devel
            )
            ;;
        apk)
            packages=(
                build-base ca-certificates curl bash
                bzip2-dev libffi-dev gdbm-dev xz-dev ncurses-dev
                readline-dev sqlite-dev openssl-dev pkgconf
                util-linux-dev zlib-dev
            )
            ;;
    esac

    for package in "${packages[@]}"; do
        if ! package_is_installed "$package"; then
            missing+=("$package")
        fi
    done

    if (( ${#missing[@]} == 0 )); then
        log "编译依赖已满足。"
        return
    fi

    log "通过 $PACKAGE_MANAGER 安装缺失依赖：${missing[*]}"
    case "$PACKAGE_MANAGER" in
        apt)
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
            ;;
        dnf)
            dnf install -y --setopt=install_weak_deps=False "${missing[@]}"
            ;;
        yum)
            yum install -y "${missing[@]}"
            ;;
        pacman)
            pacman -S --noconfirm --needed "${missing[@]}"
            ;;
        zypper)
            zypper --non-interactive install --no-recommends "${missing[@]}"
            ;;
        apk)
            apk add --no-cache "${missing[@]}"
            ;;
    esac
}

run_logged() {
    local description="$1"
    local logfile="$2"
    shift 2

    log "$description"
    if ! "$@" >"$logfile" 2>&1; then
        tail -n 40 "$logfile" >&2 || true
        die "$description失败。上方为最后 40 行日志。"
    fi
}

download_source() {
    local version="$1"
    local destination="$2"
    local url="https://www.python.org/ftp/python/$version/Python-$version.tgz"

    curl \
        --fail --location \
        --proto '=https' --tlsv1.2 \
        --retry 3 --retry-delay 2 \
        --output "$destination" \
        "$url"
}

verify_source() {
    local tarball="$1"
    local expected="$2"
    local actual

    if [[ -z "$expected" ]]; then
        warn "已按你的明确要求跳过源码校验。只有完全信任下载来源时才应这样做。"
        return
    fi

    actual="$(sha256sum "$tarball")"
    actual="${actual%% *}"
    expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"

    [[ "$actual" == "$expected" ]] || die "SHA-256 不匹配，源码包可能已损坏或被篡改。"
    log "源码 SHA-256 校验通过。"
}

create_managed_link() {
    local target="$1"
    local link="$2"
    local current=""

    if [[ -L "$link" ]]; then
        current="$(readlink "$link" 2>/dev/null || true)"
        [[ "$current" == "$target" ]] || die "拒绝覆盖指向其他目标的软链接：$link"
        return
    fi
    if [[ -e "$link" ]]; then
        die "拒绝覆盖已有文件：$link"
    fi
    ln -s -- "$target" "$link"
}

register_installation() {
    local version="$1"
    local python mm pip
    python="$(python_for "$version")"
    mm="$(major_minor "$version")"
    pip="$(dirname "$python")/pip$mm"

    mkdir -p -- "$BIN_DIR"
    create_managed_link "$python" "$BIN_DIR/python$version"
    if [[ -x "$pip" ]]; then
        create_managed_link "$pip" "$BIN_DIR/pip$version"
    fi
}

command_install() {
    local version="${1:-}"
    local sha256=""
    local allow_unverified=0
    local prefix python tarball source_dir jobs

    [[ -n "$version" ]] || die "install 需要版本号。"
    shift

    while (( $# > 0 )); do
        case "$1" in
            --sha256)
                (( $# >= 2 )) || die "--sha256 需要 64 位十六进制校验值。"
                sha256="$2"
                shift 2
                ;;
            --allow-unverified)
                allow_unverified=1
                shift
                ;;
            *)
                die "未知安装选项：$1"
                ;;
        esac
    done

    is_valid_version "$version" || die "仅支持 Python 3 的完整版本号，例如 3.12.12。"
    if [[ -n "$sha256" ]]; then
        is_valid_sha256 "$sha256" || die "SHA-256 必须是 64 位十六进制字符串。"
    elif (( allow_unverified == 0 )); then
        die "请通过 --sha256 提供官方校验值，或明确使用 --allow-unverified。"
    fi
    if [[ -n "$sha256" && $allow_unverified -eq 1 ]]; then
        die "--sha256 与 --allow-unverified 不能同时使用。"
    fi

    require_root
    prefix="$(prefix_for "$version")"
    python="$(python_for "$version")"

    if [[ -e "$prefix" ]]; then
        if verify_install "$version"; then
            register_installation "$version"
            log "Python $version 已经安装并完成验证：$prefix"
            return
        fi
        die "$prefix 已存在但不是完整安装。请检查后用 uninstall $version 清理，再重新安装。"
    fi

    install_dependencies
    for command in curl sha256sum tar tail make; do
        command -v "$command" >/dev/null 2>&1 || die "缺少命令：$command"
    done

    jobs="${JOBS:-$(nproc 2>/dev/null || printf '1')}"
    [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "JOBS 必须是正整数。"
    BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lxspacepy.XXXXXXXX")"
    chmod 700 "$BUILD_DIR"
    INSTALL_PREFIX="$prefix"
    tarball="$BUILD_DIR/Python-$version.tgz"
    source_dir="$BUILD_DIR/Python-$version"

    log "下载 Python $version 源码。"
    download_source "$version" "$tarball"
    verify_source "$tarball" "$sha256"

    log "解压源码。"
    tar -xzf "$tarball" -C "$BUILD_DIR"
    [[ -d "$source_dir" ]] || die "源码包结构与预期不符。"

    (
        cd "$source_dir"
        run_logged "配置编译环境" "$BUILD_DIR/configure.log" \
            ./configure --prefix="$prefix" --with-ensurepip=install
        run_logged "编译 Python（使用 $jobs 个并行任务）" "$BUILD_DIR/make.log" \
            make -j"$jobs"
        run_logged "安装 Python" "$BUILD_DIR/install.log" \
            make altinstall
    )

    [[ -x "$python" ]] || die "安装结束，但未找到 $python。"
    printf 'version=%s\nprefix=%s\n' "$version" "$prefix" >"$prefix/$MARKER_NAME"
    chmod 0644 "$prefix/$MARKER_NAME"

    verify_install "$version" || die "安装后的模块或 pip 验证失败。"
    register_installation "$version"
    INSTALL_PREFIX=""

    log "Python $version 安装成功：$prefix"
    log "独立命令：$BIN_DIR/python$version"
}

command_list() {
    local marker version python
    local count=0

    printf '本工具管理的 Python：\n'
    for marker in "$VERSIONS_ROOT"/*/"$MARKER_NAME"; do
        [[ -f "$marker" ]] || continue
        version="$(basename "$(dirname "$marker")")"
        if is_valid_version "$version" && is_managed_install "$version"; then
            python="$(python_for "$version")"
            if [[ -x "$python" ]]; then
                printf '  %-12s %s\n' "$version" "$python"
                ((count += 1))
            else
                warn "$version 缺少可执行文件，安装可能已损坏。"
            fi
        fi
    done

    if (( count == 0 )); then
        printf '  （无）\n'
    fi

    printf '\n当前默认命令：\n'
    if command -v python >/dev/null 2>&1; then
        printf '  python -> '
        python --version
    else
        printf '  未配置 python 命令\n'
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '  python3 -> '
        python3 --version
    fi
}

command_verify() {
    local version="${1:-}"
    is_valid_version "$version" || die "请提供完整的 Python 3 版本号。"
    verify_install "$version" || die "Python $version 未安装、不是本工具管理，或未通过验证。"
    "$(python_for "$version")" --version
    log "Python $version 的核心模块和 pip 均正常。"
}

command_switch() {
    local version="${1:-}"
    local python
    is_valid_version "$version" || die "请提供完整的 Python 3 版本号。"
    require_root
    verify_install "$version" || die "Python $version 未通过验证，不能切换。"
    python="$(python_for "$version")"

    register_installation "$version"
    create_managed_link "$python" "$BIN_DIR/python"
    log "默认 python 已切换为 Python $version（$BIN_DIR/python）。"
    "$BIN_DIR/python" --version
}

remove_link_if_owned() {
    local link="$1"
    local prefix="$2"
    local target

    if [[ -L "$link" ]]; then
        target="$(readlink "$link" 2>/dev/null || true)"
        if [[ "$target" == "$prefix/"* ]]; then
            rm -f -- "$link"
        else
            warn "保留不属于此安装的软链接：$link"
        fi
    elif [[ -e "$link" ]]; then
        warn "保留非软链接文件：$link"
    fi
}

command_uninstall() {
    local version="${1:-}"
    local assume_yes=0
    local prefix answer

    [[ -n "$version" ]] || die "uninstall 需要版本号。"
    shift
    while (( $# > 0 )); do
        case "$1" in
            --yes)
                assume_yes=1
                shift
                ;;
            *)
                die "未知卸载选项：$1"
                ;;
        esac
    done

    is_valid_version "$version" || die "请提供完整的 Python 3 版本号。"
    require_root
    prefix="$(prefix_for "$version")"

    [[ -d "$prefix" ]] || die "未找到 Python $version。"
    if ! is_managed_install "$version"; then
        warn "$prefix 没有有效安装标记，可能是不完整的安装。"
    fi

    if (( assume_yes == 0 )); then
        printf '将删除 %s，不会卸载任何系统软件包。输入 yes 继续：' "$prefix"
        read -r answer
        [[ "$answer" == "yes" ]] || die "已取消卸载。"
    fi

    remove_link_if_owned "$BIN_DIR/python" "$prefix"
    remove_link_if_owned "$BIN_DIR/python$version" "$prefix"
    remove_link_if_owned "$BIN_DIR/pip$version" "$prefix"
    rm -rf -- "$prefix"
    log "Python $version 已卸载。系统 python3 和系统软件包未被修改。"
}

pause_menu() {
    printf '\n按回车键返回菜单……'
    read -r _
}

command_menu() {
    local choice version sha256

    while true; do
        if [[ -t 1 && -n "${TERM:-}" ]]; then
            clear
        fi
        cat <<'EOF'
================================
       lxspacepy 版本管理器
================================
  1. 安装 Python
  2. 查看已安装版本
  3. 修改默认 python
  4. 卸载 Python
  5. 验证安装
  0. 退出
================================
EOF
        printf '请选择 [0-5]：'
        read -r choice

        case "$choice" in
            1)
                printf '版本号（例如 3.12.12）：'
                read -r version
                printf '官方 SHA-256（输入 skip 可明确跳过校验）：'
                read -r sha256
                if [[ "$sha256" == "skip" ]]; then
                    command_install "$version" --allow-unverified
                else
                    command_install "$version" --sha256 "$sha256"
                fi
                pause_menu
                ;;
            2)
                command_list
                pause_menu
                ;;
            3)
                command_list
                printf '要切换到的版本：'
                read -r version
                command_switch "$version"
                pause_menu
                ;;
            4)
                command_list
                printf '要卸载的版本：'
                read -r version
                command_uninstall "$version"
                pause_menu
                ;;
            5)
                printf '要验证的版本：'
                read -r version
                command_verify "$version"
                pause_menu
                ;;
            0)
                return
                ;;
            *)
                warn "无效选择。"
                pause_menu
                ;;
        esac
    done
}

main() {
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    local command="${1:-menu}"
    if (( $# > 0 )); then
        shift
    fi

    case "$command" in
        menu)
            command_menu "$@"
            ;;
        install)
            command_install "$@"
            ;;
        list)
            (( $# == 0 )) || die "list 不接受参数。"
            command_list
            ;;
        verify)
            command_verify "$@"
            ;;
        switch)
            command_switch "$@"
            ;;
        uninstall)
            command_uninstall "$@"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            usage >&2
            die "未知命令：$command"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

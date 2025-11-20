#!/bin/bash
# Python 版本管理器 (增强修复版)

set -o pipefail

# 0. 权限检查
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：请使用 root 权限运行本脚本（例如：sudo $0）"
    exit 1
fi

# 0.1 基础环境检查（基于 Debian/Ubuntu）
for cmd in dpkg-query apt-get update-alternatives wget tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "错误：未找到命令 $cmd，本脚本仅支持 Debian/Ubuntu 且需要该命令。"
        exit 1
    fi
done

# --- 动画函数：带退出码传递 ---
show_spinner() {
    local pid="$1"
    local delay=0.1
    local spinstr='|/-\'
    local hide_cursor=0

    if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
        hide_cursor=1
        tput civis
    fi

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep "$delay"
        printf "\b\b\b\b\b\b"
    done

    if [ "$hide_cursor" -eq 1 ]; then
        tput cnorm
    fi

    printf "      \b\b\b\b\b\b"

    # 返回被监控进程的退出码
    wait "$pid"
    return $?
}

# --- 核心逻辑：获取系统自带版本 (用于隐藏) ---
get_system_hidden_pkg() {
    local real_path
    if command -v python3 >/dev/null 2>&1; then
        real_path=$(readlink -f "$(command -v python3)" 2>/dev/null || command -v python3)
        basename "$real_path"
    else
        echo "none"
    fi
}

# --- 核心逻辑：获取用户手动安装的APT版本 (过滤掉 minimal/dev 等杂项) ---
get_safe_apt_list() {
    local sys_hidden="$1"
    local pkg
    local candidates

    candidates=$(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | grep -E '^python[0-9]+\.[0-9]+$' || true)

    for pkg in $candidates; do
        if [ "$pkg" != "$sys_hidden" ]; then
            echo "$pkg"
        fi
    done
}

# --- 安装依赖 ---
CheckDeps() {
    local libs=(build-essential libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev zlib1g-dev make)
    local missing=()
    local lib

    for lib in "${libs[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$lib" 2>/dev/null | grep -q "install ok installed"; then
            missing+=("$lib")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "将安装缺失的依赖：${missing[*]}"
        if ! apt-get update; then
            echo "错误：apt-get update 失败，请检查网络或软件源配置。"
            return 1
        fi
        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"; then
            echo "错误：依赖安装失败，请检查网络或软件源配置。"
            return 1
        fi
    else
        echo "系统依赖已满足。"
    fi

    return 0
}

while true; do
    clear
    # 获取要隐藏的系统版本名
    sys_hidden=$(get_system_hidden_pkg)

    cat << END
================================
      Python 版本管理器
================================
    1. 安装 python
    2. 查看已安装 python
    3. 修改默认 python
    4. 卸载 python
    0. 退出
================================
END

    read -p "    请选择 [0-4]: " parameter
    echo ""

    case "$parameter" in
        1)
            # --- 安装 ---
            echo "提示：可访问 https://www.python.org/ftp/python 查看版本号"
            read -p "请输入安装版本号 (如 3.9.9): " version

            if [ -z "$version" ]; then
                echo "未输入版本号，已返回主菜单。"
            else
                if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo "版本号格式不正确，请输入类似 3.9.9 的完整三段版本号。"
                else
                    echo "正在检查系统依赖..."
                    if ! CheckDeps; then
                        echo "依赖检查/安装失败，无法继续安装 Python。"
                    else
                        install_path="/usr/local/python-$version"
                        IFS='.' read -r major minor patch <<< "$version"

                        if [ -d "$install_path" ]; then
                            echo "该版本已存在，无需重复安装。安装目录：$install_path"
                        else
                            workdir=$(pwd)
                            build_dir="/tmp/python-build-$version-$$"
                            mkdir -p "$build_dir"
                            cd "$build_dir" || {
                                echo "切换工作目录失败。"
                                cd "$workdir"
                                continue
                            }

                            echo "正在下载源码包..."
                            wget --progress=bar:force:noscroll "https://www.python.org/ftp/python/$version/Python-$version.tgz"
                            if [ $? -ne 0 ] || [ ! -f "Python-$version.tgz" ]; then
                                echo "下载失败，请检查版本号或网络连接。"
                                cd "$workdir"
                                rm -rf "$build_dir"
                                continue
                            fi

                            echo "正在解压..."
                            if ! tar -zxf "Python-$version.tgz"; then
                                echo "解压失败。"
                                cd "$workdir"
                                rm -rf "$build_dir"
                                continue
                            fi

                            cd "Python-$version" || {
                                echo "进入源码目录失败。"
                                cd "$workdir"
                                rm -rf "$build_dir"
                                continue
                            }

                            echo -n "1/3 正在配置环境... "
                            if ./configure --prefix="$install_path" > /tmp/python-configure.log 2>&1; then
                                echo "完成"
                            else
                                echo "失败 (详见 /tmp/python-configure.log)"
                                cd "$workdir"
                                rm -rf "$build_dir"
                                continue
                            fi

                            echo "2/3 正在编译源码 (可能需要 5-20 分钟)..."
                            echo -n "    编译中 "
                            make -j"$(nproc 2>/dev/null || echo 1)" > /tmp/python-make.log 2>&1 &
                            build_pid=$!
                            show_spinner "$build_pid"
                            build_status=$?

                            if [ "$build_status" -ne 0 ]; then
                                echo "失败 (详见 /tmp/python-make.log)"
                                cd "$workdir"
                                rm -rf "$build_dir"
                                continue
                            else
                                echo "完成"
                            fi

                            echo "3/3 正在安装文件 (可能需要数分钟)..."
                            echo -n "    安装中 "
                            make altinstall > /tmp/python-install.log 2>&1 &
                            install_pid=$!
                            show_spinner "$install_pid"
                            install_status=$?

                            if [ "$install_status" -ne 0 ]; then
                                echo "失败 (详见 /tmp/python-install.log)"
                                cd "$workdir"
                                rm -rf "$build_dir"
                                continue
                            else
                                echo "完成"
                            fi

                            cd "$workdir"
                            rm -rf "$build_dir"

                            # 创建版本专用软链，便于识别
                            ln -sf "$install_path/bin/python${major}.${minor}" "/usr/bin/python${major}.${minor}.${patch}"
                            if [ -x "$install_path/bin/pip${major}.${minor}" ]; then
                                ln -sf "$install_path/bin/pip${major}.${minor}" "/usr/bin/pip${major}.${minor}.${patch}"
                            fi

                            # 注册到 update-alternatives
                            update-alternatives --install /usr/bin/python python "$install_path/bin/python${major}.${minor}" 1

                            echo -n "正在升级 pip... "
                            if "$install_path/bin/python${major}.${minor}" -m pip install --upgrade pip --no-warn-script-location >/dev/null 2>&1; then
                                echo "完成"
                            else
                                echo "失败（可稍后手动执行：$install_path/bin/python${major}.${minor} -m pip install --upgrade pip）"
                            fi

                            echo ""
                            echo "Python $version 安装成功！安装目录：$install_path"
                        fi
                    fi
                fi
            fi
            ;;
        2)
            # --- 查看已安装python ---
            echo "--- 已安装 Python 版本列表 ---"
            count=0

            # 1. 扫描编译安装
            mapfile -t compiled_list < <(ls -d /usr/local/python-* 2>/dev/null || true)
            for p in "${compiled_list[@]}"; do
                ver=$(basename "$p" | sed 's/python-//')
                echo "  Python $ver (源码安装)"
                ((count++))
            done

            # 2. 扫描APT安装 (调用严格过滤函数)
            mapfile -t apt_list < <(get_safe_apt_list "$sys_hidden" || true)
            for pkg in "${apt_list[@]}"; do
                if [ -n "$pkg" ]; then
                    echo "  $pkg (APT 安装)"
                    ((count++))
                fi
            done

            if [ "$count" -eq 0 ]; then
                echo "  (暂无手动安装的版本)"
            fi

            echo ""
            echo "--- 当前默认版本 ---"
            python --version 2>/dev/null || echo "无 (可能未配置 /usr/bin/python)"
            ;;
        3)
            # --- 修改默认 ---
            echo "正在获取可用版本列表..."
            mapfile -t alt_list < <(update-alternatives --list python 2>/dev/null || true)

            if [ "${#alt_list[@]}" -eq 0 ]; then
                echo "错误：未检测到多版本配置。"
                echo "请先使用选项 1 安装一个新版本。"
            else
                echo -n "当前默认 python: "
                python --version 2>/dev/null || echo "无"

                echo "可用版本："
                idx=1
                for p in "${alt_list[@]}"; do
                    real_ver=$("$p" --version 2>&1 | awk '{print $2}')
                    echo "  $idx) Python $real_ver ($p)"
                    ((idx++))
                done
                echo "  0) 取消"

                read -p "请输入序号切换: " selection

                if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ] && [ "$selection" -le "${#alt_list[@]}" ]; then
                    target_path=${alt_list[$((selection-1))]}
                    if update-alternatives --set python "$target_path" >/dev/null 2>&1; then
                        echo ""
                        echo "切换成功！当前 python："
                        python --version 2>/dev/null || echo "未知"
                    else
                        echo "切换失败，请检查 update-alternatives 配置。"
                    fi
                elif [ "$selection" -eq 0 ] 2>/dev/null; then
                    echo "已取消。"
                else
                    echo "无效输入。"
                fi
            fi
            ;;
        4)
            # --- 卸载 ---
            # 1. 获取编译版列表
            mapfile -t src_list < <(ls -d /usr/local/python-* 2>/dev/null || true)

            # 2. 获取APT版列表
            mapfile -t clean_apt_list < <(get_safe_apt_list "$sys_hidden" || true)

            total_count=$(( ${#src_list[@]} + ${#clean_apt_list[@]} ))

            if [ "$total_count" -eq 0 ]; then
                echo "未发现可卸载的 Python 版本。"
            else
                echo "已安装版本："
                idx=1

                # 展示编译版
                for p in "${src_list[@]}"; do
                    ver=$(basename "$p" | sed 's/python-//')
                    echo "  $idx) Python $ver (源码安装)"
                    ((idx++))
                done

                # 展示APT版
                for p in "${clean_apt_list[@]}"; do
                    if [ -n "$p" ]; then
                        echo "  $idx) $p (APT 安装)"
                        ((idx++))
                    fi
                done
                echo "  0) 取消"

                read -p "请输入序号卸载: " selection

                if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ]; then
                    src_len=${#src_list[@]}
                    if [ "$selection" -le "$src_len" ]; then
                        # === 命中编译版 ===
                        target_path=${src_list[$((selection-1))]}
                        ver_num=$(basename "$target_path" | sed 's/python-//')
                        echo "正在卸载 Python $ver_num (源码安装)..."

                        # 先从 alternatives 中移除，再删除目录和软链
                        update-alternatives --remove python "$target_path/bin/python${ver_num%.*}" >/dev/null 2>&1 || true

                        rm -rf "$target_path"
                        rm -f "/usr/bin/python$ver_num" 2>/dev/null
                        rm -f "/usr/bin/pip$ver_num" 2>/dev/null

                        echo "卸载完成。"
                    elif [ "$selection" -le "$total_count" ]; then
                        # === 命中APT版 ===
                        real_idx=$((selection - src_len - 1))
                        if [ "$real_idx" -ge 0 ] && [ "$real_idx" -lt "${#clean_apt_list[@]}" ]; then
                            pkg_name=${clean_apt_list[$real_idx]}
                            echo "即将使用 apt 卸载 $pkg_name ..."
                            echo "注意：此操作可能影响系统中的其他软件。"
                            # 不加 -y，防止误删，让用户自行确认
                            apt-get remove "$pkg_name"
                            echo "apt 操作结束。"
                        else
                            echo "序号无效。"
                        fi
                    else
                        echo "序号无效。"
                    fi
                elif [ "$selection" -eq 0 ] 2>/dev/null; then
                    echo "已取消。"
                else
                    echo "无效输入。"
                fi
            fi
            ;;
        0)
            echo "已退出。"
            exit 0
            ;;
        *)
            echo "无效选择。"
            ;;
    esac

    echo ""
    read -n 1 -s -r -p "按任意键返回菜单..."
done

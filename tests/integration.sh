#!/usr/bin/env bash
# 在一次性 Linux 容器中执行真实下载、编译、验证、切换和卸载。
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="3.12.12"
SHA256="487c908ddf4097a1b9ba859f25fe46d22ccaabfb335880faac305ac62bffb79b"
SCRIPT="${1:-./pyinstall.sh}"
PREFIX="/usr/local/lxspacepy/versions/$VERSION"
PYTHON="/usr/local/bin/python$VERSION"
DEFAULT_PYTHON="/usr/local/bin/python"
export JOBS="${JOBS:-2}"

cleanup() {
    if [[ -d "$PREFIX" ]]; then
        bash "$SCRIPT" uninstall "$VERSION" --yes >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

printf '==> 安装 Python %s（JOBS=%s）\n' "$VERSION" "$JOBS"
bash "$SCRIPT" install "$VERSION" --sha256 "$SHA256"

printf '==> 验证独立命令和核心模块\n'
[[ "$("$PYTHON" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')" == "$VERSION" ]]
"$PYTHON" -m pip --version
bash "$SCRIPT" verify "$VERSION"
bash "$SCRIPT" list

printf '==> 验证重复安装是幂等操作\n'
bash "$SCRIPT" install "$VERSION" --sha256 "$SHA256"

# Arch 安装依赖时可能合法升级系统 Python；从切换前开始检查脚本没有改动它。
if command -v python3 >/dev/null 2>&1; then
    SYSTEM_PYTHON_BEFORE="$(command -v python3):$(python3 --version 2>&1)"
else
    SYSTEM_PYTHON_BEFORE="absent"
fi

printf '==> 切换默认 python\n'
bash "$SCRIPT" switch "$VERSION"
[[ "$("$DEFAULT_PYTHON" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')" == "$VERSION" ]]

if command -v python3 >/dev/null 2>&1; then
    SYSTEM_PYTHON_AFTER="$(command -v python3):$(python3 --version 2>&1)"
else
    SYSTEM_PYTHON_AFTER="absent"
fi
[[ "$SYSTEM_PYTHON_AFTER" == "$SYSTEM_PYTHON_BEFORE" ]]

printf '==> 卸载并确认清理完成\n'
bash "$SCRIPT" uninstall "$VERSION" --yes
[[ ! -e "$PREFIX" ]]
[[ ! -L "$PYTHON" ]]
[[ ! -L "$DEFAULT_PYTHON" ]]
if bash "$SCRIPT" verify "$VERSION" >/dev/null 2>&1; then
    printf '卸载后验证命令仍然成功，不符合预期。\n' >&2
    exit 1
fi

printf '==> 集成测试通过，系统 python3 未改变：%s\n' "$SYSTEM_PYTHON_AFTER"

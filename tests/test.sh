#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_DIR/pyinstall.sh"

PASSED=0
FAILED=0
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/lxspacepy-test.XXXXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT

pass() {
    printf 'ok - %s\n' "$1"
    ((PASSED += 1))
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    ((FAILED += 1))
}

check() {
    local description="$1"
    shift
    if "$@"; then
        pass "$description"
    else
        fail "$description"
    fi
}

check_equal() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$description"
    else
        printf '  expected: %s\n  actual:   %s\n' "$expected" "$actual" >&2
        fail "$description"
    fi
}

reject_version() {
    ! is_valid_version "$1"
}

reject_sha256() {
    ! is_valid_sha256 "$1"
}

reject_managed_install() {
    ! is_managed_install "$1"
}

expect_failure_in_subshell() {
    if ( "$@" ); then
        return 1
    fi
    return 0
}

expect_cli_failure() {
    if bash "$PROJECT_DIR/pyinstall.sh" "$@" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

link_is_absent() {
    [[ ! -L "$1" ]]
}

external_link_is_preserved() {
    [[ -L "$1" && -f "$2" ]]
}

check "接受标准 Python 3 版本号" is_valid_version 3.12.12
check "接受 Python 3.14" is_valid_version 3.14.0
check "拒绝缺少补丁号的版本" reject_version 3.12
check "拒绝 Python 2" reject_version 2.7.18
check "拒绝命令注入字符" reject_version '3.12.1;touch /tmp/pwned'
check_equal "提取主副版本号" "3.12" "$(major_minor 3.12.12)"

VALID_SHA="$(printf 'a%.0s' {1..64})"
check "接受 64 位 SHA-256" is_valid_sha256 "$VALID_SHA"
check "拒绝过短 SHA-256" reject_sha256 abc123
check "拒绝非十六进制 SHA-256" reject_sha256 "${VALID_SHA//a/g}"

VERSIONS_ROOT="$TEST_TMP/versions"
BIN_DIR="$TEST_TMP/bin"
TEST_VERSION="3.12.12"
TEST_PREFIX="$(prefix_for "$TEST_VERSION")"
mkdir -p "$TEST_PREFIX/bin" "$BIN_DIR"
printf 'version=%s\nprefix=%s\n' "$TEST_VERSION" "$TEST_PREFIX" >"$TEST_PREFIX/$MARKER_NAME"
check "识别有效安装标记" is_managed_install "$TEST_VERSION"
check_equal "安装目录位于专用根目录" "$TEST_TMP/versions/$TEST_VERSION" "$TEST_PREFIX"
check_equal "生成带补丁版本的 Python 路径" "$TEST_PREFIX/bin/python3.12" "$(python_for "$TEST_VERSION")"

printf 'prefix=/tmp/not-managed\n' >>"$TEST_PREFIX/$MARKER_NAME"
check "拒绝标记中目录不匹配的版本" reject_managed_install "$TEST_VERSION"
printf 'version=%s\nprefix=%s\n' "$TEST_VERSION" "$TEST_PREFIX" >"$TEST_PREFIX/$MARKER_NAME"

SOURCE_FILE="$TEST_TMP/source.tgz"
printf 'lxspacepy-test\n' >"$SOURCE_FILE"
SOURCE_SHA="$(sha256sum "$SOURCE_FILE")"
SOURCE_SHA="${SOURCE_SHA%% *}"
check "接受正确的源码 SHA-256" verify_source "$SOURCE_FILE" "$SOURCE_SHA"
check "拒绝错误的源码 SHA-256" expect_failure_in_subshell verify_source "$SOURCE_FILE" "$VALID_SHA"

printf 'python\n' >"$TEST_PREFIX/bin/python3.12"
ln -s "$TEST_PREFIX/bin/python3.12" "$BIN_DIR/python$TEST_VERSION"
remove_link_if_owned "$BIN_DIR/python$TEST_VERSION" "$TEST_PREFIX"
check "删除属于本安装的软链接" link_is_absent "$BIN_DIR/python$TEST_VERSION"

EXTERNAL_FILE="$TEST_TMP/external-python"
printf 'external\n' >"$EXTERNAL_FILE"
ln -s "$EXTERNAL_FILE" "$BIN_DIR/external-link"
remove_link_if_owned "$BIN_DIR/external-link" "$TEST_PREFIX"
check "保留指向外部文件的软链接" external_link_is_preserved "$BIN_DIR/external-link" "$EXTERNAL_FILE"

REGULAR_FILE="$BIN_DIR/regular-file"
printf 'keep\n' >"$REGULAR_FILE"
remove_link_if_owned "$REGULAR_FILE" "$TEST_PREFIX"
check_equal "保留非软链接文件内容" "keep" "$(<"$REGULAR_FILE")"

REGISTER_LINK="$BIN_DIR/registered-python"
create_managed_link "$TEST_PREFIX/bin/python3.12" "$REGISTER_LINK"
check_equal "创建指向本安装的软链接" "$TEST_PREFIX/bin/python3.12" "$(readlink "$REGISTER_LINK")"
check "拒绝覆盖其他软链接" expect_failure_in_subshell \
    create_managed_link "$EXTERNAL_FILE" "$REGISTER_LINK"
check_equal "冲突后保留原软链接目标" "$TEST_PREFIX/bin/python3.12" "$(readlink "$REGISTER_LINK")"
check "拒绝覆盖已有普通文件" expect_failure_in_subshell \
    create_managed_link "$EXTERNAL_FILE" "$REGULAR_FILE"
check_equal "冲突后保留普通文件" "keep" "$(<"$REGULAR_FILE")"

check "list 可在无安装记录时运行" env \
    LXSPACEPY_INSTALL_ROOT="$TEST_TMP/empty-root" \
    LXSPACEPY_BIN_DIR="$TEST_TMP/empty-bin" \
    bash "$PROJECT_DIR/pyinstall.sh" list
check "缺少 SHA-256 时拒绝非交互安装" expect_cli_failure install 3.12.12
check "拒绝冲突的源码校验选项" expect_cli_failure \
    install 3.12.12 --sha256 "$VALID_SHA" --allow-unverified
check "帮助命令正常退出" bash "$PROJECT_DIR/pyinstall.sh" --help

printf '\n通过：%d，失败：%d\n' "$PASSED" "$FAILED"
(( FAILED == 0 ))

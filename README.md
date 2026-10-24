# lxspacepy

在主流 **Linux 发行版**上编译、验证和管理独立的 Python 3 版本。

脚本遵循一个原则：**只管理自己安装的 Python，不卸载或替换系统 `python3` 及系统软件包。**

## 支持的系统

| 发行版 | 包管理器 |
|---|---|
| Ubuntu、Debian | `apt` |
| Fedora、RHEL、CentOS | `dnf` / `yum` |
| Arch Linux | `pacman` |
| openSUSE | `zypper` |
| Alpine Linux | `apk` |

CI 覆盖 Ubuntu、Debian、Fedora、Arch Linux、openSUSE 和 Alpine 的单元测试及真实编译流程。RHEL／CentOS 可能需要先启用对应的开发软件仓库。

## 安全设计

- 默认要求提供官方源码包的 SHA-256，校验通过后才解压和编译。
- 使用 `mktemp` 创建私有临时目录，退出或失败时自动清理。
- 安装到 `/usr/local/lxspacepy/versions/<版本>`，不扫描 `/usr/local/python-*`。
- 每个完整安装都有严格的标记文件；安装失败会清理本次产生的半成品。
- 安装后验证 `ssl`、`sqlite3`、`bz2`、`lzma`、`ctypes`、`readline` 和 pip。
- 卸载只删除专用目录及指向它的软链接，不卸载系统 Python 软件包。
- 默认 `python` 使用 `/usr/local/bin/python` 受控软链接，系统 `python3` 保持不变。
- 不覆盖已有同名文件或指向其他位置的软链接。

## 环境要求

- 上表所列的 Linux 发行版
- Bash 4 及以上
- 安装、切换和卸载需要 root 权限；查看和验证不需要
- 能访问 `https://www.python.org`
- `PATH` 中 `/usr/local/bin` 应位于 `/usr/bin` 之前，才能直接使用切换后的 `python`

缺少的编译依赖会通过系统包管理器安装。

## 快速开始

下载脚本：

```bash
curl --fail --location --proto '=https' --tlsv1.2 \
  --output pyinstall.sh \
  https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh
chmod +x pyinstall.sh
```

打开交互菜单：

```bash
sudo ./pyinstall.sh
```

菜单中的安装功能会要求输入版本号和 SHA-256。输入 `skip` 可以明确跳过校验，但不推荐。

## 命令行用法

### 1. 安装

SHA-256 必须属于所选的官方 `Python-<版本>.tgz`。可以从你信任的软件包元数据获取，或在独立下载后计算并与可信来源交叉核对。以下示例使用 Python 3.12.12 源码包的固定校验值：

```bash
sudo ./pyinstall.sh install 3.12.12 \
  --sha256 487c908ddf4097a1b9ba859f25fe46d22ccaabfb335880faac305ac62bffb79b
```

如明确接受不校验源码的风险：

```bash
sudo ./pyinstall.sh install 3.12.12 --allow-unverified
```

默认使用全部 CPU 核编译，可以限制并行数：

```bash
sudo JOBS=2 ./pyinstall.sh install 3.12.12 \
  --sha256 487c908ddf4097a1b9ba859f25fe46d22ccaabfb335880faac305ac62bffb79b
```

安装后可以使用独立命令，不会改变系统 `python3`：

```bash
python3.12.12 --version
pip3.12.12 --version
```

### 2. 查看与验证

```bash
./pyinstall.sh list
./pyinstall.sh verify 3.12.12
```

### 3. 切换默认 `python`

```bash
sudo ./pyinstall.sh switch 3.12.12
python --version
```

这只创建或更新 `/usr/local/bin/python`，不修改 `python3`。如果当前系统的 `PATH` 顺序不同，请使用绝对路径 `/usr/local/bin/python`。

### 4. 卸载

```bash
sudo ./pyinstall.sh uninstall 3.12.12
```

非交互环境可以跳过确认：

```bash
sudo ./pyinstall.sh uninstall 3.12.12 --yes
```

## 从旧版本迁移

旧脚本安装在 `/usr/local/python-*` 的版本不会自动纳入新脚本管理，也不会被新脚本卸载。建议先记录旧版本，再按需手动清理；不要直接删除系统 Python 软件包。

## 本地检查

```bash
bash -n pyinstall.sh tests/test.sh
shellcheck pyinstall.sh tests/test.sh
bash tests/test.sh
```

## 免责声明

编译和安装系统工具始终存在风险。请先备份重要数据，并优先在测试机或容器中验证。

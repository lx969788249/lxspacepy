# Python环境一键安装脚本，适用于Linux

这是一个用于在 Linux 系统上一键安装 Python 的脚本。该脚本使用 curl 或 wget 命令从 GitHub 下载并执行，可以帮助你快速安装 Python。

## 使用方法

### 1. 复制以下命令并在终端中运行：

```shell
curl -O https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh
```

国内：

```shell
curl -O https://ghproxy.com/https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh
```

或者使用 `wget` 命令：

```shell
wget --no-check-certificate https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh
```

国内：

```shell
wget --no-check-certificate https://ghproxy.com/https://raw.githubusercontent.com/lx969788249/lxspacepy/master/pyinstall.sh && chmod +x pyinstall.sh && ./pyinstall.sh
```



### 2. 按照提示进行操作

运行脚本后，你将看到一些提示信息，例如选择要安装的 Python 版本、安装目录等。按照提示进行操作即可完成安装。

## 注意事项

- 运行脚本需要在 Linux 终端下执行。
- 需要根据当前系统的架构选择合适的版本，否则可能会安装失败。
- 如果您已经安装了 Python，请不要重复安装。

## 其他

个人网站：[lxspace.top](https://lxspace.top/)

免责声明：本脚本仅供学习和交流使用，请勿用于非法用途，由此引起的任何法律问题与本脚本作者无关。

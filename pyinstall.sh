#!/bin/bash
# Python版本管理器优化版
# 原作者: LingFeng, 优化: AI Assistant

# 0. 预先检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 该脚本需要 Root 权限运行。"
    echo "请使用 sudo ./脚本名.sh 或切换到 root 用户后重试。"
    exit 1
fi

# python支持库函数
function Supportlibraries()
{
    echo "正在检查并安装依赖库..."
    local libs=(build-essential libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev zlib1g-dev make)
    
    # 自动更新apt索引（可选，建议加上）
    # apt update -y > /dev/null 2>&1 

    for lib in ${libs[@]}; do
        if [ `dpkg-query -l | grep $lib | wc -l` -eq "0" ]; then
             echo "正在安装缺少依赖: $lib"
             apt install $lib -y &> /dev/null
             if [ $? -eq 0 ]; then echo "$lib 安装成功"; else echo "$lib 安装失败"; fi
        else
             echo "依赖 $lib 已存在"
        fi
    done
}

# 字符串效验
function is_exists_arg() {
    local version=$1
    if [ -z $version ];then
        echo "错误：缺少版本号参数！"
        return 1
    fi
}

# 判断是否安装
function is_exists_python() {
    local version=$1
    local v=(${version//./ })
    # 重新构造路径变量以便检查
    local i_path="/usr/local/python-$version"
    if [ -d "$i_path" ]; then
        return 0
    else
        return 1
    fi
}

# --- 主程序循环 ---
while true; do
    clear
    cat << END
==========================================================
           欢迎使用 Python 版本管理器
==========================================================
    1. 安装 Python (自选版本)
    2. 查看已安装的 Python 版本
    3. 修改系统默认 Python 版本
    4. 卸载 Python
    0. 退出脚本
==========================================================
END
    
    # 1. 优化输入体验：光标在同一行
    read -p "    请输入你的选择 [0-4]: " parameter
    echo "" # 换行，美观

    case "$parameter" in
        1)
            # --- 安装功能 ---
            echo "可访问 https://www.python.org/ftp/python 查看可用版本"
            read -p "请输入要安装的版本号 (例如: 3.9.9): " version
            
            if [ -z "$version" ]; then
                echo "版本号不能为空！"
            else
                # 解析版本号
                v=(${version//./ })
                install_path="/usr/local/python-$version"
                python_path="$install_path/bin/python${v[0]}.${v[1]}"
                python_bin_path="/usr/bin/python${v[0]}.${v[1]}.${v[2]}"
                pip_path="$install_path/bin/pip${v[0]}.${v[1]}"
                pip_bin_path="/usr/bin/pip${v[0]}.${v[1]}.${v[2]}"

                # 检查是否已安装
                if [ -d "$install_path" ]; then
                    echo -e "\e[1;31mPython $version 已存在于 $install_path，无需重复安装。\e[m"
                else
                    echo -e "准备安装 Python版本：\e[1;33m$version\e[m"
                    Supportlibraries
                    
                    # 下载环节
                    dl_success=0
                    if [ ! -e "./Python-$version.tgz" ]; then
                        echo "正在下载 Python-$version.tgz ..."
                        wget -q --show-progress https://www.python.org/ftp/python/$version/Python-$version.tgz
                        if [ "$?" -eq "0" ]; then
                            echo "下载成功。"
                            dl_success=1
                        else
                            echo "下载失败，请检查网络或版本号是否正确。"
                        fi
                    else
                        echo "检测到本地已有安装包，直接使用。"
                        dl_success=1
                    fi

                    if [ "$dl_success" -eq "1" ]; then
                        echo "正在解压与编译安装，这可能需要几分钟..."
                        tar -zxf Python-$version.tgz
                        cd Python-$version
                        ./configure --prefix=$install_path > /dev/null
                        make -j$(nproc) > /dev/null && make install > /dev/null
                        
                        # 回到上级目录清理
                        cd ..
                        
                        # 配置软连接
                        ln -sf $python_path $python_bin_path
                        ln -sf $pip_path $pip_bin_path

                        if [ -d "$install_path" ]; then
                            echo -e "\e[1;32mPython $version 安装成功！\e[m"
                            echo "安装位置：$install_path"
                            # 添加到 alternatives
                            update-alternatives --install /usr/bin/python python /usr/bin/python$version 1
                            # 尝试更新 pip 源
                            echo "正在升级 pip..."
                            $install_path/bin/pip3 install --upgrade pip &> /dev/null
                        else
                            echo -e "\e[1;31m安装似乎失败了，请检查编译日志。\e[m"
                        fi
                    fi
                fi
            fi
            ;;
            
        2)
            # --- 查看功能 (优化版) ---
            echo "---------------------------------------"
            echo "【自定义安装版本】(/usr/local/python-*):"
            # 使用 find 或 ls 检查是否存在，避免报错
            if ls /usr/local/python-* 1> /dev/null 2>&1; then
                ls -d /usr/local/python-* | awk -F'python-' '{print $2}'
            else
                echo "  (暂无通过本脚本安装的自定义版本)"
            fi
            
            echo ""
            echo "【当前系统默认版本】:"
            if command -v python &> /dev/null; then
                python --version
                echo "对应路径: $(which python)"
            else
                echo "  (未找到默认 python 命令)"
            fi
            
            echo ""
            echo "【Alternatives 配置情况】:"
            update-alternatives --display python 2>/dev/null | grep "link currently points to" || echo "  (未配置 alternatives)"
            echo "---------------------------------------"
            ;;
            
        3)
            # --- 修改默认版本 ---
            echo "正在调用系统 update-alternatives 工具..."
            # 检查是否有候选项
            if update-alternatives --query python &>/dev/null; then
                update-alternatives --config python
            else
                echo "当前没有配置多版本 python 供选择。"
                echo "请先使用选项 1 安装新版本。"
            fi
            ;;
            
        4)
            # --- 卸载功能 ---
            read -p "请输入要卸载的python版本号 (例: 3.9.9): " vr
            if [ -z "$vr" ]; then
                 echo "版本号不能为空。"
            else
                target_dir="/usr/local/python-$vr"
                if [ ! -d "$target_dir" ]; then
                    echo "错误：目录 $target_dir 不存在，无法卸载。"
                else
                    echo "正在卸载 Python $vr ..."
                    # 删除文件
                    rm -rf "$target_dir"
                    # 删除可能的软连接 (忽略错误)
                    rm -f "/usr/bin/python$vr" "/usr/bin/pip$vr" 2>/dev/null
                    # 从 alternatives 移除
                    update-alternatives --remove python "/usr/bin/python$vr" &>/dev/null
                    echo "卸载完毕!"
                fi
            fi
            ;;
            
        0)
            # --- 退出 ---
            echo "感谢使用，再见！"
            exit 0
            ;;
            
        *)
            echo "输入无效，请输入 0-4 之间的数字。"
            ;;
    esac

    # 5. 暂停机制：让用户看完结果再清屏
    echo ""
    read -n 1 -s -r -p "按任意键返回主菜单..."
done

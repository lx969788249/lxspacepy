#!/bin/bash
# Python版本管理器 (最终优化版)
# 功能：安装、查看、切换默认、卸载 (支持菜单选择)

# 0. 预先检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "\033[31m错误: 该脚本需要 Root 权限运行。\033[0m"
    echo "请使用 sudo $0 或切换到 root 用户后重试。"
    exit 1
fi

# --- 函数定义区域 ---

# 检查并安装依赖
function Supportlibraries()
{
    echo "正在检查并安装系统依赖..."
    # 常用构建依赖
    local libs=(build-essential libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev zlib1g-dev make)
    
    # 建议更新 apt 索引，防止找不到包
    # apt update -y > /dev/null 2>&1

    for lib in ${libs[@]}; do
        # 使用 dpkg -s 检查安装状态可能更准确，但在脚本中 dpkg-query 足够快
        if [ `dpkg-query -l | grep $lib | wc -l` -eq "0" ]; then
             echo "正在安装: $lib ..."
             apt install $lib -y &> /dev/null
             if [ $? -eq 0 ]; then echo "  - $lib 安装成功"; else echo "  - $lib 安装失败"; fi
        else
             echo "  - $lib 已存在"
        fi
    done
}

# --- 主程序循环 ---
while true; do
    clear
    cat << END
==========================================================
           Python 多版本管理器 (Linux)
==========================================================
    1. 安装 Python (在线下载编译)
    2. 查看已安装版本
    3. 修改系统默认 Python (Alternatives)
    4. 卸载 Python (菜单选择)
    0. 退出
==========================================================
END
    
    read -p "    请输入你的选择 [0-4]: " parameter
    echo "" 

    case "$parameter" in
        1)
            # === 安装功能 ===
            echo "提示：可访问 https://www.python.org/ftp/python 查看版本号"
            read -p "请输入要安装的版本号 (例如: 3.9.9): " version
            
            if [ -z "$version" ]; then
                echo "错误：版本号不能为空！"
            else
                # 解析版本号
                v=(${version//./ })
                install_path="/usr/local/python-$version"
                
                # 路径定义
                python_path="$install_path/bin/python${v[0]}.${v[1]}"
                python_bin_path="/usr/bin/python${v[0]}.${v[1]}.${v[2]}" # 这里的软连接名稍微有点长，保留原逻辑
                pip_path="$install_path/bin/pip${v[0]}.${v[1]}"
                pip_bin_path="/usr/bin/pip${v[0]}.${v[1]}.${v[2]}"

                if [ -d "$install_path" ]; then
                    echo -e "\033[31m检测到 Python $version 已存在 ($install_path)，无需重复安装。\033[0m"
                else
                    echo -e "准备安装版本：\033[33m$version\033[0m"
                    Supportlibraries
                    
                    # 下载
                    dl_success=0
                    if [ ! -e "./Python-$version.tgz" ]; then
                        echo "正在下载源码包..."
                        # -q --show-progress 显示进度条
                        wget -q --show-progress https://www.python.org/ftp/python/$version/Python-$version.tgz
                        if [ "$?" -eq "0" ]; then
                            dl_success=1
                        else
                            echo -e "\033[31m下载失败，请检查版本号是否存在或网络连接。\033[0m"
                        fi
                    else
                        echo "使用本地已存在的安装包。"
                        dl_success=1
                    fi

                    # 编译安装
                    if [ "$dl_success" -eq "1" ]; then
                        echo "正在解压与编译 (这可能需要几分钟，请耐心等待)..."
                        tar -zxf Python-$version.tgz
                        cd Python-$version
                        
                        # 编译配置
                        ./configure --prefix=$install_path > /dev/null
                        # 使用多核编译
                        make -j$(nproc) > /dev/null && make install > /dev/null
                        
                        cd ..
                        
                        # 创建软连接
                        # 注意：原脚本的逻辑是创建非常具体的版本号软连，这里保持一致
                        ln -sf $python_path $python_bin_path
                        ln -sf $pip_path $pip_bin_path

                        if [ -d "$install_path" ]; then
                            echo -e "\033[32mPython $version 安装成功！\033[0m"
                            echo "安装路径：$install_path"
                            
                            # 添加到 alternatives 管理
                            # 优先级设为 1，避免自动覆盖系统自带版本，除非用户手动切换
                            update-alternatives --install /usr/bin/python python $python_path 1
                            
                            # 尝试升级 pip
                            echo "正在升级 pip..."
                            $install_path/bin/pip3 install --upgrade pip &> /dev/null
                        else
                            echo -e "\033[31m编译安装似乎失败了，目录未生成。\033[0m"
                        fi
                    fi
                fi
            fi
            ;;
            
        2)
            # === 查看功能 ===
            echo "---------------------------------------"
            echo "【已安装的自定义版本】:"
            # 扫描目录
            installed_list=$(ls -d /usr/local/python-* 2>/dev/null)
            if [ -z "$installed_list" ]; then
                echo "  (暂无)"
            else
                for dir in $installed_list; do
                    ver_num=$(basename "$dir" | sed 's/python-//')
                    echo "  - Python $ver_num  ($dir)"
                done
            fi
            
            echo ""
            echo "【当前环境 python 命令指向】:"
            if command -v python &> /dev/null; then
                curr_ver=$(python --version 2>&1)
                curr_path=$(which python)
                # 检查是否是软连接
                if [ -L "$curr_path" ]; then
                    real_path=$(readlink -f "$curr_path")
                    echo "  $curr_ver (路径: $curr_path -> $real_path)"
                else
                    echo "  $curr_ver (路径: $curr_path)"
                fi
            else
                echo "  (未找到 python 命令)"
            fi
            echo "---------------------------------------"
            ;;
            
        3)
            # === 切换默认版本 ===
            echo "正在调用 alternatives 配置工具..."
            if update-alternatives --query python &>/dev/null; then
                update-alternatives --config python
            else
                echo "系统未配置 alternatives，或只有一个版本。"
                echo "请先安装新版本后再尝试切换。"
            fi
            ;;
            
        4)
            # === 卸载功能 (重点优化) ===
            # 1. 获取所有已安装版本到数组
            # ls -d 获取路径，awk提取版本号
            raw_versions=($(ls -d /usr/local/python-* 2>/dev/null | awk -F'python-' '{print $2}'))
            
            if [ ${#raw_versions[@]} -eq 0 ]; then
                echo "提示：当前没有检测到通过本脚本安装的 Python 版本，无法卸载。"
            else
                echo "检测到以下已安装版本："
                echo "------------------------"
                i=1
                # 循环显示菜单
                for ver in "${raw_versions[@]}"; do
                    echo "  $i) Python $ver"
                    let i++
                done
                echo "  0) 取消操作"
                echo "------------------------"
                
                read -p "请输入序号选择要卸载的版本: " selection
                
                # 验证输入是否为数字
                if [[ ! "$selection" =~ ^[0-9]+$ ]]; then
                     echo "输入错误，请输入数字。"
                elif [ "$selection" -eq "0" ]; then
                     echo "操作已取消。"
                elif [ "$selection" -gt "${#raw_versions[@]}" ]; then
                     echo "输入序号超出范围。"
                else
                    # 获取数组中的版本号 (数组下标从0开始，所以 selection-1)
                    target_ver=${raw_versions[$selection-1]}
                    target_dir="/usr/local/python-$target_ver"
                    
                    echo ""
                    echo -e "\033[31m警告：即将卸载 Python $target_ver \033[0m"
                    echo "这将删除: $target_dir 及相关软连接。"
                    read -p "确认要继续吗? [y/N]: " confirm
                    
                    if [[ "$confirm" =~ ^[yY]$ ]]; then
                        echo "正在卸载..."
                        # 删除目录
                        rm -rf "$target_dir"
                        
                        # 删除软连接 (尝试删除常见的几种命名方式)
                        rm -f "/usr/bin/python$target_ver"
                        rm -f "/usr/bin/pip$target_ver"
                        
                        # 从 alternatives 移除 (需要找到具体的 bin 路径)
                        # 这里的路径构造要和安装时保持一致，或者直接用通配符尝试移除
                        # 最稳妥的方式是尝试移除 alternatives 中注册的路径
                        # 我们构建一个大概率的路径：
                        possible_bin="$target_dir/bin/python${target_ver%.*}" # 取前两位版本号 例如 3.9
                        update-alternatives --remove python "$possible_bin" &>/dev/null
                        
                        echo "卸载完毕!"
                    else
                        echo "已取消卸载。"
                    fi
                fi
            fi
            ;;
            
        0)
            echo "再见！"
            exit 0
            ;;
            
        *)
            echo "无效输入，请重试。"
            ;;
    esac

    echo ""
    read -n 1 -s -r -p "按任意键返回主菜单..."
done

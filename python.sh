#!/bin/bash
#python支持库函数，我也是百度搜索的，看自己系统库看却什么加什么库
#by:LingFeng 
function Supportlibraries()
{
    [ `dpkg-query -l | grep build-essential |wc -l` -eq "0" ]&&{
         echo "缺少build-essential开始安装"
         apt install build-essential -y
    }
    [ `dpkg-query -l | grep libncurses5-dev|wc -l` -eq "0" ]&&{
         echo "缺少libncurses5-dev开始安装"
         apt install libncurses5-dev -y
    }
    [ `dpkg-query -l | grep libgdbm-dev |wc -l` -eq "0" ]&&{
         echo "缺少libgdbm-dev开始安装"
         apt install libgdbm-dev -y
    }
    [ `dpkg-query -l | grep libnss3-dev |wc -l` -eq "0" ]&&{
         echo "缺少libnss3-dev开始安装"
         apt install libnss3-dev -y
    }
    [ `dpkg-query -l | grep libssl-dev |wc -l` -eq "0" ]&&{
         echo "缺少libssl-dev开始安装"
         apt install libssl-dev -y
    }
    [ `dpkg-query -l | grep libreadline-dev |wc -l` -eq "0" ]&&{
         echo "缺少libreadline-dev开始安装"
         apt install libreadline-dev -y
    }
    [ `dpkg-query -l | grep libffi-dev |wc -l` -eq "0" ]&&{
         echo "缺少libffi-dev开始安装"
         apt install libffi-dev -y
    }
    [ `dpkg-query -l | grep zlib1g-dev |wc -l` -eq "0" ]&&{
         echo "缺少zlib1g-dev开始安装"
         apt install zlib1g-dev -y
    }

    [ `dpkg-query -l | grep make |wc -l` -eq "0" ]&&{
         echo "缺少make开始安装"
         apt install make -y
    }
}
#字符串效验
function is_exists_arg() {
    local version=$1
    if [ -z $version ];then
    echo "缺少版本号参数！"
    exit 1
fi
}
#判断是否安装
function is_exists_python() {
    local version=$1
    local v=(${version//./ })
    if [ -e $python_path ] && [ -e $pip_path ] && [ -e $python_bin_path ] && [ -e $pip_bin_path ];then
    return 0
    else
    return 1
    fi
}

cat << END
    欢迎使用python管理器。请选择你需要的使用的功能
    1.安装python(可选择版本:https://www.python.org/ftp/python)
    2.查看已经安装的python
    3.修改默认python
    4.卸载python
END

read parameter
echo "你选择了:$parameter"
if [ "$parameter" -eq "1" ];then
    echo "请输入版本号(例子: 3.9.9)"
    read version
    #检测有效性
    is_exists_arg $version
    v=(${version//./ })
    
    install_path="/usr/local/python-$version"
    python_path="$install_path/bin/python${v[0]}.${v[1]}"
    python_bin_path="/usr/bin/python${v[0]}.${v[1]}.${v[2]}"
    pip_path="$install_path/bin/pip${v[0]}.${v[1]}"
    pip_bin_path="/usr/bin/pip${v[0]}.${v[1]}.${v[2]}"
    
    #判断是否安装
    is_exists_python $version
    
    if [ $? == 0 ]
    then
        echo -e "\e[1;31mPython$version 已存在！\e[m"
        echo "安装位置：$python_path"
        echo "          $pip_path"
        echo "软连接：  $python_bin_path"
        echo "          $pip_bin_path"
        exit 1
    fi
    

    echo -e "Python版本号：\e[1;33m$version\e[m"
    Supportlibraries
     [ ! -e "./Python-$version.tgz" ]&&{
        echo "开始下载 Python-$version.tgz"
        #使用华为国内镜像
        #官方镜像地址 https://www.python.org/ftp/python/$version/Python-$version.tgz
        wget https://www.python.org/ftp/python/$version/Python-$version.tgz
        clear
        [ "$?" -eq "0" ] &&{
            echo "下载成功,准备安装"
            sleep 1
        }
    }
    #下面是正常的操作步骤命令，可以修改为自己符合的
    # 解压python
    tar -zxvf Python-$version.tgz
    # 进入目录
    cd Python-$version
    ./configure --prefix=$install_path
    make && make install

    # 配置软连接
    ln -s $python_path $python_bin_path
    ln -s $pip_path $pip_bin_path

    is_exists_python $version
    if [ $? == 0 ]
    then
    echo -e "\e[1;mPython $version 安装成功！\e[m"
    echo "安装位置：$python_path"
    echo "          $pip_path"
    echo "软连接：  $python_bin_path"
    echo "          $pip_bin_path"
    #添加到alternatives
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python$version 1
    exit 0
    else
    echo -e "\e[1;31mPython $version 安装失败！请确保有root权限正确\e[m"
    exit 0
    fi
fi

if [ "$parameter" -eq "2" ];then
    echo "当前安装的路径和python版本（如果报错则没有任何版本）"
    pythonDir=`ls /usr/local | grep '^python*'|awk '{printf "%s\n",$1}'`
    for dr in $pythonDir
    do
        echo $dr
    done
    echo "当前系统默认版本："
    python --version
fi
#配置默认版本
if [ "$parameter" -eq "3" ];then
    update-alternatives --config python
fi
#卸载模块
if [ "$parameter" -eq "4" ];then
    read -p "请输入要卸载的python版本号(例:3.9.9):" vr
    #检测有效性
    is_exists_arg $vr
    [ ! -e "/usr/local/python-$vr" ] &&{
        echo "没有此版本，请先核对哦！"
        exit 1
    }
    #删除文件
    rm -rf /usr/local/python-$vr &>>/dev/null
    #删除软连接
    rm -rf /usr/bin/python$vr &>>/dev/null
    rm -rf /usr/bin/pip$vr &>>/dev/null
    #删除alternatives
    update-alternatives --remove python /usr/local/python$vr &>>/dev/null
    echo "卸载完毕!"
fi

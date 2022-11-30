#!/bin/bash
####################################################参数修改开始########################################################################

#单机还是多机（0为单机，1为多机）
server=0
#最大内存
VM_MEM=512m
#java内存
JAVA_MEM=256m
#容器名字
docker_name=test
#项目名
APPNAME=test
#作者(如果是多机的话填入dockerhub或者oss地址)
admin=test
#日志参数 默认为syslog，删除这个参数可以变成json-file
log_driver=syslog
#java端口
port=8080
#服务版本
ENV=test
#syslog地址（默认本机）
syslog_server=tcp://127.0.0.1:514
#框架
frame=SSM
#脚本大师模式和新手模式（脚本设有等待时间看参数，大师模式1可以去掉等待时间）
shell_type=0
#检查版本（0是不检查；1是检测gitee；2是检测github）
inspect_script=1

####################################################参数修改结束########################################################################

#本地脚本版本号
shell_version=v1.0.1
#版本号
tag=$1
#脚本执行目录
DEPLOYDIR=$(pwd)
#赋值当前镜像
docker_image=${admin}/${APPNAME}:${tag}
#远程仓库作者
git_project_author_name=buyfakett
#远程仓库项目名
git_project_project_name=Launch_java_project
#远程仓库名
git_project_name=${git_project_author_name}/${git_project_project_name}

#颜色参数，让脚本更好看
Green="\033[32m"
Font="\033[0m"
Red="\033[31m" 

#打印帮助文档
function echo_help(){
    echo -e "${Green}
    ——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
    #此脚本用于docker上线java项目
    #在脚本后面加上版本号
    #如：bash $(pwd)/$0 v1.0
    #本脚本支持选择单机或者多机
    #脚本不是很成熟，有bug请及时在github反馈哦~
    #或者发作者邮箱：buyfakett@vip.qq.com
    ——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————
    ${Font}"
}

#等待5秒
function sleep_3s(){
    echo -e "${Red}3秒后继续执行脚本${Font}"
    for i in {3..1}
    do
      sleep 1
      echo -e ${Red}$i${Font}
    done
}

#root权限
function root_need(){
    if [[ $EUID -ne 0 ]]; then
        echo -e "${Red}你现在不是root权限，请使用sudo命令或者联系网站管理员${Font}"
        exit 1
    fi
}

#检查版本
function is_inspect_script(){
    yum install -y wget jq

    if [ $inspect_script == 1 ];then
        remote_version=$(wget -qO- -t1 -T2 "https://gitee.com/api/v5/repos/${git_project_name}/releases/latest" |  jq -r '.tag_name')
    elif [ $inspect_script == 2 ];then
        remote_version=$(wget -qO- -t1 -T2 "https://api.github.com/repos/${git_project_name}/releases/latest" |  jq -r '.tag_name')
    fi

    if [ ! ${remote_version}=${shell_version} ];then
        if [ $inspect_script == 1 ];then
            wget -qO- -t1 -T2 "https://gitee.com/${git_project_name}/releases/download/${remote_version}/$0"
        elif [ $inspect_script == 2 ];then
            wget -qO- -t1 -T2 "https://github.com/${git_project_name}/releases/download/${remote_version}/$0"
        fi
    else
        echo -e "${Green}您现在的版本是最新版${Font}"
    fi
}

#打印当前参数
function usage(){
    if [[ $server == 0 ]];then
        server_status=当前为多机状态，会帮您上传镜像并生成启动脚本
    else
        server_status=当前为单机状态，会帮您生成镜像并启动
    fi

    if [[ $shell_type == 0 ]];then
        shell_type_status=当前为新手模式，会有时间等待哦~
    else
        shell_type_status=当前为自动化模式，一键去掉等待时间~感谢您使用本脚本~
    fi

    echo -e "${Green}
    ${shell_type_status}
    ${server_status}
    docker内存为：${VM_MEM}
    java内存为：${JAVA_MEM}
    当前镜像为：${docker_image}
    java端口：${port}
    服务版本：${ENV}
    框架：${frame}
    日志参数：${log_driver}
    ${Font}"
    if [[ $shell_type == 0 ]];then
        sleep_3s
    fi
}

#执行前检查
function pre_deploy_app(){
    root_need
    #检查版本号
    if [ "$tag"x =  ""x ] ;then
        echo -e "${Red}您没有传版本号 如：$(pwd)/$0 v1.0${Font}"
        exit 1
    fi
    if [ "$frame"x =  "SSM"x ] ;then
        if [ ! -f "./docker/application.properties" ];then
            echo -e "${Red}您没有上传application.properties，请在$(pwd)/docker/目录下上传${Font}"
            exit 1
        fi
    fi
}

#构建容器
function build_docker(){
    cd $(pwd)/docker
    if [ ! -f "./Dockerfile" ];then
        echo -e "${Red}您没有创建Dockerfile，请在$(pwd)/docker下创建，即将为您创建默认模板${Font}"
        if [[ $shell_type == 0 ]];then
            sleep_3s
        fi
        cat << EOF > Dockerfile 
FROM java:8
USER root
WORKDIR /app
COPY ./ /app/
EOF
    fi
    echo -e "${Red}即将为您创建容器容器名为：${docker_image}${Font}"
    if [[ $shell_type == 0 ]];then
        sleep_3s
    fi
    docker build -t ${docker_image} -f Dockerfile .
    echo -e "${Green}创建容器完成${Font}"
    cd ..
}

#开始部署
function deploy_app(){
#docker 日志参数
    if [ "${log_driver}"x == "syslog"x ];then
        log_args="\
--log-driver=syslog \
--log-opt syslog-address=${syslog_server} \
--log-opt tag="log/${APPNAME}/{{.Name}}" \
"
    else
        log_args="\
--log-driver=json-file \
--log-opt max-size="100m" \
--log-opt max-file=10 \
"
    fi

#docker参数
    docker_opt="\\
-id -m ${VM_MEM} --restart=always \\
--name ${APPNAME} \\
--network=host \\
-w /app/ \\
${log_args} \\
-v /etc/timezone:/etc/timezone:ro \\
-v /etc/localtime:/etc/localtime:ro \\
-v \$(pwd)/data/:/app/data \\
-v \$(pwd)/workdir/${ENV}/:/app/ \\
-v /data/logs/${APPNAME}.log:/files/base64.log \\
-v /data/logs/${APPNAME}.json:/files/json.log \\
"

# java 命令
    java_cmd="\
java -Duser.timezone=GMT+8 -Dlog4j2.formatMsgNoLookups=true -Dfile.encoding=utf-8 -jar \\
-server -Xmx${JAVA_MEM} -Xms${JAVA_MEM} -Xss256K \\
${APPNAME}-${tag}.jar --spring.config.name=application --spring.profiles.active=${ENV} --server.port=${port}
"
}

#上传脚本
function update_images(){
    docker push ${docker_image}
#生成启动文件
    cat << EOF > setup.sh
#!/bin/bash
echo 'Asia/Shanghai' > /etc/timezone
container_name=$1

if [ "$container_name"x =  ""x ] ;then
        echo -e "${Red}您没有传旧docker版本号${Font}"
        exit 1
    fi

docker pull ${docker_image}
docker rm -f ${container_name}
dokcer run ${docker_opt} \${docker_image} ${java_cmd}
EOF
    chmod 755 setup.sh
}

#脚本执行结束打印
function post_deploy_app(){
    echo -e "${Green}脚本执行结束${Font}"
    cd ${DEPLOYDIR}/
    if [[ $server == 1 ]];then
        echo -e "${Green}您已上传镜像到${docker_image}！！${Font}"
    else
        echo -e "${Green}您已启动${docker_image}！！${Font}"
    fi
}

#主方法
function main(){
    if [ ! $inspect_script == 0 ];then
        echo -e "${Green}您已开始检查版本${Font}"
        is_inspect_script
    else
        echo -e "${Green}您已跳过检查版本${Font}"
    fi
    echo_help
    if [[ $shell_type == 0 ]];then
        sleep_3s
    fi
    usage
    # step1 部署前检查
    pre_deploy_app

    # step2 构建
    build_docker

    # step3 部署 or 上传镜像
    if [[ $server == 1 ]];then
        deploy_app
        update_images
    else
        deploy_app
        container_name=`docker ps |grep ${APPNAME} | awk '{print $1}'`
        docker rm -f ${container_name}
        #启动docker
        docker run ${docker_opt} \${docker_image} ${java_cmd}
    fi

    if [ $? != 0 ];then
        echo "部署失败"
        exit 1
    fi

    # step4 启动后的操作
    post_deploy_app
}

main
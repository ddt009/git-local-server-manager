#!/bin/bash
# 功能：快捷管理本地服务器的git服务，包括创建仓库，增加用户，实现用户ssh远程访问的安全性
# PS: 脚本需要root权限运行

# 默认git用户组名
GIT_GROUP_NAME=git-users
# git用户名统一前缀
GIT_USER_FIX=git-
# git用户限定访问目录,对用户是根目录
DEFAULT_CHROOT_BASE=/data/git-base
# git仓库根目录所在，必须是用户组路径以下（本例直接同级）
DEFAULT_REPO_ROOT=${DEFAULT_CHROOT_BASE}

AddGitGroup(){
    if getent group ${GIT_GROUP_NAME} > /dev/null; then
        echo "Group ${GIT_GROUP_NAME} exists."
    else
        echo "Group Add ${GIT_GROUP_NAME}."
        groupadd ${GIT_GROUP_NAME}
    fi
}

InitGitRepo(){
    
    AddGitGroup
    rsp_path=${1}
    # 路径前加上DEFAULT_REPO_ROOT生成绝对路径
    if [[ ${rsp_path} == "/"* ]]; then
        rsp_path="${DEFAULT_REPO_ROOT}${rsp_path}"
    else
        rsp_path="${DEFAULT_REPO_ROOT}/${rsp_path}"
    fi
    # 确保路径以.git结尾
    if [[ ${rsp_path} != *".git" ]]; then
        rsp_path="${rsp_path}.git"
    fi
:
    if [ ! -d "${rsp_path}/.git" ]; then
        echo "Init .git in ${rsp_path}"
        mkdir -p ${rsp_path}
        pushd ${rsp_path}
        git init --bare
        popd
        chown -R root:${GIT_GROUP_NAME} ${rsp_path}
        chmod -R g+w ${rsp_path}
    else
        echo "${rsp_path}/.git exists."
    fi
}

ChangGitUserSShKey(){
    username=${1}
    if [[ ${username} != ${GIT_USER_FIX}* ]]; then
        username=${GIT_USER_FIX}${1}
    fi

    if [  -d "/home/${username}" ]; then
        workdir=/home/${username}/.ssh
        
        mkdir -p ${workdir}

        if [  -f "${workdir}/authorized_keys" ]; then
            current_time=$(date +"%Y%m%d%H%M")
            mkdir -p ${workdir}/${current_time}
            mv ${workdir}/id_rsa* ${workdir}/${current_time}/
            mv ${workdir}/authorized_keys ${workdir}/${current_time}/
            echo "Move origin key file to ${current_time}"
        fi
        echo "Generating new id_rsa"
        ssh-keygen -t rsa -b 4096 -C "${username}@gt-users" -f ${workdir}/id_rsa
        mv ${workdir}/id_rsa.pub ${workdir}/authorized_keys
        chown -R ${username}:${username} ${workdir}
        chmod 600 ${workdir}/authorized_keys
        chmod 600 ${workdir}/id_rsa
        chmod 700 ${workdir}
        cat ${workdir}/id_rsa
    fi
}

# 确保用户限定访问目录及其以上目录为root:root 755
function fix_chroot_permissions() {
    current_dir=${DEFAULT_CHROOT_BASE}
    while [[ $current_dir != / ]]; do
        if [[ $(stat -c '%U:%G' $current_dir) != 'root:root' ]]; then
            echo "chown root:root $current_dir"
            chown root:root $current_dir
        fi
        if [[ $(stat -c '%a' $current_dir) != '755' ]]; then
            echo "chmod 755 $current_dir"
            chmod 755 $current_dir
        fi
        current_dir=$(dirname $current_dir)
    done
    echo "All directories up to ${DEFAULT_CHROOT_BASE} are owned by root:root and have permissions 755"
}

# 用户限定目录前的准备工作
SetChrootEnv(){
    if [ ! -f "${DEFAULT_CHROOT_BASE}/usr/bin/git-shell" ];then
        mkdir -p ${DEFAULT_CHROOT_BASE}/{usr/bin,bin,lib,lib64}

        fix_chroot_permissions

        # 复制git,git-shell和git-shell的依赖 
        cp /usr/bin/git ${DEFAULT_CHROOT_BASE}/usr/bin/
        cp /usr/bin/git-shell ${DEFAULT_CHROOT_BASE}/usr/bin/
        ldd /usr/bin/git-shell | grep -o '/[^ ]*' | xargs -I '{}' cp '{}' ${DEFAULT_CHROOT_BASE}/lib/
        ldd /usr/bin/git-shell | grep -o '/lib64/[^ ]*' | xargs -I '{}' cp '{}' ${DEFAULT_CHROOT_BASE}/lib64/
        # 挂载系统目录
        mkdir -p ${DEFAULT_CHROOT_BASE}/{dev,proc,sys}
        mount --bind /dev ${DEFAULT_CHROOT_BASE}/dev
        #mount --bind /proc ${DEFAULT_CHROOT_BASE}/proc
        #mount --bind /sys ${DEFAULT_CHROOT_BASE}/sys
        # 挂载登记进fstab内(重启有效)
        CHECK_FATAB_DATA=$(cat /etc/fstab|grep "${DEFAULT_CHROOT_BASE}/dev")
        if [[ -z $CHECK_FATAB_DATA ]]; then
            echo "echo \"/dev  ${DEFAULT_CHROOT_BASE}/dev none   bind    0   0\" >> /etc/fstab"
            echo "/dev  ${DEFAULT_CHROOT_BASE}/dev none   bind    0   0" >> /etc/fstab
        fi
    fi            
}

# 限定git-users用户组目录
ChangeSshConfig(){

    SetChrootEnv

    sshd_config=/etc/ssh/sshd_config
    if grep -q "^Match Group ${GIT_GROUP_NAME}" "${sshd_config}"; then
        echo "Group ${GIT_GROUP_NAME} already been matched in ssh_config"
    else
        echo "Add group match in ssh_config"
        (cat <<HERE
Match Group ${GIT_GROUP_NAME}
    ChrootDirectory ${DEFAULT_CHROOT_BASE}
HERE
)>>${sshd_config}
    fi
    systemctl restart sshd
}

AddGitUser(){
    username=${1}
    if [[ ${username} != ${GIT_USER_FIX}* ]]; then
        username=${GIT_USER_FIX}${1}
    fi

    if ! id "$username" &>/dev/null; then
        
        AddGitGroup

        echo "Add user ${username}"
        useradd --shell /usr/bin/git-shell --groups ${GIT_GROUP_NAME} ${username}

        mkdir -p /home/${username}/.ssh

        chown -R ${username}:${username} /home/${username}

        ChangGitUserSShKey ${username}

        ChangeSshConfig 

    else
        echo "${username} exists."
    fi
}

if [ "$#" -lt 1 ]; then

    echo "Usage: $0 <git-user>              create git user"
    echo "Usage: $0 <git-user> [git-repo]   create git user and repository"
    echo "Usage: $0 -p   <git-repo>         create git repository"
    echo "Usage: $0 -key <git-user>         change git-user's ssh-key file"
    exit 1
fi

if [ "$1" = "-p" ] ; then 
    if [ "$2" == "" ] ;then
        echo "git-repo required"
    else
        InitGitRepo $2
    fi
    exit 1
fi

if [ "$1" = "-key" ] ; then 
    if [ "$2" == "" ] ;then
        echo "git-user required"
    else

        ChangGitUserSShKey $2
    
    fi
    exit 1
fi

if  [ "$#" -eq 1 ] || [ "$#" -eq 2 ]; then
    if [[ ${1} == "-"* ]]; then
        echo "illegal paramete $1"
        exit 1
    fi
    
    AddGitUser $1

    if [ "$2" != "" ] ;then
        if [[ ${2} == "-"* ]]; then
            echo "illegal paramete 2"
            exit 1
        fi

        InitGitRepo $2

    fi
fi
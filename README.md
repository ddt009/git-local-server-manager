# git-local-server-manager
git本地仓库服务器简易管理脚本

## 场景：

小公司上私有git仓库，有时候不需要gitlab之类的重应用，简单在linux部署一个git本地仓库，实现多用户协作就可以了。
本脚本实现了功能的方便管理，同时兼顾了安全性。

## 功能：
```
创建仓库、增加用户，实现用户ssh远程访问的安全性
1.git用户名统一前缀(默认"git-",可配置) 
2.仓库统一后缀.git
3.git用户限定在git用户组的目录
```

## 使用前视需要修改以下内容：
```
#默认git用户组名
GIT_GROUP_NAME=git-users

#git用户名统一前缀
GIT_USER_FIX=git-

#git用户限定访问目录,对用户是根目录(重要)
DEFAULT_CHROOT_BASE=/data/git-base

#git仓库根目录所在，必须是用户组路径以下（本例直接同级）
DEFAULT_REPO_ROOT=${DEFAULT_CHROOT_BASE}
```
### 用法（需要root权限）：
```
bash ./m-git.sh <git-user>          生成新用户git-user(“git-”可以省)

bash ./m-git.sh <git-user> [abc/git-repo]   生成用户同时生成"abc/git-repo.git"仓库

bash ./m-git.sh -p <git-repo>           生成"git-repo.git"仓库

bash ./m-git.sh -key <git-user>         重新生成git-user用户的id_rsa
```
### 补充
1./home/`<git-user>`/.ssh/id_rsa 是git用户证书，生成过程有展示，可直接复制使用
2.删除用户直接使用系统命令userdel
3.git地址为 git-user@git-server:/git-repo  (用户@服务器:仓库路径)

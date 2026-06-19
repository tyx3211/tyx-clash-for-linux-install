# 当前版本使用指南

本文补充 README 中没有展开的安装、启动模式、订阅、代理和迁移说明。

## 快速选择

如果是在共享机、没有 sudo、希望容易查看进程：

```bash
bash install.sh
```

这会使用默认 `tmux` 模式。

如果没有 tmux，且只需要一个简单后台进程：

```bash
bash install.sh --init nohup
```

如果机器允许 sudo，并且需要 Tun：

```bash
sudo bash install.sh --init systemd
```

## 安装前配置

可以先编辑 `.env`：

```bash
CLASH_BASE_DIR="$HOME/clashctl"
INIT_TYPE=tmux
CLASH_CONFIG_URL=""
```

常用配置：

- `CLASH_BASE_DIR`：安装目录。必须是绝对路径，默认 `~/clashctl`。
- `INIT_TYPE`：启动方式，可选 `tmux`、`nohup`、`systemd`。
- `CLASH_CONFIG_URL`：订阅链接。可以留空，安装末尾会交互输入。
- `URL_GH_PROXY`：GitHub 下载代理前缀。
- `SUBCONVERTER_REPO`：subconverter 下载来源。
- `CLASHCTL_DOWNLOAD_TIMEOUT`：依赖下载超时。
- `CLASHCTL_SUB_TIMEOUT`：订阅下载超时。

订阅链接请始终使用双引号包起来：

```bash
CLASH_CONFIG_URL="https://example.com/sub?clash=3&extend=1"
```

## 启动模式说明

### tmux

默认模式：

```bash
bash install.sh --init tmux
```

适合共享机普通用户。内核进程运行在 tmux 会话中，默认会话名类似 `clash-mihomo`。

常用检查方式：

```bash
tmux ls
clashstatus
clashlog
```

### nohup

备用用户态模式：

```bash
bash install.sh --init nohup
```

它不依赖 tmux，但只通过 pid / pgrep 管理进程。若机器上有 tmux，优先使用 tmux。

### systemd

sudo 模式：

```bash
sudo bash install.sh --init systemd
```

适合需要 Tun 的机器。通过 sudo 安装时，服务文件由 root 写入系统目录，实际服务进程以 sudo 调用用户身份运行。

卸载也需要 sudo：

```bash
sudo bash ~/clashctl/uninstall.sh
```

## 常用命令

启动和关闭：

```bash
clashon
clashoff
clashstatus
```

代理环境变量：

```bash
clashproxy on
clashproxy off
clashproxy status
clashproxy on -g
clashproxy mode silent
```

Web 面板：

```bash
clashui
clashsecret
clashsecret "new-secret"
```

订阅：

```bash
clashsub add "https://example.com/sub?clash=3&extend=1"
clashsub ls
clashsub use 1
clashsub update 1
clashsub update --convert 1
clashsub log
```

Mixin：

```bash
clashmixin
clashmixin -e
clashmixin -m
clashmixin -r
```

Tun：

```bash
clashtun
clashtun on
clashtun off
```

Tun 只在 `systemd` 安装模式下可用。

## 自动化安装

跳过 shell rc 写入：

```bash
CLASHCTL_NO_RC=1 bash install.sh
```

跳过安装末尾的订阅导入交互：

```bash
CLASHCTL_NO_QUIT=1 bash install.sh
```

同时指定启动方式：

```bash
CLASHCTL_NO_RC=1 CLASHCTL_NO_QUIT=1 bash install.sh --init tmux
```

如果没有写入 shell rc，需要手动加载：

```bash
. ~/clashctl/scripts/cmd/clashctl.sh
```

## 从 nosudo-tmux 迁移

旧 `nosudo-tmux` 分支用户建议重新 clone 当前 `main`：

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git clash-for-linux-install
cd clash-for-linux-install
bash install.sh --init tmux
```

如果旧安装目录还在，先执行旧安装目录里的卸载脚本：

```bash
bash ~/clashctl/uninstall.sh
```

迁移时需要注意：

- 默认仍然是 tmux 用户态，不需要 sudo。
- `resources/clashctl.yaml` 是新增的 sidecar 配置。
- `resources/mixin.yaml` 只放会参与内核运行时合并的配置。
- Tun 不再是 no-sudo 路线的一部分，需要 `sudo bash install.sh --init systemd`。
- 安装路径限制比旧版本更明确，不建议使用带空格或特殊字符的目录。

## 远程访问 Web 面板

默认控制口绑定 `127.0.0.1:23571`，共享机上推荐用 SSH 端口转发：

```bash
ssh -L 23571:127.0.0.1:23571 user@remote-host
```

然后访问：

```text
http://localhost:23571/ui
```

如果使用 VS Code Remote-SSH，也可以直接在 VS Code 里转发远端 `23571` 端口。

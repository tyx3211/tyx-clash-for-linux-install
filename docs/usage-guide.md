# 当前版本使用指南

本文补充 README 中没有展开的安装、运行托管模式、订阅、代理、项目更新和迁移说明。

真实机器上的运行托管切换会启动或停止内核进程，不适合在自动测试里默认执行。需要实机验证时，可以按 [手工端到端检查清单](manual-e2e-checklist.md) 执行。

## 快速选择

如果是在共享机、没有 sudo、希望容易查看进程：

```bash
bash install.sh
```

这会把默认运行托管模式设为 `tmux`。

如果没有 tmux，且只需要一个简单后台进程，可以安装后运行：

```bash
clashon --mode nohup
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
- `INIT_TYPE`：默认运行托管模式，可选 `tmux`、`nohup`、`systemd`。
- `CLASH_CONFIG_URL`：订阅链接。可以留空，安装末尾会交互输入。
- `URL_GH_PROXY`：GitHub 下载代理前缀。
- `SUBCONVERTER_REPO`：subconverter 下载来源。
- `CLASHCTL_DOWNLOAD_TIMEOUT`：依赖下载超时。
- `CLASHCTL_SUB_TIMEOUT`：订阅下载超时。

订阅链接请始终使用双引号包起来：

```bash
CLASH_CONFIG_URL="https://example.com/sub?clash=3&extend=1"
```

## 运行托管模式说明

### tmux

默认托管模式：

```bash
bash install.sh --init tmux
```

适合共享机普通用户。内核进程运行在带安装路径标识的 tmux 会话中，避免不同安装目录互相冲突。

常用检查方式：

```bash
tmux ls
clashstatus
clashlog
```

### nohup

备用用户态模式可在运行时选择：

```bash
clashon --mode nohup
```

它不依赖 tmux，但只通过 pid / pgrep 管理进程。若机器上有 tmux，优先使用 tmux。

### systemd

sudo 模式：

```bash
sudo bash install.sh --init systemd
```

适合需要 Tun 的机器。通过 sudo 安装时，服务文件由 root 写入系统目录，实际服务进程以 sudo 调用用户身份运行。

注册完成后，运行时切到 systemd：

```bash
clashrestart --mode systemd
clashtun on
```

卸载也需要 sudo：

```bash
sudo bash ~/clashctl/uninstall.sh
```

## 常用命令

启动和关闭：

```bash
clashon
clashon --mode tmux
clashrestart --mode nohup
clashoff
clashstatus
clashstatus --all
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
clashsub update 1 --convert
clashsub delete 1
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

Tun 需要 systemd 服务已注册，并且当前内核以 `systemd` 模式运行。

## 更新项目脚本

更新类型需要分开理解：

- `clashsub update`：更新订阅。
- `clashupgrade`：升级 mihomo/clash 内核。
- `bash update.sh --target <安装目录>` 或 `clashctl update-self --source <源码目录>`：更新本项目 shell 脚本和文档资产。
- `clashctl update-self`：直接从 GitHub 下载当前 fork 的 `main` 分支并无损更新当前安装目录。

日常使用时，直接执行：

```bash
clashctl update-self
```

指定分支或 tag：

```bash
clashctl update-self --ref main
```

指定 GitHub 仓库和分支：

```bash
clashctl update-self --repo tyx3211/tyx-clash-for-linux-install --ref main
```

从源码仓库 pull 新版本后，在源码仓库执行：

```bash
bash update.sh --target "$HOME/clashctl"
```

在已安装环境中也可以显式指定刚 pull 过的源码仓库：

```bash
clashctl update-self --source "$HOME/src/clash-shell/tyx-clash-for-linux-install"
```

项目脚本更新会保留 `.env`、`resources/mixin.yaml`、`resources/clashctl.yaml`、`resources/config.yaml`、`resources/runtime.yaml`、`resources/profiles.yaml`、`resources/profiles/`、日志和 pid 状态。

## 自动化安装

跳过 shell rc 写入：

```bash
CLASHCTL_NO_RC=1 bash install.sh
```

跳过安装末尾的订阅导入交互：

```bash
CLASHCTL_NO_QUIT=1 bash install.sh
```

同时指定默认托管模式：

```bash
CLASHCTL_NO_RC=1 CLASHCTL_NO_QUIT=1 bash install.sh --init tmux
```

如果没有写入 shell rc，需要手动加载：

```bash
. "$CLASH_BASE_DIR/scripts/cmd/clashctl.sh"
```

## 从 nosudo-tmux 迁移

旧 `nosudo-tmux` 分支已经退役。旧分支用户建议重新 clone 当前 `main` 后执行无损更新或迁移，不要先卸载旧安装目录。已有 `~/clashctl` 时，主路径是从新源码目录原地刷新旧安装：

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git clash-for-linux-install
cd clash-for-linux-install
bash update.sh --target ~/clashctl
```

如果想做全新安装，请先选择一个不存在的新目录，或明确完成旧目录备份/卸载后再执行：

```bash
CLASH_BASE_DIR="$HOME/experiment/clashctl-new" bash install.sh --init tmux
```

迁移时需要注意：

- 默认仍然是 tmux 用户态，不需要 sudo。
- `resources/clashctl.yaml` 是新增的 sidecar 配置。
- `resources/mixin.yaml` 只放会参与内核运行时合并的配置。
- Tun 不再是 no-sudo 路线的一部分，需要注册 systemd 服务并执行 `clashrestart --mode systemd`。
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

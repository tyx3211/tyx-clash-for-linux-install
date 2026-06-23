# 当前版本使用指南

本文补充 README 中没有展开的安装、运行托管模式、订阅、代理、项目更新和迁移说明。

真实机器上的运行托管切换会启动或停止内核进程，不适合在自动测试里默认执行。需要实机验证时，可以按 [手工端到端检查清单](manual-e2e-checklist.md) 执行。

## 快速选择

如果是在共享机、没有 sudo、希望容易查看进程：

```bash
bash install.sh
```

这会把默认运行托管模式设为 `tmux`。

如果没有 tmux，且只需要一个简单后台进程，安装时就选择 nohup：

```bash
bash install.sh --init nohup
```

如果机器允许 sudo，并且需要 Tun：

```bash
sudo bash install.sh --init systemd
```

## 安装前配置

安装前可以先编辑源码目录里的 `.env`。它只表示这次安装的默认值，不是安装后的主配置中心：

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
- `SUBCONVERTER_REPO`：subconverter 下载来源，默认 `tindy2013/subconverter`。
- `CLASHCTL_DOWNLOAD_TIMEOUT`：依赖下载超时。
- `CLASHCTL_SUB_TIMEOUT`：订阅下载超时。

安装完成后，本机安装状态会写入 `resources/install-state.yaml`。新版 `clashctl`、`update.sh` 和 `uninstall.sh` 都优先读取这个状态文件；`.env` 仍会保留，用于旧版本兼容和安装前默认值。适合长期维护和版本管理的配置在 `config/mixin.yaml`、`config/clashctl.yaml` 和 `config/subscriptions.yaml`。

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
默认安装目录仍是 sudo 调用用户的 `~/clashctl`，脚本会把 root 环境下展开出来的 `/root/clashctl` 归一化回普通用户目录。

运行时启动、停止和重启 systemd 服务会走 `sudo -n systemctl`。这意味着执行命令的用户需要是 root，或者已经拥有免密 sudo 权限；脚本不会停下来等待输入 sudo 密码。

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

`clashon` / `clashrestart` 只启动或切换内核托管模式，不会自动写入当前终端代理变量。需要当前终端走代理时，执行 `clashproxy on`。`clashproxy status` 中只有 `no_proxy` / `NO_PROXY` 时，不视为代理开启。`clashoff` 只关闭内核，不改当前终端代理变量；需要关闭当前终端代理时，执行 `clashproxy off`。如果曾经执行过 `clashproxy on -g`，关闭内核后建议再执行 `clashproxy off -g`，避免新终端自动写入已经不可用的代理地址。

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

该命令默认从 GitHub 获取当前 fork 的 `main`，不会使用本机源码目录里的未提交改动。正在本地调试修复时，必须使用下面的 `--source` 路线，或者直接在源码仓库中执行 `bash update.sh --target "$HOME/clashctl"`。

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

项目脚本更新会保留 `config/`、`resources/install-state.yaml`、`resources/config.yaml`、`resources/runtime.yaml`、`resources/profiles/`、日志和 pid 状态。旧安装目录如果已有 `.env`，会继续保留；旧安装目录如果还在使用 `resources/mixin.yaml`、`resources/clashctl.yaml`、`resources/profiles.yaml`，这些文件也会原样保留。

## 配置目录与 git

`git clone` 得到的是源码目录，用来执行初装或本地 `--source` 更新。默认安装目录 `~/clashctl` 是运行时目录，不是项目 git 仓库；初装不会复制源码目录里的 `.git`，`clashctl update-self` 也不依赖安装目录中的 git 状态。

适合人工维护的源配置集中在：

```text
~/clashctl/config/
  mixin.yaml
  clashctl.yaml
  subscriptions.yaml
```

安装时可以直接初始化这个配置仓库：

```bash
bash install.sh --config-git
# 或
CLASHCTL_CONFIG_GIT=1 bash install.sh
```

如果已经通过环境变量打开，但本次想关闭：

```bash
CLASHCTL_CONFIG_GIT=1 bash install.sh --no-config-git
```

该选项只会在 `~/clashctl/config` 下执行 `git init`，不会自动提交，也不会把 `~/clashctl` 根目录变成 git 仓库。更多说明见 [配置版本管理](config-versioning.md)。

旧版本安装目录如果已经在根目录带有 `.git`，它通常是历史全量复制遗留。为了避免误删用户手工创建的仓库，`update-self` 不会自动删除已有 `.git`。确认没有自定义用途后，可以手工删除：

```bash
rm -rf "$HOME/clashctl/.git"
```

不建议在安装目录根启用 git 管理配置。该目录包含脚本、二进制、订阅展开结果、运行时配置、日志和 pid 状态。真正适合版本管理的是 `config/` 下的源配置；`resources/` 下的 `config.yaml`、`runtime.yaml`、`profiles/`、日志和 pid 都是运行时文件。

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

旧 `nosudo-tmux` 分支已经退役。旧 `nosudo-tmux`、旧 `master`、[`legacy-nosudo-tmux`](https://github.com/tyx3211/tyx-clash-for-linux-install/tree/legacy-nosudo-tmux) 这个 tag 及以前版本，或者还没有执行过 `migrate.sh` 的早期中间版安装，都建议先按 [旧版迁移指南](legacy-migration.md) 原地迁移，不要先卸载旧安装目录。

迁移后的心智变化：

- 默认仍然是 tmux 用户态，不需要 sudo。
- `config/clashctl.yaml` 是新增的 sidecar 配置。
- `config/mixin.yaml` 只放会参与内核运行时合并的配置。
- Tun 不再是 no-sudo 路线的一部分，需要注册 systemd 服务并执行 `clashrestart --mode systemd`。
- 安装路径限制比旧版本更明确，不建议使用带空格或特殊字符的目录。

## 远程访问 Web 面板

新安装默认控制口绑定 `127.0.0.1:9090`，共享机上推荐用 SSH 端口转发：

```bash
ssh -L 9090:127.0.0.1:9090 user@remote-host
```

然后访问：

```text
http://localhost:9090/ui
```

如果使用 VS Code Remote-SSH，也可以直接在 VS Code 里转发远端 `9090` 端口。

旧安装执行 `clashctl update-self` 后不会自动改已有 `mixin.yaml`，因此旧安装可能仍在使用 `127.0.0.1:23571` 或其他自定义端口。实际地址以 `clashui` 输出或当前 `mixin.yaml` 为准。如需迁移到 9090，手工修改 `external-controller` 后执行 `clashmixin -m` 或 `clashctl mixin -m`。

启动前会检查 `external-controller` 控制端口。如果该端口被其他进程占用，脚本只报错并提示一个空闲端口；不会自动写入 `mixin.yaml`，也不会自动合并配置。我们需要手工改 `~/clashctl/config/mixin.yaml`，旧兼容安装则可能是 `~/clashctl/resources/mixin.yaml`，然后执行 `clashmixin -m` 或 `clashctl mixin -m`。

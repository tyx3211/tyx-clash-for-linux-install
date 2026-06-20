# 快速上手教程

本文按第一次使用者的顺序说明：安装、启动、开代理、看面板、更新、关闭和卸载。

## 适用场景

默认路线适合共享机或普通 Linux 用户环境：

- 没有 sudo 也能使用。
- 默认用 `tmux` 托管 mihomo / clash 内核。
- 不依赖 `systemd --user`。
- 需要 Tun 时，再单独走 sudo + systemd 路线。

## 第一次安装

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git
cd tyx-clash-for-linux-install
bash install.sh
```

安装脚本会下载依赖、创建默认安装目录 `~/clashctl`，并提示输入订阅链接。

如果希望从第一天开始就把个人配置放进独立 git 仓库，可以安装时加上：

```bash
bash install.sh --config-git
```

这只会在 `~/clashctl/config` 下执行 `git init`，不会把整个安装目录变成 git 仓库。后续可以按自己的习惯在该目录里 `git add` / `git commit`。详细说明见 [配置版本管理](config-versioning.md)。

如果订阅链接需要写在命令或 `.env` 中，请使用双引号：

```bash
CLASH_CONFIG_URL="https://example.com/sub?clash=3&extend=1"
```

这里的 `.env` 只用于安装前默认值和旧版本兼容。安装完成后，本机安装状态以 `~/clashctl/resources/install-state.yaml` 为主；长期维护和可选 git 管理的代理偏好在 `~/clashctl/config`。

安装结束后，脚本会尝试让当前终端立即拥有 `clashctl`、`clashon`、`clashoff` 等命令。如果当前终端没有这些命令，执行：

```bash
. "$HOME/clashctl/scripts/cmd/clashctl.sh"
```

## 启动代理

```bash
clashon
clashstatus
```

默认会使用 `tmux` 托管内核。可以查看 tmux 会话：

```bash
tmux ls
```

如果当前机器没有 `tmux`，可以改用 `nohup`：

```bash
clashrestart --mode nohup
```

## 让当前终端走代理

```bash
clashproxy on
clashproxy status
```

`clashproxy on` 只影响当前终端，不会修改系统代理。关闭当前终端代理：

```bash
clashproxy off
```

如果希望新开的交互式 shell 也自动写入代理变量：

```bash
clashproxy on -g
clashproxy mode silent
```

## Web 面板

```bash
clashui
```

新安装默认控制口绑定 `127.0.0.1:9090`。如果在远程共享机上使用，推荐在本机开 SSH 转发：

```bash
ssh -L 9090:127.0.0.1:9090 user@remote-host
```

然后访问：

```text
http://localhost:9090/ui
```

旧安装执行 `clashctl update-self` 后不会自动改已有控制口，实际地址以 `clashui` 输出或当前 `mixin.yaml` 为准。如需迁移到 9090，可以手工编辑 `config/mixin.yaml` 或旧兼容路径 `resources/mixin.yaml` 里的 `external-controller`。

## 订阅管理

添加并立即使用订阅：

```bash
clashsub add --use "https://example.com/sub?clash=3&extend=1"
```

查看订阅：

```bash
clashsub ls
```

更新当前订阅：

```bash
clashsub update
```

更新指定订阅并启用本地转换：

```bash
clashsub update 1 --convert
```

## 直接更新项目脚本

项目更新、订阅更新、内核升级是三件事：

- `clashctl update-self`：更新本项目脚本和文档。
- `clashsub update`：更新订阅。
- `clashupgrade`：升级 mihomo / clash 内核。

旧 `nosudo-tmux` 分支、旧 `master` 或早期中间版安装用户，第一次升级到当前 `main` 前建议先从新源码目录执行迁移：

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git
cd tyx-clash-for-linux-install
bash migrate.sh --target "$HOME/clashctl"
source "$HOME/clashctl/scripts/cmd/clashctl.sh"
clashstatus --all
```

迁移默认不停止内核、不启动内核、不修改当前 shell 的代理变量。确认状态后，再按需执行 `clashrestart --mode tmux`。

已迁移到新版后，日常更新本项目直接执行：

```bash
clashctl update-self
```

该命令默认从当前 fork 的 GitHub `main` 分支下载最新源码，并无损刷新当前安装目录。它不会停止内核、不会启动内核、不会覆盖 `config/`、`resources/install-state.yaml`、订阅、运行时配置、日志和 pid 状态。

默认安装目录不是 git 仓库，也不需要 `.git`。如果旧安装目录里已经有 `.git`，通常是历史安装复制遗留；确认没有自定义用途后，可以手工删除。配置版本管理推荐放在 `~/clashctl/config`。

指定分支或 tag：

```bash
clashctl update-self --ref main
```

使用本地源码目录刷新安装目录：

```bash
clashctl update-self --source "$HOME/src/clash-shell/tyx-clash-for-linux-install"
```

如果不迁移而选择重装，请先备份 `config/`、旧 `resources/mixin.yaml`、`resources/clashctl.yaml`、`resources/profiles.yaml`、`resources/profiles/`、`resources/config.yaml`、`resources/runtime.yaml` 和 `.env`。重装后，旧 `mixin.yaml` 放到 `config/mixin.yaml`，旧 `clashctl.yaml` 放到 `config/clashctl.yaml`，旧 `profiles.yaml` 放到 `config/subscriptions.yaml`，订阅 profile 文件继续放回 `resources/profiles/`。

## 关闭和卸载

关闭内核：

```bash
clashoff
```

卸载普通用户安装：

```bash
bash "$HOME/clashctl/uninstall.sh"
```

如果使用 `sudo bash install.sh --init systemd` 安装，则卸载也需要 sudo：

```bash
sudo bash "$HOME/clashctl/uninstall.sh"
```

## Tun 路线

默认 `tmux` / `nohup` 模式不支持 Tun。需要 Tun 时，在允许 sudo 的机器上安装 systemd 服务：

运行时管理 systemd 服务需要 root 或免密 sudo。可以先用 `sudo -n systemctl status mihomo` 判断当前用户是否具备非交互 sudo 能力；如果该命令要求输入密码，`clashrestart --mode systemd` 和 `clashtun on` 也会失败。

```bash
sudo bash install.sh --init systemd
clashrestart --mode systemd
clashtun on
```

共享机上如果没有明确授权，不建议启用这条路线。

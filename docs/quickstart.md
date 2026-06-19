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

如果订阅链接需要写在命令或 `.env` 中，请使用双引号：

```bash
CLASH_CONFIG_URL="https://example.com/sub?clash=3&extend=1"
```

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

默认控制口绑定 `127.0.0.1:23571`。如果在远程共享机上使用，推荐在本机开 SSH 转发：

```bash
ssh -L 23571:127.0.0.1:23571 user@remote-host
```

然后访问：

```text
http://localhost:23571/ui
```

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

日常更新本项目直接执行：

```bash
clashctl update-self
```

该命令默认从当前 fork 的 GitHub `main` 分支下载最新源码，并无损刷新 `~/clashctl`。它不会停止内核、不会启动内核、不会覆盖订阅、`mixin.yaml`、`clashctl.yaml`、profiles、日志和 pid 状态。

指定分支或 tag：

```bash
clashctl update-self --ref main
```

使用本地源码目录刷新安装目录：

```bash
clashctl update-self --source "$HOME/src/clash-shell/tyx-clash-for-linux-install"
```

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

```bash
sudo bash install.sh --init systemd
clashrestart --mode systemd
clashtun on
```

共享机上如果没有明确授权，不建议启用这条路线。

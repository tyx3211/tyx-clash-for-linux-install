# Linux 一键安装 Clash

![GitHub License](https://img.shields.io/github/license/nelvko/clash-for-linux-install)
![GitHub top language](https://img.shields.io/github/languages/top/nelvko/clash-for-linux-install)
![GitHub Repo stars](https://img.shields.io/github/stars/nelvko/clash-for-linux-install)

![preview](resources/preview.png)

## ✨ 功能特性

- 支持一键安装 `mihomo` 与 `clash` 代理内核。
- 面向 no-sudo 环境，默认使用 `tmux` 管理内核进程，不依赖 `systemd`。
- 支持运行时选择托管模式：`clashon --mode tmux|nohup|systemd`。其中 `systemd` 需要 root 或 sudo，并支持 Tun。
- 当前维护入口是 `main`。历史 `nosudo-tmux` 分支保留为早期用户态 fork 快照，不再代表当前完整功能面。
- 默认代理端口为 `port: 7890`、`socks-port: 7891`，默认控制端口为 `127.0.0.1:23571`。
- 代理内核配置与 `clashctl` 自身行为配置分离：
  `resources/mixin.yaml` 只放会参与 mihomo/clash 合并的配置；
  `resources/clashctl.yaml` 只放 `clashctl` 的 sidecar 配置，不再把私有键混进运行时配置。
- 自动检测端口占用情况，在冲突时随机分配可用端口。
- 在需要时调用 [subconverter](https://github.com/tindy2013/subconverter) 进行本地订阅转换。
- 默认 no-sudo / tmux 模式不提供 Tun；显式选择 `systemd` 模式时支持 Tun。

## 🧭 当前 fork（分叉）定位

这个 fork 已经不是单一的 `nosudo-tmux` 分支版本，而是把共享机用户态链路和上游较新的安装/订阅/Tun 机制合并后的维护版本。

- 默认路线：普通用户执行 `bash install.sh`，默认运行托管模式为 `tmux`。
- 备用用户态路线：执行 `clashon --mode nohup`，用 nohup 托管本次内核进程。
- sudo 路线：root 或 sudo 执行 `bash install.sh --init systemd` 注册 systemd 服务，用于需要 Tun 的机器。
- 不支持路线：不使用 `systemd --user`；共享机上这一能力经常被禁用，当前 fork 不把它作为依赖。

更多说明：

- [Fork 差异与分支策略](docs/fork-differences.md)
- [当前版本使用指南](docs/usage-guide.md)
- [手工端到端检查清单](docs/manual-e2e-checklist.md)
- [上游同步计划记录](docs/superpowers/plans/2026-06-18-shell-upstream-sync.md)

## ✅ no-sudo 使用补充

- 当前 fork 以 `INIT_TYPE=tmux` 为默认运行托管模式，请先确保系统已安装 `tmux`。
- 如需纯用户态但不想依赖 `tmux`，可以在运行时使用 `clashon --mode nohup`。
- 如需 Tun，请先使用 `sudo bash install.sh --init systemd` 注册 systemd 服务，再执行 `clashrestart --mode systemd` 和 `clashtun on`。
- `external-controller` 默认绑定 `127.0.0.1:23571`，远程访问面板请优先使用 SSH 端口转发。
- `clashproxy on` / `clashproxy off` 只影响当前 shell 的环境变量，不会改系统级代理。
- `clashproxy status` 只看当前终端实际环境变量，避免与配置状态偏离。
- 新终端是否自动写入代理变量，由 `resources/clashctl.yaml` 里的 sidecar 配置控制。

## 🚀 安装

这个 README 对应当前 fork 的 `main` 维护线，不是 upstream 原仓库。历史 `nosudo-tmux` 分支只建议用于回看旧实现，不建议新安装继续使用。

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git clash-for-linux-install
cd clash-for-linux-install
bash install.sh
```

如需 GitHub 代理前缀，也可以使用：

```bash
git clone --branch main --depth 1 https://gh-proxy.org/https://github.com/tyx3211/tyx-clash-for-linux-install.git clash-for-linux-install
cd clash-for-linux-install
bash install.sh
```

### 默认托管模式

默认安装把 `INIT_TYPE` 设为 `tmux`：

```bash
bash install.sh
```

安装时也可以修改默认托管模式：

```bash
bash install.sh --init nohup
```

显式注册 `systemd` 服务并启用 sudo 能力：

```bash
sudo bash install.sh --init systemd
```

也可以使用等价形式：

```bash
bash install.sh --init=tmux
bash install.sh --init=nohup
sudo bash install.sh --init=systemd
```

- `tmux`：默认托管模式，适合共享机普通用户，便于查看会话和日志。
- `nohup`：普通用户备用模式，不依赖 `tmux`，但进程托管能力较弱。
- `systemd`：需要 root 或 sudo，会注册系统服务，支持 `clashtun on/off`。
- 安装后也可以用 `clashon --mode ...` / `clashrestart --mode ...` 在运行时选择本次托管模式。

- `.env` 里的 `CLASH_CONFIG_URL` 默认留空，不再内置任何真实订阅链接。
- 安装结束时，如果 `CLASH_CONFIG_URL` 仍为空，脚本会交互式提示输入订阅链接。
- 也可以先编辑 `.env` 再安装，显式指定订阅链接；链接务必使用双引号包起来。
- 默认安装会把 `clashctl` 初始化片段写入 `~/.bashrc` / `~/.zshrc`，并在安装完成后进入一个新的交互 shell，使 `clashctl` 能立即使用。

```bash
CLASH_CONFIG_URL="https://example.com/sub?clash=3&extend=1"
```

- 如果安装阶段先跳过订阅导入，后续也可以显式添加：

```bash
clashctl sub add "https://example.com/sub?clash=3&extend=1"
# 或
clashsub add "https://example.com/sub?clash=3&extend=1"
```

- 订阅链接里通常会带 `?`、`&` 等特殊字符，因此无论在安装前写 `.env`，还是安装后手工执行 `clashctl sub add`，都建议始终用双引号包起来。

### 非交互 / 自动化

```bash
# 不写入 shell rc 文件
CLASHCTL_NO_RC=1 bash install.sh

# 跳过安装末尾的订阅导入交互
CLASHCTL_NO_QUIT=1 bash install.sh
```

- 如果显式设置了 `CLASHCTL_NO_RC=1` 或 `CLASHCTL_NO_QUIT=1`，安装脚本不会帮当前终端切入新 shell；此时请自行执行：
  `. "$CLASH_BASE_DIR/scripts/cmd/clashctl.sh"`
  或
  `. "$HOME/clashctl/scripts/cmd/clashctl.sh"`

## ⌨️ 命令一览

```bash
Usage:
  clashctl COMMAND [OPTIONS]

Commands:
  on                    开启代理内核
  off                   关闭代理内核
  restart               重启或切换托管模式
  status                查看内核状态
  proxy                 管理当前终端代理变量
  ui                    查看 Web 面板地址
  secret                管理 Web 密钥
  sub                   管理订阅
  tun                   管理 Tun 模式（仅 systemd）
  mixin                 查看或刷新 Mixin 配置
  upgrade               升级内核
  update-self           无损更新项目脚本

Global Options:
  -h, --help            显示帮助信息
```

💡 `clashon`、`clashoff`、`clashproxy`、`clashsub` 等函数同样可直接使用，补全更方便。

## 🔌 代理行为

```bash
$ clashon
😼 已开启代理环境（mode=tmux）

$ clashrestart --mode nohup
😼 已开启代理环境（mode=nohup）

$ clashproxy on
😼 已为当前终端开启代理

$ clashproxy status
😼 当前终端代理：开启
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
all_proxy=socks5h://127.0.0.1:7891

$ clashproxy on -g
😼 已为当前终端开启代理，并开启全局自动代理
```

- `clashon` / `clashoff` 负责启动或关闭代理内核；`clashrestart --mode <mode>` 用于显式切换托管模式。
- `clashstatus --all` 可以查看 `tmux`、`nohup`、`systemd` 三种 adapter 的探测结果。
- `clashproxy on` / `clashproxy off` 只负责写入或清理当前 shell 的代理变量，不改 sidecar 全局状态。
- `clashproxy on -g` / `clashproxy off -g` 会在处理当前 shell 的同时，更新 sidecar 中的全局自动代理开关。
- `clashproxy status` 只根据当前 shell 的实际环境变量输出结果，不读 sidecar 状态。
- `clashproxy mode status` 用于查看 sidecar 中记录的全局自动代理状态与模式。

### 自动代理模式

`resources/clashctl.yaml` 用来描述 `clashctl` 自身的行为。当前内置：

```yaml
system-proxy:
  enable: true
  mode: silent
```

其中：

- `system-proxy.enable`
  控制新开的交互式 shell 是否允许 `watch_proxy` 自动写入代理变量。
- `system-proxy.mode`
  控制 `watch_proxy` 的动作，可选值：
  `none`、`silent`、`verbose`

对应行为：

- `none`
  新终端启动时不自动写入代理变量。
- `silent`
  新终端启动时按 `runtime.yaml` 中的端口静默写入代理变量。
- `verbose`
  新终端启动时按 `runtime.yaml` 中的端口写入代理变量，并输出提示。

可以通过命令查看或修改：

```bash
clashproxy mode
clashproxy mode status
clashproxy mode none
clashproxy mode silent
clashproxy mode verbose
clashproxy mode --help
```

如果需要临时与全局两种开关并存，推荐记法如下：

- 临时只改当前终端：`clashproxy on` / `clashproxy off`
- 同时改当前终端和全局自动代理：`clashproxy on -g` / `clashproxy off -g`

## 🌐 Web 控制台

- 默认控制端口为 `127.0.0.1:23571`。
- `clashui` 会输出控制台入口地址；默认推荐通过 SSH 端口转发访问。
- 如需远程访问面板，请确保 `secret` 与客户端保持一致。
- zashboard 的访问路径是 `/ui`，不是根路径；也就是说最终访问地址应类似：
  `http://localhost:<controller_port>/ui`

### 典型 SSH 转发示例

```bash
# 将远端控制口映射到本地
ssh -L 23571:127.0.0.1:23571 user@remote-host

# 如需把本地 HTTP 代理口一并转回来
ssh -L 23571:127.0.0.1:23571 -L 7890:127.0.0.1:7890 user@remote-host
```

### VS Code Remote-SSH 端口转发

- 如果我们本身就在用 VS Code 的 `Remote - SSH` 连远端开发，也可以直接在 VS Code 里转发 `23571` 这个远端端口。
- 这件事本质上等价于帮我们建立一条到远端控制口的 SSH 本地转发，因此不必再额外手写一条 `ssh -L`。
- 官方文档可参考：
  `https://code.visualstudio.com/docs/remote/ssh#_forwarding-a-port-creating-ssh-tunnel`
- 转发完成后，同样访问：
  `http://localhost:<controller_port>/ui`

## 🧩 Mixin 与 Sidecar

```bash
$ clashmixin
😼 查看 Mixin 配置

$ clashmixin -e
😼 编辑 Mixin 配置

$ clashmixin -m
😼 配置已显式合并并重启生效

$ clashmixin -c
😼 查看原始订阅配置

$ clashmixin -r
😼 查看运行时配置
```

- `resources/mixin.yaml` 只用于和原始订阅做深度合并，生成 `resources/runtime.yaml`。
- `resources/clashctl.yaml` 是 sidecar 配置，不会参与 mihomo/clash 的运行时合并。
- 修改 `mixin.yaml` 之后，如果不想进入编辑器，直接执行 `clashmixin -m` 即可显式 merge 并刷新内核；该命令不会打开 `less` 或其他查看器。
- 如果当前终端已经开启了代理变量，`clashmixin -m` 在刷新后会按新的 runtime 端口重新写入当前终端环境变量，避免端口变更后变量过期。

## 📦 订阅管理

```bash
$ clashsub -h
Usage:
  clashsub COMMAND [OPTIONS]

Commands:
  add <url>       添加订阅
  ls              查看订阅
  del <id>        删除订阅
  use <id>        使用订阅
  update [id]     更新订阅
  log             订阅日志

Options:
  update:
    --auto        配置自动更新
    --convert     使用订阅转换
```

常见用法：

```bash
clashctl sub add "https://example.com/sub?clash=3&extend=1"
clashctl sub use 1
clashctl sub update 1
clashctl sub ls
```

- 订阅链接请始终使用双引号包起来。
- 支持本地订阅，例如：
  `clashctl sub add "file://$HOME/clashctl/resources/config.yaml"`
- 当原始订阅不兼容时，可以配合 `--convert` 使用本地转换链路。
- 自动更新任务可通过 `crontab -e` 进行修改和管理。

## 🧭 Tun 模式

Tun 需要内核权限，因此默认 `tmux` / `nohup` 模式会拒绝执行：

```bash
$ clashtun on
😾 Tun 需要当前内核以 systemd 模式运行；请先执行 clashrestart --mode systemd
```

注册 `systemd` 服务并切换到 systemd 托管模式后，可以执行：

```bash
$ clashrestart --mode systemd
$ clashtun
$ clashtun on
$ clashtun off
```

- `systemd` 注册会使用 root 或 sudo 写入系统服务；通过 sudo 安装时，服务进程会以 sudo 调用用户身份运行，并由 systemd 授予 Tun 所需网络能力。
- 开启 Tun 时会修改 `resources/mixin.yaml` 中的 `tun.enable`，重新合并运行时配置并重启内核。
- 共享机默认不建议启用 Tun，除非我们明确知道该机器允许普通用户通过 sudo 管理这个服务。

## 🔄 更新项目脚本

`clashsub update` 更新订阅，`clashupgrade` 升级内核，二者都不会更新本项目的 shell 脚本。

从源码仓库 pull 新版本后，可以执行无损项目更新：

```bash
# 在已经 pull 到最新的源码仓库中执行
bash update.sh --target "$HOME/clashctl"

# 或从已安装环境显式指定源码仓库
clashctl update-self --source "$HOME/src/clash-shell/tyx-clash-for-linux-install"
```

该操作只刷新脚本、service 模板和文档资产，不覆盖 `.env`、`resources/mixin.yaml`、`resources/clashctl.yaml`、订阅 profiles、日志和运行状态。

## ⬆️ 升级内核

```bash
$ clashupgrade
😼 请求内核升级...
{"status":"ok"}
😼 内核升级成功
```

- 升级过程由代理内核自动完成。
- 如需查看详细升级日志，可添加 `-v` / `--verbose`。
- 建议通过 `clashmixin` 为 `github` 相关域名补充代理规则，避免升级请求被网络环境影响。

## 🗑️ 卸载

```bash
bash ~/clashctl/uninstall.sh
```

- 如果使用 `sudo bash install.sh --init systemd` 安装，则卸载也需要执行：

```bash
sudo bash ~/clashctl/uninstall.sh
```

- 请执行安装目录里的卸载脚本，而不是源码仓库里的同名脚本，避免把安装副本和源码目录混淆。

## 📖 常见问题

👉 [Wiki · FAQ](https://github.com/nelvko/clash-for-linux-install/wiki/FAQ)

## 🔗 引用

- [clash](https://clash.wiki/)
- [mihomo](https://github.com/MetaCubeX/mihomo)
- [subconverter](https://github.com/tindy2013/subconverter)
- [yq](https://github.com/mikefarah/yq)
- [zashboard](https://github.com/Zephyruso/zashboard)

## ⭐ Star History

<a href="https://www.star-history.com/#nelvko/clash-for-linux-install&Date">

 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=nelvko/clash-for-linux-install&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=nelvko/clash-for-linux-install&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=nelvko/clash-for-linux-install&type=Date" />
 </picture>
</a>

## 🙏 Thanks

[@鑫哥](https://github.com/TrackRay)

## ⚠️ 特别声明

1. 编写本项目主要目的为学习和研究 `Shell` 编程，不得将本项目中任何内容用于违反国家/地区/组织等的法律法规或相关规定的其他用途。
2. 本项目保留随时对免责声明进行补充或更改的权利，直接或间接使用本项目内容的个人或组织，视为接受本项目的特别声明。

# Clash/Mihomo Linux 多模式托管工具

默认免 sudo，以 `tmux` / `nohup` 在用户态托管内核；需要 Tun 时，可切换到 sudo + `systemd` 模式。

![GitHub License](https://img.shields.io/github/license/tyx3211/tyx-clash-for-linux-install)
![GitHub top language](https://img.shields.io/github/languages/top/tyx3211/tyx-clash-for-linux-install)
![GitHub Repo stars](https://img.shields.io/github/stars/tyx3211/tyx-clash-for-linux-install)

## 🚀 新用户 3 分钟上手

### 1. 第一次安装

共享机、没有 sudo、想用 `tmux` 托管内核时，直接执行：

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git
cd tyx-clash-for-linux-install
bash install.sh
```

安装脚本会提示输入订阅链接。订阅链接里通常带 `?`、`&`，手工输入命令时请始终用双引号包起来。

如果安装完成后当前终端还没有 `clashctl` 命令，执行：

```bash
. "$HOME/clashctl/scripts/cmd/clashctl.sh"
```

### 2. 日常启动

```bash
clashon
clashstatus
clashproxy on
```

- `clashon` 启动 mihomo / clash 内核，默认使用 `tmux`。
- `clashstatus` 查看当前内核是否运行。
- `clashproxy on` 只给当前终端写入代理环境变量，不改系统代理。

需要 Web 面板地址：

```bash
clashui
```

共享机远程访问面板时，推荐先做 SSH 端口转发：

```bash
ssh -L 9090:127.0.0.1:9090 user@remote-host
```

然后在本机浏览器访问 `http://localhost:9090/ui`。

### 3. 关闭与切换托管模式

```bash
clashoff
clashrestart --mode nohup
clashrestart --mode tmux
```

- 没有 `tmux` 时，可以用 `clashrestart --mode nohup`。
- 需要 Tun 时，需要 sudo 安装 systemd 服务，然后用 `clashrestart --mode systemd`。

### 4. 直接更新项目脚本

已安装后，以后更新本项目脚本和文档只需要：

```bash
clashctl update-self
```

这个命令会从当前 fork 的 GitHub `main` 分支下载最新源码，并无损刷新安装目录。它不会停止内核、不会启动内核、不会覆盖 `config/`、订阅、运行时配置、日志和 pid 状态。

`git clone` 得到的是安装源目录；默认安装目录 `~/clashctl` 不是项目 git 仓库，也不需要 `.git`。如果希望版本管理个人配置，推荐只在 `~/clashctl/config` 下建立 git 仓库。安装时可以使用 `bash install.sh --config-git` 或 `CLASHCTL_CONFIG_GIT=1 bash install.sh` 自动执行 `git init`。

更多新手说明见 [快速上手教程](docs/quickstart.md)。运行托管模式、订阅和项目更新见 [当前版本使用指南](docs/usage-guide.md)。旧版升级见 [旧版迁移指南](docs/legacy-migration.md)。配置 Git 管理见 [配置版本管理](docs/config-versioning.md)。

## ✨ 功能特性

- 支持安装和托管 `mihomo` / `clash` 代理内核。
- 面向 no-sudo 环境，默认使用 `tmux` 管理内核进程，不依赖 `systemd`。
- 支持运行时选择托管模式：`clashon --mode tmux|nohup|systemd`。其中 `systemd` 需要 root 或 sudo，并支持 Tun。
- 当前维护入口统一为 `main`。历史 `nosudo-tmux` 分支已经退役；新的 no-sudo / tmux 能力直接在 `main` 维护。
- 默认代理端口为 `port: 7890`、`socks-port: 7891`；新安装默认控制端口为 `127.0.0.1:9090`。
- 代理内核配置与 `clashctl` 自身行为配置分离：
  `config/mixin.yaml` 只放会参与 mihomo/clash 合并的配置；
  `config/clashctl.yaml` 只放 `clashctl` 的 sidecar 配置，不再把私有键混进运行时配置。
- 适合人工维护的配置集中在 `config/`，可选用 git 管理；运行时生成物继续放在 `resources/`。
- 自动检测代理端口占用情况，并在冲突时为代理端口随机分配可用端口；`external-controller` 控制端口冲突时只提示建议端口，不自动改用户配置。
- 在需要时调用 [subconverter](https://github.com/tindy2013/subconverter) 进行本地订阅转换。
- 默认 no-sudo / tmux 模式不提供 Tun；显式选择 `systemd` 模式时支持 Tun。

## 🧭 项目定位

本项目是面向共享机和普通 Linux 用户环境的 Clash/Mihomo 多模式托管工具。默认路线免 sudo，使用 `tmux` 托管内核；需要更轻量后台进程时可以切到 `nohup`；需要 Tun 时再显式使用 sudo 注册 `systemd` 服务。

- 默认路线：普通用户执行 `bash install.sh`，默认运行托管模式为 `tmux`。
- 备用用户态路线：执行 `clashon --mode nohup`，用 nohup 托管本次内核进程。
- sudo 路线：root 或 sudo 执行 `bash install.sh --init systemd` 注册 systemd 服务，用于需要 Tun 的机器。
- 不支持路线：不使用 `systemd --user`；共享机上这一能力经常被禁用，当前 fork 不把它作为依赖。
- 分支策略：GitHub 默认分支为 `main`；旧 `nosudo-tmux` 远程分支不再作为发布入口保留。

更多说明：

- [Fork 差异与分支策略](docs/fork-differences.md)
- [快速上手教程](docs/quickstart.md)
- [当前版本使用指南](docs/usage-guide.md)
- [旧版迁移指南](docs/legacy-migration.md)
- [手工端到端检查清单](docs/manual-e2e-checklist.md)

## ✅ no-sudo 使用补充

- 当前 fork 以 `INIT_TYPE=tmux` 为默认运行托管模式，请先确保系统已安装 `tmux`。
- 如需纯用户态但不想依赖 `tmux`，可以在运行时使用 `clashon --mode nohup`。
- 如需 Tun，请先使用 `sudo bash install.sh --init systemd` 注册 systemd 服务，再执行 `clashrestart --mode systemd` 和 `clashtun on`。运行时启动/停止 systemd 服务使用 `sudo -n systemctl`，因此需要 root 或免密 sudo；脚本不会停下来等待输入 sudo 密码。
- 新安装的 `external-controller` 默认绑定 `127.0.0.1:9090`，远程访问面板请优先使用 SSH 端口转发。旧安装无损更新后不会自动改已有端口，实际地址以 `clashui` 输出为准。
- `clashproxy on` / `clashproxy off` 只影响当前 shell 的环境变量，不会改系统级代理。
- `clashproxy status` 只看当前终端实际环境变量，避免与配置状态偏离。
- 新终端是否自动写入代理变量，由 `config/clashctl.yaml` 里的 sidecar 配置控制。

## 🚀 安装

这个 README 对应当前 `main` 维护线。历史 `nosudo-tmux` 分支已经退役，新安装和更新都应使用 `main`。

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

如果希望安装时直接在配置目录建立 git 仓库：

```bash
bash install.sh --config-git
# 或
CLASHCTL_CONFIG_GIT=1 bash install.sh
```

该选项只会在安装目录的 `config/` 子目录执行 `git init`，不会把 `~/clashctl` 根目录变成 git 仓库，也不会自动提交。

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
- `systemd`：需要 root 或 sudo，会注册系统服务，支持 `clashtun on/off`。运行时管理服务要求 root 或免密 sudo。
- 安装后也可以用 `clashon --mode ...` / `clashrestart --mode ...` 在运行时选择本次托管模式。
- `.env` 现在只作为安装前默认值和旧版本兼容入口。安装完成后，本机安装状态以 `resources/install-state.yaml` 为主；普通使用者通常不需要修改它。
- `.env` 里的 `VERSION_MIHOMO`、`VERSION_YQ`、`VERSION_SUBCONVERTER` 默认固定版本；如果留空，安装脚本会通过 GitHub `releases/latest` 自动解析最新 tag。共享机或网络受限环境建议固定版本，便于复现和排错。
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

`config/clashctl.yaml` 用来描述 `clashctl` 自身的行为。当前内置：

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

- 新安装默认控制端口为 `127.0.0.1:9090`。旧安装执行 `clashctl update-self` 后不会自动改已有 `mixin.yaml`，实际端口以 `clashui` 输出或当前 `mixin.yaml` 为准。
- 如果 `external-controller` 控制端口被其他进程占用，启动命令会失败并给出建议端口。请手工修改 `~/clashctl/config/mixin.yaml` 里的 `external-controller`，然后执行 `clashmixin -m`；旧兼容安装也可能需要修改 `~/clashctl/resources/mixin.yaml`。
- `clashui` 会输出控制台入口地址；默认推荐通过 SSH 端口转发访问。
- 当控制口绑定 `127.0.0.1` / `localhost` 时，`clashui` 只输出本机地址和 SSH 转发示例，不提示公网地址或开放防火墙端口。
- 如需远程访问面板，请确保 `secret` 与客户端保持一致。
- zashboard 的访问路径是 `/ui`，不是根路径；也就是说最终访问地址应类似：
  `http://localhost:<controller_port>/ui`

### 典型 SSH 转发示例

```bash
# 将远端控制口映射到本地
ssh -L 9090:127.0.0.1:9090 user@remote-host

# 如需把本地 HTTP 代理口一并转回来
ssh -L 9090:127.0.0.1:9090 -L 7890:127.0.0.1:7890 user@remote-host
```

### VS Code Remote-SSH 端口转发

- 如果我们本身就在用 VS Code 的 `Remote - SSH` 连远端开发，也可以直接在 VS Code 里转发 `9090` 这个远端端口。
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

- `mixin.yaml` 默认位于 `~/clashctl/config/mixin.yaml`，只用于和原始订阅做深度合并，生成 `resources/runtime.yaml`。
- `config/clashctl.yaml` 是 sidecar 配置，不会参与 mihomo/clash 的运行时合并。
- 除了 `clashmixin -e`，也鼓励直接用 VS Code Remote、vim 或其他编辑器修改 `~/clashctl/config/mixin.yaml`。直接编辑后记得执行 `clashmixin -m` 或 `clashctl mixin -m`，显式合并并刷新内核。
- 如果不想进入编辑器，直接执行 `clashmixin -m` 即可显式 merge 并刷新内核；该命令不会打开 `less` 或其他查看器。
- 如果当前终端已经开启了代理变量，`clashmixin -m` 在刷新后会按新的 runtime 端口重新写入当前终端环境变量，避免端口变更后变量过期。

## 📦 订阅管理

```bash
$ clashsub -h
Usage:
  clashsub COMMAND [OPTIONS]

Commands:
  add [-u|--use] <url>
                  添加订阅
  ls              查看订阅
  del|delete <id> 删除订阅
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
clashctl sub add --use "https://example.com/sub?clash=3&extend=1"
clashctl sub use 1
clashctl sub update 1
clashctl sub update 1 --convert
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
- 运行时的 `clashrestart --mode systemd`、`clashoff --mode systemd` 和 `clashtun on/off` 会使用非交互 sudo；如果当前用户执行 `sudo -n systemctl status mihomo` 会要求密码，这条路线也会失败。
- 开启 Tun 时会修改 `config/mixin.yaml` 中的 `tun.enable`，重新合并运行时配置并重启内核。旧安装目录如果还没有 `config/`，会继续使用兼容路径 `resources/mixin.yaml`。
- 共享机默认不建议启用 Tun，除非我们明确知道该机器允许普通用户通过 sudo 管理这个服务。

## 🔄 更新项目脚本

`clashsub update` 更新订阅，`clashupgrade` 升级内核，二者都不会更新本项目的 shell 脚本。

### 旧版用户先迁移

如果记得安装来源：旧 `nosudo-tmux` 分支、旧 `master`、[`legacy-nosudo-tmux`](https://github.com/tyx3211/tyx-clash-for-linux-install/tree/legacy-nosudo-tmux) 这个 tag 及以前版本，都按旧版处理。只看本地目录时，如果 `~/clashctl` 里还带有 `.git`、`placeholder_start1` 或旧 `resources/mixin.yaml` 布局，也按旧版处理；如果知道自己还没有执行过 `migrate.sh`，同样先按旧版迁移。

旧版用户请先阅读 [旧版迁移指南](docs/legacy-migration.md)，从新源码目录执行 `migrate.sh`。不建议先卸载旧安装目录，也不建议直接重装覆盖。

### 已迁移后的日常更新

已迁移到新版后，可以直接从 GitHub 更新当前 fork 的 `main` 分支：

```bash
clashctl update-self
```

也可以指定分支或 tag：

```bash
clashctl update-self --ref main
```

如果正在本地开发源码，或者已经手工 pull 了源码仓库，可以执行本地无损项目更新：

```bash
# 在已经 pull 到最新的源码仓库中执行
bash update.sh --target "$HOME/clashctl"

# 或从已安装环境显式指定源码仓库
clashctl update-self --source "$HOME/src/clash-shell/tyx-clash-for-linux-install"
```

该操作只刷新脚本、service 模板和文档资产，不覆盖 `config/`、`resources/install-state.yaml`、`resources/config.yaml`、`resources/runtime.yaml`、订阅 profiles、日志和运行状态。旧安装目录如果已有 `.env`，会继续保留并只做兼容性更新；旧安装目录如果还在使用 `resources/mixin.yaml`、`resources/clashctl.yaml`、`resources/profiles.yaml`，这些文件也会原样保留。

### 如果选择重装

不建议为了升级先卸载旧目录。确实要重装时，请先按 [旧版迁移指南：如果选择重装](docs/legacy-migration.md#如果选择重装) 备份关键文件，再按新版布局恢复。

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

## 🔗 相关项目

- [clash](https://clash.wiki/)
- [mihomo](https://github.com/MetaCubeX/mihomo)
- [subconverter](https://github.com/tindy2013/subconverter)
- [yq](https://github.com/mikefarah/yq)
- [zashboard](https://github.com/Zephyruso/zashboard)
- [nelvko/clash-for-linux-install](https://github.com/nelvko/clash-for-linux-install)：本项目的上游基础，感谢其长期维护。

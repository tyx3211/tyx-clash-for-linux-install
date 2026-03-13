# Linux 一键安装 Clash

![GitHub License](https://img.shields.io/github/license/nelvko/clash-for-linux-install)
![GitHub top language](https://img.shields.io/github/languages/top/nelvko/clash-for-linux-install)
![GitHub Repo stars](https://img.shields.io/github/stars/nelvko/clash-for-linux-install)

![preview](resources/preview.png)

## ✨ 功能特性

- 支持一键安装 `mihomo` 与 `clash` 代理内核。
- 面向 no-sudo 环境，默认使用 `tmux` 管理内核进程，不依赖 `systemd`。
- 默认代理端口为 `port: 7890`、`socks-port: 7891`，默认控制端口为 `127.0.0.1:23571`。
- 代理内核配置与 `clashctl` 自身行为配置分离：
  `resources/mixin.yaml` 只放会参与 mihomo/clash 合并的配置；
  `resources/clashctl.yaml` 只放 `clashctl` 的 sidecar 配置，不再把私有键混进运行时配置。
- 自动检测端口占用情况，在冲突时随机分配可用端口。
- 在需要时调用 [subconverter](https://github.com/tindy2013/subconverter) 进行本地订阅转换。
- 不提供 Tun 模式；该 fork 以 no-sudo 场景为目标。

## ✅ no-sudo 使用补充

- 当前 fork 以 `INIT_TYPE=tmux` 为默认配置，请先确保系统已安装 `tmux`。
- `external-controller` 默认绑定 `127.0.0.1:23571`，远程访问面板请优先使用 SSH 端口转发。
- `clashproxy on` / `clashproxy off` 只影响当前 shell 的环境变量，不会改系统级代理。
- `clashproxy status` 只看当前终端实际环境变量，避免与配置状态偏离。
- 新终端是否自动写入代理变量，由 `resources/clashctl.yaml` 里的 sidecar 配置控制。

## 🚀 安装

这个 README 对应的是当前 fork 的 `nosudo-tmux` 分支，不是 upstream 原仓库。

```bash
git clone --branch nosudo-tmux --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git clash-for-linux-install
cd clash-for-linux-install
bash install.sh
```

如需 GitHub 代理前缀，也可以使用：

```bash
git clone --branch nosudo-tmux --depth 1 https://gh-proxy.org/https://github.com/tyx3211/tyx-clash-for-linux-install.git clash-for-linux-install
cd clash-for-linux-install
bash install.sh
```

- `.env` 里的 `CLASH_CONFIG_URL` 默认留空，不再内置任何真实订阅链接。
- 安装结束时，如果 `CLASH_CONFIG_URL` 仍为空，脚本会交互式提示输入订阅链接。
- 也可以先编辑 `.env` 再安装，显式指定订阅链接；链接务必使用双引号包起来。

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

## ⌨️ 命令一览

```bash
Usage:
  clashctl COMMAND [OPTIONS]

Commands:
  on                    开启代理内核
  off                   关闭代理内核
  status                查看内核状态
  proxy                 管理当前终端代理变量
  ui                    查看 Web 面板地址
  secret                管理 Web 密钥
  sub                   管理订阅
  mixin                 查看或刷新 Mixin 配置
  upgrade               升级内核

Global Options:
  -h, --help            显示帮助信息
```

💡 `clashon`、`clashoff`、`clashproxy`、`clashsub` 等函数同样可直接使用，补全更方便。

## 🔌 代理行为

```bash
$ clashon
😼 已开启代理环境

$ clashproxy on
😼 已开启系统代理

$ clashproxy status
😼 系统代理：开启
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
all_proxy=socks5h://127.0.0.1:7891
```

- `clashon` / `clashoff` 负责启动或关闭代理内核。
- `clashproxy on` / `clashproxy off` 负责写入或清理当前 shell 的代理变量，同时更新 sidecar 中的自动代理开关。
- `clashproxy status` 只根据当前 shell 的实际环境变量输出结果，不读 sidecar 状态。

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
clashproxy mode none
clashproxy mode silent
clashproxy mode verbose
```

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
- 修改 `mixin.yaml` 之后，如果不想进入编辑器，直接执行 `clashmixin -m` 即可显式 merge 并刷新内核。
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
  `clashctl sub add "file:///root/clashctl/resources/config.yaml"`
- 当原始订阅不兼容时，可以配合 `--convert` 使用本地转换链路。
- 自动更新任务可通过 `crontab -e` 进行修改和管理。

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
bash uninstall.sh
```

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

# 上游致谢与项目差异

本文说明 `tyx3211/clash-for-linux-install-multimode` 相对上游项目 `nelvko/clash-for-linux-install` 的刻意调整，以及当前推荐的分支使用方式。

本项目基于 `nelvko/clash-for-linux-install` 改造，感谢上游作者提供的原始安装脚本和长期维护基础。当前仓库作为独立的多模式托管版本维护，重点面向 no-sudo `tmux` / `nohup` 用户态链路，并保留可选 sudo `systemd` / Tun 路线。

## 当前维护线

当前维护入口应使用 `main`：

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/clash-for-linux-install-multimode.git clash-for-linux-install-multimode
```

历史 `nosudo-tmux` 分支已经退役。早期共享机用户态实现已经合入 `main`，并和上游同步机制、systemd sudo 模式、Tun 支持、事务回滚和安全修复一起维护。新安装、更新和问题修复都不再以 `nosudo-tmux` 作为入口。

本地建议分支语义如下：

- `main`：当前维护版本，默认 tmux 用户态，兼容 `nohup` 和 `systemd` sudo 模式。
- `experiment-bun-ts`：实验性 Bun + TypeScript 重写路线，不影响 shell 版本。

GitHub 远程分支策略：

- 默认分支应指向 `main`。
- 旧 `nosudo-tmux` 远程分支不再保留为发布入口，避免新用户误装旧实现。
- 旧 `master` 若仍存在，只能视为迁移前遗留分支，不代表当前文档描述的功能面。

## 与上游项目的关系

本项目保留上游项目的核心目标：下载内核、合并配置、管理订阅、启动代理、提供 shell CLI。

同步上游时，我们优先吸收这些机制：

- 订阅下载失败后不继续验证旧临时文件。
- 订阅转换、下载超时、subconverter 仓库来源可配置。
- Tun 配置使用较新的 DNS 与 fake-ip 默认建议。
- `clashctl` 子命令拆分、帮助输出、配置合并和安全校验的改进。
- systemd 服务只授予网络相关能力，而不是无差别扩大权限。

## 本项目刻意保留的差异

### 默认用户态启动

上游项目更偏向系统服务式安装；本项目默认走 `tmux`：

```bash
bash install.sh
```

这适合共享开发机和 no-sudo 环境。我们不依赖 `systemd --user`，因为共享机上它经常不可用或被运维策略禁用。

### 多运行托管模式

本项目支持三种运行托管模式：

- `tmux`：默认模式，普通用户可用，可通过 tmux 会话观察进程。
- `nohup`：普通用户备用模式，不依赖 tmux，但可观测性弱。
- `systemd`：需要 root 或 sudo，支持 Tun；运行时管理服务需要 root 或免密 sudo。

`INIT_TYPE` 表示默认运行托管模式；`--init` 命令行参数只是在安装时覆盖这个默认值：

```bash
bash install.sh --init tmux
bash install.sh --init nohup
sudo bash install.sh --init systemd
```

安装后可以按次选择托管模式：

```bash
clashon --mode tmux
clashrestart --mode nohup
clashrestart --mode systemd
```

### Tun 只在 systemd sudo 模式开放

Tun 需要网络能力。本项目不在 `tmux` / `nohup` 模式里绕过权限限制，也不尝试通过 `systemd --user` 获取能力。

```bash
sudo bash install.sh --init systemd
clashrestart --mode systemd
clashtun on
```

通过 sudo 安装时，systemd 服务会以 sudo 调用用户身份运行，并由 systemd 授予 `CAP_NET_ADMIN`、`CAP_NET_RAW`、`CAP_NET_BIND_SERVICE`。

运行时的 start/stop/restart 使用 `sudo -n systemctl`，不会停下来等待输入 sudo 密码。如果当前用户没有免密 sudo，systemd/Tun 路线会明确失败。

### Sidecar 配置分离

本项目把代理内核运行配置和 `clashctl` 自身行为配置分开：

- `config/mixin.yaml`：参与 mihomo / clash 运行时配置合并。
- `config/clashctl.yaml`：只描述 `clashctl` 自身行为，例如新 shell 是否自动写入代理变量。
- `config/subscriptions.yaml`：保存订阅元信息和当前使用的订阅 id。

旧安装目录如果还没有 `config/`，脚本会继续兼容 `resources/mixin.yaml`、`resources/clashctl.yaml` 和 `resources/profiles.yaml`。

本机安装状态不放在 `config/`，而是写入 `resources/install-state.yaml`。`.env` 只作为安装前默认值和旧版本兼容入口保留。

这样可以避免把 `clashctl` 私有配置混进内核运行时配置。

### 代理变量只影响当前 shell

`clashproxy on` / `clashproxy off` 默认只修改当前 shell 的代理环境变量，不改系统级代理。

如果需要让新终端自动写入代理变量，使用：

```bash
clashproxy on -g
clashproxy mode silent
```

### 订阅和配置变更尽量事务化

本项目对以下操作补了失败回滚：

- `clashsub use <id>`：切换订阅后如果运行时合并或重启失败，恢复旧 `config.yaml`。
- `clashsub update [id]`：当前订阅更新后如果重新应用失败，恢复旧 profile 和 base。
- `clashsecret <new_secret>`：密钥写入或重启失败时恢复旧 `mixin.yaml`。
- `clashtun off`：关闭 Tun 失败时恢复旧 Tun 配置；如果服务本来没启动，不会为了关闭 stale 配置而启动服务。

这些改动不是为了支持任意异常输入，而是为了避免常见失败分支把当前可用配置写坏。

### 安装路径限制

安装目录必须是绝对路径，并且不能是 `/`、`$HOME` 本身、相对路径，也不能包含空白、`#`、`&`。

原因是当前项目仍然是 shell 实现，安装路径会进入 service 模板、sed 替换、启动命令和 shell rc 片段。与其支持复杂转义组合，不如明确限制这些低收益路径，保持安装行为可预测。

默认路径 `~/clashctl` 不受影响。

## 不刻意兼容的场景

- 不支持 `systemd --user` 作为安装模式。
- 不保证安装路径里包含空白、`#`、`&` 时可用。
- 不把 `tmux` / `nohup` 模式伪装成支持 Tun。
- 不在 `clashproxy` 中修改桌面环境或系统级代理。

## 后续重写方向

Shell 版本仍是第一版跟进版本。Bun + TypeScript 或 Rust / Go 重写可以降低字符串拼接、全局变量、隐式返回码、trap 和 quoting 带来的风险，但短期内 shell 版本更容易跟进上游机制，也更容易被现有用户直接审查和部署。

实验路线应放在独立分支，例如 `experiment-bun-ts`，不要阻塞当前 shell 主线。生产使用、共享机部署和文档示例都以 `main` 为准。

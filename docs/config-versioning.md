# 配置版本管理

本文说明当前 fork 的配置目录布局，以及如何选择性地用 git 管理个人配置。

## 推荐心智模型

安装目录默认是 `~/clashctl`。这个目录不是项目源码仓库，也不是默认的配置仓库，它同时包含脚本、二进制、资源包、运行时状态和日志。

当前版本按三层理解配置和状态：

```text
config/                       # 用户长期维护、可选 git 管理的偏好
resources/install-state.yaml  # 本机安装状态，不建议 git 管理
命令行参数 / 环境变量          # 本次命令的临时覆盖，不覆盖安装身份
```

源码根目录里的 `.env` 只作为安装前默认值和旧版本兼容入口。安装完成后，安装目录、内核名、默认托管模式、systemd 服务是否注册、版本线索等本机状态以 `resources/install-state.yaml` 为主。`.env` 不属于推荐版本管理的配置集合，因为这些值通常和单台机器、单次安装、网络环境或升级策略绑定。

环境变量适合临时覆盖下载超时、GitHub 代理前缀、订阅 User-Agent 这类非安装身份字段。安装目录、内核名和默认托管模式属于安装身份；一旦 `resources/install-state.yaml` 存在，`clashctl` 会以它为准，不再让外部 shell 中残留的 `CLASH_BASE_DIR`、`KERNEL_NAME`、`INIT_TYPE` 覆盖当前安装实例。

当前版本把适合人工维护的源配置集中到：

```text
~/clashctl/config/
  mixin.yaml          # 参与 mihomo / clash 运行时配置合并
  clashctl.yaml       # clashctl 自身行为，例如新 shell 是否自动写入代理变量
  subscriptions.yaml  # 订阅元信息和当前使用的订阅 id
```

运行时生成或下载得到的文件继续放在：

```text
~/clashctl/resources/
  install-state.yaml  # 本机安装状态：安装目录、内核名、默认模式、版本线索
  config.yaml         # 当前使用订阅的原始展开配置
  runtime.yaml        # mixin 后生成的实际运行配置
  service-state.yaml  # 托管模式状态线索
  profiles/           # 订阅下载后的配置缓存
  *.log / *.pid       # 日志与进程状态
```

因此，如果需要自己做配置版本管理，推荐只在 `~/clashctl/config` 目录建立 git 仓库，不建议在 `~/clashctl` 根目录建立 git 仓库，也不建议把 `.env` 或 `resources/install-state.yaml` 放进这个仓库。

## 安装时直接初始化配置仓库

安装时可以通过命令行打开：

```bash
bash install.sh --config-git
```

也可以通过环境变量打开：

```bash
CLASHCTL_CONFIG_GIT=1 bash install.sh
```

如果已经在环境变量里打开，但这次想临时关闭：

```bash
CLASHCTL_CONFIG_GIT=1 bash install.sh --no-config-git
```

该选项只会在 `~/clashctl/config` 下执行 `git init`，不会自动提交、不会创建远程仓库、不会把安装根目录变成 git 仓库。

首次安装后可以手动提交一次基线：

```bash
cd "$HOME/clashctl/config"
git status
git add mixin.yaml clashctl.yaml subscriptions.yaml
git commit -m "chore: initialize clashctl config"
```

如果本机没有配置 git 用户信息，`git commit` 可能会要求先设置 `user.name` 和 `user.email`。这属于用户自己的配置仓库策略，安装脚本不会代为设置。

## 已安装环境如何补建

如果安装时没有使用 `--config-git`，后续也可以手工初始化：

```bash
cd "$HOME/clashctl/config"
git init
git status
```

旧版本无损更新上来时，可能还没有 `config/` 目录，旧配置仍在 `resources/mixin.yaml`、`resources/clashctl.yaml`、`resources/profiles.yaml`。当前脚本会继续兼容这些旧路径，但推荐按 [旧版迁移指南](legacy-migration.md) 执行 `migrate.sh`，由脚本统一迁移到新版布局。

迁移完成后，再进入 `config/` 初始化配置仓库即可。

## update-self 会保留什么

`clashctl update-self` 只刷新项目脚本、service 模板、README、docs 和 tests，不会覆盖：

- `config/`
- `resources/install-state.yaml`
- `resources/config.yaml`
- `resources/runtime.yaml`
- `resources/profiles/`
- 日志、pid 和服务状态文件
- 历史安装目录中已经存在的 `.git`

旧安装目录如果已有 `.env`，`update-self` 会继续保留它，只在必要时更新兼容字段；如果旧目录已经迁移到 `resources/install-state.yaml` 且没有 `.env`，`update-self` 不会凭空重新创建 `.env`。

旧安装目录如果还在使用 `resources/mixin.yaml`、`resources/clashctl.yaml`、`resources/profiles.yaml`，这些旧路径文件也会原样保留。

这意味着配置目录中的 `.git` 会被完整保留。项目更新不会自动提交配置变更，也不会重写用户配置仓库。

## 是否要脱敏

`subscriptions.yaml` 可能包含订阅链接；`mixin.yaml` 可能包含 Web 控制密钥、认证信息或规则偏好。如果配置仓库只在本机或内网使用，可以按个人运维习惯处理。若计划推到公网或不可信远端，应先脱敏，尤其是订阅链接和密钥。

## 为什么不在安装根目录建 git

安装根目录里混有大量非源配置：

- 二进制内核和工具；
- Web UI 压缩包和解压目录；
- 本机安装状态；
- 当前订阅展开结果；
- 运行时合并结果；
- 日志、pid 和临时文件；
- `update-self` 刷新的脚本和文档。

这些文件变化频繁，且很多不是人手维护的配置。把 git 仓库放在 `config/` 下，目录边界更清楚，也不需要维护复杂的 `.gitignore`。

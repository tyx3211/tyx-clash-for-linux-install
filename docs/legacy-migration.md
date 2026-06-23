# 旧版迁移指南

本文说明从旧 `nosudo-tmux`、旧 `master` 或早期中间版安装迁移到当前 `main` 的推荐方式。迁移目标是原地刷新脚本和文档，同时保留订阅、`mixin.yaml`、sidecar 配置、运行时配置和日志。

## 什么情况算旧版

如果记得安装来源，符合下面任意一种情况，都建议先按本文执行迁移：

- 安装目录来自旧 `nosudo-tmux` 分支。
- 安装目录来自旧 `master` 分支。
- 安装目录对应 [`legacy-nosudo-tmux`](https://github.com/tyx3211/tyx-clash-for-linux-install/tree/legacy-nosudo-tmux) 这个 tag 及以前的版本。

如果只看本地安装目录，符合下面任意一种情况，也按旧版处理：

- 安装目录里还存在 `placeholder_start1`。
- `~/clashctl` 根目录里带有历史遗留的 `.git`。
- 主要配置还在 `~/clashctl/resources/mixin.yaml`、`resources/clashctl.yaml`、`resources/profiles.yaml`。
- 已经从中间版无损更新过脚本，但还没有执行过 `migrate.sh`。

旧版不要先卸载。直接卸载或覆盖安装更容易丢掉订阅、mixin 配置和已经调好的运行时配置。

## 推荐迁移方式

从新的源码目录执行迁移：

```bash
git clone --branch main --depth 1 https://github.com/tyx3211/tyx-clash-for-linux-install.git
cd tyx-clash-for-linux-install
bash migrate.sh --target "$HOME/clashctl"
source "$HOME/clashctl/scripts/cmd/clashctl.sh"
clashstatus --all
```

`migrate.sh` 默认只做原地迁移：

- 不停止当前内核。
- 不启动新的内核。
- 不修改当前 shell 的代理环境变量。
- 刷新安装目录里的项目脚本、service 模板和文档。
- 写入 `resources/install-state.yaml`。
- 将旧 `resources/mixin.yaml` 复制到 `config/mixin.yaml`。
- 将旧 `resources/clashctl.yaml` 复制到 `config/clashctl.yaml`。
- 将旧 `resources/profiles.yaml` 复制到 `config/subscriptions.yaml`。
- 清理 `placeholder_start1`、`preview.png`、`.github`、`.editorconfig`、`.gitattributes`、`.shellcheckrc`、`resources/preview.png` 等旧项目遗留文件。这些路径只按安装根目录下的旧项目资产处理，不应承载用户配置；如果曾经手工改过这些文件，请先备份。

如果旧 `resources/` 配置和新版 `config/` 配置已经同时存在且内容不同，迁移会在刷新脚本前拒绝继续。这是为了避免新版优先读取 `config/` 后，旧 `resources/` 配置看似保留但实际不生效。处理方式是先手工 `diff` 两边内容，确认以后以哪一边为准。

确认状态后，再按需重启：

```bash
clashrestart
```

`clashrestart` 不带 `--mode` 时，会优先重启当前活跃托管模式；没有活跃模式时才按默认模式启动。明确要切换模式时，再使用：

```bash
clashrestart --mode tmux
clashrestart --mode nohup
clashrestart --mode systemd
```

## 迁移后移走旧配置

默认迁移会保留旧 `resources/` 下的配置副本，便于回看和排错。如果希望旧配置从 `resources/` 移走，不在旧位置保留副本，可以执行：

```bash
bash migrate.sh --target "$HOME/clashctl" --move-legacy-config
```

如果之前已经执行过默认迁移，且 `config/` 和旧 `resources/` 文件内容不同，`--move-legacy-config` 会拒绝删除旧文件。确认以后以 `config/` 为准时，再显式追加：

```bash
bash migrate.sh --target "$HOME/clashctl" --move-legacy-config --force-remove-legacy-config
```

`--force-remove-legacy-config` 会在内容不一致时删除旧 `resources/` 配置文件。执行前建议先备份或手工 `diff`，确认 `config/` 才是唯一准配置。

## 迁移后自动重启

远程会话依赖当前代理链路时，不建议迁移脚本里直接重启。更稳妥的做法是先执行默认迁移，确认 `clashstatus --all` 后，再手动执行 `clashrestart`。

如果明确希望迁移后自动重启，可以显式指定目标模式：

```bash
bash migrate.sh --target "$HOME/clashctl" --restart-mode tmux
```

## 迁移后检查

```bash
source "$HOME/clashctl/scripts/cmd/clashctl.sh"
clashstatus --all
clashstatus
clashui
ls -la "$HOME/clashctl/config"
```

新版推荐的长期配置位置是：

```text
~/clashctl/config/
  mixin.yaml
  clashctl.yaml
  subscriptions.yaml
```

运行时生成物和本机状态继续放在：

```text
~/clashctl/resources/
  install-state.yaml
  config.yaml
  runtime.yaml
  profiles/
```

## 已迁移后的日常更新

迁移完成后，日常更新本项目脚本和文档直接执行：

```bash
clashctl update-self
```

该命令默认从 GitHub 获取当前 fork 的 `main`，不会使用本机源码目录里的未提交改动。迁移后如果正在本地调试修复，使用下面的 `--source` 路线。

指定分支或 tag：

```bash
clashctl update-self --ref main
```

如果已经手工 `git pull` 了源码仓库，也可以从本地源码刷新安装目录：

```bash
bash update.sh --target "$HOME/clashctl"
# 或
clashctl update-self --source "$HOME/src/clash-shell/tyx-clash-for-linux-install"
```

项目更新不会停止内核、不会启动内核、不会覆盖 `config/`、订阅、`resources/install-state.yaml`、`resources/config.yaml`、`resources/runtime.yaml`、日志和 pid 状态。

## 如果选择重装

不建议为了升级先卸载旧目录。如果确实要全新安装，优先选择一个不存在的新目录：

```bash
CLASH_BASE_DIR="$HOME/clashctl-new" bash install.sh --init tmux
```

普通旧版升级仍应优先走原地 `migrate.sh`。只有明确选择重装时，才考虑卸载、清理旧目录或复用旧安装目录。

如果必须复用旧安装目录，至少先备份关键文件：

```bash
mkdir -p "$HOME/clashctl-backup"
cp -a "$HOME/clashctl/.env" "$HOME/clashctl-backup/" 2>/dev/null || true
cp -a "$HOME/clashctl/config" "$HOME/clashctl-backup/config" 2>/dev/null || true
cp -a "$HOME/clashctl/resources/mixin.yaml" "$HOME/clashctl-backup/mixin.yaml" 2>/dev/null || true
cp -a "$HOME/clashctl/resources/clashctl.yaml" "$HOME/clashctl-backup/clashctl.yaml" 2>/dev/null || true
cp -a "$HOME/clashctl/resources/profiles.yaml" "$HOME/clashctl-backup/profiles.yaml" 2>/dev/null || true
cp -a "$HOME/clashctl/resources/profiles" "$HOME/clashctl-backup/profiles" 2>/dev/null || true
cp -a "$HOME/clashctl/resources/config.yaml" "$HOME/clashctl-backup/config.yaml" 2>/dev/null || true
cp -a "$HOME/clashctl/resources/runtime.yaml" "$HOME/clashctl-backup/runtime.yaml" 2>/dev/null || true
```

重装后按新版布局恢复。下面命令优先恢复新版 `config/` 目录；旧 `resources/` 单文件只在目标配置不存在时补齐，避免用旧副本覆盖较新的 `config/` 配置：

```bash
mkdir -p "$HOME/clashctl/config" "$HOME/clashctl/resources"

if [ -d "$HOME/clashctl-backup/config" ]; then
  cp -a "$HOME/clashctl-backup/config/." "$HOME/clashctl/config/"
fi

[ -e "$HOME/clashctl/config/mixin.yaml" ] || cp -a "$HOME/clashctl-backup/mixin.yaml" "$HOME/clashctl/config/mixin.yaml" 2>/dev/null || true
[ -e "$HOME/clashctl/config/clashctl.yaml" ] || cp -a "$HOME/clashctl-backup/clashctl.yaml" "$HOME/clashctl/config/clashctl.yaml" 2>/dev/null || true
[ -e "$HOME/clashctl/config/subscriptions.yaml" ] || cp -a "$HOME/clashctl-backup/profiles.yaml" "$HOME/clashctl/config/subscriptions.yaml" 2>/dev/null || true

mkdir -p "$HOME/clashctl/resources/profiles"
if [ -d "$HOME/clashctl-backup/profiles" ]; then
  cp -a "$HOME/clashctl-backup/profiles/." "$HOME/clashctl/resources/profiles/"
fi

[ -e "$HOME/clashctl/resources/config.yaml" ] || cp -a "$HOME/clashctl-backup/config.yaml" "$HOME/clashctl/resources/config.yaml" 2>/dev/null || true
[ -e "$HOME/clashctl/resources/runtime.yaml" ] || cp -a "$HOME/clashctl-backup/runtime.yaml" "$HOME/clashctl/resources/runtime.yaml" 2>/dev/null || true
```

备份里的 `.env` 不建议直接覆盖新安装生成的 `.env`。它主要是安装前默认值和旧版本兼容入口；需要保留下载代理、固定版本等本机字段时，建议用编辑器或 `diff -u "$HOME/clashctl/.env" "$HOME/clashctl-backup/.env"` 手工合并。

恢复后执行：

```bash
source "$HOME/clashctl/scripts/cmd/clashctl.sh"
clashmixin -m
clashstatus --all
```

## 关于旧 `.git`

默认安装目录 `~/clashctl` 不是项目 git 仓库。旧版本安装目录如果已经在根目录带有 `.git`，通常是历史全量复制遗留。确认没有把它当作个人配置仓库后，可以手工删除：

```bash
rm -rf "$HOME/clashctl/.git"
```

不建议在安装目录根启用 git 管理配置。该目录包含脚本、二进制、订阅展开结果、运行时配置、日志和 pid 状态。真正适合版本管理的是 `config/` 下的源配置，详细说明见 [配置版本管理](config-versioning.md)。

## 迁移后的心智变化

- 默认仍然是 tmux 用户态，不需要 sudo。
- `config/mixin.yaml` 是参与 mihomo / clash 运行时合并的源配置。
- `config/clashctl.yaml` 是 `clashctl` 自己使用的 sidecar 配置。
- `config/subscriptions.yaml` 记录订阅索引，订阅展开后的 profile 文件仍在 `resources/profiles/`。
- `resources/runtime.yaml` 是合并后生成的运行时配置，不建议手工维护。
- Tun 不属于 no-sudo 路线，需要注册 systemd 服务并执行 `clashrestart --mode systemd`。

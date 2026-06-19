# 手工端到端检查清单

本文记录真实机器上验证运行托管模式的建议步骤。自动化测试默认不执行这些步骤，因为它们会启动或停止真实 `mihomo` / `clash` 进程，并可能影响当前用户正在使用的代理环境。

## 自动化测试覆盖范围

当前仓库测试主要覆盖以下内容：

- 静态检查：确认脚本里没有残留运行时替换占位符、危险的宽泛进程匹配、无损更新覆盖清单偏移。
- 假环境行为测试：通过临时目录、桩函数和假命令验证 `clashon --mode ...`、`clashrestart --mode ...`、`clashoff`、`clashstatus --all`、`clashtun on/off` 的分支逻辑。
- 无损更新测试：确认 `update.sh` 只刷新脚本和项目资产，不覆盖 `.env`、`resources/mixin.yaml`、`resources/clashctl.yaml`、订阅 profiles、日志和 pid 状态。

这些测试不会：

- 启动真实内核。
- 停止当前正在运行的代理进程。
- 修改真实系统代理变量。
- 注册或修改真实 systemd 服务。

## 执行前检查

在共享机上做手工端到端检查前，先确认当前代理是否正在服务其他工作：

```bash
clashstatus --all
pgrep -af 'mihomo|clash'
```

如果当前安装目录正在承担日常代理，建议另选一个临时安装目录，并使用测试订阅或最小配置：

```bash
CLASH_BASE_DIR="$HOME/experiment/clashctl-e2e" bash install.sh --init tmux
```

## 用户态托管切换

验证 `tmux` 与 `nohup` 可以顺序切换：

```bash
clashon --mode tmux
clashstatus --all
clashoff

clashon --mode nohup
clashstatus --all
clashoff
```

验证已有模式运行时，直接启动另一个模式会被拒绝：

```bash
clashon --mode tmux
clashon --mode nohup
clashrestart --mode nohup
clashstatus --all
clashoff
```

预期结果：

- 第二条 `clashon --mode nohup` 拒绝，并提示使用 `clashrestart --mode nohup`。
- `clashrestart --mode nohup` 会先停掉当前活跃模式，再用 `nohup` 启动。
- `clashoff` 默认只关闭当前活跃模式。

## systemd 与 Tun

只在明确具备 sudo/root 权限且允许注册系统服务的机器上验证：

```bash
sudo bash install.sh --init systemd
clashrestart --mode systemd
clashstatus --all
clashtun on
clashtun status
clashtun off
clashoff
```

预期结果：

- 未注册 systemd 服务时，`clashon --mode systemd` 会明确失败。
- 当前活跃模式不是 `systemd` 时，`clashtun on` 会拒绝，并提示先执行 `clashrestart --mode systemd`。
- `clashtun` 不会静默切换托管模式。

## 无损项目更新

在源码仓库 pull 新版本后，从源码目录执行：

```bash
bash update.sh --target "$HOME/experiment/clashctl-e2e"
```

更新后检查用户配置仍然保留：

```bash
test -f "$HOME/experiment/clashctl-e2e/resources/mixin.yaml"
test -f "$HOME/experiment/clashctl-e2e/resources/clashctl.yaml"
test -d "$HOME/experiment/clashctl-e2e/resources/profiles"
clashstatus --all
```

预期结果：

- 更新不会启动或停止内核。
- 更新不会改订阅、mixin、sidecar 配置、运行时端口、日志和 pid 状态。
- 更新只刷新脚本、README、docs、tests 等项目资产。

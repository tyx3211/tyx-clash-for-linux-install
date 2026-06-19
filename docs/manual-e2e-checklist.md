# 手工端到端检查清单

本文记录真实机器上验证运行托管模式的建议步骤。自动化测试默认不执行这些步骤，因为它们会启动或停止真实 `mihomo` / `clash` 进程，并可能影响当前用户正在使用的代理环境。

## 自动化测试覆盖范围

当前仓库测试主要覆盖以下内容：

- 静态检查：确认脚本里没有残留运行时替换占位符、危险的宽泛进程匹配、无损更新覆盖清单偏移。
- 假环境行为测试：通过临时目录、桩函数和假命令验证 `clashon --mode ...`、`clashrestart --mode ...`、`clashoff`、`clashstatus --all`、`clashtun on/off` 的分支逻辑。
- 无损更新测试：确认 `update.sh` 只刷新脚本和项目资产，不覆盖 `config/`、`resources/install-state.yaml`、订阅 profiles、日志和 pid 状态。

这些测试不会：

- 启动真实内核。
- 停止当前正在运行的代理进程。
- 修改真实系统代理变量。
- 注册或修改真实 systemd 服务。

## 执行前检查

在共享机上做手工端到端检查前，先确认当前 shell 和系统里可能存在的代理进程。下面命令只读，不会启动或停止服务：

```bash
type -a clashctl clashon clashoff || true
env | grep -i -E '^(http|https|all|no)_proxy=' || true
tmux ls 2>/dev/null | grep clash || true
pgrep -af '[/](mihomo|clash)( |$)' || true
systemctl cat mihomo clash 2>/dev/null || true
ss -ltnp 2>/dev/null | grep -E ':(7890|7891|9090|23571)\b' || true
```

如果当前安装目录正在承担日常代理，请另选一个临时安装目录。共享机上默认只做 `tmux` / `nohup` 用户态 E2E，不做 systemd/Tun E2E。这样可以验证新代码路径，同时不碰日常使用中的 `~/clashctl` 和当前正在运行的 mihomo / clash。

准备隔离安装目录：

```bash
export E2E_DIR="$HOME/experiment/clashctl-e2e-$(date +%Y%m%d%H%M%S)"
test ! -e "$E2E_DIR"
```

安装时不要写 shell rc；订阅仍正常导入，便于后续真实启动内核：

```bash
read -rsp "SUB_URL: " SUB_URL
echo

CLASH_BASE_DIR="$E2E_DIR" \
CLASHCTL_NO_RC=1 \
bash install.sh --init tmux "$SUB_URL"

unset SUB_URL
```

进入隔离子 shell，并显式加载测试目录里的 `clashctl`：

```bash
bash --noprofile --norc
. "$E2E_DIR/scripts/cmd/clashctl.sh"
printf 'CLASH_BASE_DIR=%s\n' "$CLASH_BASE_DIR"
```

确认输出的 `CLASH_BASE_DIR` 必须等于 `$E2E_DIR`。如果不是，停止测试。

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

关闭后检查测试目录没有残留托管进程：

```bash
pgrep -af "$E2E_DIR" || true
test ! -s "$E2E_DIR/resources/mihomo.pid"
```

预期结果：

- 第二条 `clashon --mode nohup` 拒绝，并提示使用 `clashrestart --mode nohup`。
- `clashrestart --mode nohup` 会先停掉当前活跃模式，再用 `nohup` 启动。
- `clashoff` 默认只关闭当前活跃模式。

如果还要继续验证无损项目更新，先不要删除 `$E2E_DIR`。完成全部 E2E 后，按本文末尾的清理步骤删除测试安装。

## systemd 与 Tun 高危可选项

只在专用机器上验证 systemd/Tun。共享机默认跳过这一段，因为 systemd 服务名是固定的 `mihomo.service` 或 `clash.service`，可能覆盖同名日常服务。

执行前必须确认同名服务不存在，或确认它已经属于本次测试安装：

```bash
systemctl cat mihomo clash 2>/dev/null || true
```

确认后使用单独的新目录执行，不要复用前面已经安装过的 `$E2E_DIR`：

```bash
export E2E_SYSTEMD_DIR="$HOME/experiment/clashctl-e2e-systemd-$(date +%Y%m%d%H%M%S)"
read -rsp "SUB_URL: " SUB_URL
echo

sudo env CLASH_BASE_DIR="$E2E_SYSTEMD_DIR" CLASHCTL_NO_RC=1 bash install.sh --init systemd "$SUB_URL"
unset SUB_URL

systemctl cat mihomo 2>/dev/null | grep -F "$E2E_SYSTEMD_DIR"

. "$E2E_SYSTEMD_DIR/scripts/cmd/clashctl.sh"
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

如果执行了 systemd/Tun 可选项，验证完成后单独清理该安装：

```bash
sudo bash "$E2E_SYSTEMD_DIR/uninstall.sh"
systemctl cat mihomo clash 2>/dev/null || true
pgrep -af "$E2E_SYSTEMD_DIR" || true
rm -rf "$E2E_SYSTEMD_DIR"
```

## 无损项目更新

在源码仓库 pull 新版本后，从源码目录执行：

```bash
bash update.sh --target "$E2E_DIR"
```

更新后检查用户配置仍然保留：

```bash
. "$E2E_DIR/scripts/cmd/clashctl.sh"
test -f "$E2E_DIR/config/mixin.yaml"
test -f "$E2E_DIR/config/clashctl.yaml"
test -f "$E2E_DIR/config/subscriptions.yaml"
test -f "$E2E_DIR/resources/install-state.yaml"
test -d "$E2E_DIR/resources/profiles"
clashstatus --all
```

预期结果：

- 更新不会启动或停止内核。
- 更新不会改订阅、mixin、sidecar 配置、运行时端口、日志和 pid 状态。
- 更新只刷新脚本、README、docs、tests 等项目资产。

## 清理测试安装

完成用户态 E2E 和无损更新验证后，清理测试目录：

```bash
clashoff || true
exit
pgrep -af "$E2E_DIR" || true
rm -rf "$E2E_DIR"
```

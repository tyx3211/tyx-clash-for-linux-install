# Shell 代码精简重构规格

本文档用于约束后续多轮 Shell 精简工作。目标不是为了减少行数而删除安全逻辑，而是在不改变现有用户行为的前提下，把重复的、容易漂移的、安全敏感的逻辑收敛到更清晰的边界内。

## 背景

当前项目已经从单一 nosudo tmux 路线扩展为同时支持 `tmux`、`nohup`、`systemd` 的运行时托管模型，并补充了无损更新、旧版迁移、配置版本管理、Tun 限制、代理副作用解耦等能力。

这些能力带来了必要复杂度：

- 需要同时处理安装、迁移、更新、卸载、运行时控制。
- 需要保护用户配置，不覆盖 `config/`、订阅、mixin、sidecar 和运行状态。
- 需要兼容旧版目录布局，并避免误删、符号链接穿透、归档路径穿透。
- 需要在共享机 no-sudo 场景保留 tmux 用户态链路，同时支持 systemd sudo + Tun。

但审计也确认了一些真实可精简点：

- `.env` / 路径展开 / 白名单解析重复散落在多个入口。
- 运行时代理端口读取有重复语义，失败处理不一致。
- 安装期 `scripts/preflight.sh` 文件边界偏宽。
- 文件备份、原子替换、恢复逻辑有低层样板重复。
- 少量 Bash 变量作用域和函数泄漏问题可以顺手修掉。

## 目标

1. 收敛安全敏感重复逻辑。
2. 降低后续修改同一规则时漏改多个文件的概率。
3. 保持当前已验证行为不变，特别是运行模式、迁移、无损更新、代理副作用隔离。
4. 保持 Bash 代码可读，不为了抽象而抽象。
5. 每一批改动都能独立测试、独立提交、独立回滚。

## 非目标

本轮不做以下事情：

- 不改成 Bun/TypeScript、Rust 或 Go。
- 不改变 `clashon`、`clashoff`、`clashrestart`、`clashstatus` 的命令语义。
- 不改变 `tmux`、`nohup`、`systemd` 三种 adapter 的用户可见行为。
- 不删除旧版迁移安全检查。
- 不删除 update 的符号链接拒绝、归档安全检查和回滚机制。
- 不为了追求行数减少而合并语义不同的业务流程。
- 不把 `service-runtime.sh` 强行拆成过细文件；除非后续确实继续增长或增加第四种托管模式。

## 重构边界

### 必须保留的复杂度

以下逻辑虽然看起来啰嗦，但属于安全边界或可靠性边界，不应为了精简而删除：

- 安装路径和删除路径的二次校验。
- 旧版迁移前置拒绝和迁移计划检查。
- update 的符号链接拒绝、备份、失败回滚。
- 运行时状态以真实 adapter 探测为准，状态文件只作为线索。
- `clashoff`、`clashrestart`、`clashproxy`、`clashtun` 之间的副作用隔离。
- Tun 只允许在 systemd 托管模式下操作。

### 应该优先收敛的重复

1. `path-env` 模块

   新增 `scripts/lib/path-env.sh`，集中处理：

   - `~` 和 `$HOME` 路径展开。
   - `.env` 单值读取。
   - 允许读取的键名白名单。
   - 对路径型键和值型键使用一致的处理规则。

   替换对象：

   - `update.sh`
   - `migrate.sh`
   - `uninstall.sh`
   - `scripts/cmd/common.sh`
   - `scripts/lib/install-state.sh`

2. `runtime ports` 模块

   新增或扩展运行时 helper，集中读取：

   - `mixed-port`
   - `port`
   - `socks-port`
   - `external-controller`

   读取失败时必须明确返回错误，不允许静默落到默认端口后继续设置当前 shell 代理变量。

3. 小范围 Bash 作用域修复

   - 修复 `scripts/lib/subscription.sh` 中未声明 `local` 的变量。
   - 移出 `scripts/preflight.sh` 内部定义后会泄漏到全局的 helper 函数。

4. `preflight` 模块拆分

   在前几批稳定后，再拆 `scripts/preflight.sh`。推荐边界：

   - `scripts/install/args.sh`
   - `scripts/install/downloads.sh`
   - `scripts/install/archive-safe.sh`
   - `scripts/install/service-render.sh`
   - `scripts/install/rc.sh`

   拆分目标是清晰职责，不要求显著减少总代码行数。

5. 文件原子操作 helper

   如果后续继续触碰配置合并、订阅更新、Tun 配置、update/migrate 回滚，再抽：

   - 备份文件。
   - 从临时文件原子替换目标文件。
   - 失败时恢复目标文件。

   不在第一批强行抽象，因为各业务回滚语义不同。

## 验收标准

每一批改动至少满足：

1. `bash -n` 覆盖所有 Shell 文件。
2. 全量 Bash 测试通过。
3. `git diff --check` 通过。
4. 对被重构的边界新增或更新回归测试。
5. 不改变 README 和 docs 中已承诺的用户命令语义。
6. 不新增 `source .env` 或等价的执行式配置读取。
7. 不让 `clashctl on/off/restart/tun/mixin/sub/update-self/migrate` 顺手改变不相关的代理变量或运行模式。

推荐验证命令：

```bash
bash -n install.sh update.sh migrate.sh uninstall.sh scripts/cmd/*.sh scripts/lib/*.sh scripts/preflight.sh tests/*.bash tests/lib/*.bash
for t in tests/test_*.bash; do bash "$t"; done
git diff --check
```

## 上下文压缩恢复协议

如果后续上下文被压缩，继续本目标前先执行：

1. 重新阅读全局 `AGENTS.md` 和项目级 `AGENTS.md`；如果项目没有 `AGENTS.md`，明确记录没有发现。
2. 重新阅读本文档。
3. 重新阅读 `docs/shell-refactor-plan.md`。
4. 执行 `git status --short`，确认工作区状态。
5. 查看最近提交和当前分支。
6. 只从计划中的下一批继续，不从聊天记忆猜测方向。

## 提交流程

每批建议一个提交：

- 第 1 批：`refactor: centralize env and path parsing`
- 第 2 批：`refactor: centralize runtime port parsing`
- 第 3 批：`refactor: tighten shell helper scopes`
- 第 4 批：`refactor: split install preflight modules`

如果某批发现收益低于风险，应保留文档说明并停止该批，不为了完成计划强行改动。

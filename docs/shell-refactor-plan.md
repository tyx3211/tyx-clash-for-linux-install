# Shell 代码精简重构实施计划

> **执行要求：** 每个任务按顺序推进。每批改动都先补测试或定位现有测试，再改实现，最后运行指定验证。若发现计划与代码事实不符，先更新本文档再继续。

**目标：** 在不改变用户可见行为的前提下，收敛重复的 Shell 辅助逻辑，让项目更容易审计、维护和继续迁移到长期架构。

**架构：** 先处理局部、高收益、低风险的重复逻辑，再处理安装期文件拆分。运行时 adapter 状态机暂时保持集中，避免把刚稳定的 tmux/nohup/systemd 行为拆散。

**技术栈：** Bash、Fish wrapper、YAML、现有 Bash 测试套件。

---

## 全局约束

- 不改变命令语义。
- 不删除安全检查，只收敛重复实现。
- 不新增执行式 `.env` 读取。
- 不让服务启停、Tun、mixin、订阅更新隐式改变代理变量。
- 不把一个清晰文件拆成一函数一文件。
- 每批完成后提交，提交前必须通过验证命令。

## Task 1: 集中 `.env` 与路径解析

**目的：** 把 `.env` 单值读取、键名白名单、`~` / `$HOME` 展开收敛到一个模块，避免 update/migrate/uninstall/common/install-state 继续各写一套。

**文件：**

- Create: `scripts/lib/path-env.sh`
- Modify: `update.sh`
- Modify: `migrate.sh`
- Modify: `uninstall.sh`
- Modify: `scripts/cmd/common.sh`
- Modify: `scripts/lib/install-state.sh`
- Test: `tests/test_path_env.bash`
- Test: `tests/test_common_safety.bash`
- Test: `tests/test_migrate.bash`
- Test: `tests/test_update_self.bash`

**接口设计：**

```bash
_path_env_expand_path VALUE
_path_env_key_allowed KEY
_path_env_read_value FILE KEY
_path_env_read_value_any FILE KEY...
_path_env_read_path_value FILE KEY
```

**步骤：**

- [x] 读取现有 `_expand_path` 和 `_read_env_value` 的所有实现，列出差异。
- [x] 在 `tests/test_common_safety.bash` 或新增测试中覆盖：拒绝未白名单键、支持 `~/x`、支持 `$HOME/x`、不执行命令替换、不改变 `PATH`。
- [x] 创建 `scripts/lib/path-env.sh`，只放纯 helper，不读取全局状态。
- [x] 将 `scripts/lib/install-state.sh` 改为 source 新 helper。
- [x] 将 `scripts/cmd/common.sh` 改为 source 新 helper。
- [x] 将 `update.sh`、`migrate.sh`、`uninstall.sh` 改为 source 新 helper；如果脚本可能在旧安装目录中运行，先用相对自身路径寻找 helper。
- [x] 删除重复的本地 `_expand_path` / `_read_env_value` 实现。
- [x] 运行本任务测试：

```bash
bash tests/test_path_env.bash
bash tests/test_common_safety.bash
bash tests/test_migrate.bash
bash tests/test_update_self.bash
```

- [x] 运行全量验证：

```bash
bash -n install.sh update.sh migrate.sh uninstall.sh scripts/cmd/*.sh scripts/lib/*.sh scripts/preflight.sh tests/*.bash tests/lib/*.bash
for t in tests/test_*.bash; do bash "$t"; done
git diff --check
```

- [x] 提交：

```bash
git add scripts tests
git commit -m "refactor: centralize env and path parsing"
```

## Task 2: 集中运行时端口读取

**目的：** 统一读取 `runtime.yaml` 中的代理端口和控制端口，避免 `yq` 失败时静默回落默认值。

**文件：**

- Create or Modify: `scripts/lib/runtime-config.sh`
- Modify: `scripts/lib/service-runtime.sh`
- Modify: `scripts/lib/proxy.sh`
- Modify: `scripts/cmd/common.sh`
- Test: `tests/test_runtime_config.bash`
- Test: `tests/test_runtime_modes.bash`
- Test: `tests/test_clashctl_behaviour.bash`

**接口设计：**

```bash
_runtime_config_read_ports RUNTIME_FILE
_runtime_config_http_port RUNTIME_FILE
_runtime_config_socks_port RUNTIME_FILE
_runtime_config_controller RUNTIME_FILE
```

返回值要求：

- `yq` 不存在、读取失败、YAML 不可读时返回非零。
- 缺少字段但 YAML 可读时才使用项目默认值。
- 调用方必须把读取失败转成明确错误信息。

**步骤：**

- [x] 为 `runtime.yaml` 不存在、`yq` 失败、字段缺失、字段存在分别补测试。
- [x] 新增或改造 `runtime-config` helper。
- [x] 替换 `scripts/lib/proxy.sh` 的 `_get_runtime_proxy_ports`。
- [x] 替换 `scripts/lib/service-runtime.sh` 的端口探测读取逻辑。
- [x] 确认 `clashproxy on` 在读取失败时不导出默认端口变量。
- [x] 运行本任务测试：

```bash
bash tests/test_runtime_config.bash
bash tests/test_runtime_modes.bash
bash tests/test_clashctl_behaviour.bash
```

- [x] 运行全量验证并提交：

```bash
bash -n install.sh update.sh migrate.sh uninstall.sh scripts/cmd/*.sh scripts/lib/*.sh scripts/preflight.sh tests/*.bash tests/lib/*.bash
for t in tests/test_*.bash; do bash "$t"; done
git diff --check
git add scripts tests
git commit -m "refactor: centralize runtime port parsing"
```

## Task 3: 修复小范围 Bash 作用域问题

**目的：** 清理不必要的全局变量污染和函数泄漏。

**文件：**

- Modify: `scripts/lib/subscription.sh`
- Modify: `scripts/preflight.sh`
- Test: `tests/test_clashctl_behaviour.bash`
- Test: `tests/test_rendered_install.bash`

**步骤：**

- [x] 将 `scripts/lib/subscription.sh` 中的 `use=` 改为局部变量。
- [x] 将 `_escape_sed_repl` 从 `_install_service` 内移动到顶层，并改名为安装期前缀，例如 `_preflight_escape_sed_repl`。
- [x] 确认替换后没有旧函数名残留。
- [x] 运行：

```bash
rg -n "^[[:space:]]*use=|_escape_sed_repl" scripts
bash tests/test_clashctl_behaviour.bash
bash tests/test_rendered_install.bash
```

- [x] 运行全量验证并提交：

```bash
bash -n install.sh update.sh migrate.sh uninstall.sh scripts/cmd/*.sh scripts/lib/*.sh scripts/preflight.sh tests/*.bash tests/lib/*.bash
for t in tests/test_*.bash; do bash "$t"; done
git diff --check
git add scripts tests
git commit -m "refactor: tighten shell helper scopes"
```

## Task 4: 拆分安装期 preflight

**目的：** 降低 `scripts/preflight.sh` 的文件宽度，让安装参数、下载、归档安全、服务渲染、shell rc 写入各自有清晰边界。

**文件：**

- Deferred: `scripts/install/args.sh`
- Deferred: `scripts/install/downloads.sh`
- Create: `scripts/install/archive-safe.sh`
- Create: `scripts/install/service-render.sh`
- Create: `scripts/install/rc.sh`
- Modify: `scripts/preflight.sh`
- Test: `tests/test_preflight_split.bash`
- Test: `tests/test_rendered_install.bash`
- Test: `tests/test_update_self.bash`

**拆分原则：**

- `scripts/preflight.sh` 保留总控流程和少量全局安装变量。
- `args.sh` 只处理参数、安装路径、模式选择。
- `downloads.sh` 只处理下载和依赖归档。
- `archive-safe.sh` 只处理 tar/zip 成员安全校验。
- `service-render.sh` 只处理 service adapter 模板渲染。
- `rc.sh` 只处理 shell rc 片段写入与撤销。

**步骤：**

- [x] 先移动归档安全函数到 `scripts/install/archive-safe.sh`，替换 `preflight.sh` 调用。
- [x] 运行安装渲染测试，确认归档安全测试仍覆盖。
- [x] 移动 service 渲染函数到 `scripts/install/service-render.sh`。
- [x] 运行安装渲染测试。
- [x] 移动 shell rc 相关函数到 `scripts/install/rc.sh`。
- [x] 运行安装渲染测试。
- [x] 再评估是否移动下载和参数解析；当前结论是暂缓，以避免暴露更多隐式全局状态。
- [x] 运行全量验证并提交：

```bash
bash tests/test_preflight_split.bash
bash -n install.sh update.sh migrate.sh uninstall.sh scripts/cmd/*.sh scripts/lib/*.sh scripts/install/*.sh scripts/preflight.sh tests/*.bash tests/lib/*.bash
for t in tests/test_*.bash; do bash "$t"; done
git diff --check
git add scripts tests
git commit -m "refactor: split install preflight modules"
```

## Task 5: 复审是否需要 atomic file helper

**目的：** 判断文件备份、替换、恢复是否已经重复到值得抽象；如果不值得，明确记录暂缓，不强行抽。

**文件：**

- Optional Create: `scripts/lib/atomic-file.sh`
- Optional Modify: `scripts/lib/config.sh`
- Optional Modify: `scripts/lib/subscription.sh`
- Optional Modify: `scripts/lib/tun.sh`
- Optional Modify: `update.sh`
- Optional Modify: `migrate.sh`

**决策标准：**

- 如果能只抽低层文件操作，不改变业务回滚语义，则可以做。
- 如果抽象会让错误处理更绕、调用方更难读，则暂缓。
- 如果只减少少量行数但增加跨文件跳转，暂缓。

**步骤：**

- [x] 对比配置合并、订阅更新、Tun、update、migrate 的回滚语义。
- [x] 写出是否抽象的短结论，更新 `docs/shell-refactor-spec.md`。
- [x] 当前结论为暂缓抽象；只提交文档决策。

**结论：** 暂缓新增 `scripts/lib/atomic-file.sh`。这些代码块的低层文件动作相似，但业务回滚语义不同；强行抽象会让错误处理和恢复路径更隐蔽。后续只在出现多个同构的“同目录临时文件校验后替换单文件”调用点时再抽低层 helper。

## 每批复审要求

每批提交前后都需要做一次人工复审，重点看：

- 是否改变用户可见行为。
- 是否删掉必要安全边界。
- 是否让错误信息变差。
- 是否引入更多 source-time 副作用。
- 是否让文件间依赖更隐蔽。
- 是否真的减少了重复或降低了维护风险。

必要时继续派子代理审：

- 一个审安全性和可靠性。
- 一个审功能一致性、旧版兼容和文档一致性。

## 完成判定

满足以下条件后，本轮精简目标可以关闭：

- Task 1 到 Task 3 完成并提交。
- Task 4 至少完成归档安全、service 渲染、shell rc 三个边界中的两个，或者有明确理由暂缓。
- Task 5 给出执行或暂缓结论。
- 全量测试通过。
- README 或相关 docs 不需要额外迁移说明更新，或者已同步更新。
- `git status --short` 干净。

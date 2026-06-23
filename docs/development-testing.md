# 开发测试说明

自动化测试默认把临时目录建在 `/tmp/tyx/clash-test-run.*` 下，并在测试进程退出时删除整棵运行目录。`test_update_self.bash` 会复制源码树，单次测试会短暂占用较多磁盘；正常退出后不应留下 `clash-test-run.*` 或旧式 `clash-*` 目录。

测试 helper 会为当前测试进程创建 `sandbox-install` 安装根，并预置 `CLASH_BASE_DIR`、`KERNEL_NAME`、`INIT_TYPE` 和 `CLASH_INSTALLED_INIT_TYPE` 这几个 shell 变量。这样 source `scripts/cmd/clashctl.sh` 的测试默认只会看到测试沙箱，不会沿用源码仓库 `.env` 里的真实安装路径，也不会把真实 `~/clashctl` 下的内核进程当成测试对象。

这几个变量只在当前测试 shell 中生效，helper 会先去掉它们的导出属性，避免调用者原本导出的真实安装路径继续传给子进程；因此 `bash install.sh`、`bash update.sh`、`bash migrate.sh` 这类子进程测试仍会走自己的参数和默认值解析。若某个用例专门验证 `.env` 或 install-state 的覆盖语义，可以在该用例子 shell 内调用 `unset_test_install_identity`，再 source 对应脚本。

需要保留失败现场时，可以显式打开。该选项会保留本次测试的整棵 `clash-test-run.*` 运行目录，无论测试成功还是失败：

```bash
TEST_KEEP_TMP=1 bash tests/test_update_self.bash
```

需要把测试临时目录放到其它位置时，可以指定运行根目录。实际测试目录会创建为 `$TEST_TMP_BASE/clash-test-run.*`：

```bash
TEST_TMP_BASE=/tmp/tyx/my-test-run bash tests/test_update_self.bash
```

资源约束：`~/experiment` 与 `/tmp/tyx` 合计不得超过 500GiB。这是共享机上的硬上限，不是测试预算；常规自动化测试应远低于该值，并在退出后自动清理到只剩少量目录元数据。任何测试资源、可重建资源和可复现资源如果短时间产生了大占用，必须在验证结束后立即清理。运行可能复制大目录的测试前，应先确认空间或指定更合适的 `TEST_TMP_BASE`。

常用全量验证：

```bash
bash -n install.sh update.sh migrate.sh uninstall.sh scripts/cmd/*.sh scripts/lib/*.sh scripts/install/*.sh scripts/preflight.sh tests/*.bash tests/lib/*.bash
for t in tests/test_*.bash; do bash "$t"; done
git diff --check
```

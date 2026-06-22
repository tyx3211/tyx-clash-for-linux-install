# 开发测试说明

自动化测试默认把临时目录建在 `/tmp/tyx/clash-test-run.*` 下，并在测试进程退出时删除整棵运行目录。`test_update_self.bash` 会复制源码树，单次测试会短暂占用较多磁盘；正常退出后不应留下 `clash-test-run.*` 或旧式 `clash-*` 目录。

需要保留失败现场时，可以显式打开：

```bash
TEST_KEEP_TMP=1 bash tests/test_update_self.bash
```

需要把测试临时目录放到其它位置时：

```bash
TEST_TMP_BASE=/tmp/tyx/my-test-run bash tests/test_update_self.bash
```

资源约束：`~/experiment` 与 `/tmp/tyx` 合计不应超过 500GiB。测试资源、可重建资源和可复现资源如果短时间超过该限制，必须在验证结束后立即清理。

常用全量验证：

```bash
bash -n install.sh update.sh migrate.sh uninstall.sh scripts/cmd/*.sh scripts/lib/*.sh scripts/install/*.sh scripts/preflight.sh tests/*.bash tests/lib/*.bash
for t in tests/test_*.bash; do bash "$t"; done
git diff --check
```

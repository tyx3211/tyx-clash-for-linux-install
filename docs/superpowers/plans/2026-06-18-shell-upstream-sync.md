# Safe Shell Upstream Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync the useful upstream shell mechanisms while preserving the no-sudo tmux user-mode path.

**Architecture:** Keep `scripts/cmd/clashctl.sh` as the user-facing command surface and `scripts/cmd/common.sh` as shared support code. Add small shell tests under `tests/` that source functions in isolated temporary homes and stub external commands instead of touching the real installation.

**Tech Stack:** Bash, yq-compatible shell calls, tmux/nohup/systemd command templates, user crontab, `bash -n` tests.

---

### Task 1: Add Shell Test Harness

**Files:**
- Create: `tests/lib/test_helpers.bash`
- Create: `tests/test_common_safety.bash`
- Create: `tests/test_clashctl_behaviour.bash`

- [ ] **Step 1: Write tests for current unsafe behaviour**
  - Test `_get_random_port` terminates after bounded retries by stubbing `_is_port_used`.
  - Test `_download_config` rejects empty, HTML, and node-less subscription files using stubbed kernel/yq calls.
  - Test crontab cleanup only removes the tagged clashctl job.
  - Test `_detect_proxy_port` does not rely on `eval`.

- [ ] **Step 2: Run tests and verify failure**

Run:
```bash
bash tests/test_common_safety.bash
bash tests/test_clashctl_behaviour.bash
```

Expected: at least the new safety tests fail on the current implementation.

### Task 2: Port Upstream Subscription Safety

**Files:**
- Modify: `scripts/cmd/common.sh`

- [ ] **Step 1: Implement `_normalize_sub_config`, `_is_html_response`, `_is_native_yaml_config`, and `_valid_sub_nodes`**
- [ ] **Step 2: Update `_download_config` to normalize, reject HTML, validate native config, and fallback to converter**
- [ ] **Step 3: Re-run tests and verify subscription safety passes**

### Task 3: Remove Shell Injection and Process-Matching Hazards

**Files:**
- Modify: `scripts/cmd/common.sh`
- Modify: `scripts/cmd/clashctl.sh`
- Modify: `scripts/preflight.sh`

- [ ] **Step 1: Replace `eval` in `_detect_proxy_port` with explicit tuple parsing**
- [ ] **Step 2: Replace broad `pkill -f` fallback with tmux-session-first stop and quoted exact binary matching where fallback is unavoidable**
- [ ] **Step 3: Add bounded retry logic for random port allocation**
- [ ] **Step 4: Re-run tests and syntax checks**

### Task 4: Make Crontab and RC Mutations Tagged and Reversible

**Files:**
- Modify: `scripts/cmd/common.sh`
- Modify: `scripts/cmd/clashctl.sh`
- Modify: `scripts/preflight.sh`
- Modify: `uninstall.sh`

- [ ] **Step 1: Add a stable cron tag variable**
- [ ] **Step 2: Update `clashsub update --auto` to write only tagged jobs**
- [ ] **Step 3: Update uninstall to remove only tagged jobs**
- [ ] **Step 4: Preserve the existing START/END shell rc block strategy**

### Task 5: Add Service Mode Configuration Without Breaking tmux Default

**Files:**
- Modify: `.env`
- Modify: `install.sh`
- Modify: `scripts/preflight.sh`
- Modify: `scripts/cmd/clashctl.sh`
- Modify: `README.md`

- [ ] **Step 1: Add `INIT_TYPE=tmux` as default and parse `--init <tmux|nohup|systemd>` / `--init=<...>` at install time**
- [ ] **Step 2: Keep tmux no-sudo as default path**
- [ ] **Step 3: Add systemd sudo mode only when explicitly selected**
- [ ] **Step 4: Enable TUN command only in sudo-capable mode; keep no-sudo mode disabled with a clear message**

### Task 6: Verify Shell Line and Prepare Bun/TS Branch

**Files:**
- Modify as needed after verification only.

- [ ] **Step 1: Run all shell tests**
- [ ] **Step 2: Run `bash -n` over every shell file**
- [ ] **Step 3: Review `git diff` for unrelated churn**
- [ ] **Step 4: Only after shell verification, create an experimental branch for Bun canary + TypeScript**

---

## Self-Review

- Spec coverage: covers upstream safety sync, no-sudo tmux preservation, explicit systemd/sudo mode, and later Bun/TS experiment.
- Placeholder scan: no implementation placeholder is intended for code generation; tasks are scoped by exact files and behaviours.
- Scope check: shell sync and Bun/TS branch are sequential; Bun/TS work starts only after shell verification.

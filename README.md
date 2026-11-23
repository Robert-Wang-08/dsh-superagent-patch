# dsh-superagent-patch

dsh-superagent 的**适配补丁与上游同步脚本**辅助仓。不含上游源码，不是运行时依赖。

## 内容
- `patches/*.patch` — fork 相对上游的 5 个适配提交（format-patch 产物），用于存档与发 PR 回上游。这些提交已经在 fork 历史里，本地打包不再重复套用。
- `patches/overlay/*.patch` — 尚未进入 fork 的本机覆盖。fork 检出保持干净，只在生成 `lib/` 时临时套上。
- `scripts/upgrade.ps1` — 上游升级后的本地同步脚本（候选分支 + clean-build + 测试闸门）。
- `scripts/build-local.ps1` — 套上 overlay、执行 `pnpm build`、再还原 fork 跟踪文件。
- `upstream.json` — 上游/fork 指针与适配提交清单。

## 适配提交
| 补丁 | 提交 | 内容 |
| --- | --- | --- |
| 0001 | c0b7df4 | fix(feishu) 直接回复不进 topic、避免 mention 展开 |
| 0002 | c10753c | fix(windows) 去掉 POSIX env 前缀跑 worker CLI |
| 0003 | 8daf4b2 | fix(windows) 跨盘符绝对 prompt 路径、Windows 跑测试 |
| 0004 | 5f294cd | fix(windows) PATHEXT 解析 PATH 命令 |
| 0005 | 822e634 | fix(worker) worker preset 支持子模型选择 |

> 父仓当前 gitlink 是 `aa575d5`，0001–0005 都已在这条历史上。fork 的 `origin/main` 是 `18822dd`，比 gitlink 更新；部署用的是父仓钉住的子模块，不是旁边另一份检出。

## 本机覆盖（不改 fork）
| 补丁 | 内容 |
| --- | --- |
| overlay/0006 | orchestrator 工具白名单只保留本机真实存在的工具。`tools.restrict()` 遇到不存在的 `bash` 会让整个插件激活失败。 |

fork 源码不提交这处改动。生成运行包：

```
pwsh -File scripts/build-local.ps1
```

脚本要求子模块工作区没有未提交的跟踪改动。它临时改 `src/`，构建完成后还原。`lib/` 在 `.gitignore` 里，profile 的 `link:` 直接用这份 `lib/`。重新 `pnpm build` 而不走这个脚本，会把 0006 从包里盖掉。

## 变更说明（2026-11-23）

fork 检出里出现过一处未提交的 `src/app/sessions.ts`：orchestrator 白名单从「Windows 去掉 bash」改成「只保留本机真实存在的工具」。按约定，这处改动不进入 fork。

- 新增 `patches/overlay/0006-orchestrator-tools-existing-only.patch` 保存该差异。
- 新增 `scripts/build-local.ps1`：临时套上 overlay，`pnpm build`，再还原 fork 跟踪文件。
- `upstream.json` 用 `local_overlays` 登记这条覆盖，和已经在 fork 历史里的 0001–0005 分开。
- 本机已用该脚本重新生成 `lib/`，并重启 3082。fork 子模块仍停在父仓钉住的 `aa575d5`，没有新的源码提交。

## 用法
```
# 1) 只查上游是否领先（默认 DryRun，只读）
pwsh -File scripts/upgrade.ps1

# 2) 执行升级（候选分支 + clean-build + 测试闸门 + push fork）
pwsh -File scripts/upgrade.ps1 -Apply

# 3) 升级并回写父仓 gitlink（跨设备生效）
pwsh -File scripts/upgrade.ps1 -Apply -BumpParent
```

前置：升级前先停服务（`dsh-superagent-service.ps1 stop`），避免 3082 服务占用 lib/；完成后重启。需本机安装 pnpm。

## 相关运营脚本（仍在 dsh 根目录，勿移动）
`dsh-superagent-service.ps1` / `dsh-superagent-profile-sync.ps1` / `dsh-superagent-lark-bot.ps1` /
`dsh-sa-local-*.ps1` / `launch-superagent.cmd` 被 `dsh-default-startup.ps1`、`dsh-ops-gate.ps1` 等引用，
保持原位；本仓只做补丁与同步，不做运营脚本。

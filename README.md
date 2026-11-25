# dsh-superagent-patch

dsh-superagent 的**适配补丁与上游同步脚本**辅助仓。不含上游源码，不是运行时依赖。父仓是 `dsh-PatchNPlugin`（原 `dsh-ynm3000`）。

## 内容
- `patches/*.patch` — fork 相对上游的 5 个适配提交（format-patch 产物），用于存档与发 PR 回上游。这些提交已经在 fork 历史里，本地打包不再重复套用。
- `patches/overlay/*.patch` — 对固定 fork 的本机覆盖。打包时临时套上，构建后还原已跟踪文件。约定见 [变更约定.md](变更约定.md)。
- `scripts/build-local.ps1` — 核对保存点、套上未吸收 overlay、执行 `pnpm build`、再还原 fork 跟踪文件。
- `scripts/check-baseline.ps1` — 只读检查换到候选提交时，archive 与 overlay 的全部本地改动是否还能落地（换基线前用）。
- `scripts/upgrade.ps1` — `-Apply` / `-BumpParent` 已停用（fork 固定）。
- `upstream.json` — 上游/fork 指针、`snapshot` 与 `overlays` 清单。

## 适配提交
| 补丁 | 提交 | 内容 |
| --- | --- | --- |
| 0001 | c0b7df4 | fix(feishu) 直接回复不进 topic、避免 mention 展开 |
| 0002 | c10753c | fix(windows) 去掉 POSIX env 前缀跑 worker CLI |
| 0003 | 8daf4b2 | fix(windows) 跨盘符绝对 prompt 路径、Windows 跑测试 |
| 0004 | 5f294cd | fix(windows) PATHEXT 解析 PATH 命令 |
| 0005 | 822e634 | fix(worker) worker preset 支持子模型选择 |

> fork 是固定版本，不再是父仓子模块。本机检出是 `D:\src\dsh-superagent`（`56bc97c`，见 `upstream.json` 的 `snapshot.commit`）。0001–0005 已在这条历史上。之后的行为变更写进本仓，不改 fork。

## 本机覆盖（不改 fork）
| id | 补丁 | absorbed_by | 内容 |
| --- | --- | --- | --- |
| orchestrator-tools-existing-only | overlay/0006 | — | orchestrator 工具白名单只保留本机真实存在的工具。`tools.restrict()` 遇到不存在的 `bash` 会让整个插件激活失败。 |
| progress-question | overlay/0007 | `23c8ef6` | 进度询问按工单进度答复。该提交已在固定版本历史上，打包时跳过。 |
| model-selector-lists | overlay/0008 | — | Eval/Executor 的模型选择器改为列出 `GET models` 目录里的全部 provider、模型和推理强度；旧 datalist 按当前值过滤，只显示已选值。 |

fork 源码不提交这些改动。生成运行包：

```
pwsh -File scripts/build-local.ps1
```

换基线前只读检查：

```
pwsh -File scripts/check-baseline.ps1 -Candidate <候选提交>
```

脚本要求固定检出没有未提交的跟踪改动，且 HEAD 等于 `snapshot.commit`。它临时改 `src/`，构建完成后还原。`lib/` 在 `.gitignore` 里，profile 的 `link:` 直接用这份 `lib/`。重新 `pnpm build` 而不走这个脚本，会把尚未进入固定版本的 overlay 从包里盖掉。

DSH 全局包的安装补丁不在本仓，由父仓子模块 `dsh-permission-compat` 负责。跨设备刷新用父仓 `dsh-deploy-latest.ps1`。

## 变更说明（2026-11-23）

fork 检出里出现过一处未提交的 `src/app/sessions.ts`：orchestrator 白名单从「Windows 去掉 bash」改成「只保留本机真实存在的工具」。按约定，这处改动不进入 fork。

- 新增 `patches/overlay/0006-orchestrator-tools-existing-only.patch` 保存该差异。
- 新增 `scripts/build-local.ps1`：临时套上 overlay，`pnpm build`，再还原 fork 跟踪文件。
- `upstream.json` 用 overlays 清单登记覆盖，和已经在 fork 历史里的 0001–0005 分开。
- 本机已用该脚本重新生成 `lib/`，并重启 3082。fork 源码没有为此新增提交。

## 变更说明（2026-11-25）

- 新增 `patches/overlay/0008-model-selector-lists.patch`（id `model-selector-lists`，基线 `56bc97c`）：Eval/Executor 的模型字段改为列出全部 provider / model / 推理强度。旧实现是自由文本 + datalist，datalist 按当前值过滤，已保存 `openai-codex` / `gpt-6.1-sol` 时看起来只有这两个选项。
- 不改 fork，不改父仓子模块指针；生效走 `scripts/build-local.ps1` + 重启 3082。

## 相关运营脚本（仍在父仓根目录，勿移动）
`dsh-superagent-service.ps1` / `dsh-superagent-profile-sync.ps1` / `dsh-superagent-lark-bot.ps1` /
`dsh-sa-local-*.ps1` / `launch-superagent.cmd` 被 `dsh-default-startup.ps1`、`dsh-ops-gate.ps1` 等引用，
保持原位；本仓只做补丁与同步，不做运营脚本。

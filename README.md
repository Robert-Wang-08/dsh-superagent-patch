# dsh-superagent-patch

dsh-superagent 的**适配补丁与上游同步脚本**辅助仓。不含上游源码，不是运行时依赖。

## 内容
- `patches/*.patch` — fork 相对上游的 5 个适配提交（format-patch 产物），用于存档与发 PR 回上游。
- `scripts/upgrade.ps1` — 上游升级后的本地同步脚本（候选分支 + clean-build + 测试闸门）。
- `upstream.json` — 上游/fork 指针与适配提交清单。

## 适配提交
| 补丁 | 提交 | 内容 |
| --- | --- | --- |
| 0001 | c0b7df4 | fix(feishu) 直接回复不进 topic、避免 mention 展开 |
| 0002 | c10753c | fix(windows) 去掉 POSIX env 前缀跑 worker CLI |
| 0003 | 8daf4b2 | fix(windows) 跨盘符绝对 prompt 路径、Windows 跑测试 |
| 0004 | 5f294cd | fix(windows) PATHEXT 解析 PATH 命令 |
| 0005 | 822e634 | fix(worker) worker preset 支持子模型选择 |

> 父仓钉的 gitlink 是 5f294cd（含 0001–0004）；0005（822e634）在 fork origin/main，
> 尚未被父仓钉入。同步时一并合入，不丢。

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

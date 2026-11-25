# 评估模型选择器：变更前后

- 基线：固定快照 `56bc97c`（本机部署当时为 `aa575d5`；该控件在两处相同）。
- 变更：`patches/overlay/0008-model-selector-lists.patch`（id `model-selector-lists`）。
- 场景：Superagent → Settings → 评估 → 研判模型；同一模型 `openai-codex / gpt-6.1-sol / low`，浅色主题，桌面宽度。

| 文件 | 内容 |
| --- | --- |
| `eval-model-picker-before.png` | 变更前：服务商 / 模型 / 推理强度是自由文本输入，suggestions 受当前值过滤。 |
| `eval-model-picker-after.png` | 变更后：三者为下拉列表，旧值仍正确显示。 |
| `eval-model-picker-after-expanded.png` | 变更后展开：列出目录中的全部 6 个 provider 及其模型。 |

截图用真实的 `ModelField` 组件和面板样式表，数据为运行中 `GET models` 的实时目录；只有组件外框是为截图搭的本地壳。实时应用本身需要进程 token 才能打开，所以没有整页截图。

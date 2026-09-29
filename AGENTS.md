# Agent 规则

- 只在 `feature/*` 工作，禁止写 `main`。
- 每个任务一个分支。
- 不读生产密钥，不合并 PR。
- 大文件放对象存储，仓库只提交 manifest。
- PR 必须由人类合并。
- 禁止 `feature/* -> feature/*` 直接合并。

## 分支命名

- Agent：`feature/<issue-id>-agent-<id>-<slug>`
- 人工：`feature/<issue-id>-<slug>`

## 允许 / 禁止

| 动作 | Agent |
|---|---|
| 从 `main` 创建 `feature/*` | ✅ 允许 |
| 在 `feature/*` 读写提交 | ✅ 允许 |
| 推送 `feature/*` 到 origin | ✅ 允许 |
| 创建 PR 到 `main` | ✅ 允许 |
| 直接 push `main` | ❌ 禁止 |
| 合并 / 关闭 PR | ❌ 禁止（由人类维护者执行） |
| 读取生产密钥 | ❌ 禁止（沙箱密钥也不行） |
| 提交权重 / 数据集 / 生成物 | ❌ 禁止（只提交 manifest） |
| 把自己加入 `main` bypass 列表 | ❌ 禁止 |

## 提交前自检

```bash
pre-commit run --all-files
pytest -q
```

## 回滚

用 revert PR，**禁止** `reset` 或 force push `main`。

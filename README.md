# SmallGitHubAigc — AIGC 工作站 Git 围栏（v0.1）

在 GitHub 仓库中落地的最小可运行 AIGC 工作站 Git 围栏。目标：让**人工和 Agent 都只在 `feature/*` 上工作**，`main` 始终稳定可发布，模型权重 / 数据集 / 生成物**永不进入 Git**。

---

## 1. 分支模型

| 分支 | 类型 | 生命周期 | 说明 |
|---|---|---|---|
| `main` | 持续型 | 永久 | 稳定、可发布，**只进 PR**，禁止直推 |
| `feature/*` | 局部型 | 短命 | 实验与开发，**合并后自动删除** |

命名约定：

- 人工：`feature/<issue-id>-<slug>`
- Agent：`feature/<issue-id>-agent-<id>-<slug>`

### 流向

- **唯一主流向：`feature/* -> main`**
- 允许：`main -> feature/*`（把主干同步回开发分支）
- **禁止：`feature/* -> feature/*` 直接合并**
- 合并方式：**squash merge**，保持线性历史
- 回滚方式：**revert PR**，绝不 `reset` / force push `main`

### 生命周期规则

- `feature/*` 超过 **72 小时无提交** → 自动提醒（`stale.yml`，PR 3 天标记 stale）
- `feature/*` 超过 **7 天无进展** → PR 自动关闭并删除分支
- **禁止存在超过 7 天的活跃 feature 分支**
- 合并后**自动删除** feature 分支（`delete_branch_on_merge=true`）

---

## 2. 角色与权限

| 角色 | `main` | `feature/*` | 生产密钥 | 合并 PR |
|---|---|---|---|---|
| 人工贡献者 | 只读 | 读写自己的 | 不可读 | 否 |
| Agent | 只读 / 不可写 | 读写自己的 | **不可读** | **否** |
| 维护者 | 合并 / 管理 | 管理 | 可读 | 是 |
| CI Bot | 按策略 | 只读 / 评论 | 沙箱密钥 | 按策略 |

**硬约束**

- 人工和 Agent 都只在 `feature/*` 工作。
- Agent 必须使用**独立 bot 身份**；Agent 不得成为仓库 admin。
- Agent **不得**出现在 `main` 分支保护 bypass 列表中。
- Agent **不读生产密钥**、**不合并 PR**；**PR 必须由人类合并**。
- 生产密钥只放在**受控 environment**，仅维护者可访问。

---

## 3. `main` 门禁

`main` 的合并必须同时满足：

- ✅ 走 **Pull Request**（禁止直推）
- ✅ **CI 全绿**，required status check 名称为 `ci`
- ✅ 分支**最新**后才能通过 CI（`strict=true`）
- ✅ **至少 1 个 approval**，且 dismiss stale reviews
- ✅ **CODEOWNERS review**（`require_code_owner_reviews=true`）
- ✅ **线性历史**（squash merge）
- ✅ `enforce_admins=true`（管理员也不能绕过）
- ✅ 禁止 force push、禁止删除、要求会话解决

> 分支保护**策略即代码**：`scripts/apply-branch-protection.sh` 可重复执行以对齐上述状态。

---

## 4. 内容边界：大文件不进 Git

**绝不提交**：模型权重、数据集、训练/推理生成物、密钥。

**只提交**：manifest、hash 校验信息、来源（source）信息。

- `models/manifest.yaml` — 模型登记表
- `datasets/manifest.yaml` — 数据集登记表

`.gitignore` 已忽略 `models/**` 与 `datasets/**`，仅白名单放行两个 manifest。`.gitattributes` 将 `*.pt / *.pth / *.safetensors / *.bin / *.png / *.jpg` 标记为 binary。

**改动 `models/` 或 `datasets/` 时必须同步更新对应 manifest**（由 CODEOWNERS + PR 模板强制人工确认）。

---

## 5. 快速开始

```bash
# 0. 前置：git、gh、python3.11、pre-commit、pytest
gh auth status

# 1. 永远从 main 切 feature 分支
git switch main && git pull --ff-only
git switch -c feature/<issue-id>-<slug>

# 2. 开发与本地自检
pre-commit install
pre-commit run --all-files
pytest -q

# 3. 提交并推送（只推 feature/*）
git add -A && git commit -m "feat: ..."
git push -u origin HEAD

# 4. 开 PR 到 main（PR 由人类 review 并 squash 合并）
gh pr create --base main --fill
```

Agent 请先阅读 [`AGENTS.md`](./AGENTS.md) 再动手。

---

## 6. 验收命令

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

git branch --show-current
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
gh api "repos/$REPO/branches/main/protection"
gh api "repos/$REPO/branches/main/protection/required_status_checks"
gh api "repos/$REPO/branches/main/protection/required_pull_request_reviews"
gh api "repos/$REPO" -q .delete_branch_on_merge

pre-commit run --all-files
pytest -q

test -f .github/CODEOWNERS
test -f .github/PULL_REQUEST_TEMPLATE.md
test -f .github/workflows/ci.yml
test -f .github/workflows/stale.yml
test -f .pre-commit-config.yaml
test -f .gitignore
test -f .gitattributes
test -f AGENTS.md
test -f README.md
test -f models/manifest.yaml
test -f datasets/manifest.yaml
test -f tests/test_smoke.py
test -f scripts/apply-branch-protection.sh
test -f MANUAL_STEPS.md
```

---

## 7. 目录结构

```text
src/          # 运行时代码
prompts/      # 提示词资产（改动需附评测结果）
evals/        # 评测集与评测脚本（改动需附评测结果）
workflows/    # 编排/流水线定义
models/       # 仅 manifest.yaml；权重在对象存储
datasets/     # 仅 manifest.yaml；数据在对象存储
infra/        # 基础设施与部署
agents/       # Agent 定义与配置
docs/         # 文档
tests/        # 测试
scripts/      # 运维脚本（含 apply-branch-protection.sh）
```

---

## 8. 分支与 worktree 清理

- 合并后 feature 分支自动删除（`delete_branch_on_merge=true`）。
- 未合并的 feature 分支：PR 关闭时手动或定时删除。
- **每周清理一次过期 `feature/*` 与本地 `git worktree`**：

```bash
# 列出所有本地 worktree 并剔除已失效的记录
git worktree list
git worktree prune

# 停用超过 7 天的本地 worktree（示例：按目录 mtime 判断）
git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r w; do
  [ -d "$w" ] || continue
  [ "$(find "$w" -maxdepth 0 -mtime +7)" ] && git worktree remove --force "$w"
done

# 删除远程已合并的过期 feature 分支
git fetch --prune
git branch -r --merged origin/main | grep 'origin/feature/' | \
  sed 's|origin/||' | xargs -r -n1 git push origin --delete
```

---

## 9. 人工待办

首次搭建完成后，仍有若干**无法自动完成**的事项（替换 CODEOWNERS 占位符、创建 Agent bot、配置生产密钥 environment 等），见 [`MANUAL_STEPS.md`](./MANUAL_STEPS.md)。

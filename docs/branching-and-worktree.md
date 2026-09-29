# 分支生命周期与 worktree 清理

本文档定义 `feature/*` 的生命周期自动化规则，以及**每周清理 stale worktree** 的操作规程。

## 1. 生命周期时间线

| 时间点 | 事件 | 执行者 |
|---|---|---|
| 0h | 从 `main` 创建 `feature/<issue-id>-<slug>` | 人工 / Agent |
| 72h 无提交 | 提醒（PR 被标记 `stale`，附 rebase 或关闭提示） | `stale.yml` |
| 168h（7 天）无进展 | PR 自动关闭 **并删除分支** | `stale.yml` |
| 合并时 | 分支自动删除 | `delete_branch_on_merge=true` |

`stale.yml` 配置：

```yaml
days-before-pr-stale: 3     # 72 小时无活动 → stale
days-before-pr-close: 7     # 7 天无活动 → 关闭
delete-branch: true         # 关闭时删除分支
exempt-pr-labels: pinned,keep
```

> **禁止存在超过 7 天的活跃 feature 分支。** 被 `pinned` / `keep` 标记的 PR 是唯一例外，且必须有明确理由。

## 2. 每周清理规程（人工，约 5 分钟）

```bash
# ── A. 远程：删除已合并的 feature 分支 ────────────────────────────
git fetch --prune
git branch -r --merged origin/main | grep 'origin/feature/' | \
  sed 's|origin/||' | xargs -r -n1 git push origin --delete

# ── B. 远程：列出超过 7 天无提交的 feature 分支 ──────────────────
for b in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin/feature/); do
  last=$(git log -1 --format=%ct "$b")
  age=$(( ( $(date +%s) - last ) / 86400 ))
  [ "$age" -gt 7 ] && echo "$b 闲置 ${age} 天"
done

# ── C. 本地：清理失效 worktree 记录 ─────────────────────────────
git worktree list
git worktree prune --verbose

# ── D. 本地：移除超过 7 天未更新的 worktree ─────────────────────
git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r w; do
  [ -d "$w" ] || continue
  case "$w" in "$PWD") continue;; esac        # 跳过主工作树
  if [ -n "$(find "$w" -maxdepth 0 -mtime +7 2>/dev/null)" ]; then
    echo "removing stale worktree: $w"
    git worktree remove --force "$w"
  fi
done

# ── E. 本地：删除已合并的本地分支 ───────────────────────────────
git branch --merged main | grep -v '^\*' | grep 'feature/' | xargs -r git branch -d
```

## 3. 为什么需要 worktree 清理

`git worktree` 会在 `.git/worktrees/` 下留下元数据、在磁盘上留下独立工作目录。若直接删除目录而不 `git worktree prune`：

- `git worktree list` 会显示大量失效条目；
- Agent 并发实验会堆积数十 GB 的临时工作目录；
- 长期失效的 worktree 可能仍指向已删除的 feature 分支，造成误提交。

**规则：Agent 每个任务结束后必须自行 `git worktree remove`，或由每周清理兜底。**

## 4. 回滚

`main` 上的错误变更是**用 revert PR 回滚**：

```bash
git switch -c feature/<issue-id>-revert-<slug>
git revert <squash-merge-sha>
git push -u origin HEAD
gh pr create --base main --title "revert: ..." --fill
```

**禁止** 对 `main` 执行 `git reset`、`--force` push 或任何历史改写——`allow_force_pushes=false` 与 `required_linear_history=true` 已从服务端阻止。

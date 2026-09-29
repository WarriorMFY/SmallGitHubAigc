#!/usr/bin/env bash
#
# apply-branch-protection.sh — 分支保护策略即代码
#
# 用途：对 main 应用最小 AIGC 围栏所需的全部分支保护，可重复执行（幂等）。
# 用法：bash scripts/apply-branch-protection.sh [owner/repo]
#
# 前置：gh auth status 已认证，且当前账号对该仓库有 admin 权限。
#
# 可调项（环境变量）：
#   BRANCH     目标分支，默认 main
#   APPROVALS  必需 approval 数，默认 1（规格口径）
#
# 单人开发说明：GitHub 不允许作者 approve 自己的 PR，因此单人仓库必须用
#   APPROVALS=0 bash scripts/apply-branch-protection.sh
# 否则没有任何人能合并 PR。此时 CI + CODEOWNERS + 线性历史 + enforce_admins
# 仍然生效，仅「至少 1 个 approval」这一条被放宽（见 MANUAL_STEPS.md 第 3 项）。
#
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
BRANCH="${BRANCH:-main}"
APPROVALS="${APPROVALS:-1}"

if ! [[ "${APPROVALS}" =~ ^[0-9]+$ ]]; then
  echo "[FAIL] APPROVALS 必须是 0-6 的整数，收到：${APPROVALS}" >&2
  exit 4
fi

echo "==> repo=${REPO} branch=${BRANCH} approvals=${APPROVALS}"
if [[ "${APPROVALS}" == "0" ]]; then
  echo "    [WARN] APPROVALS=0：已放宽「至少 1 个 approval」，规格 9.1 该条将不满足。"
fi

# ---------------------------------------------------------------------------
# 前置校验 1：CODEOWNERS 不能还留着占位符，否则 require_code_owner_reviews
# 会被 GitHub 拒绝（422），且没有任何人能 approve 这些路径。
# ---------------------------------------------------------------------------
if [[ -f .github/CODEOWNERS ]] && grep -q '@REPLACE_MAINTAINER' .github/CODEOWNERS; then
  cat >&2 <<'EOF'
[FAIL] .github/CODEOWNERS 仍包含占位符 @REPLACE_MAINTAINER。

分支保护的 require_code_owner_reviews=true 需要真实的 owner。请先：
  1. 编辑 .github/CODEOWNERS，把 @REPLACE_MAINTAINER 换成真实维护者账号；
  2. 通过 PR 合入 main；
  3. 重新运行本脚本。

详见 MANUAL_STEPS.md 第 1 项。
EOF
  exit 2
fi

# ---------------------------------------------------------------------------
# 前置校验 2：必须拥有 admin 权限才能设置分支保护。
# ---------------------------------------------------------------------------
PERM="$(gh api "repos/${REPO}" -q .permissions.admin 2>/dev/null || echo false)"
if [[ "${PERM}" != "true" ]]; then
  echo "[FAIL] 当前账号对 ${REPO} 没有 admin 权限，无法设置分支保护。" >&2
  echo "       请由仓库管理员执行，或授予本账号 admin。" >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# 应用 main 分支保护
#   - required_status_checks.strict=true          → 分支必须最新后 CI 通过
#   - contexts=["ci"]                             → 必需状态检查名 ci
#   - enforce_admins=true                         → 管理员也不能绕过（无 bypass）
#   - required_pull_request_reviews              → 必须 PR + ≥APPROVALS 个 approval
#   - dismiss_stale_reviews=true                  → 新提交后旧 review 失效
#   - require_code_owner_reviews=true             → CODEOWNERS 必须 review
#   - required_linear_history=true                → 线性历史（squash/rebase）
#   - allow_force_pushes=false / allow_deletions=false
#   - required_conversation_resolution=true       → 会话必须解决
#
# 注意：下面的 heredoc 用 <<JSON（不加引号），以便展开 ${APPROVALS}。
# ---------------------------------------------------------------------------
echo "==> 应用分支保护"
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": ${APPROVALS}
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON

# ---------------------------------------------------------------------------
# 仓库级策略：合并后自动删除 feature 分支
# ---------------------------------------------------------------------------
echo "==> 开启合并后自动删除分支"
gh api --method PATCH "repos/${REPO}" -f delete_branch_on_merge=true >/dev/null

# ---------------------------------------------------------------------------
# 只允许 squash 合并，保证 main 线性历史
# ---------------------------------------------------------------------------
echo "==> 合并策略：仅 squash"
gh api --method PATCH "repos/${REPO}" \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false >/dev/null

# ---------------------------------------------------------------------------
# 回读校验
# ---------------------------------------------------------------------------
echo "==> 回读校验"
gh api "repos/${REPO}/branches/${BRANCH}/protection" \
  -q '{strict: .required_status_checks.strict, contexts: .required_status_checks.contexts, enforce_admins: .enforce_admins.enabled, reviews: .required_pull_request_reviews.required_approving_review_count, codeowners: .required_pull_request_reviews.require_code_owner_reviews, dismiss_stale: .required_pull_request_reviews.dismiss_stale_reviews, linear: .required_linear_history.enabled, force_push: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled, conversation: .required_conversation_resolution.enabled}'

echo "delete_branch_on_merge = $(gh api "repos/${REPO}" -q .delete_branch_on_merge)"

echo "[OK] 分支保护已应用。"

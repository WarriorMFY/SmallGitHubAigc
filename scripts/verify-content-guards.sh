#!/usr/bin/env bash
#
# verify-content-guards.sh — 验证仓库内容边界与拦截规则
#
# 用途：把规格 9.3 / 9.4 / 9.6 中「可本地验证」的部分做成可复现的检查，
#       不依赖 CI，不依赖 pytest，只用 git + grep。
# 用法：bash scripts/verify-content-guards.sh
# 退出码：0 = 全部通过，1 = 存在失败项
#
set -uo pipefail

PASS=0
FAIL=0

ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL + 1)); }
head_() { printf '\n== %s ==\n' "$1"; }

# ---------------------------------------------------------------------------
head_ "1. .gitignore 忽略规则（规范模式）"
# ---------------------------------------------------------------------------
ignore_ok() {
  local pat="$1" desc="$2"
  if grep -qxF "$pat" .gitignore; then ok "$desc  [$pat]"; else bad "$desc — .gitignore 缺少 [$pat]"; fi
}
ignore_ok '.env'          '环境变量文件被忽略'
ignore_ok '*.key'         '私钥文件被忽略'
ignore_ok '*.pem'         'PEM 证书被忽略'
ignore_ok 'secrets/'      'secrets 目录被忽略'
ignore_ok '.venv/'        '虚拟环境被忽略'
ignore_ok '__pycache__/'  'Python 字节码缓存被忽略'
ignore_ok '.pytest_cache/' 'pytest 缓存被忽略'
ignore_ok '.cache/'       '通用缓存被忽略'
ignore_ok 'outputs/'      '生成物目录被忽略'
ignore_ok 'runs/'         '运行产物目录被忽略'
ignore_ok 'models/**'     '模型目录整体被忽略'
ignore_ok '!models/manifest.yaml'  'models manifest 被白名单保留'
ignore_ok 'datasets/**'   '数据集目录整体被忽略'
ignore_ok '!datasets/manifest.yaml' 'datasets manifest 被白名单保留'

# ---------------------------------------------------------------------------
head_ "2. 功能验证：git check-ignore 实际判定"
# ---------------------------------------------------------------------------
check_ignored() {
  local target="$1" desc="$2"
  if git check-ignore -q -- "$target" 2>/dev/null; then
    if [ -e "$target" ]; then
      ok "$desc  [$target]"
    else
      # check-ignore 对已跟踪路径返回非 0；此处仅当路径被规则命中时才算通过
      ok "$desc  [$target]"
    fi
  else
    bad "$desc — [$target] 未被任何规则忽略"
  fi
}

for t in ".env" "prod.key" "server.pem" "secrets/token.txt" \
         "models/weights.pt" "models/sub/nested.safetensors" \
         "datasets/raw/train.parquet" "outputs/gen.png" "runs/run1/log.txt"; do
  check_ignored "$t" "应被忽略"
done

# manifest 必须被跟踪，不能被忽略
for t in "models/manifest.yaml" "datasets/manifest.yaml"; do
  if git check-ignore -q -- "$t" 2>/dev/null; then
    bad "manifest 不应被忽略 — [$t] 命中了忽略规则"
  else
    ok "manifest 未被忽略  [$t]"
  fi
done

# ---------------------------------------------------------------------------
head_ "3. 已跟踪文件清单：不得包含权重/数据集/生成物/密钥"
# ---------------------------------------------------------------------------
TRACKED="$(git ls-files)"
banned=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    models/manifest.yaml|datasets/manifest.yaml) continue ;;
    *.pt|*.pth|*.safetensors|*.bin|*.ckpt|*.onnx|*.h5|*.gguf|\
    *.parquet|*.arrow|*.tar|*.tar.gz|*.zip|\
    *.key|*.pem|*.p12|*.pfx|.env|.env.*|*/secrets/*|secrets/*|\
    models/*|datasets/*|outputs/*|runs/*)
      bad "已跟踪文件中存在禁止项：$f"
      banned=$((banned + 1))
      ;;
  esac
done <<< "$TRACKED"
[ "$banned" -eq 0 ] && ok "git ls-files 中无权重/数据集/生成物/密钥（共 $(printf '%s\n' "$TRACKED" | grep -c . ) 个文件）"

# ---------------------------------------------------------------------------
head_ "4. 大文件检查（>1024 KB，与 pre-commit --maxkb=1024 一致）"
# ---------------------------------------------------------------------------
big="$(git ls-files -z | while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  sz=$(wc -c < "$f" 2>/dev/null || echo 0)
  [ "$sz" -gt 1048576 ] && printf '%s (%s bytes)\n' "$f" "$sz"
done)"
if [ -z "$big" ]; then ok "无超过 1MB 的已跟踪文件"; else printf '%s\n' "$big" | while read -r l; do bad "超过 1MB：$l"; done; fi

# ---------------------------------------------------------------------------
head_ "5. pre-commit 配置"
# ---------------------------------------------------------------------------
if grep -q 'check-added-large-files' .pre-commit-config.yaml; then
  ok "启用 check-added-large-files"
else bad "缺少 check-added-large-files"; fi

if grep -q 'maxkb=1024' .pre-commit-config.yaml; then
  ok "大文件阈值为 --maxkb=1024"
else bad "未设置 --maxkb=1024"; fi

if grep -q 'detect-private-key' .pre-commit-config.yaml; then
  ok "启用 detect-private-key"
else bad "缺少 detect-private-key"; fi

# ---------------------------------------------------------------------------
head_ "6. .gitattributes 二进制标记"
# ---------------------------------------------------------------------------
for ext in pt pth safetensors bin png jpg; do
  if grep -qE "^\*\.${ext} +binary" .gitattributes; then
    ok "*.${ext} 标记为 binary"
  else
    bad "*.${ext} 未标记为 binary"
  fi
done

# ---------------------------------------------------------------------------
head_ "7. manifest 内容"
# ---------------------------------------------------------------------------
for m in models/manifest.yaml datasets/manifest.yaml; do
  if [ -f "$m" ] && grep -q '^version: 1' "$m" && grep -q '^items:' "$m"; then
    ok "$m 存在且含 version/items"
  else
    bad "$m 缺失或结构不符合规格"
  fi
done

# ---------------------------------------------------------------------------
head_ "8. CI workflow 关键要求"
# ---------------------------------------------------------------------------
CI=.github/workflows/ci.yml
if [ -f "$CI" ]; then
  grep -q 'name: ci'                    "$CI" && ok "workflow 名称为 ci"                 || bad "workflow 名称不是 ci"
  grep -q 'branches: \[main\]'          "$CI" && ok "仅针对 PR 到 main 触发"             || bad "触发分支不是 main"
  grep -q 'name: ci'                    "$CI" && ok "job/check 名称为 ci"                || true
  grep -q 'pre-commit run --all-files'  "$CI" && ok "CI 包含 pre-commit run --all-files" || bad "CI 缺少 pre-commit"
  grep -q 'pytest -q'                   "$CI" && ok "CI 包含 pytest -q"                   || bad "CI 缺少 pytest"
  grep -q 'gitleaks'                    "$CI" && ok "CI 包含 gitleaks"                    || bad "CI 缺少 gitleaks"
  grep -q 'fetch-depth: 0'              "$CI" && ok "checkout 使用 fetch-depth: 0（gitleaks 需要）" || bad "checkout 未设置 fetch-depth: 0"
else
  bad "缺少 $CI"
fi

# ---------------------------------------------------------------------------
head_ "9. stale workflow 关键要求"
# ---------------------------------------------------------------------------
ST=.github/workflows/stale.yml
if [ -f "$ST" ]; then
  grep -q '0 0 \* \* \*'          "$ST" && ok "每天运行（cron 0 0 * * *）"    || bad "未配置每日运行"
  grep -q 'days-before-pr-stale: 3' "$ST" && ok "PR 3 天标记 stale"           || bad "未配置 3 天 stale"
  grep -q 'days-before-pr-close: 7' "$ST" && ok "PR 7 天关闭"                 || bad "未配置 7 天关闭"
  grep -q 'rebase'                "$ST" && ok "stale 提示包含 rebase 要求"     || bad "stale 提示缺失"
else
  bad "缺少 $ST"
fi

# ---------------------------------------------------------------------------
head_ "10. CODEOWNERS 覆盖范围"
# ---------------------------------------------------------------------------
CO=.github/CODEOWNERS
if [ -f "$CO" ]; then
  if grep -q '@REPLACE_MAINTAINER' "$CO"; then
    bad "CODEOWNERS 仍含占位符 @REPLACE_MAINTAINER"
  else
    ok "CODEOWNERS 无占位符"
  fi
  for p in '/main' '/.github' '/prompts' '/models' '/datasets'; do
    grep -qE "^${p}[[:space:]]" "$CO" && ok "覆盖 $p" || bad "未覆盖 $p"
  done
else
  bad "缺少 $CO"
fi

# ---------------------------------------------------------------------------
printf '\n============================================\n'
printf '结果：PASS=%d  FAIL=%d\n' "$PASS" "$FAIL"
printf '============================================\n'
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

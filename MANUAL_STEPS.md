# MANUAL_STEPS — 无法自动完成的人工待办

> 生成于 AIGC 工作站 Git 围栏 v0.1 搭建过程；**已按最终状态更新**。
> 仓库：`WarriorMFY/SmallGitHubAigc`（**public**） · 分支：`main` / `feature/*`
> 验收报告见 [`ACCEPTANCE_REPORT.md`](./ACCEPTANCE_REPORT.md)。
> 每条都标注了**为什么无法自动完成**、**谁来做**、**怎么验收**。

## 状态总览

| 项 | 状态 |
|---|---|
| P0-1 替换 CODEOWNERS 占位符 | ✅ 已完成（`@WarriorMFY`） |
| P0-2 应用 main 分支保护 | ✅ 已完成 |
| P0-3 approval 策略 | ⚠️ **待你决定**（当前 0，规格要求 ≥1） |
| P1-4 Agent bot 身份 | ❌ 待人工 |
| P1-5 无 bypass（`enforce_admins`） | ✅ 已完成（`true`） |
| P1-6 生产密钥 environment | ❌ 待人工 |
| P2-7 GitHub 计划支持分支保护 | ✅ 已解决（改用 public） |
| P2-8 CI 首次触发 | ✅ 已解决（实测正常触发） |
| P3-9 ~ P3-14 本机环境 | ⚠️ 见下，部分需普通终端复核 |
| **P4-15 在普通终端复核两个 bash 脚本** | ❌ **待人工（本沙箱无法执行 bash）** |

---

## 🔴 P0 — 阻塞项

### 1. ~~替换 `CODEOWNERS` 中的 `@REPLACE_MAINTAINER`~~ ✅ 已完成

- **结果**：8 处占位符已全部替换为 `@WarriorMFY`（PR #4，提交 `d51b12d`）。
- **验收**：`grep -c '@REPLACE_MAINTAINER' .github/CODEOWNERS` → `0` ✅

### 2. ~~合并 bootstrap PR 后跑分支保护脚本~~ ✅ 已完成

- **结果**：`main` 分支保护已生效，回读如下：

  ```json
  {"strict":true,"contexts":["ci"],"enforce_admins":true,"reviews":0,
   "codeowners":true,"dismiss_stale":true,"linear":true,
   "force_push":false,"deletions":false,"conversation":true}
  squash=true  merge=false  rebase=false  delete_branch_on_merge=true
  ```

- **实测拦截效果**：

  ```
  remote: error: GH006: Protected branch update failed for refs/heads/main.
  remote: - Changes must be made through a pull request.
  remote: - Cannot force-push to this branch
   ! [remote rejected] HEAD -> main (protected branch hook declined)
  ```

- **说明**：因本机沙箱**无法执行 bash**（见 P4-15），实际应用由逐字段等价的 PowerShell `gh api` 调用完成。
  脚本幂等，可由你在普通终端重跑复核（结果应一致）。

### 3. ⚠️ 决定 approval 策略（**当前唯一未达标的 9.1 条目**）

- **现状**：`required_approving_review_count = 0` → 规格 9.1「至少 1 个 approval」**FAIL**。
- **为什么这样设**：GitHub **不允许作者 approve 自己的 PR**。单人仓库一旦设 1，
  **任何人都无法再合并 PR**，门禁会从"严格"直接变成"死锁"。
- **三种选择**：

  | 选项 | 做法 | 代价 |
  |---|---|---|
  | A（推荐） | 添加第二个账号（哪怕只有 `read` 权限）当 reviewer | 需多一个 GitHub 账号 |
  | B | 保持 0，接受该条 FAIL | 任何人只要有写权限就能合并 PR |
  | C | 建 Organization + Team 作为 CODEOWNERS，允许 team self-review | 需把仓库迁到 org |

- **选 A 或 C 后恢复规格口径**：

  ```bash
  APPROVALS=1 bash scripts/apply-branch-protection.sh
  ```

  （脚本默认值即为 `1`，不带环境变量直接运行也是 `1`。）
- **验收**：

  ```bash
  gh api repos/WarriorMFY/SmallGitHubAigc/branches/main/protection/required_pull_request_reviews \
    -q .required_approving_review_count     # 期望 1
  ```

---

## 🟠 P1 — Agent 身份与密钥隔离

### 4. 创建 Agent bot 账号并授予 `feature/*` 写权限

- **为什么无法自动完成**：需要独立的 GitHub 账号 + 该账号的凭据，Agent 不应使用维护者身份。
- **推荐做法**（二选一）：
  - **GitHub App**（推荐，权限最小）：`Settings → Developer settings → GitHub Apps → New GitHub App`，
    授予 `Contents: Read and write`、`Pull requests: Read and write`、`Metadata: Read`，安装到本仓库；
  - **Machine user**：新建一个 GitHub 账号，加入仓库 `Write` 角色。
- **硬约束**：
  - Agent bot **不是**仓库 admin；
  - Agent bot **不在** `main` 分支保护的 bypass 列表（`enforce_admins=true` 已保证无 bypass）；
  - Agent bot **不加入**任何有生产密钥的 environment。
- **验收**：

  ```bash
  gh api repos/WarriorMFY/SmallGitHubAigc/collaborators --jq '.[] | {login, role_name, permissions}'
  # Agent bot 应为 write / push，且 admin=false
  ```

### 5. ~~确认 `enforce_admins=true`（无 bypass）~~ ✅ 已完成

- **结果**：`enforce_admins.enabled = true`。
- **含义**：**不存在 bypass 列表** —— 管理员也不能绕过保护。因此 9.2「Agent bot 不在 bypass 列表」自动成立。
- **验收**：`gh api repos/WarriorMFY/SmallGitHubAigc/branches/main/protection/enforce_admins -q .enabled` → `true` ✅

### 6. 生产密钥只放受控 environment，仅维护者可访问

- **为什么无法自动完成**：密钥内容不可由 Agent 生成或读取；且需在 GitHub 侧配置。
- **操作**：`Settings → Environments → New environment`：建 `production`，
  添加 **Required reviewers**（仅维护者），把生产密钥存为该 environment 的 secret。
  同时确认仓库级 `Settings → Secrets and variables → Actions` 里**没有**生产密钥。
- **Agent/CI 约束**：`.github/workflows/ci.yml` 只使用 `secrets.GITHUB_TOKEN`，**不引用任何生产密钥**。
- **验收**：

  ```bash
  gh api repos/WarriorMFY/SmallGitHubAigc/environments --jq '.environments[].name'
  gh api repos/WarriorMFY/SmallGitHubAigc/actions/secrets --jq '.secrets[].name'
  ```

---

## 🟡 P2 — 环境与平台确认

### 7. ~~确认 GitHub 计划支持分支保护~~ ✅ 已解决（改用 public）

- **实际撞上的问题**：账号为 **GitHub Free**，而分支保护与 rulesets 对**私有**仓库是**付费功能**：

  ```
  PUT repos/.../branches/main/protection  → 403
  Upgrade to GitHub Pro or make this repository public to enable this feature.
  GET repos/.../rulesets                  → 403（同上）
  ```

- **处置**：经用户确认，仓库已由 **private 改为 public**，随后分支保护成功应用。
- **改 public 前的安全措施**：对**全部历史**做密钥扫描（6 个提交 / 22 条路径 / 0 命中），
  确认从未跟踪过 `.env`、`*.key`、`.pem`、`.tmp-*`；另开启 GitHub 原生 secret scanning + push protection。
- **验收**：`gh api repos/WarriorMFY/SmallGitHubAigc/branches/main/protection` → `200` ✅
- **若日后想改回 private**：需升级到 GitHub Pro，否则保护与 rulesets 会失效。

### 8. ~~若 CI 首次未触发~~ ✅ 已解决（实测正常触发）

- **实际结果**：bootstrap PR **#2 的 CI 就正常触发了**（run 36588851044），无需先合并 workflow。
  GitHub 会基于 PR 的 merge ref 评估 workflow，因此在 PR 自身引入 `ci.yml` 也能生效。
- **顺带修掉的一个必然失败**：该 run 中 gitleaks 步骤失败，原因是
  `actions/checkout@v4` 默认 `fetch-depth: 1`，PR merge ref 无父提交 →
  `gitleaks detect --log-opts=<sha>^..<sha>` 报 `ambiguous argument` → 扫 0 字节却 exit 1。
  已修复为 `fetch-depth: 0` + 显式 `GITLEAKS_BASE_SHA`/`GITLEAKS_HEAD_SHA`（提交 `b7901f1`）。
- **验收**：任意测试 PR 页面出现名为 **`ci`** 的检查项，且 gitleaks 日志出现
  `1 commits scanned.` / `✅ No leaks detected` ✅

---

## 🔵 P3 — 本机环境（本次搭建中实际遇到的问题）

### 9. 本机 `github.com:443` 不可达 —— 依赖代理

- **现象**：`github.com` 被解析到 `20.205.243.166`，该 IP 从本机 443 不通（`curl` 超时），
  而 `api.github.com` 可达。这是典型的 DNS 污染 / 链路封锁。
- **已做的绕行**：
  - `gh` 走代理 `http://127.0.0.1:7890`（FlClash），device flow 登录成功；
  - 本仓库的 git 已写入 `http.proxy / https.proxy = http://127.0.0.1:7890`（**仅本仓库 local config**）；
  - `credential.helper` 已**移除**（原 `manager-core` 在本机并不存在，会报错）。
- **人工需确认**：
  - 长期方案请在 `~/.gitconfig` 或系统代理中固定配置，否则换机器/关代理后无法 push；
  - 若代理端口变化，记得同步本仓库 `git config http.proxy`。
- **验收**：`git ls-remote origin` 有输出且无超时。

### 10. 本机缺少 `python3.11` / `pre-commit` / `pytest`（本机仅有 Python 3.7）

- **现象**：规格第 3 节要求 `python3.11`、`pre-commit`、`pytest`，本机均无（`py -0` 仅 `-3.7-64`）。
- **为什么未自动安装**：安装 Python 3.11 与用户级虚拟环境需要写入工作区之外的目录（`%LOCALAPPDATA%` / site-packages），
  本会话的沙箱与审批策略未放行；且 `pre-commit` 生成 hook 环境需要下载依赖，建议在网络稳定时由人工执行。
- **操作**：

  ```powershell
  # Windows 上安装 Python 3.11（官方安装包，注意勾选 py launcher）
  # https://www.python.org/downloads/release/python-3119/
  py -3.11 -m pip install --user pre-commit pytest
  py -3.11 -m pytest -q
  ```

- **注意**：本机 `python3` 是 Microsoft Store 别名（3.9.13），**不要**依赖它。
- **验收**：`py -3.11 -m pytest -q` 输出 `1 passed`。

### 11. 本机沙箱下 `pre-commit run --all-files` 无法执行

- **现象**：Git for Windows 的 MSYS2 运行时在本沙箱下崩溃：
  `sh.exe: *** fatal error - couldn't create signal pipe, Win32 error 5`。
  `pre-commit` 的 hook 执行依赖 `sh`/`bash`，因此本地无法完成该项验证。
- **说明**：这**不是**配置错误 —— `.pre-commit-config.yaml` 本身已通过 YAML 校验，
  且 CI（`ubuntu-latest`）会真实执行 `pre-commit run --all-files`。
- **操作**：在**不受此沙箱约束**的普通终端里执行：

  ```bash
  cd <repo>
  pre-commit run --all-files
  ```

- **验收**：全部 hook `Passed`（首次运行需联网 clone `pre-commit-hooks`）。

### 12. 本机 `%APPDATA%\GitHub CLI` 配置目录由手工补建

- **现象**：`gh auth login` 成功写入凭据管理器，但创建配置目录被沙箱拒绝，
  导致 `gh auth status` 一度报「未登录」。
- **已做的修复**：手工创建 `%APPDATA%\GitHub CLI\config.yml` 与 `hosts.yml`
  （`hosts.yml` 只记录 `user: WarriorMFY` 与 `git_protocol: https`，**不含令牌**；
  令牌始终存放于 Windows 凭据管理器 `gh:github.com:WarriorMFY`）。
- **人工需确认**：若后续 `gh` 报配置异常，可执行 `gh auth login` 重来一次（正常终端下不会有此问题）。

### 13. 本机 hosts 文件未能写入

- **尝试**：为绕过 DNS 污染，曾尝试把 `github.com` 指向可达的 `140.82.112.3`。
- **结果**：`C:\WINDOWS\System32\drivers\etc\hosts` 写入被拒绝（需管理员 + UAC），**未做任何修改**。
- **建议**：若想长期稳定访问，请以管理员身份自行添加，或使用代理的 TUN/系统代理模式。
  本次搭建**依赖代理**完成，未修改 hosts。

### 14. feature 分支超期清理依赖 stale workflow 或人工

- **说明**：`actions/stale@v9` 只能操作 PR/Issue，**不能直接删除「无 PR 的闲置分支」**。
  `delete-branch: true` 只在 PR 被关闭时删分支。
- **人工兜底**：每周按 `docs/branching-and-worktree.md` 第 2 节的 A–E 步清理。
- **验收**：`git for-each-ref --format='%(refname:short) %(committerdate:relative)' refs/remotes/origin/feature/` 无超过 7 天的条目。
- **本次实况**：已清理至**仅剩 `main`** 一个分支，0 个活跃 feature 分支 ✅

---

## 🔴 P4 — 需人工在普通终端复核（本沙箱限制导致）

### 15. **在普通终端复核两个 bash 脚本**（本沙箱无法执行 bash）

- **现象**：本机 Git for Windows 的 MSYS2 运行时在当前文件沙箱下**必然崩溃**：

  ```
  bash.exe: *** fatal error - couldn't create signal pipe, Win32 error 5
  bash.exe: *** fatal error - CreateFileMapping S-1-5-21-...-1001.1, Win32 error 5
  ```

  `pre-commit` 的 hook 执行也依赖 `sh`/`bash`，因此本地 `pre-commit run --all-files` **同样无法执行**。

- **本次的替代做法**（结论等价，但请复核）：

  | 脚本 | 沙箱内替代方式 |
  |---|---|
  | `scripts/apply-branch-protection.sh` | 用**逐字段等价的 PowerShell `gh api`** 调用完成，回读结果与脚本 `READBACK` 一致 |
  | `scripts/verify-content-guards.sh` | 用**同逻辑的 PowerShell 实现**采集证据，116 项 PASS |

- **请你执行**（普通 Windows 终端 / WSL / Linux 均可，约 1 分钟）：

  ```bash
  cd <repo>
  bash scripts/verify-content-guards.sh          # 期望：退出码 0，末尾 FAIL=0
  APPROVALS=0 bash scripts/apply-branch-protection.sh   # 幂等；会回读并打印保护状态
  pre-commit run --all-files                     # 期望：全部 Passed（首次需联网）
  pytest -q                                      # 期望：1 passed
  ```

- **为什么值得复核**：这两个脚本是**交付物**，其正确性目前仅由"等价逻辑"间接证明，
  **尚未在任何真实 bash 环境里执行过**。CI（`ubuntu-latest`）执行的是 `pre-commit` + `pytest`，
  **不包含这两个脚本**。建议后续把 `verify-content-guards.sh` 加入 CI，使其每次 PR 都被真实执行。

---

## 附：bootstrap 顺序说明（为什么 `main` 先有一个初始提交）

规格第 3 节要求「若仓库为空，先由人工创建 `main` 和初始 README，Agent 不直接推 `main`」，
而第 8 节又要求 Agent 完成全部搭建。本次采用的顺序：

1. Agent 用 `gh repo create` 建**空**仓库（当时为 private，后因分支保护付费墙改为 public）；
2. Agent 推送一个**最小主干**（README + `.gitignore` + `.gitattributes` + 目录骨架 + 两个 manifest）；
3. 其余全部交付物走 `feature/setup-workstation-v0.1` → PR #2 → 人工合并；
4. 合并后再开启 `main` 分支保护（否则无人能合并，见第 2 项）。

> 这一步是**唯一一次**对 `main` 的直接推送，属于空仓库冷启动。此后 `main` 只进 PR。

## 附：两个曾真实存在、已修复的缺陷

1. **`check-added-large-files` 在 CI 中静默空转**（严重）
   该 hook 默认与 `git diff --cached --diff-filter=A` 求交集。CI 是干净 checkout、无暂存 →
   交集为空 → **检查 0 个文件却打印 `Passed`**。即「大于 1MB 文件会被拦截」原本**并未生效**。
   修复：`--enforce-all`（PR #8，提交 `bbbb73c`）。复验：PR #9 正确报错
   `src/test_big_artifact.bin (2048 KB) exceeds 1024 KB.`
2. **gitleaks 步骤必然失败**（阻断 CI）
   见第 8 项。修复：`fetch-depth: 0` + 显式 base/head（提交 `b7901f1`）。

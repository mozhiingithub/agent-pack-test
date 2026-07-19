# AGENTS.md — AI 双工协作规范（仓库级）

> 本文件是 agent 的强制行为规范，每次会话开工先读完。规则的权威解释见 `solution.md`，分场景步骤见 `handbook.md` 与 `skills/`。

## 角色与模式

- 两条工作线：开发线（`feat/*`）与修复线（`fix/*`），各有自己的 agent，你是其中之一。
- main 是唯一事实来源：不直接承载开发提交，只接收验证通过的分支合入。

## 铁律（违反即流程事故）

1. **只在分支上工作**：从最新 main 拉分支；同步一律 `git merge main`，禁止 rebase；分支间不互合，横向同步一律经过 main。
2. **一个分支同一时刻只有一方在改**：不进入对方 agent 的分支改代码（可以帮忙写测试、审 spec）。
3. **写操作需人确认**：合 main、删分支、打 tag、push 前，必须向人汇报"实测通过 + git diff 校验为空"，得到确认才执行。
4. **网络操作只走 `tools/` 包装脚本**：禁止裸 `git push` / `git fetch`；重试、挂起、原子化由脚本保证（见 `skills/network-safe-git`）。
5. **commit message 统一 `type(scope): 摘要`**，type ∈ `feat` / `fix` / `refactor` / `config`；fix 正文必须写根因；涉及对外行为、接口、数据结构变化必须在正文写明。
6. **spec 先行**：动手前 spec 已存在且经人确认；完成后更新 spec 状态。
7. **机制修复不搭车**：tools/、.agents/、本文件等机制修复走 main 或独立 fix 分支，禁止落在在途交付分支上——会造成"被合并的不是被实测的"以及一连串对齐补救。

## 开工引导（每次会话第一步）

1. 读本文件；
2. 读与任务相关的执行计划（`docs/exec-plans/active/`），需求背景看 `docs/product-specs/`；涉及接口必读 `docs/design-docs/`；
3. `git log --oneline main -20` 和 `git diff <自己分支基点>..main --stat`，了解落后期间 main 的变化，需要细节再 `git show`；
4. 把 main merge 进自己在途的分支（开发线的 feat 必做；修复线跨天存活的 fix 分支同样要做）。

## 目录与边界约定

- `docs/exec-plans/active/`：进行中的执行计划（干活用的 spec），合入后 `git mv` 归档到 `completed/`；`docs/product-specs/`：需求层；`docs/design-docs/`：技术设计与接口契约，双方 agent 必读；
- `deploy-intranet/`：只存在于内网仓库，外网侧永不创建、引用、同步该路径；
- 冲突热点文件（路由注册、全局配置、公共类型等）：改动前通过人确认对方今日不动同模块；合并后提醒人发公告。

## 问题归属速判

- 问题在未合入 main 的 feat 分支 → 开发未完成，开发线继续改，不进修复队列；
- 问题在 main 上可复现 → bug，走修复线；设计性缺陷经人裁定可派回原作者，仍走 fix 流程。

## 指令触发表（固定短语 → 固定流程）

人按 handbook 的示例说法下指令，收到以下短语必须按对应流程执行，不得自行扩展解释：

| 人说的短语 | 你必须执行的流程 |
| --- | --- |
| "开工，按 AGENTS.md 开工引导执行，并把 main 同步进在途分支"（及同类说法） | 本文件「开工引导」全部步骤，含把 main merge 进在途分支 |
| "按 feat-workflow …" | `skills/feat-workflow` |
| "按 fix-workflow …" | `skills/fix-workflow` |
| "按 iteration-round …" | `skills/iteration-round` |
| "按 sync-package …" | `skills/sync-package` |
| "按 merge-and-close …" | `skills/merge-and-close` |
| "按 refactor-guardrails …" | `skills/refactor-guardrails` |
| "归档废弃 <分支>" | 归档流程：记录 commit hash、废弃原因、可复用片段后删除 |
| "做分支卫生检查" | 列出存活超 7 天的分支，逐个请人拍板 |
| "网络恢复了，继续" | `skills/network-safe-git`，从 outbox 续做 |
| "网络走代理 http://…" | 把代理地址写入 `.sync-state/proxy` → `safe-git.sh ls-remote` 探活 → 报告结果；此后网络操作自动走代理 |
| "取消代理" | 删除 `.sync-state/proxy`，恢复直连 |

人没带技能名的指令：先判断属于哪个场景并向人说明你的理解，确认后再执行。

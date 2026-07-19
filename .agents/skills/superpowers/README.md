#  vendored superpowers 技能（上游副本）

> 来源：`chargeX_fault_platform/.claude/skills/superpowers/`（上游为开源 superpowers 技能库，许可证随上游）。
> 本目录为**原样副本（vendor）**，仅复制采纳项；本地适配规则见本包根级 skills（feat-workflow、fix-workflow 等），两者配合使用。

## 采纳清单（6 个）

| 技能 | 用于 | 与本包规则的衔接 |
| --- | --- | --- |
| `brainstorming` | 新需求设计、产出 product-spec | spec 自审四项已纳入 `skills/feat-workflow`；产物落 `docs/product-specs/` 而非上游默认路径 |
| `writing-plans` | 把 spec 拆成 exec-plan | 模板见项目 `docs/exec-plans/template.md`（已含 checkbox 任务拆分） |
| `executing-plans` | 执行 exec-plan | 写操作（合 main/push/删分支）仍须人确认——本包铁律 3 优先于上游"连续执行" |
| `test-driven-development` | 编码纪律 | 外网侧全流程适用；内网侧只跑验收实测 |
| `systematic-debugging` | 修复线根因调查 | 纪律要点已纳入 `skills/fix-workflow`（含"两轮失败停手"红线） |
| `verification-before-completion` | 完成声明的证据门 | 对应本包铁律 3（实测通过 + diff 为空） |

## 明确未采纳（与本包双工机制冲突）

- `subagent-driven-development` / `dispatching-parallel-agents`：同会话派子代理、连续执行不问人，与"开发/修复各一个独立 agent + 人对写操作确认"冲突；
- `finishing-a-development-branch`：其"push 建 PR"假设在线 GitHub，本包走 merge-and-close + 同步包；
- `using-git-worktrees`：本包 import.sh 已内建 worktree 契约，不叠加；
- `requesting-code-review` / `receiving-code-review` / `writing-skills` / `using-superpowers`：暂不需要。

## 使用注意

- 副本内引用上游默认路径（如 `docs/superpowers/...`）时，以本包约定路径为准（`docs/product-specs/`、`docs/exec-plans/`）；
- 副本内"问用户"类交互，按本包规则改为**批量提问**（人异步在线）；
- 上游更新时整目录替换即可，本目录不做局部修改。

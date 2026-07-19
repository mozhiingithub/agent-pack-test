# agent-pack-test：AI 双工协作试运行项目

极简留言板（零外部依赖的 Node 前后端），用于按 `handbook.md` 实践双工协作模式，跑通后再推广到正式项目。

## 运行

```bash
npm start          # 或 node server/index.js，默认 :3000
npm test           # node:test 冒烟测试
bash tools/check.sh  # 本地检查（语法+测试，写 .checks-ok 标记）
```

## 目录

```
server/    后端（原生 http，JSON 文件存储）
web/       前端（原生 HTML/JS/CSS）
tests/     API 冒烟测试
docs/      spec 结构（exec-plans 执行计划 / product-specs 需求 / design-docs 契约）
tools/     check.sh、export_package.sh、safe-git.sh、templates/import.sh
.agents/skills/  agent 场景技能；AGENTS.md 为 agent 必读规范
.githooks/ pre-push 裸推拦截（已配置 core.hooksPath）
```

## 演练提示

- 本仓库为"外网仓库"。模拟内网时：另克隆一份作为内网仓库，把 `tools/templates/import.sh` 可变区的 `REPO` 改为内网克隆路径，内网仓库中自行建立 `deploy-intranet/` 配置目录；
- 第一个练习任务已备好：`docs/exec-plans/active/add-message-timestamp.md`；
- 协作规则见 AGENTS.md；操作说法见 handbook（260717-multi-agent-mode-problem/handbook.md）。

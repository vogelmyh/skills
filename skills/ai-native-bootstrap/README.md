# ai-native-bootstrap

通过交互式提问梳理项目约束与架构设计，根据当前宿主生成 `AGENTS.md`（Codex）或 `CLAUDE.md`（Claude Code），以及 spec-driven 开发所需的 `requirements.md`、`design.md`、`tasks.md`，让 coding agent 基于这些文档自动化完成编码、自测试、自 debug 和文档生成。

## 安装

Codex：

```bash
mkdir -p ~/.agents/skills
ln -s "$(pwd)/skills/ai-native-bootstrap" ~/.agents/skills/ai-native-bootstrap
```

Claude Code：

```bash
mkdir -p ~/.claude/skills
ln -s "$(pwd)/skills/ai-native-bootstrap" ~/.claude/skills/ai-native-bootstrap
```

## 使用

在 Codex 或 Claude Code 中直接描述意图即可触发，例如：

- "帮我把这个项目改造成 AI Native 的开发方式"
- "初始化 spec-driven 开发，生成 agent instructions 和 specs"
- "我有一份 PRD，帮我生成需求、设计和任务拆分文档"

Skill 会先识别场景（是否有 PRD、新建还是存量代码库），再分四个阶段交互式生成文档，每个阶段生成后都需要你确认才进入下一阶段：

1. 项目约束访谈 → `AGENTS.md`（Codex）或 `CLAUDE.md`（Claude Code）
2. 需求梳理 → `specs/{feature}/requirements.md`
3. 架构设计 → `specs/{feature}/design.md`
4. 任务拆分 → `specs/{feature}/tasks.md`

文档生成完毕后，即可让当前 coding agent 基于 `tasks.md` 逐任务实施。

## 模板来源

模板体系采用 Kiro 风格（requirements / design / tasks），参考了 [claude-code-spec-workflow](https://github.com/Pimzino/claude-code-spec-workflow)、[cc-sdd](https://github.com/gotalab/cc-sdd) 与 [GitHub spec-kit](https://github.com/github/spec-kit) 的实践；宿主规则模板可输出 Codex 使用的 `AGENTS.md` 或 Claude Code 使用的 `CLAUDE.md`。

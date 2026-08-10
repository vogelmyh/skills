# ai-native-skills

Claude Code Agent Skills for AI Native development.

## Skills

| Skill | Description |
|-------|-------------|
| [ai-native-bootstrap](skills/ai-native-bootstrap/SKILL.md) | 通过交互式提问梳理项目约束与架构设计，生成 spec-driven 开发所需的 `CLAUDE.md`、`requirements.md`、`design.md`、`tasks.md`，让 Claude Code agent 模式可以基于这些文档自动化完成编码、自测试、自 debug 和文档生成。 |

## 安装

Claude Code 从 `~/.claude/skills/`（个人级）或项目内 `.claude/skills/`（项目级）加载 Skill。

安装为个人 Skill（推荐软链，仓库更新后自动生效）：

```bash
ln -s "$(pwd)/skills/ai-native-bootstrap" ~/.claude/skills/ai-native-bootstrap
```

或复制安装：

```bash
cp -r skills/ai-native-bootstrap ~/.claude/skills/
```

## 使用

在 Claude Code 中直接描述意图即可触发，例如：

- "帮我把这个项目改造成 AI Native 的开发方式"
- "初始化 spec-driven 开发，生成 CLAUDE.md 和 specs"
- "我有一份 PRD，帮我生成需求、设计和任务拆分文档"

Skill 会先识别场景（是否有 PRD、新建还是存量代码库），再分四个阶段交互式生成文档，每个阶段生成后都需要你确认才进入下一阶段：

1. 项目约束访谈 → `CLAUDE.md`
2. 需求梳理 → `specs/{feature}/requirements.md`
3. 架构设计 → `specs/{feature}/design.md`
4. 任务拆分 → `specs/{feature}/tasks.md`

文档生成完毕后，即可让 Claude Code 基于 `tasks.md` 逐任务实施。

## 模板来源

模板体系采用 Claude Code 生态主流的 Kiro 风格（requirements / design / tasks），参考了 [claude-code-spec-workflow](https://github.com/Pimzino/claude-code-spec-workflow)、[cc-sdd](https://github.com/gotalab/cc-sdd) 与 [GitHub spec-kit](https://github.com/github/spec-kit) 的实践；`CLAUDE.md` 模板遵循 Anthropic 官方最佳实践。

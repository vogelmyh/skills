# ai-native-skills

Claude Code Agent Skills for AI Native development.

## Skills

| Skill | Description | Docs |
|-------|-------------|------|
| [ai-native-bootstrap](skills/ai-native-bootstrap/) | 通过交互式提问梳理项目约束与架构设计，生成 spec-driven 开发所需的文档 | [README](skills/ai-native-bootstrap/README.md) |

## 安装

Claude Code 从 `~/.claude/skills/`（个人级）或项目内 `.claude/skills/`（项目级）加载 Skill。

将某个 skill 安装为个人 Skill（推荐软链，仓库更新后自动生效）：

```bash
ln -s "$(pwd)/skills/{skill-name}" ~/.claude/skills/{skill-name}
```

或复制安装：

```bash
cp -r skills/{skill-name} ~/.claude/skills/
```

各 skill 的具体安装与使用说明见对应目录下的 README。

## 仓库结构

```text
skills/
└── {skill-name}/
    ├── README.md      # 人类使用说明
    ├── SKILL.md       # Agent 执行指令
    └── templates/     # 可选：该 skill 使用的模板
```

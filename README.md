# Personal Codex Skills

这个仓库保存可独立使用的个人 Codex skills。每个顶层目录都是一个完整、聚焦单一任务的 skill，不依赖仓库级工作流包装目录。

## Skills

- [`incremental-change-design`](./incremental-change-design/README.md)：为现有代码库中的非平凡增量变更生成经用户确认的冻结规格。
- [`greenfield-requirement-design`](./greenfield-requirement-design/README.md)：为无需保留既有产品行为或源码实现的非平凡全新需求生成经用户确认的冻结规格。
- [`implement-frozen-spec`](./implement-frozen-spec/README.md)：严格按照已冻结的规格实施并验证候选实现。
- [`review-spec-implementation`](./review-spec-implementation/README.md)：独立审查候选实现是否满足冻结规格。
- [`oc-ops`](./oc-ops/README.md)：运维、发布、回滚和诊断 LOA 数据链路及 OC Flow Guard 验收控制面。
- [`architecture-boundary-page`](./architecture-boundary-page/README.md)：从代码证据生成单页交互式业务流程与跨组件边界说明，并准备 GitHub Pages 交付。
- [`archify`](./archify/README.md)：将系统描述或代码证据生成可交互的独立 HTML 架构图、流程图、时序图、数据流图与生命周期图。

两个设计 skill 是互斥入口：已有系统的变更使用 `incremental-change-design`，全新产品、服务、组件或独立能力使用 `greenfield-requirement-design`。二者产出相同的 `Status: FROZEN` 规格接口，并与后续两个 skill 组成三段式流程：

```text
incremental-change-design -----------\
                                      +--> implement-frozen-spec --> review-spec-implementation
greenfield-requirement-design -------/
```

设计、实现和审查应分别在独立 Agent 上下文中运行。阶段之间通过冻结的 `SPEC.md`、边界明确的候选实现及 `REVIEW.md` 交接，不依赖上一阶段的私有对话上下文。

以上四个设计、实现与审查 skill 均关闭隐式调用；只有用户通过 `$skill-name` 显式指定时才会加载。

`oc-ops` 是独立的运维 skill，不属于上述规格设计、实现与审查链路。

## Repository layout

```text
skills/
├── README.md
├── incremental-change-design/
│   ├── README.md
│   ├── SKILL.md
│   └── agents/openai.yaml
├── greenfield-requirement-design/
│   ├── README.md
│   ├── SKILL.md
│   └── agents/openai.yaml
├── implement-frozen-spec/
│   ├── README.md
│   ├── SKILL.md
│   └── agents/openai.yaml
├── review-spec-implementation/
│   ├── README.md
│   ├── SKILL.md
│   └── agents/openai.yaml
├── architecture-boundary-page/
│   ├── README.md
│   └── SKILL.md
├── archify/
│   ├── README.md
│   ├── SKILL.md
│   └── ...（上游渲染器、模板、schema 与示例）
└── oc-ops/
    ├── README.md
    ├── SKILL.md
    ├── agents/
    │   └── openai.yaml
    ├── assets/
    │   └── agent-lite-tls/
    └── references/
        ├── agent-lite/
        ├── agent-lite-diagnosis.md
        ├── crawler/
        ├── crawler-diagnosis.md
        ├── end-to-end-diagnosis.md
        ├── environment.md
        ├── gateway/
        ├── gateway-diagnosis.md
        └── deployment-control-plane.md
```

每个 skill 的 `SKILL.md` 是 Codex 加载的唯一指令入口，并包含必需的 `name` 与 `description` frontmatter。`README.md` 仅供仓库浏览和维护，不参与 skill 执行。

如某个 skill 后续确实需要额外资源，可在该 skill 内按需增加 OpenAI 支持的标准目录：

- `scripts/`：可执行辅助脚本
- `references/`：按需读取的参考资料
- `assets/`：输出模板或静态资源
- `agents/openai.yaml`：可选的界面元数据、调用策略与依赖声明

不要为未使用的资源创建空目录。

## Use

在 Codex 中显式调用：

```text
$incremental-change-design
$greenfield-requirement-design
$implement-frozen-spec
$review-spec-implementation
$oc-ops
$architecture-boundary-page
$archify
```

需要在 Codex 中全局启用时，将个人 skills 目录中的同名入口链接到本仓库内的 skill 目录：

```bash
ln -s /absolute/path/to/skills/<skill-name> "$HOME/.codex/skills/<skill-name>"
```

本仓库内的目录是唯一事实源；`$HOME/.codex/skills/` 只作为 Codex 的全局发现入口，不单独保留或维护副本。Codex 通常会根据 `SKILL.md` 中的 `description` 自动匹配；配置了 `policy.allow_implicit_invocation: false` 的 skill 只支持通过 `$skill-name` 显式调用。

## Maintenance rules

- 每个 skill 保持单一职责并可独立加载。
- skill 目录名应与 `SKILL.md` 的 `name` 一致。
- 只在本仓库内编辑 skill；不直接修改 `$HOME/.codex/skills/` 中的全局入口。
- 如果本仓库被移动或重新 clone，重建全局符号链接并重新校验 skill。
- 指令和行为约束只维护在 `SKILL.md`；README 不复制完整工作流。
- 仅在有实际用途时增加 `scripts/`、`references/`、`assets/` 或 `agents/`。
- 提交前检查压缩包、系统元数据和其他临时归档未进入仓库。

## References

- [OpenAI：Build skills](https://learn.chatgpt.com/docs/build-skills)
- [OpenAI：Save workflows as skills](https://learn.chatgpt.com/use-cases/reusable-codex-skills)

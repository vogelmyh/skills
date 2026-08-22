# review-spec-implementation

在独立审查上下文中，对照冻结规格检查候选实现的合规性、正确性、最小性、风险和验证证据，并形成可复核的审查结论。

## When to use

在候选实现和基线可见、冻结规格可读取时使用。该 skill 只负责审查、发现和结论，不负责设计、实现或修复问题。

## Invoke

```text
$review-spec-implementation
```

调用时提供冻结的 `SPEC.md`、实际候选实现、项目工作区，以及存在时的候选基线。具体独立性要求、审查通道、严重级别、状态门禁与 `REVIEW.md` 格式以 [`SKILL.md`](./SKILL.md) 为准。

## Contents

- `SKILL.md`：Codex 指令入口与完整工作流
- `README.md`：面向维护者的概览，不参与运行

该 skill 是独立单元，不依赖实现阶段的私有推理或原分组目录中的共享说明。


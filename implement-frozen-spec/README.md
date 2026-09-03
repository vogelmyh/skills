# implement-frozen-spec

在独立的实现上下文中，严格按照已批准且标记为 `Status: FROZEN` 的规格完成最小充分实现、验证和作者自审，并交付边界清晰的候选实现。

## When to use

仅在用户显式调用 `$implement-frozen-spec`、冻结规格已经存在且用户明确授权实施时使用。它可以处理增量变更、绿地系统、缺陷修复或迁移，但不会探索或重做未冻结的设计，也不会独立批准自己的实现。

## Invoke

```text
$implement-frozen-spec
```

调用时提供冻结的 `SPEC.md`、项目工作区和明确的实施授权。具体规格门禁、阻塞状态、验证要求与交接格式以 [`SKILL.md`](./SKILL.md) 为准。

## Contents

- `SKILL.md`：Codex 指令入口与完整工作流
- `agents/openai.yaml`：关闭隐式调用的调用策略
- `README.md`：面向维护者的概览，不参与运行

该 skill 是独立单元，只依赖冻结规格、工作区、用户授权以及项目自身适用的指令。

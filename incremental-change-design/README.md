# incremental-change-design

为不熟悉的现有代码库设计非平凡的增量变更，并通过针对性侦察和面向决策的协作，产出可供后续实现与审查独立使用的冻结规格。

## When to use

仅在用户显式调用 `$incremental-change-design` 时使用。适合在开始实现之前理解现状、关闭关键设计决策并获得用户批准的增量变更。不适用于简单编辑、明显缺陷修复、绿地架构设计或已冻结规格的实现。

## Invoke

```text
$incremental-change-design
```

调用时提供需求、目标代码库、相关约束和已有文档。具体输入门槛、设计边界、规格格式与停止条件以 [`SKILL.md`](./SKILL.md) 为准。

## Contents

- `SKILL.md`：Codex 指令入口与完整工作流
- `agents/openai.yaml`：关闭隐式调用的调用策略
- `README.md`：面向维护者的概览，不参与运行

该 skill 是独立单元，不要求仓库级 `AGENTS.md` 或其他同组 skill 才能执行。

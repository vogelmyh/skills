# Archify

将系统描述或代码证据生成可交互、可独立打开的 HTML 架构图，也支持流程图、时序图、数据流图与生命周期图。

## 来源

- 上游：[tt-a1i/archify](https://github.com/tt-a1i/archify)
- 版本：2.16.0
- 安装提交：[5de7275fe87a66a19d52a4d9b0b3a4f2a5a90115](https://github.com/tt-a1i/archify/commit/5de7275fe87a66a19d52a4d9b0b3a4f2a5a90115)
- 导入目录：上游仓库的 `archify/`
- 许可证：[MIT](./LICENSE)

本目录保留上游 skill 文件；此 README 为本地安装说明。执行指令以 [SKILL.md](./SKILL.md) 为准。

## 使用

在 Codex 中输入：

```text
$archify 分析当前仓库，生成中文交互式 HTML 架构图。
```

需要 Node.js 18 或更高版本。日常生成与校验使用随包提供的渲染器，无需运行 `npm install`。

文件维护在本仓库，全局发现入口 `~/.codex/skills/archify` 链接到本目录，与其他个人 skills 保持一致。

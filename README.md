# PEI Bot

Perry Ellis International 内部的企业级 Agent 平台:员工创建 24x7 运行的 Bot,Bot 之间可以互相调用,模型经由 Vertex AI 上的 Gemini 自动选择或强制指定。

当前阶段:可行性评估。仓库里目前只有原型。

## 内容

| 路径 | 说明 |
| --- | --- |
| `prototype/index.html` | 可交互原型。单文件、无后端,Bot 回复为模拟,数字为示例数据。左下角可切换中英文。 |

## 查看原型

- 在线版本:https://claude.ai/artifact/7i8kCGWgXm1KmFFsFoaL4r (私有,需由所有者分享)
- 本地:用浏览器直接打开 `prototype/index.html`

## 可行性分析与实施规划

完整文档:https://claude.ai/artifact/XSxmyUMZahT1Zy1w57RXgq (私有,需由所有者分享)

要点:

- 结论:可行。推荐基于 Google Agent Platform(ADK、Agent Runtime、A2A)自建。
- 周期:约 38 周到全员可用,第 4 周有一个决定是否立项的验证关口。
- 团队:约 9 人,80 人月。
- 运行成本:1,000 名活跃员工、1,500 个 Bot 的假设下约 7 万美元/月(估算,单价待用官方报价复核)。
- 模型路由优先级:管理员强制 > Bot 所有者指定 > 自动选模。

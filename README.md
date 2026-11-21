# PEI Bot

Perry Ellis International 内部的企业级 Agent 平台:员工创建 24x7 运行的 Bot,Bot 之间可以互相调用,模型由 Gemini Decision 1 逐次自动选择,也可强制指定。网站可独立运作,Google Chat 和 Gmail 是可选入口。

当前阶段:技术设计。第一版只做底座空壳,Bot 功能以后作为插件加入。底座以北京团队的"PEI 全栈插件化应用平台"为主干(.NET、Cloud Run、插件化)。

## 内容

| 路径 | 说明 |
| --- | --- |
| `docs/design/` | 技术设计与已确认的决定 |
| `dev/` | 本地开发依赖:PostgreSQL 与 Redis 的 Compose 文件和数据库初始化脚本 |
| `contracts/` | 插件清单 JSON Schema、后端契约 `PEI.Platform.Abstractions`(.NET 10)、前端 `@pei/sdk` 类型,以及示例插件 |
| `prototype/index.html` | 可交互原型。单文件、无后端,Bot 回复为模拟,数字为示例数据。左下角可切换中英文。 |

## 查看原型

- 在线版本:https://claude.ai/artifact/7i8kCGWgXm1KmFFsFoaL4r (私有,需由所有者分享)
- 本地:用浏览器直接打开 `prototype/index.html`

## 可行性分析与实施规划

完整文档:https://claude.ai/artifact/XSxmyUMZahT1Zy1w57RXgq (私有,需由所有者分享)

要点:

- 结论:可行。推荐基于 Google Agent Platform(ADK、Agent Runtime、A2A)自建。
- 周期:约 44–46 周到全员可用,第 4 周有一个决定是否立项的验证关口。
- 团队:约 9 人,104–110 人月(含模块化内核 24–30 人月)。
- 运行成本:1,000 名活跃员工、1,500 个 Bot 的假设下约 7 万美元/月(估算,单价待用官方报价复核)。
- 模型路由优先级:管理员强制 > Bot 所有者指定 > Gemini Decision 1 自动选模。Decision 1 目前为预览版且尚未登陆 Vertex AI,期间由 Vertex 上的 Flash-Lite 兜底。
- 入口:网站是主系统;Google Chat、Gmail 为可选渠道,关闭后不影响功能。
- 架构:PEI Bot 内核是唯一部署的底层;界面、后端接口(TypeScript,V8 隔离运行时)和 Bot 工具都以模块形式上传并动态加载。原型的"模块"页演示了推送、晋升、回滚和停用。

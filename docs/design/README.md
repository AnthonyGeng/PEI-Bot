# PEI Bot 技术设计

本目录是 PEI Bot 底座的技术设计,主要读者是北京开发团队和 Coding Agent。能被机器校验的部分(清单格式、契约接口)放在 `contracts/` 下,设计说明放在这里。

可行性分析与决策过程见:https://claude.ai/artifact/XSxmyUMZahT1Zy1w57RXgq (私有,需由所有者分享)

## 已确认的决定

| 决定 | 内容 | 出处 |
| --- | --- | --- |
| 底座 | 以北京团队的"PEI 全栈插件化应用平台"为主干,PEI Bot 内核即其纯技术内核 | 可行性文档第 14 节 |
| 后端语言 | 统一 .NET;前端为 ESM | 第 14.5 节 |
| 进程结构 | Admin 控制面;User 拆为网关(内核,不加载插件)和宿主池(加载插件) | 第 14.3 节 |
| 宿主池 | 同一镜像、不同插件清单;起步三个:core、trade、experimental | 第 14.3 节 |
| 数据库 | 每插件一个 schema 和独立数据库角色;跨插件只读走带版本号的视图 | 第 14.4 节 |
| 后台任务 | 由内核调度服务(Cloud Scheduler + Cloud Tasks)回调,插件不自建线程 | 第 14.4 节 |
| 模型选择 | 管理员强制 > 所有者指定 > Gemini Decision 1;Decision 1 登陆 Vertex 前由 Flash-Lite 兜底 | 第 5 节 |
| 入口 | 网站独立运作;Google Chat、Gmail 为可选渠道,第二阶段再做 | 第 4.4 节 |
| 外部用户 | B2B 客户和大陆供应链用户暂不使用 Bot,由 `bot` 功能开关控制 | 第 14.9 节 |
| 范围 | 暂缓电脑操作和录屏教学;先到 30–50 人试点 | 第 13 节 |
| 实施顺序 | 先用 PEI Bot 插件验证底座,再迁主数据和 PLM,WebOrder 最后 | 第 14.7 节 |

## 设计文档

| 编号 | 主题 | 状态 |
| --- | --- | --- |
| 01 | [插件清单](01-plugin-manifest.md) · [Schema](../../contracts/manifest.schema.json) | 草案 v0.1 |
| 02 | 内核契约:`PEI.Platform.Abstractions` 与 `@pei/sdk` | 未开始 |
| 03 | 宿主池、隔离与资源配额 | 未开始 |
| 04 | 身份与权限:用户、Bot、委托、调用链、功能开关 | 未开始 |
| 05 | 数据模型:Bot、线程、运行、审批、审计 | 未开始 |
| 06 | Bot 运行时:Agent 循环、持久化、调度、互调 | 未开始 |
| 07 | 模型网关与 Decision 1 适配 | 未开始 |
| 08 | 部署拓扑:GCP 服务清单与环境 | 未开始 |
| 09 | 可观测性与运维手册 | 未开始 |

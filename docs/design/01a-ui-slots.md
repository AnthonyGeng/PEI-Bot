# 01a 界面插槽(草案 v0.1)

插件的界面全部通过插槽进入平台。外壳(内核前端)提供一组固定插槽;插件也可以提供扩展点,让其他插件往自己的页面里挂内容。清单写法见 [01 插件清单](01-plugin-manifest.md),格式见 [`contracts/manifest.schema.json`](../../contracts/manifest.schema.json)。

## 设计原则

1. **外壳业务全盲。** 外壳只提供页面、首页、顶栏、搜索、命令、设置这类通用位置。“款号详情页”“订单详情页”这类业务位置由业务插件以扩展点的形式提供。
2. **插件之间通过扩展点组合,不互相引用代码。** 工艺单插件往款号详情页加一个标签页,只需在清单里写 `core.masterdata/style.detail.tab@1`,不需要引用主数据插件的任何代码。
3. **涉及信任的界面只由内核绘制,不开放插槽。** 包括登录、审批卡片、权限确认、功能开关、通知中心和导航框架本身。插件提供数据,内核负责渲染,所以插件无法伪造或遮挡这些界面。
4. **任何一个插槽出错,只影响它自己。** 每个挂载点都有独立的错误边界和加载超时。

## 外壳插槽

| 插槽 | 位置 | 必填字段 | 外壳传入的参数 | 说明 |
| --- | --- | --- | --- | --- |
| `nav.page` | 左侧导航 + 主内容区 | `export` `route` `label` | 路由参数 | 带导航入口的页面。`group` 决定所在分组,`icon` 取自 SDK 图标集 |
| `route.page` | 主内容区 | `export` `route` | 路由参数 | 没有导航入口的页面,如详情页、深链接 `/techpack/:styleNo` |
| `home.widget` | 首页(值班台)卡片区 | `export` `label` `size` | 无 | 宽度 `s` / `m` / `l`。外壳按 `order` 排列,用户可隐藏 |
| `header.action` | 顶栏右侧按钮 | `export` `label` `icon` | 当前路由 | 全局入口,如“交给 Bot”。整个顶栏最多显示 4 个,其余收进“更多” |
| `command` | 命令面板(Ctrl/⌘ + K) | `label`,以及 `route` 或 `export` 二选一 | 无 | 填 `route` 时跳转;填 `export` 时运行该组件导出的命令函数 |
| `search.provider` | 全局搜索框 | `label` `endpoint` | 搜索词 | 外壳并行调用所有提供方的搜索接口,按 `label` 分组显示。不填 `export` 时用标准样式渲染结果 |
| `settings.page` | “设置”下的业务配置页 | `export` `route` `label` | 路由参数 | 路由挂在 `/settings` 下。插件的配置页在 User 端,不进入 Admin |
| `profile.section` | 个人设置中的一个分区 | `export` `label` | 无 | 个人偏好,如 Bot 通知方式 |

所有插槽都可以加 `permission`;没有权限的用户看不到这个挂载点。插件声明的 `requiresFeatures` 对它的全部插槽生效。

插件的业务配置页放在 User 端的 `settings.page`,不进 Admin。Admin 是控制面,保持不加载任何插件代码。

## 插件提供的扩展点

业务位置由插件在清单的 `frontend.extensionPoints` 里声明,其他插件用 `插件id/扩展点名@主版本` 挂载。

```json
"extensionPoints": [
  { "name": "style.detail.tab", "version": 1, "kind": "tab",
    "description": { "zh": "款号详情页的标签页", "en": "Tab on the style detail page" },
    "params": "frontend/extension-points/style-detail-tab.v1.json" }
]
```

| 字段 | 说明 |
| --- | --- |
| `name` | 扩展点名,在插件内唯一 |
| `version` | 主版本。传给挂载组件的参数一旦变化,必须新开主版本;旧版本至少保留一个大版本周期 |
| `kind` | `tab` 标签页、`panel` 区块、`action` 按钮或菜单项、`card` 卡片。决定外壳给它多大空间、怎么排列 |
| `params` | 传入参数的 JSON Schema 文件。SDK 据此为挂载方生成 TypeScript 类型 |
| `matchBy` | 挂载方可在 `match` 中使用的字段,如 `tool.result` 按工具名匹配 |

**挂载不需要 `dependsOn`。** 提供扩展点的插件不存在或被关闭时,挂载的内容不显示,其他功能照常。比如工艺单插件给 Bot 线程挂了一张结果卡片,而某个租户关闭了 Bot,工艺单插件仍然正常工作。提供方存在时,上传和加载都会检查主版本是否匹配。

### 第一批建议的扩展点

| 扩展点 | 提供方 | 种类 | 用途 |
| --- | --- | --- | --- |
| `core.masterdata/style.detail.tab@1` | 主数据 | tab | 工艺单、核价、打样往款号详情页加标签页 |
| `core.masterdata/style.detail.action@1` | 主数据 | action | 款号详情页上的操作,如“发起打样” |
| `core.masterdata/vendor.detail.tab@1` | 主数据 | tab | 供应商详情页的标签页 |
| `weborder.orders/order.detail.panel@1` | WebOrder | panel | 订单详情页的附加信息区 |
| `bot.threads/tool.result@1` | Bot 线程 | card | 业务插件为自己的工具结果提供卡片,如工艺单摘要;未挂载时显示通用卡片 |
| `bot.threads/message.action@1` | Bot 线程 | action | Bot 消息上的操作,如“在工艺单中打开” |
| `bot.manager/bot.tab@1` | Bot 管理 | tab | Bot 详情页的标签页 |

## 每个挂载组件拿到什么

外壳给每个挂载的组件传入两样东西,类型定义见 [02 内核契约](02-kernel-contracts.md):

- **`ctx`(所有插槽相同)**:当前用户、租户、界面语言、用户时区、权限检查函数、功能开关,以及读取上下文的方法。品牌这类业务上下文由提供它的插件发布,其他插件按键名读取,例如 `ctx.context.get("core.brandscope/current@1")`。外壳本身不知道“品牌”是什么。
- **`params`(按插槽不同)**:路由参数、卡片尺寸,或扩展点 `params` 文件定义的参数。


## 加载与出错

| 情况 | 外壳的处理 |
| --- | --- |
| 首次进入视野 | 才加载对应模块;首页卡片和标签页都按需加载 |
| 加载超过 10 秒或脚本加载失败 | 显示占位卡片和“重试”按钮,其他挂载点照常 |
| 渲染时抛出异常 | 错误边界接住,显示占位卡片,上报到插件的错误统计 |
| 同一插件短时间内反复出错 | 外壳暂时不再加载它,提示“该功能暂不可用”;错误统计同时触发第 14.3 节的自动回滚判断 |
| 样式 | 插件样式只作用于自己的挂载点,不能修改外壳和其他插件 |

## 排序、冲突与管理员覆盖

- **排序**:按 `order` 从小到大,相同时按插件 ID 排序。
- **路由冲突**:上传时拒绝。路由第一段默认应与插件 ID 相关,避免抢占通用路径。
- **导航分组**:由 Admin 按租户配置(如“企划”“产品开发”“订单”“Bot”)。插件只写分组 ID,未知分组归入“其他”。
- **管理员覆盖**:Admin 可以按租户调整顺序、隐藏某个挂载点、改分组名,不需要重新发布插件。

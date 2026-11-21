# 01 插件清单(草案 v0.2)

每个全栈插件包的根目录有一份 `manifest.json`,它是插件与内核之间唯一的声明式契约。内核据此加载插件、分配权限、注册工具和定时任务、开放网络。格式由 [`contracts/manifest.schema.json`](../../contracts/manifest.schema.json) 定义,示例见 [`contracts/examples/`](../../contracts/examples/)。

## 包结构

```
plm.techpack-0.3.0.zip
├── manifest.json
├── backend/
│   ├── Pei.Plm.TechPack.dll
│   └── openapi.json        # 接口定义,工具的参数结构由此生成
├── frontend/
│   ├── index.js            # ES Module,导出各插槽组件
│   ├── index.css
│   └── extension-points/   # 本插件提供的扩展点的参数定义
└── migrations/
    └── 0001_init.sql       # 幂等、只增不改
```

## 字段说明

| 字段 | 必填 | 作用 |
| --- | --- | --- |
| `manifestVersion` | 是 | 固定为 1 |
| `id` | 是 | 全局唯一,小写点分,如 `plm.techpack`;发布后不可更改 |
| `version` | 是 | 语义化版本;每次上传必须大于当前最高版本 |
| `displayName` / `description` | 前者是 | 中英文名称和说明 |
| `sdk` | 是 | 兼容的契约版本范围,同时约束后端和前端 SDK。NuGet 写法,见下文 |
| `dependsOn` | 否 | 前置插件及版本范围,决定安装顺序;不允许直接代码引用 |
| `requiresFeatures` | 否 | 依赖的功能开关。Bot 相关插件必须声明 `bot`,开关关闭时整个插件对该租户或用户组不可见 |
| `poolHint` | 否 | 建议的宿主池,最终由 Admin 分配 |
| `permissions` | 否 | 本插件定义的权限点,用户和 Bot 共用 |
| `backend` | 否 | 程序集、入口类型、路由前缀、接口定义 |
| `frontend` | 否 | ESM 入口、样式、挂载的插槽、本插件提供的扩展点。见 [01a 界面插槽](01a-ui-slots.md) |
| `database` | 否 | 自有 schema、迁移目录、对外视图、要读取的视图 |
| `tools` | 否 | 暴露给 Bot 的工具,见下文 |
| `schedules` | 否 | 定时任务,由内核回调;cron 按 UTC 解释 |
| `events` | 否 | 发布和订阅的事件,主题带版本号 |
| `egress` | 否 | 出站网络;未声明的目标一律拒绝 |
| `limits` | 否 | 数据库连接数、请求超时、并发上限 |

## 版本范围

`sdk` 和 `dependsOn[].version` 一律使用 NuGet 的版本范围写法,前后端相同:

| 写法 | 含义 |
| --- | --- |
| `1.2` | ≥ 1.2 |
| `[1.0,2.0)` | ≥ 1.0 且 < 2.0 |
| `[1.2.3]` | 恰好 1.2.3 |
| `(,2.0]` | ≤ 2.0 |

不支持浮动版本(`1.*`)。`sdk` 建议写成“当前主版本到下一个主版本之前”,如 `[1.0,2.0)`。插件自身的 `version` 仍是三段式语义化版本。

## 工具

> 第一版不做 Bot。内核会校验并登记工具声明,但不启用;Bot 插件上线后直接可用。

插件把已有接口声明为工具,Bot 即可调用;插件不需要知道 Bot 的存在。

```json
{
  "name": "techpack.submit_for_review",
  "description": { "zh": "把一份草稿工艺单提交给技术部审核……", "en": "Submit a draft tech pack……" },
  "risk": "L2",
  "endpoint": "POST /techpacks/{styleNo}/submit",
  "permission": "techpack.submit"
}
```

- **参数结构**从 `backend.openApi` 里对应接口生成,不在清单里重复书写。
- **`description` 写给模型看**:做什么、什么时候用、什么时候不该用。它直接影响 Bot 选工具的准确度。
- **`summary`** 是审批卡片上的一句话,可用 `{参数名}` 引用调用参数,L2、L3 工具必填。卡片由内核渲染,插件只提供这句话。
- **`risk`** 决定审批:L0 只读,L1 可撤销的内部写入,L2 对外或难撤销,L3 付款、删除、改权限。运行时 Decision 1 只能把级别调高,不能调低。
- **`permission`** 是调用所需的权限点。Bot 以委托它的员工身份调用,权限不会超过该员工。
- **`externalAllowed`** 默认为否。将来即使对外部租户打开 Bot,也只有显式标记的工具会提供给它。

## 定时任务与时间

**平台内的时间一律用 UTC。** 数据库存储、接口传输、日志、cron 都是 UTC;接口中的时间写成带 `Z` 的 ISO 8601,如 `2026-11-21T00:00:00Z`。界面显示时换算成用户的时区:默认取浏览器的时区,用户可在个人设置中覆盖。`@pei/sdk` 提供统一的格式化函数,插件不自己换算。

```json
"schedules": [
  { "id": "overdue_reminders", "cron": "0 0 * * 1-5", "endpoint": "POST /jobs/overdue-reminders" }
]
```

上例是 UTC 工作日 00:00,即北京时间早上 8 点。

**有一个例外。** UTC 没有夏令时,而美国有。一个按 UTC 写死的任务,在美国夏令时切换后会提前或推后一小时。北京没有夏令时,不受影响;但“每个工作日纽约时间早上 9 点”这类必须跟着当地钟点走的任务,可以填 `timeZone`(IANA 时区名),此时 cron 按该时区解释。这个字段默认为 `UTC`,插件自带的任务通常不需要填。

用户在界面上为 Bot 设的定时(如“每天早上 8 点给我简报”)属于这种情况:平台会记下用户的时区,让简报在夏令时切换后仍然是当地早上 8 点。

## 上传时的校验

Schema 只覆盖格式。内核在上传时还要做以下检查,任何一项不过都不生成版本:

**引用完整性**

1. 工具和插槽引用的权限点必须存在于本插件或 `dependsOn` 的插件中。
2. 挂载到其他插件扩展点时,若提供方已安装,主版本必须存在;提供方未安装时允许上传,挂载内容不显示。
3. `database.reads` 中的每个视图,必须由 `dependsOn` 里某个插件的 `exposes` 提供。
4. 工具的 `endpoint` 必须出现在 `openApi` 中;`summary` 引用的参数必须是该接口的参数。
5. `routePrefix`、页面路由、`database.schema`、事件主题的前缀不得与其他插件冲突。
6. 声明了 `egress.internalNetwork` 的插件,只能分配到开放内网出口的池。

**只增不改(与当前正式版本对比)**

1. 权限点、工具、对外视图、扩展点、发布的事件不得删除。不再使用的标记为弃用,保留至少一个大版本。
2. 工具的 `risk` 不得调低,`permission` 不得改成更宽的权限点。
3. 新增的权限点或 `egress` 目标,需要管理员批准后才能进入正式通道。

## 与平台原设计的差异

相对于北京团队平台设计中的 manifest(ID、版本、`dependsOn`、菜单排序、权限点),本草案新增:`requiresFeatures`、`poolHint`、`tools`、`schedules`、`events`、`egress`、`limits`、`frontend.extensionPoints`,以及 `database.exposes` / `reads`。这些都对应可行性文档第 14 节的整合决定。

## 变更记录

| 版本 | 变更 |
| --- | --- |
| v0.2 | 版本范围改为 NuGet 写法;定时任务改为 UTC,保留 `timeZone` 例外;完整的插槽与扩展点设计(见 01a);工具增加审批摘要 `summary` |
| v0.1 | 初稿 |

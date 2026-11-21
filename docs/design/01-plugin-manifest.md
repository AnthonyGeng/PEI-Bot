# 01 插件清单(草案 v0.1)

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
│   └── index.css
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
| `sdk` | 是 | 兼容的契约版本范围,同时约束后端和前端 SDK |
| `dependsOn` | 否 | 前置插件及版本范围,决定安装顺序;不允许直接代码引用 |
| `requiresFeatures` | 否 | 依赖的功能开关。Bot 相关插件必须声明 `bot`,开关关闭时整个插件对该租户或用户组不可见 |
| `poolHint` | 否 | 建议的宿主池,最终由 Admin 分配 |
| `permissions` | 否 | 本插件定义的权限点,用户和 Bot 共用 |
| `backend` | 否 | 程序集、入口类型、路由前缀、接口定义 |
| `frontend` | 否 | ESM 入口、样式、插槽挂载点 |
| `database` | 否 | 自有 schema、迁移目录、对外视图、要读取的视图 |
| `tools` | 否 | 暴露给 Bot 的工具,见下文 |
| `schedules` | 否 | 定时任务,由内核回调 |
| `events` | 否 | 发布和订阅的事件,主题带版本号 |
| `egress` | 否 | 出站网络;未声明的目标一律拒绝 |
| `limits` | 否 | 数据库连接数、请求超时、并发上限 |

## 工具

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
- **`risk`** 决定审批:L0 只读,L1 可撤销的内部写入,L2 对外或难撤销,L3 付款、删除、改权限。运行时 Decision 1 只能把级别调高,不能调低。
- **`permission`** 是调用所需的权限点。Bot 以委托它的员工身份调用,权限不会超过该员工。
- **`externalAllowed`** 默认为否。将来即使对外部租户打开 Bot,也只有显式标记的工具会提供给它。

## 上传时的校验

Schema 只覆盖格式。内核在上传时还要做以下检查,任何一项不过都不生成版本:

**引用完整性**

1. 工具和插槽引用的权限点必须存在于本插件或 `dependsOn` 的插件中。
2. `database.reads` 中的每个视图,必须由 `dependsOn` 里某个插件的 `exposes` 提供。
3. 工具的 `endpoint` 必须出现在 `openApi` 中。
4. `routePrefix`、`database.schema`、事件主题的前缀不得与其他插件冲突。
5. 声明了 `egress.internalNetwork` 的插件,只能分配到开放内网出口的池。

**只增不改(与当前正式版本对比)**

1. 权限点、工具、对外视图、发布的事件不得删除。不再使用的标记为弃用,保留至少一个大版本。
2. 工具的 `risk` 不得调低,`permission` 不得改成更宽的权限点。
3. 新增的权限点或 `egress` 目标,需要管理员批准后才能进入正式通道。

## 与平台原设计的差异

相对于北京团队平台设计中的 manifest(ID、版本、`dependsOn`、菜单排序、权限点),本草案新增:`requiresFeatures`、`poolHint`、`tools`、`schedules`、`events`、`egress`、`limits`,以及 `database.exposes` / `reads`。这些都对应可行性文档第 14 节的整合决定。

## 待定

- `sdk` 版本范围的写法(NuGet 风格还是 npm 风格),需与 02 号文档一起定。
- 插槽列表 `nav.page`、`thread.card`、`bot.tab`、`admin.page`、`home.widget` 是初稿,随外壳设计调整。
- 定时任务默认时区暂定 `America/New_York`;是否改为按租户配置待定。

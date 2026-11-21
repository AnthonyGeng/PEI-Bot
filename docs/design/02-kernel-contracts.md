# 02 内核契约(草案 v0.1)

插件与内核之间只通过两份契约交互:后端的 `PEI.Platform.Abstractions`(.NET 程序集)和前端的 `@pei/sdk`(TypeScript 类型)。两者版本号一致,规则相同:只增不改。

| 契约 | 位置 | 状态 |
| --- | --- | --- |
| 后端 `PEI.Platform.Abstractions` 1.0.0-preview.1 | [`contracts/dotnet/Pei.Platform.Abstractions/`](../../contracts/dotnet/Pei.Platform.Abstractions/) | .NET 10 编译通过,警告视为错误 |
| 后端示例插件 | [`contracts/dotnet/examples/Pei.Sample.Hello/`](../../contracts/dotnet/examples/Pei.Sample.Hello/) | 编译通过;输出不含契约程序集 |
| 前端 `@pei/sdk` 1.0.0-preview.1 | [`contracts/sdk/pei-sdk.d.ts`](../../contracts/sdk/pei-sdk.d.ts) | TypeScript strict 模式检查通过 |
| 前端示例 | [`contracts/sdk/examples/hello-frontend.tsx`](../../contracts/sdk/examples/hello-frontend.tsx) | 类型检查通过 |
| 示例插件清单与迁移脚本 | [`contracts/examples/sample.hello.manifest.json`](../../contracts/examples/sample.hello.manifest.json) | Schema 校验通过 |

`sample.hello` 就是第一版用来验证底座的示例插件:一个读接口、一个写接口、一个定时任务、一个事件订阅、三个插槽。

## 后端契约

### 插件入口

```csharp
public interface IPlugin
{
    void ConfigureServices(IServiceCollection services, IPluginContext context);
    void MapEndpoints(IEndpointRouteBuilder endpoints, IPluginContext context);
    Task OnActivatedAsync(IPluginContext context, CancellationToken ct) => Task.CompletedTask;
    Task OnDeactivatingAsync(IPluginContext context, CancellationToken ct) => Task.CompletedTask;
}
```

- 宿主为每个插件版本创建独立的 `AssemblyLoadContext` 和独立的依赖注入容器,内核服务预先注册在其中。
- 接口直接用 ASP.NET Core 的 Minimal API 或 Controller 写,路由相对于清单中的 `routePrefix`。
- 权限点用 `.RequirePermission("techpack.read")` 声明,由宿主执行,插件代码里不必再判断。
- 定时任务和事件订阅的接口用 `.KernelOnly()` 标记,浏览器发来的请求一律拒绝。

### 内核提供的服务

插件通过依赖注入拿到以下服务。插件拿不到登录令牌、数据库主账号、其他插件的数据和任何全局配置。

| 服务 | 作用 | 第一版 |
| --- | --- | --- |
| `IRequestContext` | 当前主体、租户、语言、时区、关联 ID | 是 |
| `IPermissionService` | 判断权限点 | 是 |
| `IFeatureFlags` | 功能开关,如 `bot` | 是 |
| `IPluginDatabase` | 打开数据库连接:插件专属角色、自己的 schema、连接数上限和语句超时 | 是 |
| `IPluginBlobStore` | 文件存储,限定在插件自己的前缀下,一律用流 | 是 |
| `IPluginCache` | 缓存,键自动加插件前缀,必须设过期时间 | 是 |
| `IPluginSecrets` | 在 Admin 中为插件配置的密钥,如机房 ERP 连接串 | 是 |
| `IAuditLog` | 写审计,内核自动补主体、租户、插件、UTC 时间、关联 ID | 是 |
| `IEventPublisher` | 发布事件,主题必须已在清单中声明 | 是 |
| `IContextValues` / `IContextValueProvider` | 读取或发布跨插件的上下文值,如当前品牌 | 接口先定,随 Brand Scope 插件启用 |
| `TimeProvider`、`ILogger<T>`、`IHttpClientFactory` | .NET 标准服务;时间一律取 UTC | 是 |

内核调用插件时的请求体:

- 定时任务收到 `JobInvocation`(`JobId`、`RunId`、`ScheduledFor`、`Attempt`)。
- 事件订阅收到 `EventDelivery<T>`(`EventId`、`Topic`、`OccurredAt`、`Attempt`、`Payload`)。

两者都可能重复投递,插件按 `RunId` 或 `EventId` 做幂等。

### 版本规则

- **契约程序集由宿主提供,插件包里不能带。** 宿主在默认加载上下文中只加载一份 `PEI.Platform.Abstractions` 和 ASP.NET Core 共享框架;上传时发现包里带了这些程序集就拒绝。示例插件的工程文件演示了正确的引用方式(`Private="false"`、`ExcludeAssets="runtime"`)。
- **内核实现、插件调用的接口**(如 `IPluginDatabase`):可以新增成员。
- **插件实现的接口**(`IPlugin`、`IContextValueProvider`):新增成员必须带默认实现,否则旧插件无法加载。
- **记录类型**(如 `Actor`):新增属性只能加在末尾,并带默认值。
- **枚举**:只增不改。`ActorKind.Bot` 已预留,第一版不会出现。
- 上传时检查插件引用的契约版本落在清单 `sdk` 范围内,并且不高于宿主当前提供的版本。

## 前端契约

插件的 `frontend/index.js` 是一个 ES Module,按清单中各插槽的 `export` 字段导出组件(`command` 导出的是命令函数)。React、设计系统和 `@pei/sdk` 由外壳通过 Import Map 提供,插件打包时设为外部依赖。

每个挂载组件收到 `{ ctx, params }`:

```ts
export const GreetingsPage: SlotComponent<PageParams> = ({ ctx, params }) => { … };
```

| `ctx` 成员 | 作用 |
| --- | --- |
| `user` `tenant` `plugin` | 当前用户(含语言和时区)、租户、插件版本与通道 |
| `can(permission)` | 权限判断,与后端用同一套权限点 |
| `features.has(name)` | 功能开关 |
| `context.get(key)` / `subscribe` | 跨插件上下文值,如当前品牌 |
| `api` | 访问本插件后端。路径相对于 `routePrefix`;自动带登录态、插件版本号和关联 ID;出错时抛出 Problem Details |
| `navigate(route)` | 页面跳转 |
| `format` | 把 UTC 时间按用户时区和语言显示;数字和货币格式化 |
| `text(i18n)` | 按当前语言取中英文文本 |
| `toast(message)` | 轻提示 |

`params` 因插槽而异:页面类插槽是路由参数,首页卡片是尺寸,扩展点是提供方在 `params` 文件中定义的结构。

## 前后端接口约定

| 项目 | 约定 |
| --- | --- |
| 路径 | `/api/{routePrefix}/…`,由前端 `ctx.api` 自动拼接 |
| 登录态 | 由外壳和网关处理,插件前后端都看不到令牌 |
| 插件版本 | 前端请求带 `X-Pei-Plugin-Version`;版本切换期间,宿主按此把请求交给对应版本 |
| 关联 ID | `X-Correlation-Id`,贯穿网关、宿主、审计和日志 |
| JSON | camelCase;时间是带 `Z` 的 UTC ISO 8601;C# 一侧用 `DateTimeOffset` |
| 错误 | RFC 9457 Problem Details;权限不足 403、找不到 404、校验失败 422 |
| 分页 | 游标分页:`?cursor=&limit=`,返回 `{ items, nextCursor }` |
| 兼容性 | 新版本接口必须兼容上一版本前端的调用(第 14.4 节) |

## 插件编码规范

这些规则保证插件能被安全地卸载和隔离。能自动检查的会放进上传校验和插件脚手架。

1. 不用可变的静态字段,不缓存在静态集合里;需要缓存用 `IPluginCache`。
2. 不自己启动线程、`Timer`、`BackgroundService` 或常驻的 `Task.Run`;需要周期执行就在清单里声明定时任务。
3. 不写本地磁盘;文件用 `IPluginBlobStore`。
4. 数据库只用 `IPluginDatabase` 给的连接,用完立即释放。
5. HTTP 调用只用 `IHttpClientFactory`;目标必须在清单 `egress` 中声明。
6. 数据访问推荐 Dapper 或直接用 ADO.NET。EF Core 在可回收加载上下文里的卸载表现,要在 PoC 中验证后再决定是否允许。
7. 不在包里携带契约程序集和 ASP.NET Core 共享框架的任何程序集。

## 第一版的身份

第一版用最基本的本地账号,之后迁到 GIP。设计上让这次迁移对插件完全透明:

| 项目 | 第一版做法 | 迁到 GIP 时 |
| --- | --- | --- |
| 用户 ID | 内核分配的内部 ID,插件只见到它 | 不变 |
| 登录 | 用户名和密码,密码用 ASP.NET Core Identity 的哈希算法存储;连续 5 次失败锁定 15 分钟 | 改为 GIP 登录,首次登录时按邮箱关联到已有用户 |
| 开户 | 只能由管理员在 Admin 中创建,不开放自助注册 | 由 GIP 和公司目录同步 |
| 会话 | 网关签发 HttpOnly、Secure、SameSite 的会话 Cookie | 不变,只是签发前的认证换成 GIP |
| 外部身份表 | 建表但为空 | 写入 GIP 的身份映射 |

Admin 控制面用基本账号保护力度有限。建议第一版就在 Admin 前面加一层 Cloud IAP(公司已有 Google Workspace 账号,配置成本低),Admin 自己的账号作为第二道门。

## 待定

- 外壳通过 Import Map 提供的 React 版本:建议 React 19,在外壳实现时确定,定下后写入 `@pei/sdk` 的说明。
- `@pei/sdk` 图标集的名单。
- 插件本地开发的方式(连共享开发环境热更新),在脚手架设计中确定。

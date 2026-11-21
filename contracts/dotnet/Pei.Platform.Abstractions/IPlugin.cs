using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;

namespace Pei.Platform.Abstractions;

/// <summary>
/// 插件入口。清单中 backend.entryType 指向实现本接口的类型,该类型须有公开的无参构造函数。
/// 宿主为每个插件版本创建独立的加载上下文和独立的依赖注入容器。
/// </summary>
/// <remarks>
/// 本接口由插件实现。以后新增的成员一律带默认实现,保证旧插件无需重新编译。
/// </remarks>
public interface IPlugin
{
    /// <summary>注册插件自己的服务。内核服务(本程序集中的接口)已预先注册,可直接注入。</summary>
    void ConfigureServices(IServiceCollection services, IPluginContext context);

    /// <summary>
    /// 注册接口。路由相对于清单中的 routePrefix。
    /// 用 <see cref="EndpointConventionExtensions.RequirePermission{TBuilder}"/> 声明权限点,
    /// 用 <see cref="EndpointConventionExtensions.KernelOnly{TBuilder}"/> 标记只允许内核调用的接口(定时任务、事件订阅)。
    /// </summary>
    void MapEndpoints(IEndpointRouteBuilder endpoints, IPluginContext context);

    /// <summary>该版本开始接收流量前调用一次。不要在这里启动后台线程。</summary>
    Task OnActivatedAsync(IPluginContext context, CancellationToken cancellationToken) => Task.CompletedTask;

    /// <summary>该版本停止接收流量、即将卸载前调用一次。用于释放资源,必须在 10 秒内返回。</summary>
    Task OnDeactivatingAsync(IPluginContext context, CancellationToken cancellationToken) => Task.CompletedTask;
}

/// <summary>插件级上下文,在插件版本的整个生命周期内不变。</summary>
public interface IPluginContext
{
    /// <summary>当前加载的插件。</summary>
    PluginInfo Plugin { get; }

    /// <summary>运行环境:dev、staging 或 prod。</summary>
    string Environment { get; }
}

/// <summary>插件的基本信息,来自清单与发布记录。</summary>
/// <param name="Id">插件 ID,如 plm.techpack。</param>
/// <param name="Version">插件版本。</param>
/// <param name="RoutePrefix">接口路由前缀,如 /api/plm/techpack。</param>
/// <param name="Schema">插件自有的数据库 schema;没有数据库时为 null。</param>
/// <param name="Channel">所在通道:dev、beta 或 stable。</param>
public sealed record PluginInfo(string Id, string Version, string RoutePrefix, string? Schema, string Channel);

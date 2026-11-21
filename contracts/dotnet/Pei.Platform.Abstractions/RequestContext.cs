namespace Pei.Platform.Abstractions;

/// <summary>当前请求的上下文,按请求注入。插件看不到登录令牌,只看到内核解析后的身份。</summary>
public interface IRequestContext
{
    /// <summary>发起本次请求的主体。</summary>
    Actor Actor { get; }

    /// <summary>当前租户。内部员工属于内部租户;外部 B2B 客户各自是一个租户。</summary>
    TenantInfo Tenant { get; }

    /// <summary>界面语言,如 zh-CN、en-US。</summary>
    string Locale { get; }

    /// <summary>用户的 IANA 时区,如 Asia/Shanghai。仅用于需要按当地日期计算的业务逻辑;存储与传输一律用 UTC。</summary>
    string TimeZone { get; }

    /// <summary>贯穿网关、宿主与日志的关联 ID。</summary>
    string CorrelationId { get; }
}

/// <summary>请求的发起者。</summary>
/// <param name="Kind">主体类型。</param>
/// <param name="Id">内部 ID。用户 ID 由内核分配,不随身份提供方变化(本地账号迁到 GIP 后不变)。</param>
/// <param name="DisplayName">显示名称。</param>
/// <param name="Email">邮箱;系统主体为 null。</param>
/// <param name="OnBehalfOfUserId">Bot 代表用户行事时,被代表用户的 ID。第一版恒为 null。</param>
public sealed record Actor(ActorKind Kind, string Id, string DisplayName, string? Email, string? OnBehalfOfUserId = null);

/// <summary>主体类型。</summary>
public enum ActorKind
{
    /// <summary>登录的用户。</summary>
    User = 0,

    /// <summary>内核自身,例如定时任务和事件投递。</summary>
    System = 1,

    /// <summary>Bot。预留,第一版不会出现。</summary>
    Bot = 2,
}

/// <summary>租户信息。</summary>
/// <param name="Id">租户 ID。</param>
/// <param name="Name">租户名称。</param>
/// <param name="IsExternal">是否外部租户。</param>
public sealed record TenantInfo(string Id, string Name, bool IsExternal);

/// <summary>权限判断。权限点写作本插件内的名称(techpack.read),或 插件id:名称 引用其他插件的权限点。</summary>
public interface IPermissionService
{
    /// <summary>当前主体是否拥有该权限点。</summary>
    bool Has(string permission);

    /// <summary>没有该权限点时抛出 <see cref="PermissionDeniedException"/>,内核将其转换为 403。</summary>
    void Demand(string permission);
}

/// <summary>权限不足。内核将其转换为 403 Problem Details。</summary>
public sealed class PermissionDeniedException(string permission)
    : Exception($"Missing permission '{permission}'.")
{
    /// <summary>缺少的权限点。</summary>
    public string Permission { get; } = permission;
}

/// <summary>功能开关,例如 bot。</summary>
public interface IFeatureFlags
{
    /// <summary>该功能对当前租户和用户是否开启。</summary>
    bool IsEnabled(string feature);
}

/// <summary>
/// 读取其他插件发布的上下文值,键写作 插件id/名称@主版本,例如 core.brandscope/current@1。
/// 内核不理解这些值的含义,只负责转发给提供方。
/// </summary>
public interface IContextValues
{
    /// <summary>读取上下文值;提供方未安装或未启用时返回 default。</summary>
    ValueTask<T?> GetAsync<T>(string key, CancellationToken cancellationToken = default);
}

/// <summary>上下文值的提供方。插件在清单 contexts.provides 中声明,并在 ConfigureServices 中注册实现。</summary>
public interface IContextValueProvider
{
    /// <summary>不含插件 ID 的名称与主版本,例如 current@1。</summary>
    string Name { get; }

    /// <summary>为当前请求解析上下文值。</summary>
    ValueTask<object?> ResolveAsync(IRequestContext request, CancellationToken cancellationToken);
}

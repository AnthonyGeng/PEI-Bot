using Microsoft.AspNetCore.Builder;

namespace Pei.Platform.Abstractions;

/// <summary>接口所需的权限点。由网关和宿主共同执行,插件代码里不必再判断。</summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public sealed class RequirePermissionAttribute(string permission) : Attribute
{
    /// <summary>权限点。</summary>
    public string Permission { get; } = permission;
}

/// <summary>只允许内核调用的接口,例如定时任务和事件订阅。浏览器的请求一律拒绝。</summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class)]
public sealed class KernelOnlyAttribute : Attribute;

/// <summary>为 Minimal API 提供与上面两个特性等价的写法。</summary>
public static class EndpointConventionExtensions
{
    /// <summary>声明接口所需的权限点。</summary>
    public static TBuilder RequirePermission<TBuilder>(this TBuilder builder, string permission)
        where TBuilder : IEndpointConventionBuilder
        => builder.WithMetadata(new RequirePermissionAttribute(permission));

    /// <summary>标记为只允许内核调用。</summary>
    public static TBuilder KernelOnly<TBuilder>(this TBuilder builder)
        where TBuilder : IEndpointConventionBuilder
        => builder.WithMetadata(new KernelOnlyAttribute());
}

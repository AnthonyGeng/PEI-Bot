using System.Data.Common;

namespace Pei.Platform.Abstractions;

/// <summary>
/// 插件的数据库访问。连接使用插件专属的数据库角色,search_path 指向插件自己的 schema,
/// 并带有清单 limits 中的连接数上限和语句超时。
/// </summary>
public interface IPluginDatabase
{
    /// <summary>打开一个连接。用完必须释放。</summary>
    ValueTask<DbConnection> OpenConnectionAsync(CancellationToken cancellationToken = default);
}

/// <summary>插件专属的文件存储,路径自动限定在插件自己的前缀下。大文件一律用流,不落本地磁盘。</summary>
public interface IPluginBlobStore
{
    /// <summary>上传。同名文件会被覆盖。</summary>
    Task UploadAsync(string path, Stream content, string contentType, CancellationToken cancellationToken = default);

    /// <summary>读取;文件不存在时返回 null。</summary>
    Task<Stream?> OpenReadAsync(string path, CancellationToken cancellationToken = default);

    /// <summary>生成有时效的下载地址,供浏览器直接下载。</summary>
    Task<Uri> GetDownloadUrlAsync(string path, TimeSpan validFor, CancellationToken cancellationToken = default);

    /// <summary>删除;文件不存在时不报错。</summary>
    Task DeleteAsync(string path, CancellationToken cancellationToken = default);
}

/// <summary>插件专属的缓存,键自动加插件前缀。缓存可能随时丢失,不能当存储用。</summary>
public interface IPluginCache
{
    /// <summary>读取;不存在时返回 default。</summary>
    ValueTask<T?> GetAsync<T>(string key, CancellationToken cancellationToken = default);

    /// <summary>写入,必须给出过期时间。</summary>
    ValueTask SetAsync<T>(string key, T value, TimeSpan expiresIn, CancellationToken cancellationToken = default);

    /// <summary>删除。</summary>
    ValueTask RemoveAsync(string key, CancellationToken cancellationToken = default);
}

/// <summary>在 Admin 中为插件配置的密钥,例如机房 ERP 的连接串。值不会写进日志。</summary>
public interface IPluginSecrets
{
    /// <summary>读取;未配置时返回 null。</summary>
    ValueTask<string?> GetAsync(string name, CancellationToken cancellationToken = default);
}

/// <summary>写审计记录。内核会自动补上主体、租户、插件、时间(UTC)和关联 ID。</summary>
public interface IAuditLog
{
    /// <summary>记录一次业务操作。</summary>
    /// <param name="action">动作,如 techpack.submitted。</param>
    /// <param name="target">对象,如款号。</param>
    /// <param name="details">附加信息,会被序列化为 JSON。不要放密钥和个人敏感信息。</param>
    /// <param name="cancellationToken">取消标记。</param>
    Task WriteAsync(string action, string? target = null, object? details = null, CancellationToken cancellationToken = default);
}

/// <summary>发布事件。主题必须已在清单 events.publishes 中声明,否则抛出异常。</summary>
public interface IEventPublisher
{
    /// <summary>发布。至少投递一次,订阅方须按 EventId 去重。</summary>
    Task PublishAsync<T>(string topic, T payload, CancellationToken cancellationToken = default);
}

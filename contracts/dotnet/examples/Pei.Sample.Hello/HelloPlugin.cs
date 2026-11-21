using System.Data.Common;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Pei.Platform.Abstractions;

namespace Pei.Sample.Hello;

/// 第一版用来验证底座的示例插件:一个读接口、一个写接口、一个定时任务、一个事件订阅。
public sealed class HelloPlugin : IPlugin
{
    public void ConfigureServices(IServiceCollection services, IPluginContext context)
        => services.AddScoped<GreetingRepository>();

    public void MapEndpoints(IEndpointRouteBuilder endpoints, IPluginContext context)
    {
        endpoints.MapGet("/greetings", async (GreetingRepository repo, CancellationToken ct)
                => Results.Ok(await repo.ListAsync(ct)))
            .RequirePermission("hello.read");

        endpoints.MapPost("/greetings", async (NewGreeting body, GreetingRepository repo,
                IRequestContext request, IAuditLog audit, IEventPublisher events, CancellationToken ct) =>
            {
                var id = await repo.AddAsync(body.Text, request.Actor.Id, ct);
                await audit.WriteAsync("hello.greeting_created", id, new { body.Text }, ct);
                await events.PublishAsync("sample.hello/greeting_created.v1", new { Id = id }, ct);
                return Results.Created($"/greetings/{id}", new { Id = id });
            })
            .RequirePermission("hello.write");

        endpoints.MapPost("/jobs/daily-digest", (JobInvocation job, TimeProvider clock)
                => Results.Ok(new { job.RunId, CompletedAt = clock.GetUtcNow() }))
            .KernelOnly();

        endpoints.MapPost("/events/style-updated", (EventDelivery<StyleUpdated> delivery)
                => Results.Ok(new { delivery.EventId }))
            .KernelOnly();
    }
}

public sealed record NewGreeting(string Text);

public sealed record StyleUpdated(string StyleNo);

public sealed record Greeting(string Id, string Text, string CreatedBy, DateTimeOffset CreatedAt);

/// 直接用 ADO.NET 访问插件自己的 schema;连接来自内核,带插件专属角色和上限。
public sealed class GreetingRepository(IPluginDatabase db, TimeProvider clock)
{
    public async Task<IReadOnlyList<Greeting>> ListAsync(CancellationToken ct)
    {
        await using DbConnection conn = await db.OpenConnectionAsync(ct);
        await using DbCommand cmd = conn.CreateCommand();
        cmd.CommandText = "select id, text, created_by, created_at from greetings order by created_at desc limit 50";
        await using DbDataReader reader = await cmd.ExecuteReaderAsync(ct);
        var items = new List<Greeting>();
        while (await reader.ReadAsync(ct))
        {
            items.Add(new Greeting(reader.GetString(0), reader.GetString(1), reader.GetString(2),
                reader.GetFieldValue<DateTimeOffset>(3)));
        }
        return items;
    }

    public async Task<string> AddAsync(string text, string createdBy, CancellationToken ct)
    {
        var id = Guid.CreateVersion7().ToString();
        await using DbConnection conn = await db.OpenConnectionAsync(ct);
        await using DbCommand cmd = conn.CreateCommand();
        cmd.CommandText = "insert into greetings (id, text, created_by, created_at) values (@id, @text, @by, @at)";
        AddParam(cmd, "id", id);
        AddParam(cmd, "text", text);
        AddParam(cmd, "by", createdBy);
        AddParam(cmd, "at", clock.GetUtcNow());
        await cmd.ExecuteNonQueryAsync(ct);
        return id;
    }

    private static void AddParam(DbCommand cmd, string name, object value)
    {
        DbParameter p = cmd.CreateParameter();
        p.ParameterName = name;
        p.Value = value;
        cmd.Parameters.Add(p);
    }
}

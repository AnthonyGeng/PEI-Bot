namespace Pei.Platform.Abstractions;

/// <summary>内核投递给事件订阅接口的请求体。同一 EventId 可能重复投递,订阅方须幂等。</summary>
/// <typeparam name="T">事件内容的类型。</typeparam>
/// <param name="EventId">事件 ID,用作幂等键。</param>
/// <param name="Topic">主题,如 core.masterdata/style_updated.v1。</param>
/// <param name="OccurredAt">发生时间,UTC。</param>
/// <param name="Attempt">第几次投递,从 1 开始。</param>
/// <param name="Payload">事件内容。</param>
public sealed record EventDelivery<T>(string EventId, string Topic, DateTimeOffset OccurredAt, int Attempt, T Payload);

/// <summary>内核调用定时任务接口时的请求体。同一 RunId 可能重复调用,任务须幂等。</summary>
/// <param name="JobId">清单中的任务 ID。</param>
/// <param name="RunId">本次运行 ID,用作幂等键。</param>
/// <param name="ScheduledFor">计划运行时间,UTC。</param>
/// <param name="Attempt">第几次尝试,从 1 开始。</param>
public sealed record JobInvocation(string JobId, string RunId, DateTimeOffset ScheduledFor, int Attempt);

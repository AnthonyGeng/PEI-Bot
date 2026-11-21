/**
 * @pei/sdk 1.0.0-preview.1
 * PEI 平台前端外壳与插件之间的契约。只增不改。
 * 运行时由外壳通过 Import Map 提供(与 React、设计系统一起),插件打包时把 "@pei/sdk" 和 "react" 设为外部依赖。
 */
import type { ReactNode } from "react";

/** 中英文文本。 */
export interface I18nText {
  zh: string;
  en: string;
}

/** 当前登录的用户。插件看不到登录令牌。 */
export interface PlatformUser {
  /** 内部用户 ID,不随身份提供方变化(本地账号迁到 GIP 后不变)。 */
  id: string;
  displayName: string;
  email: string;
  /** 界面语言,如 "zh-CN"、"en-US"。 */
  locale: string;
  /** IANA 时区,如 "Asia/Shanghai"。默认取浏览器,用户可在个人设置中覆盖。 */
  timeZone: string;
}

export interface TenantInfo {
  id: string;
  name: string;
  isExternal: boolean;
}

export interface PluginInfo {
  id: string;
  version: string;
  channel: "dev" | "beta" | "stable";
}

/** RFC 9457 Problem Details。插件接口出错时 api 方法抛出此对象。 */
export interface ApiError {
  status: number;
  title: string;
  detail?: string;
  /** 可在审计和日志中检索的关联 ID。 */
  correlationId?: string;
}

export interface ApiRequestOptions {
  signal?: AbortSignal;
  headers?: Record<string, string>;
}

/**
 * 访问本插件后端的客户端。路径相对于清单中的 routePrefix;
 * 自动携带登录态、插件版本号(X-Pei-Plugin-Version)和关联 ID。
 */
export interface PluginApi {
  get<T>(path: string, options?: ApiRequestOptions): Promise<T>;
  post<T>(path: string, body?: unknown, options?: ApiRequestOptions): Promise<T>;
  put<T>(path: string, body?: unknown, options?: ApiRequestOptions): Promise<T>;
  patch<T>(path: string, body?: unknown, options?: ApiRequestOptions): Promise<T>;
  delete<T = void>(path: string, options?: ApiRequestOptions): Promise<T>;
}

/** 时间与数字格式化。输入的时间一律是带 Z 的 UTC ISO 8601 字符串,输出按用户时区和语言。 */
export interface Formatters {
  dateTime(utcIso: string, style?: "short" | "medium" | "long"): string;
  date(utcIso: string, style?: "short" | "medium" | "long"): string;
  time(utcIso: string): string;
  /** 如 "3 小时前"、"in 2 days"。 */
  relative(utcIso: string): string;
  number(value: number, options?: Intl.NumberFormatOptions): string;
  currency(amount: number, currencyCode: string): string;
}

/** 外壳传给每个挂载组件的上下文,所有插槽相同。 */
export interface ShellContext {
  user: PlatformUser;
  tenant: TenantInfo;
  plugin: PluginInfo;
  /** 权限点写作本插件内的名称,或 "插件id:名称"。 */
  can(permission: string): boolean;
  features: {
    /** 功能开关,例如 "bot"。 */
    has(feature: string): boolean;
  };
  /** 其他插件发布的上下文值,键写作 "插件id/名称@主版本",如 "core.brandscope/current@1"。 */
  context: {
    get<T>(key: string): Promise<T | undefined>;
    /** 值变化时回调(例如用户切换品牌)。返回取消订阅的函数。 */
    subscribe<T>(key: string, onChange: (value: T | undefined) => void): () => void;
  };
  api: PluginApi;
  navigate(route: string, options?: { replace?: boolean }): void;
  format: Formatters;
  /** 按当前语言从 I18nText 中取文本。 */
  text(value: I18nText): string;
  toast(message: string, kind?: "info" | "success" | "error"): void;
}

/** 挂载组件收到的参数。params 因插槽而异。 */
export interface SlotProps<P = Record<string, never>> {
  ctx: ShellContext;
  params: P;
}

/** 插件入口模块中按清单 export 字段导出的组件。 */
export type SlotComponent<P = Record<string, never>> = (props: SlotProps<P>) => ReactNode;

/** 路由参数,如 /techpack/:styleNo 中的 styleNo。 */
export type RouteParams = Record<string, string>;

// ---- 外壳插槽的 params ----

/** nav.page、route.page、settings.page */
export type PageParams = RouteParams;

/** home.widget */
export interface HomeWidgetParams {
  size: "s" | "m" | "l";
}

/** header.action */
export interface HeaderActionParams {
  /** 当前页面路由。 */
  currentRoute: string;
}

/** profile.section 没有参数。 */
export type ProfileSectionParams = Record<string, never>;

/** command 填 export 时,导出的是命令函数而不是组件。 */
export type CommandHandler = (ctx: ShellContext) => void | Promise<void>;

// ---- 全局搜索 ----

/** search.provider 的后端接口(GET,参数 q 和 limit)返回的结构。 */
export interface SearchResponse {
  items: SearchResult[];
}

export interface SearchResult {
  title: string;
  subtitle?: string;
  /** 点击后跳转的路由。 */
  route: string;
  /** @pei/sdk 图标集中的名称。 */
  icon?: string;
}

/** search.provider 填 export 时,用于自定义结果的渲染。 */
export interface SearchResultsParams {
  query: string;
  items: SearchResult[];
}

// ---- 分页约定 ----

/** 列表接口统一用游标分页:?cursor=&limit=。 */
export interface Page<T> {
  items: T[];
  /** 没有下一页时为 null。 */
  nextCursor: string | null;
}

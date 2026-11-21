// 示例插件 sample.hello 的前端入口,仅用于类型检查契约是否好用。
import type {
  SlotComponent, PageParams, HomeWidgetParams, CommandHandler, Page,
} from "@pei/sdk";

interface Greeting { id: string; text: string; createdBy: string; createdAt: string }

export const GreetingsPage: SlotComponent<PageParams> = ({ ctx }) => {
  const canWrite = ctx.can("hello.write");
  void ctx.api.get<Page<Greeting>>("/greetings?limit=20").then((page) => {
    for (const g of page.items) console.log(g.text, ctx.format.relative(g.createdAt));
  });
  return canWrite ? ctx.text({ zh: "问候", en: "Greetings" }) : null;
};

export const LatestGreetingWidget: SlotComponent<HomeWidgetParams> = ({ ctx, params }) =>
  params.size === "s" ? null : ctx.format.dateTime(new Date().toISOString(), "short");

export const createGreeting: CommandHandler = async (ctx) => {
  try {
    await ctx.api.post<{ id: string }>("/greetings", { text: "Hello" });
    ctx.toast(ctx.text({ zh: "已创建", en: "Created" }), "success");
  } catch (e) {
    ctx.toast((e as { title?: string }).title ?? "Error", "error");
  }
};

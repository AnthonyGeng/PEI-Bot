-- 幂等、只增不改。在插件自己的 schema 中执行(search_path 由内核设置)。
create table if not exists greetings (
  id          text primary key,
  text        text not null,
  created_by  text not null,
  created_at  timestamptz not null
);
create index if not exists greetings_created_at on greetings (created_at desc);

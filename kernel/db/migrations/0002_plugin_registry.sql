-- 内核:插件注册表与发布流程(第一版)。以 pei_kernel 角色在 core schema 中执行。幂等、只增不改。
-- 需要 PostgreSQL 16 或更高版本(用到 GRANT ... WITH SET)。
set search_path = core;

-- 宿主池。由基础设施建一次,这里只登记。
create table if not exists pools (
  id               text primary key,
  description      text not null,
  internal_network boolean not null default false
);
insert into pools (id, description, internal_network) values
  ('core',         '核心业务池',               false),
  ('trade',        '交易池,唯一开放内网出口',    true),
  ('experimental', '试验池,新插件和示例插件',    false)
on conflict (id) do nothing;

-- 插件。id 一经发布不可更改。
create table if not exists plugins (
  id               text primary key,
  display_name_zh  text not null,
  display_name_en  text not null,
  owner            text,
  pool_id          text not null references pools (id),
  status           text not null default 'active' check (status in ('active', 'disabled')),
  created_by       uuid references users (id),
  created_at       timestamptz not null default now()
);

-- 版本。上传即不可变;只能新增,不删除。
create table if not exists plugin_versions (
  plugin_id         text not null references plugins (id),
  version           text not null,
  major             int not null,
  minor             int not null,
  patch             int not null,
  prerelease        text,
  manifest          jsonb not null,
  package_sha256    bytea not null,
  package_uri       text not null,             -- 私有桶中的不可变路径
  assets_base_url   text,                      -- 前端产物在 CDN 上的根路径
  size_bytes        bigint not null,
  status            text not null check (status in
                      ('uploaded', 'validated', 'rejected', 'migrating', 'migration_failed', 'available')),
  validation_report jsonb,
  uploaded_by       uuid references users (id),
  uploaded_at       timestamptz not null default now(),
  available_at      timestamptz,
  primary key (plugin_id, version)
);
create index if not exists plugin_versions_order on plugin_versions (plugin_id, major desc, minor desc, patch desc);

-- 全局唯一的“占用”:路由前缀、页面路由、数据库 schema、事件主题前缀、扩展点。
-- 唯一约束保证两个插件不可能同时占用同一个值,冲突在上传校验阶段就会暴露。
create table if not exists plugin_claims (
  claim_type text not null check (claim_type in
               ('route_prefix', 'page_route', 'db_schema', 'topic_prefix', 'extension_point', 'context')),
  value      text not null,
  plugin_id  text not null references plugins (id),
  primary key (claim_type, value)
);

-- 已执行的迁移脚本。同名脚本内容改变即拒绝上传(只增不改)。
create table if not exists plugin_migrations (
  plugin_id   text not null references plugins (id),
  file_name   text not null,
  sha256      bytea not null,
  applied_in  text not null,                    -- 首次执行它的插件版本
  applied_at  timestamptz not null default now(),
  duration_ms int not null,
  primary key (plugin_id, file_name)
);

-- 通道指针。dev、beta、stable 各指向一个版本;回滚就是把指针指回 previous_version。
create table if not exists plugin_channels (
  plugin_id          text not null references plugins (id),
  channel            text not null check (channel in ('dev', 'beta', 'stable')),
  active_version     text not null,
  previous_version   text,
  rollout_percent    int not null default 100 check (rollout_percent between 0 and 100),
  rollout_started_at timestamptz,
  updated_by         uuid references users (id),
  updated_at         timestamptz not null default now(),
  primary key (plugin_id, channel),
  foreign key (plugin_id, active_version) references plugin_versions (plugin_id, version),
  foreign key (plugin_id, previous_version) references plugin_versions (plugin_id, version)
);

-- 开发、试用通道的受众:用户或角色。正式通道面向所有有权限的用户,不需要受众。
create table if not exists channel_audiences (
  plugin_id      text not null,
  channel        text not null check (channel in ('dev', 'beta')),
  principal_type text not null check (principal_type in ('user', 'role')),
  principal_id   uuid not null,
  primary key (plugin_id, channel, principal_type, principal_id),
  foreign key (plugin_id, channel) references plugin_channels (plugin_id, channel) on delete cascade
);

-- 晋升到正式通道的申请。审批人默认不能是上传者(见 kernel_settings)。
create table if not exists release_requests (
  id           uuid primary key default gen_random_uuid(),
  plugin_id    text not null,
  version      text not null,
  requested_by uuid not null references users (id),
  requested_at timestamptz not null default now(),
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by   uuid references users (id),
  decided_at   timestamptz,
  note         text,
  foreign key (plugin_id, version) references plugin_versions (plugin_id, version)
);
create unique index if not exists release_requests_one_pending
  on release_requests (plugin_id) where status = 'pending';

-- 发布历史:每一次指针变化、池迁移、启停,都在这里留一条。
create table if not exists release_events (
  id           uuid primary key default gen_random_uuid(),
  plugin_id    text not null references plugins (id),
  channel      text,
  action       text not null check (action in
                 ('publish', 'promote', 'ramp', 'complete', 'rollback', 'auto_rollback',
                  'pool_move', 'enable', 'disable')),
  from_version text,
  to_version   text,
  actor_id     uuid references users (id),          -- 自动操作为空
  reason       text,
  occurred_at  timestamptz not null default now()
);
create index if not exists release_events_by_plugin on release_events (plugin_id, occurred_at desc);

-- 宿主实例与它加载的插件版本。实例每 10 秒心跳一次,超过 60 秒未心跳视为已退出。
create table if not exists host_instances (
  instance_id        text primary key,
  pool_id            text not null references pools (id),
  kernel_version     text not null,
  state              text not null check (state in ('starting', 'serving', 'draining')),
  started_at         timestamptz not null default now(),
  last_heartbeat_at  timestamptz not null default now(),
  managed_heap_mb    int,
  leaked_contexts    int not null default 0
);
create table if not exists instance_plugins (
  instance_id text not null references host_instances (instance_id) on delete cascade,
  plugin_id   text not null,
  version     text not null,
  state       text not null check (state in
                ('loading', 'serving', 'draining', 'unloaded', 'leaked', 'failed')),
  error       text,
  updated_at  timestamptz not null default now(),
  primary key (instance_id, plugin_id, version)
);

-- 运行事故:崩溃归因、卡死、错误率、发布后退化。自动回滚的判断依据。
create table if not exists plugin_incidents (
  id          uuid primary key default gen_random_uuid(),
  plugin_id   text not null references plugins (id),
  version     text not null,
  kind        text not null check (kind in ('crash', 'stuck', 'error_rate', 'regression', 'load_failed', 'leak')),
  instance_id text,
  details     jsonb,
  occurred_at timestamptz not null default now()
);
create index if not exists plugin_incidents_recent on plugin_incidents (plugin_id, version, occurred_at desc);

-- 插件密钥的元数据。值在 Secret Manager 中,这里只存引用。
create table if not exists plugin_secrets (
  plugin_id    text not null references plugins (id),
  name         text not null,
  secret_ref   text not null,
  updated_by   uuid references users (id),
  updated_at   timestamptz not null default now(),
  primary key (plugin_id, name)
);

-- 命令行工具(pei push)用的个人访问令牌。只存哈希。
create table if not exists api_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users (id) on delete cascade,
  name         text not null,
  token_hash   bytea not null unique,
  scopes       text[] not null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  last_used_at timestamptz,
  revoked_at   timestamptz
);

create table if not exists kernel_settings (
  key        text primary key,
  value      jsonb not null,
  updated_by uuid references users (id),
  updated_at timestamptz not null default now()
);
insert into kernel_settings (key, value) values
  ('release.require_second_approver', 'true'),
  ('release.stable_ramp_percent',     '5'),
  ('release.stable_ramp_minutes',     '15'),
  ('release.package_max_mb',          '50')
on conflict (key) do nothing;

-- 注册表版本号。网关的路由表和宿主的加载清单都以它为缓存键,任何变化立即生效。
create table if not exists registry_version (
  singleton boolean primary key default true check (singleton),
  version   bigint not null default 0
);
insert into registry_version (singleton) values (true) on conflict do nothing;

create or replace function bump_registry_version() returns trigger language plpgsql as $$
begin
  update core.registry_version set version = version + 1;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['plugins', 'plugin_channels', 'channel_audiences', 'pools']
  loop
    if not exists (select 1 from pg_trigger where tgname = 'bump_registry_version'
                   and tgrelid = format('core.%I', t)::regclass) then
      execute format('create trigger bump_registry_version after insert or update or delete on core.%I
                      for each statement execute function core.bump_registry_version()', t);
    end if;
  end loop;
end $$;

-- 为插件创建两个数据库登录角色:迁移角色(拥有 schema,只在 Admin 执行迁移时使用)
-- 和运行角色(只有增删改查,宿主运行时使用)。两者都直接登录,不经 SET ROLE 切换,
-- 因此插件提供的 SQL 无法通过 RESET ROLE 取得内核权限。
create or replace function ensure_plugin_roles(
  p_schema text, p_owner_password text, p_runtime_password text,
  p_connection_limit int, p_statement_timeout_ms int)
returns void language plpgsql as $$
declare
  owner_role   text := 'plg_' || p_schema || '_owner';
  runtime_role text := 'plg_' || p_schema || '_rt';
begin
  if p_schema !~ '^[a-z][a-z0-9_]{1,40}$' then
    raise exception 'invalid schema name %', p_schema;
  end if;
  if not exists (select 1 from pg_roles where rolname = owner_role) then
    execute format('create role %I login password %L nosuperuser nocreatedb nocreaterole noinherit', owner_role, p_owner_password);
  end if;
  if not exists (select 1 from pg_roles where rolname = runtime_role) then
    execute format('create role %I login password %L nosuperuser nocreatedb nocreaterole noinherit', runtime_role, p_runtime_password);
  end if;
  -- PostgreSQL 16 起,把 schema 交给某个角色前,当前角色必须能 SET ROLE 到它。
  -- 内核成为插件角色的成员(不继承其权限);反方向不成立,插件角色永远不是内核角色的成员。
  if not exists (select 1 from pg_auth_members m join pg_roles r on r.oid = m.roleid
                 where r.rolname = owner_role and m.set_option
                   and m.member = (select oid from pg_roles where rolname = current_user)) then
    execute format('grant %I to %I with inherit false, set true', owner_role, current_user);
  end if;
  execute format('create schema if not exists %I', p_schema);
  execute format('alter schema %I owner to %I', p_schema, owner_role);
  -- schema 归迁移角色所有后,授权必须以它的身份进行;内核临时切换过去,做完立即切回。
  execute format('set local role %I', owner_role);
  execute format('grant usage on schema %I to %I', p_schema, runtime_role);
  execute format('alter default privileges in schema %I grant select, insert, update, delete on tables to %I',
                 p_schema, runtime_role);
  execute format('alter default privileges in schema %I grant usage, select on sequences to %I',
                 p_schema, runtime_role);
  reset role;
  execute format('alter role %I set search_path = %I', owner_role, p_schema);
  execute format('alter role %I set search_path = %I', runtime_role, p_schema);
  execute format('alter role %I set statement_timeout = %s', runtime_role, p_statement_timeout_ms);
  execute format('alter role %I connection limit %s', runtime_role, p_connection_limit);
  execute format('alter role %I connection limit 2', owner_role);
end $$;

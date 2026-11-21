-- 内核:身份与权限(第一版)。以 pei_kernel 角色在 core schema 中执行。幂等、只增不改。
set search_path = core;

-- 租户。第一版只有内部租户 pei;外部 B2B 租户以后加入,数据模型现在就带上 tenant_id。
create table if not exists tenants (
  id          text primary key,
  name        text not null,
  is_external boolean not null default false,
  status      text not null default 'active' check (status in ('active', 'disabled')),
  created_at  timestamptz not null default now()
);
insert into tenants (id, name, is_external) values ('pei', 'Perry Ellis International', false)
on conflict (id) do nothing;

-- 用户。id 由内核分配,迁到 GIP 后不变;插件只见到这个 id。
create table if not exists users (
  id           uuid primary key,
  tenant_id    text not null references tenants (id),
  email        text not null,
  display_name text not null,
  locale       text not null default 'zh-CN',
  time_zone    text,                    -- 为空表示跟随浏览器
  status       text not null default 'active' check (status in ('active', 'disabled')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists users_email_uq on users (lower(email));
create index if not exists users_tenant on users (tenant_id);

-- 第一版的本地密码。迁到 GIP 后停用,只保留一个应急管理员账号。
create table if not exists local_credentials (
  user_id         uuid primary key references users (id) on delete cascade,
  password_hash   text not null,        -- ASP.NET Core Identity PasswordHasher 的输出
  must_change     boolean not null default true,
  failed_attempts int not null default 0,
  locked_until    timestamptz,
  changed_at      timestamptz not null default now()
);

-- 外部身份(GIP)。第一版为空。
create table if not exists external_identities (
  provider      text not null,
  subject       text not null,
  user_id       uuid not null references users (id) on delete cascade,
  email_at_link text not null,
  linked_at     timestamptz not null default now(),
  primary key (provider, subject)
);

-- 服务端会话。Cookie 里只放随机令牌,库里只存它的 SHA-256,禁用用户或强制下线立即生效。
create table if not exists sessions (
  token_hash          bytea primary key,
  user_id             uuid not null references users (id) on delete cascade,
  audience            text not null check (audience in ('app', 'admin')),
  created_at          timestamptz not null default now(),
  last_seen_at        timestamptz not null default now(),
  idle_expires_at     timestamptz not null,
  absolute_expires_at timestamptz not null,
  revoked_at          timestamptz,
  ip                  inet,
  user_agent          text
);
create index if not exists sessions_active_by_user on sessions (user_id) where revoked_at is null;

-- 权限点。插件的权限点在发布时从清单写入;内核自己的权限点以 kernel: 开头。只增不删。
create table if not exists permission_points (
  id            text primary key,       -- 插件id:名称,如 plm.techpack:techpack.read
  plugin_id     text not null,          -- 内核为 kernel
  label_zh      text not null,
  label_en      text not null,
  deprecated_at timestamptz
);

create table if not exists roles (
  id          uuid primary key default gen_random_uuid(),
  tenant_id   text not null references tenants (id),
  name        text not null,
  description text,
  is_builtin  boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (tenant_id, name)
);

create table if not exists role_permissions (
  role_id       uuid not null references roles (id) on delete cascade,
  permission_id text not null references permission_points (id),
  primary key (role_id, permission_id)
);

create table if not exists user_roles (
  user_id    uuid not null references users (id) on delete cascade,
  role_id    uuid not null references roles (id) on delete cascade,
  granted_by uuid references users (id),
  granted_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

-- 插件是否对某租户启用。插件对用户可见 = 对其租户启用 且 用户至少拥有该插件的一个权限点。
create table if not exists tenant_plugins (
  tenant_id  text not null references tenants (id),
  plugin_id  text not null,
  enabled    boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (tenant_id, plugin_id)
);

-- 功能开关。对用户开启 = 租户级开启,或用户属于开关的放行角色。
create table if not exists feature_flags (
  tenant_id text not null references tenants (id),
  feature   text not null,
  enabled   boolean not null default false,
  note      text,                       -- 对外部租户开启 bot 时记录法务评估结论
  primary key (tenant_id, feature)
);
create table if not exists feature_flag_roles (
  tenant_id text not null,
  feature   text not null,
  role_id   uuid not null references roles (id) on delete cascade,
  primary key (tenant_id, feature, role_id),
  foreign key (tenant_id, feature) references feature_flags (tenant_id, feature) on delete cascade
);

-- 访问控制版本号。上面任何一张表变化都会加一,网关和宿主据此让缓存立即失效。
create table if not exists access_version (
  singleton boolean primary key default true check (singleton),
  version   bigint not null default 0
);
insert into access_version (singleton) values (true) on conflict do nothing;

create or replace function bump_access_version() returns trigger language plpgsql as $$
begin
  update core.access_version set version = version + 1;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['users', 'roles', 'role_permissions', 'user_roles', 'tenant_plugins',
                           'feature_flags', 'feature_flag_roles', 'permission_points', 'tenants']
  loop
    if not exists (select 1 from pg_trigger where tgname = 'bump_access_version'
                   and tgrelid = format('core.%I', t)::regclass) then
      execute format('create trigger bump_access_version after insert or update or delete on core.%I
                      for each statement execute function core.bump_access_version()', t);
    end if;
  end loop;
end $$;

-- 审计。内核和插件的审计都写在这里;以后按月分区。
create table if not exists audit_log (
  id             uuid primary key,
  occurred_at    timestamptz not null default now(),
  tenant_id      text,
  actor_kind     text not null check (actor_kind in ('user', 'system', 'bot')),
  actor_id       text,
  plugin_id      text not null,         -- 内核为 kernel
  action         text not null,
  target         text,
  details        jsonb,
  correlation_id text,
  ip             inet
);
create index if not exists audit_log_time on audit_log (occurred_at desc);
create index if not exists audit_log_actor on audit_log (actor_id, occurred_at desc);
create index if not exists audit_log_action on audit_log (plugin_id, action, occurred_at desc);

-- 内核权限点。
insert into permission_points (id, plugin_id, label_zh, label_en) values
  ('kernel:admin.plugins.read',    'kernel', '查看插件',             'View plugins'),
  ('kernel:admin.plugins.publish', 'kernel', '上传插件到开发和试用通道', 'Publish plugins to dev and beta'),
  ('kernel:admin.plugins.promote', 'kernel', '晋升到正式通道与回滚',     'Promote to stable and roll back'),
  ('kernel:admin.plugins.assign',  'kernel', '分配宿主池与按租户启用',   'Assign pools and enable per tenant'),
  ('kernel:admin.users.manage',    'kernel', '管理用户',             'Manage users'),
  ('kernel:admin.roles.manage',    'kernel', '管理角色与授权',         'Manage roles and grants'),
  ('kernel:admin.features.manage', 'kernel', '管理功能开关',          'Manage feature switches'),
  ('kernel:admin.secrets.manage',  'kernel', '管理插件密钥',          'Manage plugin secrets'),
  ('kernel:admin.audit.read',      'kernel', '查看审计',             'Read audit log')
on conflict (id) do nothing;

-- 内置角色。
insert into roles (tenant_id, name, description, is_builtin) values
  ('pei', '平台管理员',   '全部 Admin 权限',                               true),
  ('pei', '插件发布者',   '上传插件到开发和试用通道',                       true),
  ('pei', '发布审批人',   '把插件晋升到正式通道、执行回滚',                 true),
  ('pei', '审计员',       '只读:插件与审计',                              true)
on conflict (tenant_id, name) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r cross join permission_points p
where r.tenant_id = 'pei' and r.name = '平台管理员' and p.plugin_id = 'kernel'
union all
select r.id, p.id from roles r join permission_points p
  on p.id in ('kernel:admin.plugins.read', 'kernel:admin.plugins.publish')
where r.tenant_id = 'pei' and r.name = '插件发布者'
union all
select r.id, p.id from roles r join permission_points p
  on p.id in ('kernel:admin.plugins.read', 'kernel:admin.plugins.promote')
where r.tenant_id = 'pei' and r.name = '发布审批人'
union all
select r.id, p.id from roles r join permission_points p
  on p.id in ('kernel:admin.plugins.read', 'kernel:admin.audit.read')
where r.tenant_id = 'pei' and r.name = '审计员'
on conflict do nothing;

-- bot 开关:第一版对内部租户关闭(第一版没有 Bot 插件)。
insert into feature_flags (tenant_id, feature, enabled) values ('pei', 'bot', false)
on conflict do nothing;

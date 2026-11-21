# 08 部署拓扑与环境(草案 v0.1,先写数据库与本地开发)

## 数据库

| 环境 | 数据库 | 连接方式 |
| --- | --- | --- |
| 云上(dev、staging、prod) | Cloud SQL for PostgreSQL | Cloud Run 经 Direct VPC Egress 走私有 IP |
| 本地开发 | 自建 PostgreSQL(本机安装或 [`dev/docker-compose.yml`](../../dev/docker-compose.yml)) | 本机 5432 端口 |

插件看不到这一差别:它们只通过 `IPluginDatabase` 拿连接,连接串由内核按环境配置。

### 本地与云上必须一致的四件事

本地库和 Cloud SQL 不一致时,问题会在上线后才暴露。以下四项必须保持一致:

1. **大版本相同。** 本地 PostgreSQL 的大版本跟随 Cloud SQL 实例。Compose 文件暂定 17,创建 Cloud SQL 实例时按实际选择的版本同步修改。
2. **扩展相同。** 只用 Cloud SQL 支持的扩展。扩展由初始化脚本统一创建,插件的迁移脚本不得执行 `create extension`。
3. **角色模型相同。** 本地也不用超级用户跑插件:内核用 `pei_kernel` 角色,每个插件用内核为它创建的专属角色,只能写自己的 schema。用超级用户开发,权限错误会被掩盖,到云上才出现。
4. **时区相同。** 数据库时区设为 UTC,时间列一律用 `timestamptz`。

本地初始化脚本见 [`dev/postgres/00-bootstrap.sql`](../../dev/postgres/00-bootstrap.sql)。云上的初始化脚本与它保持同一套角色和扩展。

### 迁移脚本在两边的执行方式相同

插件的 `migrations/*.sql` 由内核在安装和升级插件时执行:先用 `pg_try_advisory_lock` 抢锁,保证多实例下只执行一次;再以该插件的角色、在它自己的 schema 中执行。本地和云上走同一段内核代码。

## 本地开发还需要的其他依赖

数据库之外,内核还依赖几项云服务。本地分别用以下方式替代:

| 云上 | 本地 | 状态 |
| --- | --- | --- |
| Memorystore for Redis(插件版本注册表、缓存) | Redis 7,已在 Compose 中 | 已定 |
| Cloud Storage(插件包、插件文件) | 本地目录,由内核的存储适配器切换 | 待定 |
| Pub/Sub(跨池事件) | Pub/Sub 模拟器,或本地用内存实现 | 待定 |
| Cloud Scheduler、Cloud Tasks(定时任务) | 内核在本地模式下用进程内调度代替 | 待定 |

待定的三项在写 03 号和后续的部署文档时确定。原则是:替代只发生在内核的适配层,插件代码在本地和云上完全相同。

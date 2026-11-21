-- 本地开发库初始化。与云上 Cloud SQL 的初始化保持同一套角色模型:
-- 内核用 pei_kernel 角色;每个插件的两个登录角色由内核在首次发布插件时创建(core.ensure_plugin_roles),都不是超级用户。
-- 需要 PostgreSQL 16 或更高版本。
-- 仅用于本地,密码不得用于任何其他环境。

create role pei_kernel login password 'local-dev-only' createrole;
create database pei owner pei_kernel;
alter database pei set timezone to 'UTC';

\connect pei
-- 扩展只能由这里(或云上的初始化脚本)创建,插件的迁移脚本不得 create extension。
-- 只启用 Cloud SQL 支持的扩展;需要新扩展时先确认 Cloud SQL 支持,再同时加到本地和云上。
create extension if not exists pgcrypto;

create schema if not exists core authorization pei_kernel;

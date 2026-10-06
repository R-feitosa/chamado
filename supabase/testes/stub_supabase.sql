-- Simula o mínimo do Supabase para testar a migration num Postgres puro.
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema auth; create schema storage;
grant usage on schema auth, storage, public to anon, authenticated;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('teste.uid', true), '')::uuid $$;
create function auth.email() returns text language sql stable as $$ select email from auth.users where id = auth.uid() $$;
grant execute on function auth.uid(), auth.email() to anon, authenticated;
grant select on auth.users to authenticated;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
alter table storage.objects enable row level security;
grant select, insert, delete on storage.objects to authenticated;
grant select, insert on storage.objects to anon;
grant usage on schema storage to anon;
insert into storage.buckets values ('placeholder', 'placeholder', false, null, null);
create function storage.foldername(name text) returns text[] language sql immutable as $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant execute on function storage.foldername(text) to authenticated;
create publication supabase_realtime;
-- Partes do projeto ATLAS lidas pelo convite do hub (só estrutura usada).
create schema extensions; create extension pgcrypto schema extensions; create extension unaccent schema extensions;
create schema acessos; create schema hub; create schema rh;
create table hub.pessoas (id uuid primary key, nome text);
create table acessos.usuarios (id uuid primary key, pessoa_id uuid, status text);
create table rh.vw_vinculos_atuais (pessoa_id uuid, departamento_nome text, cargo_nome text, data_admissao date);
create function acessos.eh_usuario_ativo() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from acessos.usuarios u where u.id = auth.uid() and u.status = 'ativo') $$;
grant usage on schema acessos to authenticated; grant execute on function acessos.eh_usuario_ativo() to authenticated;
-- Vault e pg_net (notificações push): só o necessário para os testes.
create schema vault;
create table vault.secrets (id uuid primary key default gen_random_uuid(), name text unique, secret text, description text);
create view vault.decrypted_secrets as select id, name, secret as decrypted_secret from vault.secrets;
create function vault.create_secret(new_secret text, new_name text default null, new_description text default '') returns uuid
  language sql as $$ insert into vault.secrets (name, secret, description) values (new_name, new_secret, new_description) returning id $$;
create schema net;
create table net.chamadas (id bigserial primary key, url text, body jsonb, headers jsonb, em timestamptz default now());
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds integer default 5000)
  returns bigint language sql as $$ insert into net.chamadas (url, body, headers) values (url, body, headers) returning id $$;

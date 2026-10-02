-- ============================================================================
-- Central de Chamados RFG — schema próprio `chamados` no projeto ATLAS - INTEGRADO
-- ----------------------------------------------------------------------------
-- Tudo do sistema vive em `chamados` (não toca `public` nem os outros schemas).
-- Fora dele, só o mínimo que o Supabase exige:
--   * bucket privado `chamados-prints` + policies em storage.objects (filtradas por bucket_id);
--   * tabela chamados.chamados na publicação supabase_realtime.
-- Login: o mesmo auth.users dos sistemas ATLAS. A pessoa é ligada à conta
-- pelo e-mail no primeiro acesso (chamados.vincular_minha_conta).
-- Escrita só por RPC security definer (search_path = '', retorno jsonb — padrão do projeto).
-- ============================================================================

create schema chamados;
comment on schema chamados is 'Central de Chamados RFG: chamados de sistemas abertos pelos colaboradores e atendidos pelo time de desenvolvimento.';

-- ============ Tipos ============
create type chamados.papel_t as enum ('solicitante', 'dev');
create type chamados.status_t as enum ('aberto', 'andamento', 'resolvido');
create type chamados.acao_t as enum ('aberto', 'assumido', 'resolvido', 'reaberto');

-- ============ Referência ============
create table chamados.setores (
  id    smallint primary key,
  nome  text not null unique,
  ordem smallint not null default 0
);

create table chamados.pessoas (
  id       uuid primary key default gen_random_uuid(),
  nome     text not null unique,
  setor_id smallint references chamados.setores(id),
  papel    chamados.papel_t not null,
  email    text unique check (email is null or email = lower(email)),
  user_id  uuid unique references auth.users(id) on delete set null,
  ativo    boolean not null default true,
  check (papel = 'dev' or setor_id is not null)
);
comment on column chamados.pessoas.email is 'E-mail de login (auth.users). Preenchido pelo time; liga a conta no primeiro acesso.';

create table chamados.sistemas (
  id    smallint primary key,
  nome  text not null unique,
  ordem smallint not null default 0,
  ativo boolean not null default true
);

-- ============ Chamados ============
-- O protótipo começava em TI-0421; mantemos a numeração.
create sequence chamados.protocolo_seq start with 421;

create function chamados.proximo_protocolo()
returns text language sql volatile set search_path = '' as $$
  select 'TI-' || lpad(n::text, greatest(4, length(n::text)), '0')
  from (select nextval('chamados.protocolo_seq') as n) s
$$;

create table chamados.chamados (
  id             uuid primary key default gen_random_uuid(),
  protocolo      text not null unique default chamados.proximo_protocolo(),
  descricao      text not null check (char_length(btrim(descricao)) between 1 and 5000),
  solicitante_id uuid not null references chamados.pessoas(id),
  sistema_id     smallint not null references chamados.sistemas(id),
  urgencia       smallint not null check (urgencia between 0 and 2),
  status         chamados.status_t not null default 'aberto',
  responsavel_id uuid references chamados.pessoas(id),
  prints         text[] not null default '{}' check (cardinality(prints) <= 3),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  resolvido_em   timestamptz,
  check (status = 'aberto' or responsavel_id is not null),
  check ((status = 'resolvido') = (resolvido_em is not null))
);
create index chamados_status_idx on chamados.chamados (status);
create index chamados_solicitante_idx on chamados.chamados (solicitante_id);
create index chamados_responsavel_idx on chamados.chamados (responsavel_id);
create index chamados_sistema_idx on chamados.chamados (sistema_id);

create table chamados.eventos (
  id         bigint generated always as identity primary key,
  chamado_id uuid not null references chamados.chamados(id) on delete cascade,
  autor_id   uuid not null references chamados.pessoas(id),
  acao       chamados.acao_t not null,
  criado_em  timestamptz not null default now()
);
create index eventos_chamado_idx on chamados.eventos (chamado_id);
create index eventos_autor_idx on chamados.eventos (autor_id);

-- ============ Funções de sessão ============
create function chamados.eu_pessoa_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select id from chamados.pessoas where user_id = auth.uid() and ativo
$$;

create function chamados.eh_dev()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from chamados.pessoas where user_id = auth.uid() and ativo and papel = 'dev')
$$;

-- Liga a conta logada à pessoa cadastrada com o mesmo e-mail. Devolve null se não houver cadastro.
create function chamados.vincular_minha_conta()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare p chamados.pessoas;
begin
  if auth.uid() is null then
    raise exception 'Sessão inválida.' using errcode = '28000';
  end if;
  select * into p from chamados.pessoas where user_id = auth.uid() and ativo;
  if not found then
    update chamados.pessoas set user_id = auth.uid()
     where email = lower(auth.email()) and user_id is null and ativo
    returning * into p;
  end if;
  if p.id is null then return null; end if;
  return jsonb_build_object('id', p.id, 'nome', p.nome, 'setor_id', p.setor_id, 'papel', p.papel, 'ativo', p.ativo);
end $$;

-- ============ RPCs de chamados ============
create function chamados.abrir_chamado(
  p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados; pr text;
begin
  if eu is null then raise exception 'Seu acesso não está liberado.' using errcode = '42501'; end if;
  foreach pr in array coalesce(p_prints, '{}') loop
    if split_part(pr, '/', 1) <> auth.uid()::text then
      raise exception 'Print inválido.' using errcode = '22023';
    end if;
  end loop;
  insert into chamados.chamados (descricao, solicitante_id, sistema_id, urgencia, prints)
  values (btrim(p_descricao), eu, p_sistema_id, p_urgencia, coalesce(p_prints, '{}'))
  returning * into c;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, eu, 'aberto');
  return to_jsonb(c);
end $$;

create function chamados.assumir_chamado(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados;
begin
  if not chamados.eh_dev() then raise exception 'Só o time de desenvolvimento assume chamados.' using errcode = '42501'; end if;
  update chamados.chamados set responsavel_id = eu, status = 'andamento', atualizado_em = now()
   where id = p_id and status <> 'resolvido' and responsavel_id is null
  returning * into c;
  if not found then raise exception 'Este chamado já foi assumido ou resolvido.' using errcode = 'P0001'; end if;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, eu, 'assumido');
  return to_jsonb(c);
end $$;

create function chamados.resolver_chamado(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados;
begin
  if not chamados.eh_dev() then raise exception 'Só o time de desenvolvimento resolve chamados.' using errcode = '42501'; end if;
  update chamados.chamados set status = 'resolvido', resolvido_em = now(), atualizado_em = now()
   where id = p_id and status = 'andamento' and responsavel_id = eu
  returning * into c;
  if not found then raise exception 'Só o responsável pode resolver este chamado.' using errcode = 'P0001'; end if;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, eu, 'resolvido');
  return to_jsonb(c);
end $$;

create function chamados.reabrir_chamado(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados;
begin
  if not chamados.eh_dev() then raise exception 'Só o time de desenvolvimento reabre chamados.' using errcode = '42501'; end if;
  update chamados.chamados set status = 'andamento', resolvido_em = null, atualizado_em = now()
   where id = p_id and status = 'resolvido'
  returning * into c;
  if not found then raise exception 'Este chamado não está resolvido.' using errcode = 'P0001'; end if;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, eu, 'reaberto');
  return to_jsonb(c);
end $$;

-- ============ Permissões ============
alter table chamados.setores  enable row level security;
alter table chamados.pessoas  enable row level security;
alter table chamados.sistemas enable row level security;
alter table chamados.chamados enable row level security;
alter table chamados.eventos  enable row level security;

create policy setores_ler  on chamados.setores  for select to authenticated using (chamados.eu_pessoa_id() is not null);
create policy pessoas_ler  on chamados.pessoas  for select to authenticated using (chamados.eu_pessoa_id() is not null);
create policy sistemas_ler on chamados.sistemas for select to authenticated using (chamados.eu_pessoa_id() is not null);
create policy chamados_ler on chamados.chamados for select to authenticated
  using (chamados.eh_dev() or solicitante_id = chamados.eu_pessoa_id());
create policy eventos_ler on chamados.eventos for select to authenticated
  using (exists (select 1 from chamados.chamados c where c.id = chamado_id
                 and (chamados.eh_dev() or c.solicitante_id = chamados.eu_pessoa_id())));

-- Só leitura direta (filtrada pela RLS); escrita exclusivamente pelas RPCs.
-- E-mail e user_id das pessoas ficam fora do alcance do front.
grant usage on schema chamados to authenticated, service_role;
grant select on chamados.setores, chamados.sistemas, chamados.chamados, chamados.eventos to authenticated;
grant select (id, nome, setor_id, papel, ativo) on chamados.pessoas to authenticated;
grant all on all tables in schema chamados to service_role;
grant all on all sequences in schema chamados to service_role;

revoke execute on all functions in schema chamados from public, anon;
grant execute on function chamados.eu_pessoa_id(), chamados.eh_dev(), chamados.vincular_minha_conta(),
  chamados.abrir_chamado(integer, text, integer, text[]),
  chamados.assumir_chamado(uuid), chamados.resolver_chamado(uuid), chamados.reabrir_chamado(uuid) to authenticated;

-- ============ Tempo real ============
alter publication supabase_realtime add table chamados.chamados;

-- ============ Storage: prints ============
-- Bucket privado; cada usuário grava em "<user_id>/arquivo". Leitura: dono ou time de dev.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chamados-prints', 'chamados-prints', false, 20971520, array['image/png', 'image/jpeg', 'image/webp', 'image/gif']);

create policy chamados_prints_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'chamados-prints' and chamados.eu_pessoa_id() is not null
              and (storage.foldername(name))[1] = auth.uid()::text);
create policy chamados_prints_ler on storage.objects for select to authenticated
  using (bucket_id = 'chamados-prints' and ((storage.foldername(name))[1] = auth.uid()::text or chamados.eh_dev()));
-- Permite apagar o próprio print quando a abertura do chamado falha depois do envio.
create policy chamados_prints_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'chamados-prints' and (storage.foldername(name))[1] = auth.uid()::text
         and not exists (select 1 from chamados.chamados c where name = any (c.prints)));

-- ============ Dados de referência (não alterar sem confirmação do Roneely) ============
insert into chamados.setores (id, nome, ordem) values
  (1, 'Sócios', 1), (2, 'Administrativo e Financeiro', 2), (3, 'Controladoria', 3), (4, 'Jurídico', 4);

insert into chamados.pessoas (nome, setor_id, papel) values
  ('Roneely Feitosa', 1, 'solicitante'), ('Anderson Mesquita', 1, 'solicitante'), ('Fábio Mendes', 1, 'solicitante'),
  ('Tayse Feitosa', 2, 'solicitante'),
  ('Raissa', 3, 'solicitante'), ('Amanda', 3, 'solicitante'), ('Sarah', 3, 'solicitante'), ('Julia', 3, 'solicitante'), ('Sophia', 3, 'solicitante'),
  ('Tamira', 4, 'solicitante'), ('Lanna', 4, 'solicitante'), ('Flávia Luquélia', 4, 'solicitante'), ('Suhiane', 4, 'solicitante'),
  ('Joana Cláudia', 4, 'solicitante'), ('Nicoly Sobral', 4, 'solicitante'), ('Carlos Brandão', 4, 'solicitante'),
  ('Aldo', null, 'dev'), ('Brenno Magalhães', null, 'dev'), ('Breno Azevedo', null, 'dev'),
  ('João Pedro', null, 'dev'), ('Ruan', null, 'dev'), ('Kaio', null, 'dev');

insert into chamados.sistemas (id, nome, ordem) values
  (1, 'ATLAS JURIS', 1), (2, 'CRM', 2), (3, 'ATLAS RH', 3), (4, 'Atlas Consult', 4),
  (5, 'ATLAS Empresas', 5), (6, 'Atlas Trib', 6), (7, 'Rfast Mail', 7), (8, 'Agente WhatsApp', 8),
  (9, 'App Connect Valley', 9), (10, 'Site Feitosa Imóveis', 10), (11, 'Site do escritório', 11), (12, 'Outro / não sei', 12);

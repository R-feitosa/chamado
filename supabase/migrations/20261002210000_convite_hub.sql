-- ============================================================================
-- Botão "Abrir chamado" nos sistemas do hub, com token de acesso (padrão DISC)
-- ----------------------------------------------------------------------------
-- O sistema do hub (mesmo login do projeto) chama gerar_link_chamado(): o banco lê
-- nome, e-mail, departamento e cargo de quem está logado e devolve um link com um
-- token opaco (32 bytes, só o hash fica guardado, vale 2 h, uso único).
-- Na Central, sem login: ler_convite() mostra quem é; abrir_chamado_por_convite()
-- abre o chamado em nome dessa pessoa, cadastrando-a como solicitante se preciso.
-- Fora do schema chamados só se LÊ: acessos.usuarios, hub.pessoas, rh.vw_vinculos_atuais, auth.users.
-- ============================================================================

-- 1. Sistemas da Central ligados aos códigos do hub; 7 sistemas novos; "Outro / não sei" no fim.
alter table chamados.sistemas add column hub_codigo text unique;
comment on column chamados.sistemas.hub_codigo is 'Código do sistema em hub.sistemas (pré-seleciona o sistema no chamado vindo do botão do hub).';
update chamados.sistemas s set hub_codigo = v.codigo
  from (values (1, 'juris'), (2, 'crm'), (3, 'rh'), (4, 'consult'), (6, 'tributario'), (9, 'valley')) v(id, codigo)
 where s.id = v.id;
insert into chamados.sistemas (id, nome, ordem, grupo, hub_codigo) values
  (16, 'Connect Academy', 12, 'sistema', 'academy'),
  (17, 'Atlas Cash',      12, 'sistema', 'cash'),
  (18, 'Atlas Hub',       12, 'sistema', 'hub'),
  (19, 'Atlas Imóveis',   12, 'sistema', 'imoveis'),
  (20, 'Legal Ops',       12, 'sistema', 'legal_ops'),
  (21, 'Atlas Ponto',     12, 'sistema', 'ponto'),
  (22, 'R. Feitosa Ops',  12, 'sistema', 'rf_ops');
update chamados.sistemas set ordem = 99 where id = 12;

-- 2. De-para: departamento do RH → setor da Central. Sem correspondência = a pessoa escolhe.
create table chamados.setor_departamento (
  departamento text primary key,
  setor_id     smallint not null references chamados.setores(id)
);
comment on table chamados.setor_departamento is 'De-para departamento (rh.departamentos.nome) → setor da Central. Departamento fora da lista: a pessoa escolhe o setor.';
insert into chamados.setor_departamento (departamento, setor_id) values
  ('Cível', 4), ('Trabalhista', 4), ('Previdenciário', 4), ('Tributário', 4), ('Execução', 4), ('Judicial/NUJI/CAC', 4),
  ('Controladoria', 3),
  ('Administrativo', 2), ('Financeiro', 2), ('RH', 2);

-- 3. Pessoas cadastradas automaticamente a partir do hub.
alter table chamados.pessoas add column origem_cadastro text not null default 'manual' check (origem_cadastro in ('manual', 'hub'));

-- 4. Convites (tokens). Só as funções acessam.
create table chamados.convites (
  id             uuid primary key default gen_random_uuid(),
  token_hash     bytea not null unique,
  usuario_id     uuid not null references auth.users(id) on delete cascade,
  nome           text not null,
  email          text,
  departamento   text,
  cargo          text,
  setor_id       smallint references chamados.setores(id),
  sistema_origem text,
  url_origem     text check (char_length(url_origem) <= 500),
  contexto       jsonb not null default '{}',
  criado_em      timestamptz not null default now(),
  expira_em      timestamptz not null,
  usado_em       timestamptz,
  chamado_id     uuid references chamados.chamados(id) on delete set null
);
create index convites_usuario_criado_idx on chamados.convites (usuario_id, criado_em);
create index convites_chamado_idx on chamados.convites (chamado_id);

-- 5. Origem e contexto técnico no chamado (só o time logado lê).
alter table chamados.chamados add column sistema_origem text, add column contexto jsonb;
comment on column chamados.chamados.sistema_origem is 'hub_codigo do sistema onde o botão "Abrir chamado" foi clicado.';
comment on column chamados.chamados.contexto is 'Dados de quem abriu pelo hub: tela, navegador, cargo, departamento, e-mail.';

-- 6. Configuração (URL do app, para trocar domínio sem mexer nos sistemas do hub).
create table chamados.configuracao (chave text primary key, valor text not null);
insert into chamados.configuracao (chave, valor) values ('app_url', 'https://chamado-jdc5.vercel.app');

alter table chamados.setor_departamento enable row level security;
alter table chamados.convites enable row level security;
alter table chamados.configuracao enable row level security;
grant all on chamados.setor_departamento, chamados.convites, chamados.configuracao to service_role;

-- 7. Funções.
-- Pessoa da Central para uma conta: primeiro pelo vínculo de login, depois pelo e-mail.
create function chamados._pessoa_da_conta(p_usuario uuid, p_email text)
returns chamados.pessoas language sql stable security definer set search_path = '' as $fn$
  select * from chamados.pessoas
   where ativo and (user_id = p_usuario or (p_email is not null and email = lower(p_email)))
   order by (user_id = p_usuario) desc nulls last
   limit 1
$fn$;

create function chamados.gerar_link_chamado(p_sistema text default null, p_url text default null, p_contexto jsonb default '{}')
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_uid uuid := auth.uid(); v_nome text; v_email text; v_dep text; v_cargo text; v_setor smallint;
  v_pessoa chamados.pessoas; v_token text; v_expira timestamptz := now() + interval '2 hours'; v_app text;
begin
  if v_uid is null or not acessos.eh_usuario_ativo() then
    raise exception 'Entre em um sistema do hub para abrir chamado por aqui.' using errcode = '42501';
  end if;
  if (select count(*) from chamados.convites where usuario_id = v_uid and criado_em > now() - interval '1 hour') >= 20 then
    raise exception 'Muitos links gerados em pouco tempo. Aguarde alguns minutos.' using errcode = 'P0001';
  end if;
  if p_contexto is null or jsonb_typeof(p_contexto) <> 'object' then p_contexto := '{}'; end if;
  if pg_column_size(p_contexto) > 2048 then
    raise exception 'Contexto grande demais.' using errcode = '22023';
  end if;

  select email into v_email from auth.users where id = v_uid;
  select hp.nome into v_nome from acessos.usuarios a join hub.pessoas hp on hp.id = a.pessoa_id where a.id = v_uid;
  v_nome := coalesce(nullif(btrim(v_nome), ''), split_part(v_email, '@', 1));
  select v.departamento_nome, v.cargo_nome into v_dep, v_cargo
    from rh.vw_vinculos_atuais v join acessos.usuarios a on a.pessoa_id = v.pessoa_id
   where a.id = v_uid order by v.data_admissao desc nulls last limit 1;

  v_pessoa := chamados._pessoa_da_conta(v_uid, v_email);
  v_setor := coalesce(v_pessoa.setor_id, (select setor_id from chamados.setor_departamento where departamento = v_dep));

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into chamados.convites (token_hash, usuario_id, nome, email, departamento, cargo, setor_id, sistema_origem, url_origem, contexto, expira_em)
  values (extensions.digest(v_token, 'sha256'), v_uid, v_nome, lower(v_email), v_dep, v_cargo, v_setor,
          left(p_sistema, 40), left(p_url, 500), p_contexto, v_expira);

  select valor into v_app from chamados.configuracao where chave = 'app_url';
  return jsonb_build_object('url', rtrim(v_app, '/') || '/?t=' || v_token, 'expira_em', v_expira);
end $fn$;

create function chamados._convite_valido(p_token text)
returns chamados.convites language plpgsql stable security definer set search_path = '' as $fn$
declare cv chamados.convites;
begin
  select * into cv from chamados.convites
   where token_hash = extensions.digest(coalesce(p_token, ''), 'sha256') and usado_em is null and expira_em > now();
  if cv.id is null then
    raise exception 'Link inválido ou expirado. Abra o chamado pelo formulário.' using errcode = 'P0002';
  end if;
  return cv;
end $fn$;

create function chamados.ler_convite(p_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare cv chamados.convites; p chamados.pessoas; v_setor smallint; s chamados.sistemas;
begin
  cv := chamados._convite_valido(p_token);
  p := chamados._pessoa_da_conta(cv.usuario_id, cv.email);
  v_setor := coalesce(p.setor_id, cv.setor_id);
  select * into s from chamados.sistemas where hub_codigo = cv.sistema_origem and ativo;
  return jsonb_build_object(
    'nome', coalesce(p.nome, cv.nome),
    'setor_id', v_setor,
    'setor', (select nome from chamados.setores where id = v_setor),
    'precisa_setor', v_setor is null and coalesce(p.papel::text, '') <> 'dev',
    'cargo', cv.cargo,
    'sistema_id', s.id,
    'sistema_origem', coalesce(s.nome, cv.sistema_origem),
    'expira_em', cv.expira_em);
end $fn$;

create function chamados.abrir_chamado_por_convite(
  p_token text, p_setor_id integer, p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare cv chamados.convites; p chamados.pessoas; v_setor smallint; c chamados.chamados; pr text; v_nome text;
begin
  cv := chamados._convite_valido(p_token);
  perform 1 from chamados.convites where id = cv.id for update;
  if (select usado_em from chamados.convites where id = cv.id) is not null then
    raise exception 'Link inválido ou expirado. Abra o chamado pelo formulário.' using errcode = 'P0002';
  end if;

  p := chamados._pessoa_da_conta(cv.usuario_id, cv.email);
  v_setor := coalesce(p.setor_id, cv.setor_id, p_setor_id::smallint);
  if p.id is null then
    if v_setor is null or not exists (select 1 from chamados.setores where id = v_setor) then
      raise exception 'Informe seu setor.' using errcode = '22023';
    end if;
    v_nome := cv.nome;
    if exists (select 1 from chamados.pessoas where nome = v_nome) then
      v_nome := v_nome || ' (' || split_part(coalesce(cv.email, cv.usuario_id::text), '@', 1) || ')';
    end if;
    insert into chamados.pessoas (nome, setor_id, papel, email, user_id, origem_cadastro)
    values (v_nome, v_setor, 'solicitante', cv.email, cv.usuario_id, 'hub')
    returning * into p;
  elsif p.user_id is null then
    update chamados.pessoas set user_id = cv.usuario_id where id = p.id and user_id is null;
  end if;

  foreach pr in array coalesce(p_prints, '{}') loop
    if pr !~ '^publico/[0-9a-f-]{36}\.(png|jpg|webp|gif)$'
       or exists (select 1 from chamados.chamados x where pr = any (x.prints)) then
      raise exception 'Print inválido.' using errcode = '22023';
    end if;
  end loop;

  insert into chamados.chamados (descricao, solicitante_id, sistema_id, urgencia, prints, origem, sistema_origem, contexto)
  values (btrim(p_descricao), p.id, p_sistema_id, p_urgencia, coalesce(p_prints, '{}'), 'publico', cv.sistema_origem,
          cv.contexto || jsonb_strip_nulls(jsonb_build_object('tela', cv.url_origem, 'cargo', cv.cargo,
                                                              'departamento', cv.departamento, 'email', cv.email)))
  returning * into c;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, p.id, 'aberto');
  update chamados.convites set usado_em = now(), chamado_id = c.id where id = cv.id;

  return jsonb_build_object('protocolo', c.protocolo, 'sistema_id', c.sistema_id, 'urgencia', c.urgencia,
    'prints', cardinality(c.prints), 'criado_em', c.criado_em, 'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em);
end $fn$;

revoke execute on function chamados._pessoa_da_conta(uuid, text), chamados._convite_valido(text),
  chamados.gerar_link_chamado(text, text, jsonb), chamados.ler_convite(text),
  chamados.abrir_chamado_por_convite(text, integer, integer, text, integer, text[]) from public, anon, authenticated;
grant execute on function chamados.gerar_link_chamado(text, text, jsonb) to authenticated;
grant execute on function chamados.ler_convite(text), chamados.abrir_chamado_por_convite(text, integer, integer, text, integer, text[]) to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- Gamificação · parte 1: gestor e novos fatos no fluxo de chamados
-- ----------------------------------------------------------------------------
-- * Gestor (pessoas.gestor): administra a gamificação e vê ranking/analytics;
--   não assume nem pontua. Login com a conta ATLAS, como o time.
-- * Avaliação do atendimento: na abertura sem login (formulário ou botão do hub)
--   o banco gera um código secreto (guarda só o hash). Só quem tem o código
--   avalia: 1 vez, chamado resolvido, até 14 dias depois da resolução.
-- * Colaboração: o responsável pede ajuda a um colega; o colega confirma ou recusa.
-- * Justificativa de atraso (responsável) e motivo obrigatório ao reabrir.
-- Nada aqui conhece a gamificação: ela reage aos fatos (eventos, avaliações,
-- colaborações) por gatilhos criados na parte 3.
-- ============================================================================

-- 1. Gestor
alter table chamados.pessoas add column gestor boolean not null default false;
comment on column chamados.pessoas.gestor is 'Administra a gamificação (Central de Gamificação); não assume chamados nem pontua.';
grant select (gestor) on chamados.pessoas to authenticated;

create function chamados.eh_gestor()
returns boolean language sql stable security definer set search_path = '' as $fn$
  select exists (select 1 from chamados.pessoas where user_id = auth.uid() and ativo and gestor)
$fn$;
revoke execute on function chamados.eh_gestor() from public, anon;
grant execute on function chamados.eh_gestor() to authenticated;

-- O gestor lê todos os chamados (ranking e analytics), sem poder agir neles.
alter policy chamados_ler on chamados.chamados
  using (chamados.eh_dev() or chamados.eh_gestor() or solicitante_id = chamados.eu_pessoa_id());
alter policy eventos_ler on chamados.eventos
  using (exists (select 1 from chamados.chamados c where c.id = chamado_id
                 and (chamados.eh_dev() or chamados.eh_gestor() or c.solicitante_id = chamados.eu_pessoa_id())));

create or replace function chamados.vincular_minha_conta()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
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
  return jsonb_build_object('id', p.id, 'nome', p.nome, 'setor_id', p.setor_id, 'papel', p.papel, 'ativo', p.ativo, 'gestor', p.gestor);
end $fn$;

-- 2. Fatos novos no chamado
alter table chamados.chamados
  add column codigo_avaliacao_hash bytea,
  add column justificativa_atraso text check (justificativa_atraso is null or char_length(justificativa_atraso) between 5 and 500),
  add column justificado_em timestamptz;
comment on column chamados.chamados.codigo_avaliacao_hash is 'SHA-256 do código secreto de avaliação (o código só existe no navegador de quem abriu).';
alter table chamados.eventos add column detalhe jsonb;
comment on column chamados.eventos.detalhe is 'Dados do evento; na reabertura: {"motivo": incompleto|recorrente|outro, "texto": ...}.';

create table chamados.avaliacoes (
  id         bigint generated always as identity primary key,
  chamado_id uuid not null unique references chamados.chamados (id) on delete cascade,
  nota       smallint not null check (nota between 1 and 5),
  elogio     boolean not null default false,
  comentario text check (comentario is null or char_length(comentario) <= 500),
  criada_em  timestamptz not null default now()
);
comment on table chamados.avaliacoes is 'Avaliação do atendimento pelo solicitante (1 por chamado, com código secreto).';

create type chamados.colaboracao_t as enum ('pedida', 'confirmada', 'recusada');
create table chamados.colaboracoes (
  id             bigint generated always as identity primary key,
  chamado_id     uuid not null references chamados.chamados (id) on delete cascade,
  responsavel_id uuid not null references chamados.pessoas (id),
  ajudante_id    uuid not null references chamados.pessoas (id),
  status         chamados.colaboracao_t not null default 'pedida',
  criada_em      timestamptz not null default now(),
  respondida_em  timestamptz,
  unique (chamado_id, ajudante_id),
  check (ajudante_id <> responsavel_id),
  check ((status = 'pedida') = (respondida_em is null))
);
create index colaboracoes_ajudante_idx on chamados.colaboracoes (ajudante_id, status);
comment on table chamados.colaboracoes is 'Ajuda entre técnicos: pedida pelo responsável, confirmada pelo colega.';

alter table chamados.avaliacoes enable row level security;
alter table chamados.colaboracoes enable row level security;
create policy avaliacoes_ler on chamados.avaliacoes for select to authenticated using (chamados.eh_dev() or chamados.eh_gestor());
create policy colaboracoes_ler on chamados.colaboracoes for select to authenticated using (chamados.eh_dev() or chamados.eh_gestor());
grant select on chamados.avaliacoes, chamados.colaboracoes to authenticated;
grant all on chamados.avaliacoes, chamados.colaboracoes to service_role;

-- 3. Código de avaliação (gerado nas aberturas sem login)
create function chamados._novo_codigo_avaliacao(p_chamado uuid)
returns text language plpgsql volatile security definer set search_path = '' as $fn$
declare v text := encode(extensions.gen_random_bytes(12), 'hex');
begin
  update chamados.chamados set codigo_avaliacao_hash = extensions.digest(v, 'sha256') where id = p_chamado;
  return v;
end $fn$;
revoke execute on function chamados._novo_codigo_avaliacao(uuid) from public, anon, authenticated;

create or replace function chamados.abrir_chamado_publico(
  p_setor_id integer, p_setor_outro text, p_nome text, p_cargo text,
  p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  c chamados.chamados; pr text; v_pessoa uuid; v_codigo text;
  v_nome text := chamados._limpar(p_nome);
  v_cargo text := chamados._limpar(p_cargo);
  v_outro text := case when p_setor_id is null then chamados._limpar(p_setor_outro) end;
begin
  if p_setor_id is not null and not exists (select 1 from chamados.setores where id = p_setor_id) then
    raise exception 'Informe seu setor.' using errcode = '22023';
  end if;
  if p_setor_id is null and char_length(coalesce(v_outro, '')) not between 2 and 60 then
    raise exception 'Informe seu setor.' using errcode = '22023';
  end if;
  if char_length(coalesce(v_nome, '')) not between 3 and 80 then
    raise exception 'Informe seu nome.' using errcode = '22023';
  end if;
  if char_length(coalesce(v_cargo, '')) not between 2 and 60 then
    raise exception 'Informe seu cargo.' using errcode = '22023';
  end if;
  if (select count(*) from chamados.chamados where origem = 'publico' and criado_em > now() - interval '10 minutes'
        and chamados._chave_nome(solicitante_nome) = chamados._chave_nome(v_nome)) >= 5
     or (select count(*) from chamados.chamados where origem = 'publico' and criado_em > now() - interval '10 minutes') >= 30 then
    raise exception 'Muitos chamados em pouco tempo. Aguarde alguns minutos e tente de novo.' using errcode = 'P0001';
  end if;
  foreach pr in array coalesce(p_prints, '{}') loop
    if pr !~ '^publico/[0-9a-f-]{36}\.(png|jpg|webp|gif)$'
       or exists (select 1 from chamados.chamados x where pr = any (x.prints)) then
      raise exception 'Print inválido.' using errcode = '22023';
    end if;
  end loop;

  -- Já cadastrado no mesmo setor? Liga ao cadastro (histórico e analytics).
  if p_setor_id is not null then
    select id into v_pessoa from chamados.pessoas
     where ativo and papel = 'solicitante' and setor_id = p_setor_id
       and chamados._chave_nome(nome) = chamados._chave_nome(v_nome)
     limit 1;
  end if;

  insert into chamados.chamados (descricao, solicitante_id, solicitante_nome, solicitante_cargo, setor_id, setor_outro,
                                 sistema_id, urgencia, prints, origem)
  values (btrim(p_descricao), v_pessoa, v_nome, v_cargo, p_setor_id, v_outro,
          p_sistema_id, p_urgencia, coalesce(p_prints, '{}'), 'publico')
  returning * into c;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, v_pessoa, 'aberto');
  v_codigo := chamados._novo_codigo_avaliacao(c.id);
  return jsonb_build_object('codigo_avaliacao', v_codigo, 'protocolo', c.protocolo, 'sistema_id', c.sistema_id, 'urgencia', c.urgencia,
    'prints', cardinality(c.prints), 'criado_em', c.criado_em, 'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em);
end $fn$;

create or replace function chamados.abrir_chamado_por_convite(
  p_token text, p_setor_id integer, p_cargo text,
  p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare cv chamados.convites; p chamados.pessoas; v_setor smallint; c chamados.chamados; pr text; v_nome text; v_cargo text; v_codigo text;
begin
  cv := chamados._convite_valido(p_token);
  perform 1 from chamados.convites where id = cv.id for update;
  if (select usado_em from chamados.convites where id = cv.id) is not null then
    raise exception 'Link inválido ou expirado. Abra o chamado pelo formulário.' using errcode = 'P0002';
  end if;

  p := chamados._pessoa_da_conta(cv.usuario_id, cv.email);
  v_cargo := coalesce(chamados._limpar(cv.cargo), chamados._limpar(p_cargo));
  if coalesce(p.papel::text, '') <> 'dev' and char_length(coalesce(v_cargo, '')) not between 2 and 60 then
    raise exception 'Informe seu cargo.' using errcode = '22023';
  end if;
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

  insert into chamados.chamados (descricao, solicitante_id, solicitante_cargo, setor_id, sistema_id, urgencia, prints,
                                 origem, sistema_origem, contexto)
  values (btrim(p_descricao), p.id, left(v_cargo, 60), p.setor_id, p_sistema_id, p_urgencia, coalesce(p_prints, '{}'),
          'publico', cv.sistema_origem,
          cv.contexto || jsonb_strip_nulls(jsonb_build_object('tela', cv.url_origem, 'cargo', v_cargo,
                                                              'departamento', cv.departamento, 'email', cv.email)))
  returning * into c;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, p.id, 'aberto');
  update chamados.convites set usado_em = now(), chamado_id = c.id where id = cv.id;

  v_codigo := chamados._novo_codigo_avaliacao(c.id);
  return jsonb_build_object('codigo_avaliacao', v_codigo, 'protocolo', c.protocolo, 'sistema_id', c.sistema_id, 'urgencia', c.urgencia,
    'prints', cardinality(c.prints), 'criado_em', c.criado_em, 'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em);
end $fn$;

-- 4. Acompanhar mostra se o chamado já foi avaliado e se ainda pode ser.
create or replace function chamados.consultar_chamado(p_protocolo text)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object(
    'protocolo', c.protocolo, 'status', c.status, 'sistema', s.nome, 'grupo', s.grupo, 'urgencia', c.urgencia,
    'criado_em', c.criado_em, 'assumido_em', c.assumido_em, 'resolvido_em', c.resolvido_em,
    'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em,
    'responsavel', split_part(r.nome, ' ', 1),
    'avaliado', exists (select 1 from chamados.avaliacoes a where a.chamado_id = c.id),
    'avaliavel', c.codigo_avaliacao_hash is not null and c.status = 'resolvido'
                 and c.resolvido_em > now() - interval '14 days'
                 and not exists (select 1 from chamados.avaliacoes a where a.chamado_id = c.id))
  from chamados.chamados c
  join chamados.sistemas s on s.id = c.sistema_id
  left join chamados.pessoas r on r.id = c.responsavel_id
  where c.protocolo = upper(btrim(p_protocolo))
$fn$;

create function chamados.avaliar_chamado(p_protocolo text, p_codigo text, p_nota integer, p_elogio boolean default false, p_comentario text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare c chamados.chamados;
begin
  select * into c from chamados.chamados where protocolo = upper(btrim(p_protocolo)) for update;
  if c.id is null or c.codigo_avaliacao_hash is null
     or c.codigo_avaliacao_hash <> extensions.digest(coalesce(lower(btrim(p_codigo)), ''), 'sha256') then
    raise exception 'Código de avaliação inválido.' using errcode = '42501';
  end if;
  if c.status <> 'resolvido' then raise exception 'O chamado ainda não foi resolvido.' using errcode = 'P0001'; end if;
  if c.resolvido_em < now() - interval '14 days' then raise exception 'O prazo para avaliar (14 dias) terminou.' using errcode = 'P0001'; end if;
  if p_nota is null or p_nota not between 1 and 5 then raise exception 'Nota de 1 a 5.' using errcode = '22023'; end if;
  if exists (select 1 from chamados.avaliacoes where chamado_id = c.id) then
    raise exception 'Este chamado já foi avaliado.' using errcode = 'P0001';
  end if;
  insert into chamados.avaliacoes (chamado_id, nota, elogio, comentario)
  values (c.id, p_nota, coalesce(p_elogio, false), nullif(left(chamados._limpar(p_comentario), 500), ''));
  return jsonb_build_object('ok', true);
end $fn$;

-- 5. Colaboração
create function chamados.pedir_ajuda(p_chamado uuid, p_ajudante uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados; r chamados.colaboracoes;
begin
  if not chamados.eh_dev() then raise exception 'Só o time pede ajuda.' using errcode = '42501'; end if;
  select * into c from chamados.chamados where id = p_chamado;
  if c.id is null or c.responsavel_id is distinct from eu or c.status = 'resolvido' then
    raise exception 'Só o responsável pede ajuda, com o chamado em andamento.' using errcode = 'P0001';
  end if;
  if p_ajudante = eu or not exists (select 1 from chamados.pessoas where id = p_ajudante and ativo and papel = 'dev') then
    raise exception 'Escolha um colega do time.' using errcode = '22023';
  end if;
  insert into chamados.colaboracoes (chamado_id, responsavel_id, ajudante_id) values (c.id, eu, p_ajudante)
  on conflict (chamado_id, ajudante_id) do nothing
  returning * into r;
  if r.id is null then raise exception 'Este colega já foi chamado neste chamado.' using errcode = 'P0001'; end if;
  return to_jsonb(r);
end $fn$;

create function chamados.responder_ajuda(p_colaboracao bigint, p_aceitar boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); r chamados.colaboracoes;
begin
  update chamados.colaboracoes set status = case when p_aceitar then 'confirmada' else 'recusada' end::chamados.colaboracao_t,
         respondida_em = now()
   where id = p_colaboracao and ajudante_id = eu and status = 'pedida'
  returning * into r;
  if r.id is null then raise exception 'Pedido de ajuda não encontrado.' using errcode = 'P0001'; end if;
  return to_jsonb(r);
end $fn$;

-- 6. Justificativa de atraso (só o responsável, com o prazo de resolver vencido)
create function chamados.justificar_atraso(p_id uuid, p_texto text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados; v text := chamados._limpar(p_texto);
begin
  if char_length(coalesce(v, '')) not between 5 and 500 then raise exception 'Explique o atraso (5 a 500 caracteres).' using errcode = '22023'; end if;
  update chamados.chamados set justificativa_atraso = v, justificado_em = now(), atualizado_em = now()
   where id = p_id and responsavel_id = eu and coalesce(resolvido_em, now()) > prazo_em
  returning * into c;
  if c.id is null then raise exception 'Só o responsável justifica, e só chamado com prazo vencido.' using errcode = 'P0001'; end if;
  return to_jsonb(c);
end $fn$;

-- 7. Reabrir pede motivo (incompleto = não estava resolvido; recorrente = voltou a acontecer)
create function chamados.reabrir_chamado(p_id uuid, p_motivo text, p_texto text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados;
begin
  if not chamados.eh_dev() then raise exception 'Só o time de desenvolvimento reabre chamados.' using errcode = '42501'; end if;
  if p_motivo is null or p_motivo not in ('incompleto', 'recorrente', 'outro') then
    raise exception 'Informe o motivo da reabertura.' using errcode = '22023';
  end if;
  update chamados.chamados set status = 'andamento', resolvido_em = null, atualizado_em = now()
   where id = p_id and status = 'resolvido'
  returning * into c;
  if not found then raise exception 'Este chamado não está resolvido.' using errcode = 'P0001'; end if;
  insert into chamados.eventos (chamado_id, autor_id, acao, detalhe)
  values (c.id, eu, 'reaberto', jsonb_strip_nulls(jsonb_build_object('motivo', p_motivo, 'texto', left(chamados._limpar(p_texto), 300))));
  return to_jsonb(c);
end $fn$;

-- 8. Permissões
revoke execute on function chamados.avaliar_chamado(text, text, integer, boolean, text),
  chamados.pedir_ajuda(uuid, uuid), chamados.responder_ajuda(bigint, boolean),
  chamados.justificar_atraso(uuid, text), chamados.reabrir_chamado(uuid, text, text) from public;
grant execute on function chamados.avaliar_chamado(text, text, integer, boolean, text) to anon, authenticated;
grant execute on function chamados.pedir_ajuda(uuid, uuid), chamados.responder_ajuda(bigint, boolean),
  chamados.justificar_atraso(uuid, text), chamados.reabrir_chamado(uuid, text, text) to authenticated;
revoke execute on function chamados.reabrir_chamado(uuid) from public, anon, authenticated;
comment on function chamados.reabrir_chamado(uuid) is 'OBSOLETA: substituída pela versão com motivo. Sem permissão de execução; pode ser removida.';

notify pgrst, 'reload schema';

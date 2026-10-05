-- ============================================================================
-- Nome e cargo livres (obrigatórios) na abertura sem login
-- ----------------------------------------------------------------------------
-- Quem não está cadastrado também abre chamado: em vez de escolher o nome numa
-- lista, a pessoa digita nome e cargo; o setor continua numa lista, com "Outro"
-- (aí digita qual). O que foi digitado fica gravado no próprio chamado; nada é
-- cadastrado em chamados.pessoas. Se o nome bater (sem acento/maiúsculas) com um
-- solicitante ativo do mesmo setor, o chamado é ligado a ele.
-- * catalogo_publico() deixa de expor os nomes cadastrados (LGPD).
-- * Botão do hub: o cargo vem do RH; se o RH não tiver, a pessoa informa.
-- * Versões antigas das funções ficam sem permissão (sem drop: o conector do
--   Supabase não roda comandos destrutivos sem confirmação).
-- ============================================================================

-- 1. O que a pessoa informou, gravado no chamado.
alter table chamados.chamados
  add column solicitante_nome text check (solicitante_nome is null or char_length(solicitante_nome) between 3 and 80),
  add column solicitante_cargo text check (solicitante_cargo is null or char_length(solicitante_cargo) between 2 and 60),
  add column setor_id smallint references chamados.setores (id),
  add column setor_outro text check (setor_outro is null or char_length(setor_outro) between 2 and 60);
alter table chamados.chamados alter column solicitante_id drop not null;
alter table chamados.chamados add constraint chamados_quem_abriu_check check (
  solicitante_id is not null
  or (solicitante_nome is not null and solicitante_cargo is not null and (setor_id is not null or setor_outro is not null)));
comment on column chamados.chamados.solicitante_nome is 'Nome digitado no formulário sem login.';
comment on column chamados.chamados.solicitante_cargo is 'Cargo digitado (ou do RH, no botão do hub).';
comment on column chamados.chamados.setor_id is 'Setor informado na abertura (nulo quando escolheu "Outro").';
comment on column chamados.chamados.setor_outro is 'Setor digitado quando a pessoa escolheu "Outro".';
create index chamados_publico_nome_idx on chamados.chamados (lower(solicitante_nome), criado_em) where origem = 'publico';

-- Evento "aberto" de quem não tem cadastro não tem autor.
alter table chamados.eventos alter column autor_id drop not null;

-- 2. Texto limpo: sem espaços nas pontas nem repetidos; vazio vira nulo.
create function chamados._limpar(p text) returns text
language sql immutable set search_path = '' as $fn$
  select nullif(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'), '')
$fn$;

-- Chave de comparação de nomes (sem acento e sem maiúsculas).
create function chamados._chave_nome(p text) returns text
language sql stable set search_path = '' as $fn$
  select lower(extensions.unaccent(chamados._limpar(p)))
$fn$;
revoke execute on function chamados._limpar(text), chamados._chave_nome(text) from public;

-- 3. Catálogo sem nomes de pessoas.
create or replace function chamados.catalogo_publico()
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object(
    'setores',   coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome, 'ordem', ordem) order by ordem) from chamados.setores), '[]'),
    'pessoas',   '[]'::jsonb,
    'sistemas',  coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome, 'ordem', ordem, 'ativo', ativo, 'grupo', grupo) order by ordem)
                             from chamados.sistemas where ativo), '[]'),
    'urgencias', coalesce((select jsonb_agg(to_jsonb(u) order by nivel) from chamados.urgencias u), '[]'),
    'prazos',    coalesce((select jsonb_agg(to_jsonb(p)) from chamados.prazos p), '[]'))
$fn$;

-- 4. Abertura sem login com nome, cargo e setor informados.
create function chamados.abrir_chamado_publico(
  p_setor_id integer, p_setor_outro text, p_nome text, p_cargo text,
  p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  c chamados.chamados; pr text; v_pessoa uuid;
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
  return jsonb_build_object('protocolo', c.protocolo, 'sistema_id', c.sistema_id, 'urgencia', c.urgencia,
    'prints', cardinality(c.prints), 'criado_em', c.criado_em, 'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em);
end $fn$;

-- 5. Botão do hub: cargo do RH ou informado pela pessoa.
create function chamados.abrir_chamado_por_convite(
  p_token text, p_setor_id integer, p_cargo text,
  p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare cv chamados.convites; p chamados.pessoas; v_setor smallint; c chamados.chamados; pr text; v_nome text; v_cargo text;
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

  return jsonb_build_object('protocolo', c.protocolo, 'sistema_id', c.sistema_id, 'urgencia', c.urgencia,
    'prints', cardinality(c.prints), 'criado_em', c.criado_em, 'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em);
end $fn$;

-- 6. Permissões: novas liberadas; antigas sem execução.
revoke execute on function chamados.abrir_chamado_publico(integer, text, text, text, integer, text, integer, text[]),
  chamados.abrir_chamado_por_convite(text, integer, text, integer, text, integer, text[]) from public;
grant execute on function chamados.abrir_chamado_publico(integer, text, text, text, integer, text, integer, text[]),
  chamados.abrir_chamado_por_convite(text, integer, text, integer, text, integer, text[]) to anon, authenticated;

revoke execute on function chamados.abrir_chamado_publico(integer, uuid, integer, text, integer, text[]),
  chamados.abrir_chamado_por_convite(text, integer, integer, text, integer, text[]) from public, anon, authenticated;
comment on function chamados.abrir_chamado_publico(integer, uuid, integer, text, integer, text[]) is
  'OBSOLETA: substituída pela versão com nome e cargo livres. Sem permissão de execução; pode ser removida.';
comment on function chamados.abrir_chamado_por_convite(text, integer, integer, text, integer, text[]) is
  'OBSOLETA: substituída pela versão com p_cargo. Sem permissão de execução; pode ser removida.';

notify pgrst, 'reload schema';

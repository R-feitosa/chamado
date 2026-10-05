-- ============================================================================
-- Gamificação · parte 3: motor de eventos
-- ----------------------------------------------------------------------------
-- O sistema de chamados não chama a gamificação. Gatilhos nas tabelas de fatos
-- (eventos, avaliacoes, colaboracoes) só ENFILEIRAM em gam_eventos (com chave
-- de idempotência) e nunca derrubam a operação do chamado.
-- gam_ciclo() (pg_cron, 1 min; e sob demanda pelo front) processa a fila:
--   evento → elegibilidade → regras de XP (ledger) → suspeitas → sequências →
--   conquistas → perfil/nível → notificações.
-- XP de resolução nasce "pendente" e só é confirmado depois de horas_pendente
-- sem reabertura (aí nasce o evento interno ticket.confirmed). Missões, sequência
-- semanal e temporadas fecham em gam_fechar_periodos() (pg_cron, 15 min).
-- ============================================================================

-- ============ Utilitários ============
create function chamados.gam_cfg(p_chave text)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select valor from chamados.gam_config where chave = p_chave
$fn$;

create function chamados.gam_ativo()
returns boolean language sql stable security definer set search_path = '' as $fn$
  select coalesce((select valor = 'true'::jsonb from chamados.gam_config where chave = 'ativo'), false)
$fn$;

create function chamados.gam_dia(p_ts timestamptz)
returns date language sql immutable set search_path = '' as $fn$
  select (p_ts at time zone 'America/Sao_Paulo')::date
$fn$;

-- Início do período (fuso de Brasília) que contém a data.
create function chamados.gam_inicio_periodo(p_periodo text, p_dia date)
returns date language sql immutable set search_path = '' as $fn$
  select case p_periodo
    when 'dia' then p_dia
    when 'semana' then p_dia - (extract(isodow from p_dia)::int - 1)
    when 'mes' then date_trunc('month', p_dia)::date
    when 'trimestre' then date_trunc('quarter', p_dia)::date
    when 'ano' then date_trunc('year', p_dia)::date
  end
$fn$;

create function chamados.gam_fim_periodo(p_periodo text, p_inicio date)
returns date language sql immutable set search_path = '' as $fn$
  select case p_periodo
    when 'dia' then p_inicio + 1
    when 'semana' then p_inicio + 7
    when 'mes' then (p_inicio + interval '1 month')::date
    when 'trimestre' then (p_inicio + interval '3 months')::date
    when 'ano' then (p_inicio + interval '1 year')::date
  end
$fn$;

-- Meia-noite de Brasília de uma data, como instante.
create function chamados.gam_instante(p_dia date)
returns timestamptz language sql immutable set search_path = '' as $fn$
  select (p_dia::timestamp at time zone 'America/Sao_Paulo')
$fn$;

-- Nível e progresso a partir do XP (fonte única; o front espelha em src/lib/gamificacao.ts).
create function chamados.gam_nivel(p_xp integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_xp integer := greatest(coalesce(p_xp, 0), 0);
  atual chamados.gam_niveis; prox chamados.gam_niveis; ant chamados.gam_niveis;
  v_nivel integer; v_min integer; v_prox integer; v_gap numeric; v_fator numeric; v_nome text;
begin
  select * into atual from chamados.gam_niveis where xp_minimo <= v_xp order by xp_minimo desc limit 1;
  select * into prox from chamados.gam_niveis where xp_minimo > v_xp order by xp_minimo limit 1;
  v_nivel := atual.nivel; v_min := atual.xp_minimo; v_nome := atual.nome;
  if prox.nivel is not null then
    v_prox := prox.xp_minimo;
  else
    -- Acima do último nível cadastrado: cada nível exige o intervalo anterior × fator.
    select * into ant from chamados.gam_niveis where xp_minimo < atual.xp_minimo order by xp_minimo desc limit 1;
    v_gap := greatest(atual.xp_minimo - coalesce(ant.xp_minimo, 0), 1000);
    v_fator := coalesce((chamados.gam_cfg('niveis_extra_fator'))::text::numeric, 1.25);
    loop
      v_gap := round(v_gap * v_fator);
      v_prox := v_min + v_gap::integer;
      exit when v_xp < v_prox;
      v_nivel := v_nivel + 1; v_min := v_prox;
    end loop;
    if v_nivel > atual.nivel then v_nome := atual.nome || ' ' || (v_nivel - atual.nivel + 1); end if;
  end if;
  return jsonb_build_object('nivel', v_nivel, 'nome', v_nome, 'xp', v_xp, 'xp_nivel', v_min, 'xp_proximo', v_prox,
    'faltam', v_prox - v_xp, 'progresso', round((v_xp - v_min)::numeric / greatest(v_prox - v_min, 1), 4));
end $fn$;

-- Por que um chamado NÃO gera XP (nulo = elegível).
create function chamados.gam_inelegivel(p_chamado uuid)
returns text language sql stable security definer set search_path = '' as $fn$
  select case
    when c.id is null then 'chamado inexistente'
    when c.responsavel_id is null then 'sem responsável'
    when r.papel <> 'dev' or r.gestor or not r.ativo then 'responsável fora do time'
    when c.origem = 'login' then 'aberto pelo próprio time'
    when c.solicitante_id = c.responsavel_id then 'chamado próprio'
    when s.id is not null and (s.papel = 'dev' or s.gestor) then 'solicitante do time'
    when c.criado_em < coalesce((chamados.gam_cfg('ligada_em') #>> '{}')::timestamptz, 'infinity') then 'anterior ao lançamento'
  end
  from (select 1) x
  left join chamados.chamados c on c.id = p_chamado
  left join chamados.pessoas r on r.id = c.responsavel_id
  left join chamados.pessoas s on s.id = c.solicitante_id
$fn$;

create function chamados.gam_temporada_de(p_ts timestamptz)
returns smallint language sql stable security definer set search_path = '' as $fn$
  select id from chamados.gam_temporadas
   where chamados.gam_dia(p_ts) between inicio and fim and status <> 'futura'
   order by inicio desc limit 1
$fn$;

create function chamados.gam_notificar(p_pessoa uuid, p_tipo text, p_titulo text, p_detalhe text default null, p_xp integer default null, p_dados jsonb default '{}')
returns void language sql volatile security definer set search_path = '' as $fn$
  insert into chamados.gam_notificacoes (pessoa_id, tipo, titulo, detalhe, xp, dados)
  values (p_pessoa, p_tipo, p_titulo, p_detalhe, p_xp, coalesce(p_dados, '{}'))
$fn$;

-- ============ Ledger ============
-- Lança XP com idempotência: (pessoa, chave) é único; repetição devolve nulo.
create function chamados.gam_lancar(
  p_pessoa uuid, p_chave text, p_valor integer, p_motivo text, p_status chamados.gam_xp_status_t,
  p_evento bigint default null, p_chamado uuid default null, p_regra text default null,
  p_tier smallint default null, p_missao bigint default null, p_confirmar_em timestamptz default null
) returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id bigint;
begin
  if p_valor = 0 or not exists (select 1 from chamados.pessoas where id = p_pessoa and papel = 'dev' and ativo and not gestor) then
    return null;
  end if;
  insert into chamados.gam_xp (pessoa_id, chave, valor, motivo, status, evento_id, chamado_id, regra_codigo,
                               conquista_tier_id, missao_resultado_id, temporada_id, confirmar_em)
  values (p_pessoa, p_chave, p_valor, p_motivo, p_status, p_evento, p_chamado, p_regra, p_tier, p_missao,
          chamados.gam_temporada_de(now()), case when p_status = 'pendente' then coalesce(p_confirmar_em, now()) end)
  on conflict (pessoa_id, chave) do nothing
  returning id into v_id;
  return case when v_id is null then null else p_valor end;
end $fn$;

-- Aplica uma regra configurável (on/off, limites por chamado e por dia, fator e teto).
create function chamados.gam_aplicar_regra(
  p_regra text, p_pessoa uuid, p_chamado uuid, p_evento bigint, p_status chamados.gam_xp_status_t,
  p_extra text default null, p_fator numeric default 1, p_teto integer default null
) returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare r chamados.gam_regras; v integer; n integer;
begin
  select * into r from chamados.gam_regras where codigo = p_regra;
  if r.codigo is null or not r.ativo then return null; end if;
  select count(*) into n from chamados.gam_xp
   where pessoa_id = p_pessoa and regra_codigo = p_regra and chamado_id is not distinct from p_chamado and status <> 'estornado';
  if p_chamado is not null and n >= r.limite_por_chamado then return null; end if;
  if r.limite_diario is not null then
    select count(*) into n from chamados.gam_xp
     where pessoa_id = p_pessoa and regra_codigo = p_regra and status <> 'estornado'
       and chamados.gam_dia(criado_em) = chamados.gam_dia(now());
    if n >= r.limite_diario then return null; end if;
  end if;
  v := round(r.xp * case when r.usa_multiplicador then p_fator else 1 end)::integer;
  if p_teto is not null and v > 0 then v := least(v, greatest(p_teto, 0)); end if;
  if v = 0 then return null; end if;
  return chamados.gam_lancar(p_pessoa, p_regra || ':' || coalesce(p_chamado::text, '-') || coalesce(':' || p_extra, ''),
    v, r.nome, p_status, p_evento, p_chamado, p_regra, null, null,
    case when p_status = 'pendente' then now() + make_interval(hours => (chamados.gam_cfg('horas_pendente'))::text::int) end);
end $fn$;

-- Recalcula o cache do perfil a partir do ledger e avisa quando sobe de nível.
create function chamados.gam_atualizar_perfil(p_pessoa uuid)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare v_conf integer; v_pend integer; v_antes smallint; n jsonb;
begin
  select greatest(coalesce(sum(valor) filter (where status = 'confirmado'), 0), 0)::int,
         coalesce(sum(valor) filter (where status = 'pendente'), 0)::int
    into v_conf, v_pend from chamados.gam_xp where pessoa_id = p_pessoa;
  n := chamados.gam_nivel(v_conf);
  select nivel into v_antes from chamados.gam_perfis where pessoa_id = p_pessoa;
  insert into chamados.gam_perfis (pessoa_id, xp_confirmado, xp_pendente, nivel, atualizado_em)
  values (p_pessoa, v_conf, v_pend, (n->>'nivel')::int, now())
  on conflict (pessoa_id) do update set xp_confirmado = excluded.xp_confirmado, xp_pendente = excluded.xp_pendente,
    nivel = excluded.nivel, atualizado_em = now();
  if v_antes is not null and (n->>'nivel')::int > v_antes then
    perform chamados.gam_notificar(p_pessoa, 'nivel', 'Nível ' || (n->>'nivel') || ' alcançado', n->>'nome', null,
      jsonb_build_object('nivel', (n->>'nivel')::int, 'nome', n->>'nome'));
  end if;
end $fn$;

-- ============ Sequências ============
create function chamados.gam_sequencia(p_pessoa uuid, p_tipo text, p_sucesso boolean)
returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare v integer;
begin
  insert into chamados.gam_sequencias (pessoa_id, tipo, atual, recorde)
  values (p_pessoa, p_tipo, case when p_sucesso then 1 else 0 end, case when p_sucesso then 1 else 0 end)
  on conflict (pessoa_id, tipo) do update
    set atual = case when p_sucesso then chamados.gam_sequencias.atual + 1 else 0 end,
        recorde = greatest(chamados.gam_sequencias.recorde, case when p_sucesso then chamados.gam_sequencias.atual + 1 else 0 end),
        atualizado_em = now()
  returning atual into v;
  if p_sucesso and v >= 5 and v % 5 = 0 then
    perform chamados.gam_notificar(p_pessoa, 'sequencia',
      case p_tipo when 'sla' then v || ' chamados seguidos dentro do SLA'
                  when 'sem_reabertura' then v || ' chamados seguidos sem reabertura'
                  when 'cinco_estrelas' then v || ' avaliações 5 estrelas seguidas'
                  else v || ' semanas seguidas com SLA ≥ 95%' end,
      null, null, jsonb_build_object('tipo', p_tipo, 'atual', v));
  end if;
  return v;
end $fn$;

-- ============ Conquistas ============
create function chamados.gam_metricas(p_pessoa uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  e jsonb := chamados.gam_cfg('expediente');
  v_ini time := (e->>'inicio')::time;
  v_horas integer := (chamados.gam_cfg('madrugador_horas'))::text::int;
  m jsonb;
begin
  with x as (
    select regra_codigo, chamado_id from chamados.gam_xp where pessoa_id = p_pessoa and status = 'confirmado'
  ), res as (
    select c.* from chamados.chamados c where c.id in (select chamado_id from x where regra_codigo = 'resolvido')
  )
  select jsonb_build_object(
    'resolvidos', (select count(*) from x where regra_codigo = 'resolvido'),
    'resolvidos_sla', (select count(*) from x where regra_codigo = 'resolvido_sla'),
    'criticos', (select count(*) from x where regra_codigo = 'critico'),
    'avaliacoes_5', (select count(*) from x where regra_codigo = 'avaliacao_5'),
    'ajudas', (select count(*) from x where regra_codigo = 'ajuda'),
    'velocista', (select count(*) from res where resolvido_em - assumido_em < interval '10 minutes'),
    'madrugador', (select count(*) from res r
                    where extract(isodow from r.resolvido_em at time zone 'America/Sao_Paulo')::int in (select jsonb_array_elements_text(e->'dias')::int)
                      and (r.resolvido_em at time zone 'America/Sao_Paulo')::time >= v_ini
                      and (r.resolvido_em at time zone 'America/Sao_Paulo')::time < v_ini + make_interval(hours => v_horas)),
    'seq_sem_reabertura', coalesce((select recorde from chamados.gam_sequencias where pessoa_id = p_pessoa and tipo = 'sem_reabertura'), 0),
    'seq_sla', coalesce((select recorde from chamados.gam_sequencias where pessoa_id = p_pessoa and tipo = 'sla'), 0),
    'seq_cinco_estrelas', coalesce((select recorde from chamados.gam_sequencias where pessoa_id = p_pessoa and tipo = 'cinco_estrelas'), 0),
    'seq_semanas_sla', coalesce((select recorde from chamados.gam_sequencias where pessoa_id = p_pessoa and tipo = 'semanas_sla'), 0))
  into m;
  return m;
end $fn$;

-- Concede uma recompensa simbólica (título, moldura…).
create function chamados.gam_dar_recompensa(p_pessoa uuid, p_recompensa smallint, p_origem text)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare r chamados.gam_recompensas;
begin
  if p_recompensa is null then return; end if;
  select * into r from chamados.gam_recompensas where id = p_recompensa and ativo;
  if r.id is null then return; end if;
  insert into chamados.gam_recompensas_pessoa (pessoa_id, recompensa_id, origem) values (p_pessoa, r.id, p_origem)
  on conflict do nothing;
  if found then
    perform chamados.gam_notificar(p_pessoa, 'conquista', 'Nova recompensa: ' || r.nome, r.descricao, null,
      jsonb_build_object('recompensa', r.codigo, 'tipo', r.tipo, 'raridade', r.raridade));
  end if;
end $fn$;

-- Desbloqueia um tier (idempotente) com XP, recompensa e notificação.
create function chamados.gam_desbloquear(p_pessoa uuid, p_tier smallint, p_origem text)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare t chamados.gam_conquista_tiers; c chamados.gam_conquistas; v_nome text;
begin
  select * into t from chamados.gam_conquista_tiers where id = p_tier;
  select * into c from chamados.gam_conquistas where id = t.conquista_id;
  insert into chamados.gam_conquistas_pessoa (pessoa_id, tier_id) values (p_pessoa, p_tier) on conflict do nothing;
  if not found then return false; end if;
  v_nome := c.nome || coalesce(' · ' || t.nome, '');
  if t.xp > 0 then
    perform chamados.gam_lancar(p_pessoa, 'conquista:' || p_tier, t.xp, 'Conquista: ' || v_nome, 'confirmado', null, null, null, p_tier);
  end if;
  perform chamados.gam_notificar(p_pessoa, 'conquista', v_nome, c.descricao, nullif(t.xp, 0),
    jsonb_build_object('codigo', c.codigo, 'icone', c.icone, 'raridade', coalesce(t.raridade, c.raridade), 'tier', t.nome, 'origem', p_origem));
  perform chamados.gam_dar_recompensa(p_pessoa, t.recompensa_id, 'conquista:' || c.codigo);
  return true;
end $fn$;

create function chamados.gam_avaliar_conquistas(p_pessoa uuid)
returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare m jsonb := chamados.gam_metricas(p_pessoa); t record; n integer := 0;
begin
  for t in
    select tr.id from chamados.gam_conquista_tiers tr join chamados.gam_conquistas c on c.id = tr.conquista_id
     where c.ativo and c.metrica is not null and coalesce((m->>c.metrica)::int, 0) >= tr.limite
       and not exists (select 1 from chamados.gam_conquistas_pessoa p where p.pessoa_id = p_pessoa and p.tier_id = tr.id)
     order by c.ordem, tr.tier
  loop
    if chamados.gam_desbloquear(p_pessoa, t.id, 'metrica') then n := n + 1; end if;
  end loop;
  return n;
end $fn$;

-- ============ Antiabuso ============
create function chamados.gam_suspeitar(p_pessoa uuid, p_chamado uuid, p_regra text, p_descricao text, p_evidencia jsonb)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
begin
  insert into chamados.gam_suspeitas (pessoa_id, chamado_id, regra, descricao, evidencia)
  values (p_pessoa, p_chamado, p_regra, p_descricao, coalesce(p_evidencia, '{}'))
  on conflict do nothing;
  if found and p_chamado is not null then
    update chamados.gam_xp set status = 'retido', atualizado_em = now()
     where pessoa_id = p_pessoa and chamado_id = p_chamado and status = 'pendente';
  end if;
end $fn$;

create function chamados.gam_tem_suspeita(p_pessoa uuid, p_chamado uuid)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select exists (select 1 from chamados.gam_suspeitas where pessoa_id = p_pessoa and chamado_id = p_chamado and status = 'aberta')
$fn$;

-- Heurísticas na resolução; devolve true se o chamado ficou em revisão.
create function chamados.gam_checar_resolucao(c chamados.chamados)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare s jsonb := chamados.gam_cfg('suspeita'); v_min numeric; n integer;
begin
  v_min := extract(epoch from (c.resolvido_em - c.assumido_em)) / 60;
  if v_min < (s->>'min_assumir_resolver_min')::numeric then
    perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'resolucao_relampago',
      'Resolvido ' || round(v_min, 1) || ' min depois de assumir.', jsonb_build_object('minutos', round(v_min, 1)));
  end if;
  if c.urgencia = 3 and extract(epoch from (c.resolvido_em - c.criado_em)) / 60 < (s->>'critico_min')::numeric then
    perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'critico_relampago',
      'Chamado muito urgente resolvido em menos de ' || (s->>'critico_min') || ' min desde a abertura.', '{}');
  end if;
  if c.solicitante_nome is not null then
    select count(*) into n from chamados.chamados x
     where x.responsavel_id = c.responsavel_id and x.status = 'resolvido'
       and chamados.gam_dia(x.resolvido_em) = chamados.gam_dia(c.resolvido_em)
       and chamados._chave_nome(x.solicitante_nome) = chamados._chave_nome(c.solicitante_nome);
    if n >= (s->>'mesmo_nome_dia')::int then
      perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'mesmo_solicitante_dia',
        n || ' chamados do mesmo nome resolvidos pelo mesmo técnico no dia.', jsonb_build_object('quantidade', n, 'nome', c.solicitante_nome));
    end if;
  end if;
  select count(*) into n from chamados.eventos where chamado_id = c.id and acao = 'reaberto';
  if n >= (s->>'reaberturas')::int then
    perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'reabre_fecha', 'Chamado reaberto ' || n || ' vezes.', jsonb_build_object('reaberturas', n));
  end if;
  return chamados.gam_tem_suspeita(c.responsavel_id, c.id);
end $fn$;

-- ============ Tratadores de evento ============
create function chamados.gam_ao_assumir(e chamados.gam_eventos)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare c chamados.chamados; f numeric := (chamados.gam_cfg('resposta_rapida_fracao'))::text::numeric;
begin
  select * into c from chamados.chamados where id = e.chamado_id;
  if chamados.gam_inelegivel(c.id) is not null or c.assumido_em is null then return; end if;
  if c.assumido_em - c.criado_em <= (c.prazo_assumir_em - c.criado_em) * f then
    if chamados.gam_aplicar_regra('resposta_rapida', c.responsavel_id, c.id, e.id, 'pendente') is not null then
      perform chamados.gam_atualizar_perfil(c.responsavel_id);
    end if;
  end if;
end $fn$;

create function chamados.gam_ao_resolver(e chamados.gam_eventos)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  c chamados.chamados; r uuid; v_status chamados.gam_xp_status_t; v_fator numeric; v_teto integer; v_total integer := 0; v integer;
  d jsonb := chamados.gam_cfg('retorno_decrescente'); n integer; v_pts text[];
begin
  select * into c from chamados.chamados where id = e.chamado_id;
  if c.status <> 'resolvido' or chamados.gam_inelegivel(c.id) is not null then return; end if;
  r := c.responsavel_id;
  v_status := case when chamados.gam_checar_resolucao(c) then 'retido' else 'pendente' end;

  -- Complexidade (urgência) com teto, e retorno decrescente para muitos chamados simples no mesmo dia.
  select least(m.fator, (chamados.gam_cfg('multiplicador_max'))::text::numeric) into v_fator
    from chamados.gam_multiplicadores m where m.urgencia = c.urgencia;
  v_fator := coalesce(v_fator, 1);
  if c.urgencia <= (d->>'urgencia_max')::int then
    select count(*) into n from chamados.gam_xp x join chamados.chamados y on y.id = x.chamado_id
     where x.pessoa_id = r and x.regra_codigo = 'resolvido' and x.status <> 'estornado'
       and y.urgencia <= (d->>'urgencia_max')::int and chamados.gam_dia(x.criado_em) = chamados.gam_dia(now());
    if n >= (d->>'a_partir')::int then v_fator := v_fator * (d->>'fator')::numeric; end if;
  end if;

  -- Teto diário do XP de resolução.
  select (chamados.gam_cfg('teto_diario_resolucao'))::text::int - coalesce(sum(valor), 0) into v_teto
    from chamados.gam_xp
   where pessoa_id = r and regra_codigo in ('resolvido', 'resolvido_sla', 'prioridade_alta', 'critico')
     and status <> 'estornado' and chamados.gam_dia(criado_em) = chamados.gam_dia(now());

  v_pts := array['resolvido'];
  if c.resolvido_em <= c.prazo_em then v_pts := array_append(v_pts, 'resolvido_sla'); end if;
  if c.urgencia = 2 then v_pts := array_append(v_pts, 'prioridade_alta'); end if;
  if c.urgencia = 3 then v_pts := array_append(v_pts, 'critico'); end if;
  for i in 1 .. cardinality(v_pts) loop
    exit when v_teto <= 0;
    v := chamados.gam_aplicar_regra(v_pts[i], r, c.id, e.id, v_status, null, v_fator, v_teto);
    if v is not null then v_total := v_total + v; v_teto := v_teto - v; end if;
  end loop;

  if v_total > 0 then
    perform chamados.gam_notificar(r, 'xp', '+' || v_total || ' XP em validação', 'Chamado ' || c.protocolo || ' resolvido' ||
      case when v_status = 'retido' then ' · em revisão pelo gestor' else '' end, v_total,
      jsonb_build_object('protocolo', c.protocolo, 'status', v_status));
  end if;
  perform chamados.gam_atualizar_perfil(r);
end $fn$;

create function chamados.gam_ao_reabrir(e chamados.gam_eventos)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  c chamados.chamados; r uuid; v_resolvido timestamptz; v integer; v_total integer := 0; n integer; v_estornado integer;
  s jsonb := chamados.gam_cfg('suspeita');
begin
  select * into c from chamados.chamados where id = e.chamado_id;
  if chamados.gam_inelegivel(c.id) is not null then return; end if;
  r := c.responsavel_id;
  select max(criado_em) into v_resolvido from chamados.eventos
   where chamado_id = c.id and acao = 'resolvido' and criado_em <= e.criado_em;

  -- XP ainda em validação deste chamado é estornado.
  with x as (
    update chamados.gam_xp set status = 'estornado', atualizado_em = now()
     where chamado_id = c.id and status in ('pendente', 'retido')
       and regra_codigo in ('resolvido', 'resolvido_sla', 'prioridade_alta', 'critico')
    returning valor
  ) select coalesce(sum(valor), 0) into v_estornado from x;

  if v_resolvido is not null and e.criado_em - v_resolvido <= make_interval(days => (chamados.gam_cfg('janela_reabertura_dias'))::text::int) then
    v := chamados.gam_aplicar_regra('reaberto', r, c.id, e.id, 'confirmado', e.id::text);
    v_total := v_total + coalesce(v, 0);
    if e.dados #>> '{detalhe,motivo}' = 'incompleto' then
      v := chamados.gam_aplicar_regra('encerrado_incorreto', r, c.id, e.id, 'confirmado');
      v_total := v_total + coalesce(v, 0);
    end if;
  end if;
  perform chamados.gam_sequencia(r, 'sem_reabertura', false);

  -- Reaberturas repetidas e reaberturas de chamados alheios viram revisão.
  select count(*) into n from chamados.eventos where chamado_id = c.id and acao = 'reaberto';
  if n >= (s->>'reaberturas')::int then
    perform chamados.gam_suspeitar(r, c.id, 'reabre_fecha', 'Chamado reaberto ' || n || ' vezes.', jsonb_build_object('reaberturas', n));
  end if;
  if e.pessoa_id is distinct from r then
    select count(*) into n from chamados.eventos ev join chamados.chamados y on y.id = ev.chamado_id
     where ev.acao = 'reaberto' and ev.autor_id = e.pessoa_id and y.responsavel_id <> e.pessoa_id
       and ev.criado_em > now() - interval '7 days';
    if n >= (s->>'reaberturas_alheias_7d')::int then
      perform chamados.gam_suspeitar(e.pessoa_id, null, 'reaberturas_alheias',
        n || ' reaberturas de chamados de colegas em 7 dias.', jsonb_build_object('reaberturas', n));
    end if;
  end if;

  if v_total <> 0 or v_estornado <> 0 then
    perform chamados.gam_notificar(r, 'xp', case when v_total < 0 then v_total || ' XP' else 'XP em validação estornado' end,
      'Chamado ' || c.protocolo || ' reaberto' || case when v_estornado > 0 then ' · ' || v_estornado || ' XP em validação estornados' else '' end,
      nullif(v_total, 0), jsonb_build_object('protocolo', c.protocolo));
  end if;
  perform chamados.gam_atualizar_perfil(r);
end $fn$;

create function chamados.gam_ao_avaliar(e chamados.gam_eventos)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  a chamados.avaliacoes; c chamados.chamados; r uuid; v_status chamados.gam_xp_status_t; v integer; v_total integer := 0; n integer;
  s jsonb := chamados.gam_cfg('suspeita');
begin
  select * into a from chamados.avaliacoes where id = (e.dados->>'avaliacao_id')::bigint;
  select * into c from chamados.chamados where id = a.chamado_id;
  if a.id is null or chamados.gam_inelegivel(c.id) is not null then return; end if;
  r := c.responsavel_id;
  -- Muitas notas 5 do mesmo nome para o mesmo técnico em 7 dias → revisão.
  if a.nota = 5 and c.solicitante_nome is not null then
    select count(*) into n from chamados.avaliacoes av join chamados.chamados y on y.id = av.chamado_id
     where av.nota = 5 and y.responsavel_id = r and av.criada_em > now() - interval '7 days'
       and chamados._chave_nome(y.solicitante_nome) = chamados._chave_nome(c.solicitante_nome);
    if n >= (s->>'avaliacoes_mesmo_nome_7d')::int then
      perform chamados.gam_suspeitar(r, c.id, 'avaliacoes_concentradas',
        n || ' avaliações 5 estrelas do mesmo nome em 7 dias.', jsonb_build_object('quantidade', n, 'nome', c.solicitante_nome));
    end if;
  end if;
  v_status := case when chamados.gam_tem_suspeita(r, c.id) then 'retido' else 'confirmado' end;
  if a.nota = 5 then v := chamados.gam_aplicar_regra('avaliacao_5', r, c.id, e.id, v_status); v_total := v_total + coalesce(v, 0); end if;
  if a.nota = 4 then v := chamados.gam_aplicar_regra('avaliacao_4', r, c.id, e.id, v_status); v_total := v_total + coalesce(v, 0); end if;
  if a.elogio then v := chamados.gam_aplicar_regra('elogio', r, c.id, e.id, v_status); v_total := v_total + coalesce(v, 0); end if;
  perform chamados.gam_sequencia(r, 'cinco_estrelas', a.nota = 5);
  if v_total > 0 then
    perform chamados.gam_notificar(r, 'xp', '+' || v_total || ' XP', 'Avaliação ' || a.nota || ' estrela' || case when a.nota > 1 then 's' else '' end
      || case when a.elogio then ' com elogio' else '' end || ' · ' || c.protocolo, v_total, jsonb_build_object('protocolo', c.protocolo, 'nota', a.nota));
  end if;
  perform chamados.gam_avaliar_conquistas(r);
  perform chamados.gam_atualizar_perfil(r);
end $fn$;

-- Evento interno: o XP de resolução passou pela validação sem reabertura.
create function chamados.gam_ao_confirmar(e chamados.gam_eventos)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  c chamados.chamados; r uuid; v integer; v_total integer := 0; co record; n_ab integer; n_ba integer; n_a integer;
  s jsonb := chamados.gam_cfg('suspeita'); v_status chamados.gam_xp_status_t;
begin
  select * into c from chamados.chamados where id = e.chamado_id;
  if c.status <> 'resolvido' or chamados.gam_inelegivel(c.id) is not null then return; end if;
  r := c.responsavel_id;
  if not exists (select 1 from chamados.eventos where chamado_id = c.id and acao = 'reaberto') then
    v := chamados.gam_aplicar_regra('sem_reabertura', r, c.id, e.id, 'confirmado'); v_total := v_total + coalesce(v, 0);
    perform chamados.gam_sequencia(r, 'sem_reabertura', true);
  end if;
  if c.resolvido_em > c.prazo_em and c.justificativa_atraso is null then
    v := chamados.gam_aplicar_regra('sla_sem_justificativa', r, c.id, e.id, 'confirmado'); v_total := v_total + coalesce(v, 0);
  end if;
  perform chamados.gam_sequencia(r, 'sla', c.resolvido_em <= c.prazo_em);

  -- Ajuda confirmada vale XP para o colega; reciprocidade excessiva vai para revisão.
  for co in select * from chamados.colaboracoes where chamado_id = c.id and status = 'confirmada' and ajudante_id <> r loop
    select count(*) filter (where responsavel_id = r and ajudante_id = co.ajudante_id),
           count(*) filter (where responsavel_id = co.ajudante_id and ajudante_id = r),
           count(*) filter (where ajudante_id = co.ajudante_id)
      into n_ab, n_ba, n_a
      from chamados.colaboracoes where status = 'confirmada' and criada_em > now() - interval '30 days';
    if n_a >= (s->>'reciprocidade_min')::int and n_ab > 0 and n_ba > 0
       and (n_ab + n_ba)::numeric / greatest(n_a, 1) > (s->>'reciprocidade')::numeric then
      perform chamados.gam_suspeitar(co.ajudante_id, c.id, 'colaboracao_reciproca',
        'Colaborações frequentes e recíprocas com o mesmo colega.', jsonb_build_object('ida', n_ab, 'volta', n_ba, 'total', n_a));
    end if;
    v_status := case when chamados.gam_tem_suspeita(co.ajudante_id, c.id) then 'retido' else 'confirmado' end;
    v := chamados.gam_aplicar_regra('ajuda', co.ajudante_id, c.id, e.id, v_status);
    if v is not null then
      perform chamados.gam_notificar(co.ajudante_id, 'xp', '+' || v || ' XP', 'Ajuda confirmada no ' || c.protocolo, v, jsonb_build_object('protocolo', c.protocolo));
      perform chamados.gam_avaliar_conquistas(co.ajudante_id);
      perform chamados.gam_atualizar_perfil(co.ajudante_id);
    end if;
  end loop;

  perform chamados.gam_notificar(r, 'xp', 'XP do ' || c.protocolo || ' confirmado',
    case when v_total > 0 then '+' || v_total || ' XP sem reabertura' when v_total < 0 then v_total || ' XP: SLA estourado sem justificativa' end,
    nullif(v_total, 0), jsonb_build_object('protocolo', c.protocolo));
  perform chamados.gam_avaliar_conquistas(r);
  perform chamados.gam_atualizar_perfil(r);
end $fn$;

-- ============ Fila ============
create function chamados.gam_processar(p_limite integer default 200)
returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare e chamados.gam_eventos; n integer := 0;
begin
  if not chamados.gam_ativo() then
    update chamados.gam_eventos set status = 'ignorado', processado_em = now() where status in ('pendente', 'erro');
    return 0;
  end if;
  for e in
    select * from chamados.gam_eventos where status = 'pendente' or (status = 'erro' and tentativas < 5)
     order by id limit p_limite for update skip locked
  loop
    begin
      if e.criado_em < coalesce((chamados.gam_cfg('ligada_em') #>> '{}')::timestamptz, 'infinity') then
        update chamados.gam_eventos set status = 'ignorado', processado_em = now() where id = e.id;
        continue;
      end if;
      case e.tipo
        when 'ticket.assigned' then perform chamados.gam_ao_assumir(e);
        when 'ticket.resolved' then perform chamados.gam_ao_resolver(e);
        when 'ticket.reopened' then perform chamados.gam_ao_reabrir(e);
        when 'ticket.confirmed' then perform chamados.gam_ao_confirmar(e);
        when 'rating.received' then perform chamados.gam_ao_avaliar(e);
        else null; -- ticket.created e collaboration.registered: só registro (contam nas estatísticas e na confirmação)
      end case;
      update chamados.gam_eventos set status = 'processado', processado_em = now(), erro = null where id = e.id;
      n := n + 1;
    exception when others then
      update chamados.gam_eventos set status = 'erro', tentativas = tentativas + 1, erro = left(sqlerrm, 500) where id = e.id;
    end;
  end loop;
  return n;
end $fn$;

-- Confirma XP pendente vencido e publica ticket.confirmed para cada chamado validado.
create function chamados.gam_confirmar_pendentes()
returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare n integer; p uuid;
begin
  if not chamados.gam_ativo() then return 0; end if;
  with conf as (
    update chamados.gam_xp x set status = 'confirmado', atualizado_em = now()
     where x.status = 'pendente' and x.confirmar_em <= now()
       and (x.chamado_id is null or x.regra_codigo not in ('resolvido', 'resolvido_sla', 'prioridade_alta', 'critico')
            or exists (select 1 from chamados.chamados c where c.id = x.chamado_id and c.status = 'resolvido'))
    returning x.pessoa_id, x.chamado_id, x.regra_codigo
  ), ev as (
    insert into chamados.gam_eventos (tipo, chave, chamado_id, pessoa_id)
    select 'ticket.confirmed', 'cf:' || chamado_id, chamado_id, pessoa_id from conf where regra_codigo = 'resolvido'
    on conflict (chave) do nothing
    returning 1
  )
  select count(*) into n from conf;
  for p in select distinct pessoa_id from chamados.gam_xp where status = 'confirmado' and atualizado_em > now() - interval '1 minute' loop
    perform chamados.gam_atualizar_perfil(p);
  end loop;
  return n;
end $fn$;

create function chamados.gam_ciclo()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare a integer; b integer; c integer;
begin
  a := chamados.gam_processar(500);
  b := chamados.gam_confirmar_pendentes();
  c := chamados.gam_processar(500);
  return jsonb_build_object('processados', a + c, 'confirmados', b);
end $fn$;

-- ============ Publicação de eventos (gatilhos: só enfileiram) ============
create function chamados.gam_publicar_evento()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  begin
    insert into chamados.gam_eventos (tipo, chave, chamado_id, pessoa_id, dados)
    values (case new.acao when 'aberto' then 'ticket.created' when 'assumido' then 'ticket.assigned'
                          when 'resolvido' then 'ticket.resolved' else 'ticket.reopened' end::chamados.gam_evento_t,
            'ev:' || new.id, new.chamado_id, new.autor_id, jsonb_strip_nulls(jsonb_build_object('detalhe', new.detalhe)))
    on conflict (chave) do nothing;
  exception when others then
    raise warning 'gamificação: evento % não enfileirado: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
create trigger gam_publicar after insert on chamados.eventos for each row execute function chamados.gam_publicar_evento();

create function chamados.gam_publicar_avaliacao()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  begin
    insert into chamados.gam_eventos (tipo, chave, chamado_id, dados)
    values ('rating.received', 'av:' || new.id, new.chamado_id, jsonb_build_object('avaliacao_id', new.id, 'nota', new.nota))
    on conflict (chave) do nothing;
  exception when others then
    raise warning 'gamificação: avaliação % não enfileirada: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
create trigger gam_publicar after insert on chamados.avaliacoes for each row execute function chamados.gam_publicar_avaliacao();

create function chamados.gam_publicar_colaboracao()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  begin
    if new.status = 'confirmada' and old.status is distinct from 'confirmada' then
      insert into chamados.gam_eventos (tipo, chave, chamado_id, pessoa_id, dados)
      values ('collaboration.registered', 'co:' || new.id, new.chamado_id, new.ajudante_id, jsonb_build_object('colaboracao_id', new.id))
      on conflict (chave) do nothing;
    end if;
  exception when others then
    raise warning 'gamificação: colaboração % não enfileirada: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
create trigger gam_publicar after update of status on chamados.colaboracoes for each row execute function chamados.gam_publicar_colaboracao();

-- ============ Estatísticas, score e fechamento de períodos ============
-- Números por técnico num intervalo (só chamados elegíveis, depois do lançamento).
create function chamados.gam_estatisticas(p_de timestamptz, p_ate timestamptz)
returns table (pessoa_id uuid, resolvidos integer, reabertos integer, no_prazo integer, assumidos integer, assumidos_prazo integer,
               avaliacoes integer, soma_sat numeric, soma_notas integer, pontos numeric, ajudas integer, xp integer, eficiencia numeric)
language sql stable security definer set search_path = '' as $fn$
  with lim as (
    select greatest(p_de, coalesce((chamados.gam_cfg('ligada_em') #>> '{}')::timestamptz, p_de)) de, p_ate ate
  ), devs as (
    select id from chamados.pessoas where papel = 'dev' and ativo and not gestor
  ), el as (
    select c.* from chamados.chamados c, lim
     where c.responsavel_id in (select id from devs) and chamados.gam_inelegivel(c.id) is null
       and not exists (select 1 from chamados.gam_suspeitas s where s.chamado_id = c.id and s.status = 'rejeitada')
  ), res as (
    select el.* from el, lim where el.status = 'resolvido' and el.resolvido_em >= lim.de and el.resolvido_em < lim.ate
  )
  select d.id,
    (select count(*) from res where res.responsavel_id = d.id)::int,
    (select count(*) from res where res.responsavel_id = d.id and exists (select 1 from chamados.eventos ev where ev.chamado_id = res.id and ev.acao = 'reaberto'))::int,
    (select count(*) from res where res.responsavel_id = d.id and res.resolvido_em <= res.prazo_em)::int,
    (select count(*) from el, lim where el.responsavel_id = d.id and el.assumido_em >= lim.de and el.assumido_em < lim.ate)::int,
    (select count(*) from el, lim where el.responsavel_id = d.id and el.assumido_em >= lim.de and el.assumido_em < lim.ate and el.assumido_em <= el.prazo_assumir_em)::int,
    (select count(*) from res join chamados.avaliacoes a on a.chamado_id = res.id where res.responsavel_id = d.id)::int,
    (select coalesce(sum((a.nota - 1) / 4.0), 0) from res join chamados.avaliacoes a on a.chamado_id = res.id where res.responsavel_id = d.id),
    (select coalesce(sum(a.nota), 0) from res join chamados.avaliacoes a on a.chamado_id = res.id where res.responsavel_id = d.id)::int,
    (select coalesce(sum(least(m.fator, (chamados.gam_cfg('multiplicador_max'))::text::numeric)), 0)
       from res join chamados.gam_multiplicadores m on m.urgencia = res.urgencia where res.responsavel_id = d.id),
    (select count(*) from chamados.colaboracoes co, lim where co.ajudante_id = d.id and co.status = 'confirmada'
        and co.respondida_em >= lim.de and co.respondida_em < lim.ate)::int,
    (select coalesce(sum(x.valor), 0) from chamados.gam_xp x, lim where x.pessoa_id = d.id and x.status in ('pendente', 'confirmado')
        and x.criado_em >= lim.de and x.criado_em < lim.ate)::int,
    (select avg(least(1, extract(epoch from (res.resolvido_em - coalesce(res.assumido_em, res.criado_em)))
                       / greatest(extract(epoch from (res.prazo_em - res.criado_em)), 60)))
       from res where res.responsavel_id = d.id)
  from devs d
$fn$;

-- Performance Score (0–100) e componentes, com suavização bayesiana pela média do time.
--   Score = (wq·Qualidade + ws·SLA + wsat·Satisfação + wp·Produtividade + wc·Colaboração) / Σw × 100
--   Qualidade = 1 − reabertos/resolvidos · SLA = 0,4·assumidos no prazo + 0,6·resolvidos no prazo
--   Satisfação = (nota − 1)/4 · Produtividade = √(pontos de complexidade) / √(maior do time)
--   Colaboração = ajudas / maior do time. Taxas suavizadas: (acertos + k·média do time)/(n + k).
create function chamados.gam_scores(p_de timestamptz, p_ate timestamptz)
returns table (pessoa_id uuid, resolvidos integer, xp integer, score numeric, qualidade numeric, sla numeric, satisfacao numeric,
               produtividade numeric, colaboracao numeric, eficiencia numeric, elegivel boolean, satisfacao_media numeric,
               sla_real numeric, reabertura_real numeric, ajudas integer)
language sql stable security definer set search_path = '' as $fn$
  with e as (select * from chamados.gam_estatisticas(p_de, p_ate)),
  cfg as (select chamados.gam_cfg('score_pesos') w, (chamados.gam_cfg('score_k'))::text::numeric k,
                 (chamados.gam_cfg('ranking_minimo'))::text::int vmin),
  t as (select sum(resolvidos)::numeric res, sum(reabertos)::numeric reab, sum(no_prazo)::numeric np, sum(assumidos)::numeric a,
               sum(assumidos_prazo)::numeric ap, sum(avaliacoes)::numeric av, sum(soma_sat)::numeric sat,
               max(sqrt(pontos)) pts, max(ajudas)::numeric aj from e),
  b as (select case when coalesce(t.res, 0) > 0 then 1 - t.reab / t.res else 0.9 end q0,
               case when coalesce(t.res, 0) > 0 then t.np / t.res else 0.9 end r0,
               case when coalesce(t.a, 0) > 0 then t.ap / t.a else 0.9 end a0,
               case when coalesce(t.av, 0) > 0 then t.sat / t.av else 0.75 end s0, t.pts, t.aj from t),
  c as (
    select e.*, cfg.w, cfg.vmin,
      ((e.resolvidos - e.reabertos) + cfg.k * b.q0) / (e.resolvidos + cfg.k) q,
      0.4 * ((e.assumidos_prazo + cfg.k * b.a0) / (e.assumidos + cfg.k)) + 0.6 * ((e.no_prazo + cfg.k * b.r0) / (e.resolvidos + cfg.k)) s,
      (e.soma_sat + cfg.k * b.s0) / (e.avaliacoes + cfg.k) sat,
      case when coalesce(b.pts, 0) > 0 then sqrt(e.pontos) / b.pts else 0.5 end p,
      case when coalesce(b.aj, 0) > 0 then e.ajudas / b.aj else 0.5 end col
    from e, cfg, b
  )
  select c.pessoa_id, c.resolvidos, c.xp,
    round(100 * ((c.w->>'qualidade')::numeric * c.q + (c.w->>'sla')::numeric * c.s + (c.w->>'satisfacao')::numeric * c.sat
                 + (c.w->>'produtividade')::numeric * c.p + (c.w->>'colaboracao')::numeric * c.col)
          / ((c.w->>'qualidade')::numeric + (c.w->>'sla')::numeric + (c.w->>'satisfacao')::numeric
             + (c.w->>'produtividade')::numeric + (c.w->>'colaboracao')::numeric), 1),
    round(c.q, 4), round(c.s, 4), round(c.sat, 4), round(c.p, 4), round(c.col, 4),
    round(1 - coalesce(c.eficiencia, 1), 4), c.resolvidos >= c.vmin,
    case when c.avaliacoes > 0 then round(c.soma_notas::numeric / c.avaliacoes, 2) end,
    case when c.resolvidos > 0 then round(c.no_prazo::numeric / c.resolvidos, 4) end,
    case when c.resolvidos > 0 then round(c.reabertos::numeric / c.resolvidos, 4) end,
    c.ajudas
  from c
$fn$;

-- Valor de uma métrica de missão num período (confirmado; com p_ao_vivo também o que está em validação).
create function chamados.gam_metrica_missao(p_metrica text, p_pessoa uuid, p_de timestamptz, p_ate timestamptz, p_ao_vivo boolean default false)
returns numeric language sql stable security definer set search_path = '' as $fn$
  with st as (select case when p_ao_vivo then array['pendente', 'confirmado'] else array['confirmado'] end::chamados.gam_xp_status_t[] s),
  res as (
    select x.pessoa_id, x.chamado_id from chamados.gam_xp x, st
     where x.regra_codigo = 'resolvido' and x.status = any (st.s) and x.criado_em >= p_de and x.criado_em < p_ate
       and (p_pessoa is null or x.pessoa_id = p_pessoa)
  )
  select case p_metrica
    when 'resolvidos' then (select count(*) from res)::numeric
    when 'resolvidos_sla' then (select count(*) from chamados.gam_xp x, st where x.regra_codigo = 'resolvido_sla' and x.status = any (st.s)
                                 and x.criado_em >= p_de and x.criado_em < p_ate and (p_pessoa is null or x.pessoa_id = p_pessoa))::numeric
    when 'resolvidos_sem_reabertura' then (select count(*) from res where not exists
                                 (select 1 from chamados.eventos ev where ev.chamado_id = res.chamado_id and ev.acao = 'reaberto'))::numeric
    when 'avaliados_ge4' then (select count(*) from res join chamados.avaliacoes a on a.chamado_id = res.chamado_id where a.nota >= 4)::numeric
    when 'ajudas' then (select count(*) from chamados.gam_xp x, st where x.regra_codigo = 'ajuda' and x.status = any (st.s)
                                 and x.criado_em >= p_de and x.criado_em < p_ate and (p_pessoa is null or x.pessoa_id = p_pessoa))::numeric
    when 'sla_equipe_pct' then (select case when count(*) = 0 then 0 else round(100.0 * count(*) filter (where c.resolvido_em <= c.prazo_em) / count(*), 1) end
                                 from res join chamados.chamados c on c.id = res.chamado_id)
    when 'satisfacao_equipe_pct' then (select coalesce(round(avg(a.nota) * 20, 1), 0) from res join chamados.avaliacoes a on a.chamado_id = res.chamado_id)
  end
$fn$;

-- Fecha missões (períodos terminados há mais que horas_pendente), sequência semanal de SLA e temporadas.
create function chamados.gam_fechar_periodos()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_horas interval := make_interval(hours => (chamados.gam_cfg('horas_pendente'))::text::int);
  v_lig timestamptz := (chamados.gam_cfg('ligada_em') #>> '{}')::timestamptz;
  v_hoje date := chamados.gam_dia(now());
  m chamados.gam_missoes; v_ini date; v_fim date; d record; v numeric; v_res bigint; n_m integer := 0; n_t integer := 0;
  v_min_eq integer := (chamados.gam_cfg('equipe_minimo'))::text::int;
  v_min_sem integer := (chamados.gam_cfg('sequencia_semana_minimo'))::text::int;
  t chamados.gam_temporadas; rk record; v_xp jsonb := chamados.gam_cfg('temporada_xp'); v_prox date;
begin
  if not chamados.gam_ativo() or v_lig is null then return jsonb_build_object('ativo', false); end if;

  -- Missões
  for m in select * from chamados.gam_missoes where ativo loop
    v_ini := chamados.gam_inicio_periodo(m.periodo, greatest(m.inicio, chamados.gam_dia(v_lig), v_hoje - 35));
    loop
      v_fim := chamados.gam_fim_periodo(m.periodo, v_ini);
      exit when chamados.gam_instante(v_fim) + v_horas > now() or (m.fim is not null and v_ini > m.fim);
      if v_fim > chamados.gam_dia(v_lig) and not exists (select 1 from chamados.gam_missoes_resultado where missao_id = m.id and periodo_inicio = v_ini) then
        if m.alvo = 'equipe' then
          v := chamados.gam_metrica_missao(m.metrica, null, chamados.gam_instante(v_ini), chamados.gam_instante(v_fim));
          insert into chamados.gam_missoes_resultado (missao_id, periodo_inicio, pessoa_id, valor, meta, concluida)
          values (m.id, v_ini, null, v, m.meta, v >= m.meta) returning id into v_res;
          if v >= m.meta then
            for d in select p.id from chamados.pessoas p where p.papel = 'dev' and p.ativo and not p.gestor
                       and chamados.gam_metrica_missao('resolvidos', p.id, chamados.gam_instante(v_ini), chamados.gam_instante(v_fim)) >= v_min_eq loop
              if chamados.gam_lancar(d.id, 'missao:' || v_res, m.xp, 'Missão da equipe: ' || m.nome, 'confirmado', null, null, null, null, v_res) is not null then
                perform chamados.gam_notificar(d.id, 'missao', 'Missão da equipe concluída: ' || m.nome, m.descricao, m.xp, jsonb_build_object('missao', m.codigo, 'equipe', true));
                perform chamados.gam_atualizar_perfil(d.id);
              end if;
            end loop;
          end if;
        else
          for d in select p.id from chamados.pessoas p where p.papel = 'dev' and p.ativo and not p.gestor loop
            v := chamados.gam_metrica_missao(m.metrica, d.id, chamados.gam_instante(v_ini), chamados.gam_instante(v_fim));
            insert into chamados.gam_missoes_resultado (missao_id, periodo_inicio, pessoa_id, valor, meta, concluida)
            values (m.id, v_ini, d.id, v, m.meta, v >= m.meta) returning id into v_res;
            if v >= m.meta then
              if m.xp > 0 then perform chamados.gam_lancar(d.id, 'missao:' || v_res, m.xp, 'Missão: ' || m.nome, 'confirmado', null, null, null, null, v_res); end if;
              perform chamados.gam_notificar(d.id, 'missao', 'Missão concluída: ' || m.nome, m.descricao, nullif(m.xp, 0), jsonb_build_object('missao', m.codigo, 'especial', m.especial));
              if m.conquista_tier_id is not null then perform chamados.gam_desbloquear(d.id, m.conquista_tier_id, 'missao:' || m.codigo); end if;
              perform chamados.gam_dar_recompensa(d.id, m.recompensa_id, 'missao:' || m.codigo);
              perform chamados.gam_atualizar_perfil(d.id);
            end if;
          end loop;
        end if;
        n_m := n_m + 1;
      end if;
      v_ini := v_fim;
    end loop;
  end loop;

  -- Sequência semanal de SLA (semana sem o mínimo de chamados não conta nem quebra).
  v_ini := chamados.gam_inicio_periodo('semana', greatest(chamados.gam_dia(v_lig), coalesce((chamados.gam_cfg('semana_sla_proxima') #>> '{}')::date, chamados.gam_dia(v_lig))));
  loop
    v_fim := v_ini + 7;
    exit when chamados.gam_instante(v_fim) + v_horas > now();
    for d in select p.id from chamados.pessoas p where p.papel = 'dev' and p.ativo and not p.gestor loop
      v := chamados.gam_metrica_missao('resolvidos', d.id, chamados.gam_instante(v_ini), chamados.gam_instante(v_fim));
      if v >= v_min_sem then
        perform chamados.gam_sequencia(d.id, 'semanas_sla',
          chamados.gam_metrica_missao('resolvidos_sla', d.id, chamados.gam_instante(v_ini), chamados.gam_instante(v_fim)) / v >= 0.95);
        perform chamados.gam_avaliar_conquistas(d.id);
      end if;
    end loop;
    v_ini := v_fim;
    insert into chamados.gam_config (chave, valor, descricao) values ('semana_sla_proxima', to_jsonb(v_ini), 'Controle interno: próxima semana a fechar na sequência de SLA.')
    on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
  end loop;

  -- Temporadas: encerra a ativa (depois da validação) e ativa a próxima.
  for t in select * from chamados.gam_temporadas where status = 'ativa' and chamados.gam_instante(fim + 1) + v_horas <= now() loop
    perform chamados.gam_encerrar_temporada(t.id);
    n_t := n_t + 1;
  end loop;
  update chamados.gam_temporadas set status = 'ativa'
   where id = (select id from chamados.gam_temporadas where status = 'futura' and inicio <= v_hoje order by inicio limit 1)
     and not exists (select 1 from chamados.gam_temporadas where status = 'ativa');
  return jsonb_build_object('missoes', n_m, 'temporadas', n_t);
end $fn$;

-- Congela o ranking da temporada, dá pódio (XP, títulos, molduras) e abre a próxima.
create function chamados.gam_encerrar_temporada(p_id smallint)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  t chamados.gam_temporadas; rk record; v_xp jsonb := chamados.gam_cfg('temporada_xp'); v_ini date; v_nome text;
begin
  select * into t from chamados.gam_temporadas where id = p_id and status = 'ativa' for update;
  if t.id is null then raise exception 'Temporada não está ativa.' using errcode = 'P0001'; end if;
  insert into chamados.gam_ranking_temporada (temporada_id, pessoa_id, posicao, score, xp, resolvidos, sla, satisfacao, qualidade, elegivel)
  select t.id, s.pessoa_id, row_number() over (order by s.elegivel desc, s.score desc, s.xp desc), s.score, s.xp, s.resolvidos,
         s.sla, s.satisfacao, s.qualidade, s.elegivel
    from chamados.gam_scores(chamados.gam_instante(t.inicio), chamados.gam_instante(least(t.fim + 1, chamados.gam_dia(now()) + 1))) s;
  for rk in select * from chamados.gam_ranking_temporada where temporada_id = t.id and elegivel and posicao <= 3 order by posicao loop
    perform chamados.gam_lancar(rk.pessoa_id, 'temporada:' || t.id, (v_xp->>(rk.posicao - 1))::int,
      t.nome || ': ' || rk.posicao || 'º lugar', 'confirmado');
    perform chamados.gam_notificar(rk.pessoa_id, 'temporada', rk.posicao || 'º lugar na ' || t.nome, 'Score ' || rk.score, (v_xp->>(rk.posicao - 1))::int,
      jsonb_build_object('temporada', t.nome, 'posicao', rk.posicao));
    perform chamados.gam_dar_recompensa(rk.pessoa_id,
      (select id from chamados.gam_recompensas where codigo = case rk.posicao when 1 then 'moldura_ouro' when 2 then 'moldura_prata' else 'moldura_bronze' end),
      'temporada:' || t.id);
    if rk.posicao = 1 then
      perform chamados.gam_dar_recompensa(rk.pessoa_id, (select id from chamados.gam_recompensas where codigo = 'titulo_campeao'), 'temporada:' || t.id);
    end if;
    perform chamados.gam_atualizar_perfil(rk.pessoa_id);
  end loop;
  update chamados.gam_temporadas set status = 'encerrada', encerrada_em = now() where id = t.id;
  -- Próxima temporada (trimestre seguinte), se ainda não existir.
  v_ini := t.fim + 1;
  if not exists (select 1 from chamados.gam_temporadas where status = 'futura' or (status = 'ativa')) then
    v_nome := 'Temporada ' || ((select count(*) from chamados.gam_temporadas) + 1) || ' · T' || extract(quarter from v_ini) || ' ' || extract(year from v_ini);
    insert into chamados.gam_temporadas (nome, inicio, fim, status)
    values (v_nome, v_ini, (date_trunc('quarter', v_ini) + interval '3 months')::date - 1,
            case when v_ini <= chamados.gam_dia(now()) then 'ativa' else 'futura' end);
  end if;
end $fn$;

-- ============ Permissões ============
revoke execute on all functions in schema chamados from public, anon;
-- As funções do motor são internas: nenhuma fica exposta para o front (exceto pelas RPCs da parte 4).
grant execute on function chamados.eu_pessoa_id(), chamados.eh_dev(), chamados.eh_gestor(), chamados.vincular_minha_conta(),
  chamados.abrir_chamado(integer, text, integer, text[]), chamados.assumir_chamado(uuid), chamados.resolver_chamado(uuid),
  chamados.reabrir_chamado(uuid, text, text), chamados.pedir_ajuda(uuid, uuid), chamados.responder_ajuda(bigint, boolean),
  chamados.justificar_atraso(uuid, text), chamados.gerar_link_chamado(text, text, jsonb), chamados.gam_nivel(integer) to authenticated;
grant execute on function chamados.catalogo_publico(), chamados.consultar_chamado(text), chamados.ler_convite(text),
  chamados.abrir_chamado_publico(integer, text, text, text, integer, text, integer, text[]),
  chamados.abrir_chamado_por_convite(text, integer, text, integer, text, integer, text[]),
  chamados.avaliar_chamado(text, text, integer, boolean, text) to anon, authenticated;

-- ============ Agendamentos (pg_cron, quando disponível) ============
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('chamados-gam-ciclo', '* * * * *', 'select chamados.gam_ciclo()');
    perform cron.schedule('chamados-gam-periodos', '*/15 * * * *', 'select chamados.gam_fechar_periodos()');
  end if;
end $$;

notify pgrst, 'reload schema';

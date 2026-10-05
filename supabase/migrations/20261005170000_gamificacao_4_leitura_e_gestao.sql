-- ============================================================================
-- Gamificação · parte 4: RPCs do time (jornada, perfil, ranking) e do gestor
-- (Central de Gamificação). Todas security definer, search_path = '', jsonb.
-- O time só lê; o gestor configura. Toda alteração de configuração é auditada.
-- ============================================================================

create function chamados.gam_exigir_gestor()
returns uuid language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not chamados.eh_gestor() then raise exception 'Só o gestor acessa a Central de Gamificação.' using errcode = '42501'; end if;
  return chamados.eu_pessoa_id();
end $fn$;

create function chamados.gam_auditar(p_acao text, p_alvo text, p_antes jsonb, p_depois jsonb)
returns void language sql volatile security definer set search_path = '' as $fn$
  insert into chamados.gam_auditoria (autor_id, acao, alvo, antes, depois) values (chamados.eu_pessoa_id(), p_acao, p_alvo, p_antes, p_depois)
$fn$;

-- Intervalo de um período (fuso de Brasília). 'geral' começa no lançamento (gam_estatisticas corta em ligada_em).
create function chamados.gam_intervalo(p_periodo text)
returns table (de timestamptz, ate timestamptz)
language sql stable security definer set search_path = '' as $fn$
  select case
           when p_periodo in ('dia', 'semana', 'mes', 'trimestre', 'ano')
             then chamados.gam_instante(chamados.gam_inicio_periodo(p_periodo, chamados.gam_dia(now())))
           when p_periodo = 'temporada'
             then coalesce((select chamados.gam_instante(inicio) from chamados.gam_temporadas where status = 'ativa'), '-infinity')
           else '-infinity'::timestamptz end,
         now() + interval '1 second'
$fn$;

-- ============ Ranking ============
-- Critérios: score (padrão; só quem tem o mínimo de resolvidos é classificado), xp, resolvidos,
-- satisfacao, sla, qualidade, eficiencia (os quatro últimos já suavizados pela média do time).
create function chamados.gam_ranking(p_periodo text default 'temporada', p_criterio text default 'score', p_temporada smallint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); v_de timestamptz; v_ate timestamptz; v jsonb; t chamados.gam_temporadas;
begin
  if not (chamados.eh_dev() or chamados.eh_gestor()) then raise exception 'Só o time vê o ranking.' using errcode = '42501'; end if;
  if p_criterio not in ('score', 'xp', 'resolvidos', 'satisfacao', 'sla', 'qualidade', 'eficiencia') then
    raise exception 'Critério inválido.' using errcode = '22023';
  end if;
  if p_temporada is not null then
    select * into t from chamados.gam_temporadas where id = p_temporada;
    if t.status = 'encerrada' then
      select coalesce(jsonb_agg(jsonb_build_object('posicao', r.posicao, 'pessoa_id', r.pessoa_id, 'nome', p.nome, 'eu', r.pessoa_id = eu,
               'score', r.score, 'xp', r.xp, 'resolvidos', r.resolvidos, 'sla', r.sla, 'satisfacao', r.satisfacao, 'qualidade', r.qualidade,
               'classificado', r.elegivel) order by r.posicao), '[]')
        into v from chamados.gam_ranking_temporada r join chamados.pessoas p on p.id = r.pessoa_id where r.temporada_id = t.id;
      return jsonb_build_object('congelado', true, 'temporada', t.nome, 'criterio', 'score', 'linhas', v);
    end if;
  end if;
  select i.de, i.ate into v_de, v_ate from chamados.gam_intervalo(coalesce(p_periodo, 'temporada')) i;
  with s as (
    select sc.*, p.nome, coalesce(pf.nivel, 1) nivel, ti.nome titulo, mo.codigo moldura,
      case p_criterio when 'score' then sc.score when 'xp' then sc.xp when 'resolvidos' then sc.resolvidos
                      when 'satisfacao' then sc.satisfacao when 'sla' then sc.sla when 'qualidade' then sc.qualidade
                      else sc.eficiencia end valor,
      case when p_criterio = 'score' then sc.elegivel when p_criterio in ('xp', 'resolvidos') then true else sc.resolvidos > 0 end classificado
      from chamados.gam_scores(v_de, v_ate) sc
      join chamados.pessoas p on p.id = sc.pessoa_id
      left join chamados.gam_perfis pf on pf.pessoa_id = sc.pessoa_id
      left join chamados.gam_recompensas ti on ti.id = pf.titulo_id
      left join chamados.gam_recompensas mo on mo.id = pf.moldura_id
  ), o as (
    select s.*, row_number() over (order by s.classificado desc, s.valor desc nulls last, s.xp desc, s.nome) pos from s
  )
  select coalesce(jsonb_agg(jsonb_build_object('posicao', o.pos, 'pessoa_id', o.pessoa_id, 'nome', o.nome, 'eu', o.pessoa_id = eu,
           'nivel', o.nivel, 'titulo', o.titulo, 'moldura', o.moldura, 'valor', o.valor, 'classificado', o.classificado,
           'score', o.score, 'xp', o.xp, 'resolvidos', o.resolvidos, 'sla', o.sla_real, 'satisfacao', o.satisfacao_media,
           'reabertura', o.reabertura_real, 'eficiencia', o.eficiencia, 'ajudas', o.ajudas) order by o.pos), '[]')
    into v from o;
  return jsonb_build_object('congelado', false, 'periodo', p_periodo, 'criterio', p_criterio,
    'minimo', (chamados.gam_cfg('ranking_minimo'))::text::int, 'linhas', v);
end $fn$;

-- ============ Jornada / perfil ============
-- p_pessoa nulo = eu. Partes privadas (feed, histórico de XP, notificações) só para a própria pessoa.
create function chamados.gam_jornada(p_pessoa uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  eu uuid := chamados.eu_pessoa_id(); v_alvo uuid := coalesce(p_pessoa, eu); pe chamados.pessoas; pf chamados.gam_perfis;
  t chamados.gam_temporadas; v_priv boolean; v_rank jsonb; v_pos jsonb; v_hoje date := chamados.gam_dia(now());
  v_de timestamptz; m jsonb;
begin
  if not (chamados.eh_dev() or chamados.eh_gestor()) then raise exception 'Só o time vê a gamificação.' using errcode = '42501'; end if;
  if not chamados.gam_ativo() and not chamados.eh_gestor() then return jsonb_build_object('ativo', false); end if;
  select * into pe from chamados.pessoas where id = v_alvo;
  if pe.id is null or pe.papel <> 'dev' or pe.gestor then
    return jsonb_build_object('ativo', chamados.gam_ativo(), 'gestor', chamados.eh_gestor(), 'participa', false);
  end if;
  v_priv := v_alvo = eu;
  select * into pf from chamados.gam_perfis where pessoa_id = v_alvo;
  select * into t from chamados.gam_temporadas where status = 'ativa';
  v_de := coalesce(chamados.gam_instante(t.inicio), '-infinity');
  v_rank := chamados.gam_ranking('temporada', 'score');
  select r into v_pos from jsonb_array_elements(v_rank->'linhas') r where (r->>'pessoa_id')::uuid = v_alvo;
  m := chamados.gam_metricas(v_alvo);

  return jsonb_build_object(
    'ativo', chamados.gam_ativo(), 'participa', true, 'privado', v_priv,
    'pessoa', jsonb_build_object('id', pe.id, 'nome', pe.nome, 'cargo', 'Desenvolvimento e suporte'),
    'perfil', jsonb_build_object(
      'xp', coalesce(pf.xp_confirmado, 0), 'xp_pendente', coalesce(pf.xp_pendente, 0),
      'nivel', chamados.gam_nivel(coalesce(pf.xp_confirmado, 0)),
      'titulo', (select jsonb_build_object('id', r.id, 'nome', r.nome, 'raridade', r.raridade) from chamados.gam_recompensas r where r.id = pf.titulo_id),
      'moldura', (select jsonb_build_object('id', r.id, 'codigo', r.codigo, 'nome', r.nome, 'raridade', r.raridade) from chamados.gam_recompensas r where r.id = pf.moldura_id)),
    'temporada', case when t.id is not null then jsonb_build_object('id', t.id, 'nome', t.nome, 'inicio', t.inicio, 'fim', t.fim) end,
    'ranking', jsonb_build_object('posicao', (v_pos->>'posicao')::int, 'classificado', (v_pos->>'classificado')::boolean,
      'total', jsonb_array_length(v_rank->'linhas'), 'score', (v_pos->>'score')::numeric, 'minimo', (v_rank->>'minimo')::int),
    'estatisticas', (select jsonb_build_object('resolvidos', s.resolvidos, 'sla', s.sla_real, 'satisfacao', s.satisfacao_media,
        'reabertura', s.reabertura_real, 'ajudas', s.ajudas, 'xp', s.xp, 'score', s.score,
        'componentes', jsonb_build_object('qualidade', s.qualidade, 'sla', s.sla, 'satisfacao', s.satisfacao,
                                          'produtividade', s.produtividade, 'colaboracao', s.colaboracao),
        'tempo_medio_h', (select round(avg(extract(epoch from (c.resolvido_em - coalesce(c.assumido_em, c.criado_em))) / 3600)::numeric, 1)
                            from chamados.chamados c where c.responsavel_id = v_alvo and c.status = 'resolvido' and c.resolvido_em >= v_de
                              and chamados.gam_inelegivel(c.id) is null))
      from chamados.gam_scores(v_de, now() + interval '1 second') s where s.pessoa_id = v_alvo),
    'sequencias', coalesce((select jsonb_agg(jsonb_build_object('tipo', q.tipo, 'atual', q.atual, 'recorde', q.recorde) order by q.tipo)
                              from chamados.gam_sequencias q where q.pessoa_id = v_alvo), '[]'),
    'conquistas', coalesce((select jsonb_agg(jsonb_build_object(
        'codigo', c.codigo, 'nome', c.nome, 'descricao', c.descricao, 'icone', c.icone, 'raridade', c.raridade, 'metrica', c.metrica,
        'valor', coalesce((m->>c.metrica)::int, 0),
        'tiers', (select jsonb_agg(jsonb_build_object('tier', tr.tier, 'nome', tr.nome, 'limite', tr.limite, 'xp', tr.xp,
                    'raridade', coalesce(tr.raridade, c.raridade),
                    'desbloqueada_em', (select cp.desbloqueada_em from chamados.gam_conquistas_pessoa cp where cp.pessoa_id = v_alvo and cp.tier_id = tr.id))
                    order by tr.tier) from chamados.gam_conquista_tiers tr where tr.conquista_id = c.id)) order by c.ordem)
      from chamados.gam_conquistas c where c.ativo), '[]'),
    'missoes', coalesce((select jsonb_agg(x order by x->>'alvo' desc, (x->>'especial')::boolean, x->>'periodo') from (
        select jsonb_build_object('codigo', mi.codigo, 'nome', mi.nome, 'descricao', mi.descricao, 'periodo', mi.periodo, 'alvo', mi.alvo,
          'especial', mi.especial, 'meta', mi.meta, 'xp', mi.xp, 'metrica', mi.metrica,
          'termina_em', chamados.gam_instante(chamados.gam_fim_periodo(mi.periodo, chamados.gam_inicio_periodo(mi.periodo, v_hoje))),
          'valor', chamados.gam_metrica_missao(mi.metrica, case when mi.alvo = 'equipe' then null else v_alvo end,
                     greatest(chamados.gam_instante(chamados.gam_inicio_periodo(mi.periodo, v_hoje)),
                              coalesce((chamados.gam_cfg('ligada_em') #>> '{}')::timestamptz, '-infinity')),
                     now() + interval '1 second', true),
          'concluidas', (select count(*) from chamados.gam_missoes_resultado mr where mr.missao_id = mi.id and mr.concluida
                           and (mr.pessoa_id = v_alvo or (mi.alvo = 'equipe' and mr.pessoa_id is null))),
          'ultima', (select jsonb_build_object('periodo', mr.periodo_inicio, 'valor', mr.valor, 'concluida', mr.concluida)
                       from chamados.gam_missoes_resultado mr where mr.missao_id = mi.id
                        and (mr.pessoa_id = v_alvo or (mi.alvo = 'equipe' and mr.pessoa_id is null))
                       order by mr.periodo_inicio desc limit 1)) x
        from chamados.gam_missoes mi where mi.ativo and mi.inicio <= v_hoje and (mi.fim is null or mi.fim >= v_hoje)) q), '[]'),
    'recompensas', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'codigo', r.codigo, 'tipo', r.tipo, 'nome', r.nome,
        'descricao', r.descricao, 'raridade', r.raridade, 'obtida_em', rp.obtida_em) order by rp.obtida_em desc)
      from chamados.gam_recompensas_pessoa rp join chamados.gam_recompensas r on r.id = rp.recompensa_id where rp.pessoa_id = v_alvo), '[]'),
    'temporadas', coalesce((select jsonb_agg(jsonb_build_object('nome', tt.nome, 'posicao', rt.posicao, 'score', rt.score) order by tt.inicio desc)
      from chamados.gam_ranking_temporada rt join chamados.gam_temporadas tt on tt.id = rt.temporada_id where rt.pessoa_id = v_alvo), '[]'),
    'feed', case when v_priv then coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'tipo', n.tipo, 'titulo', n.titulo, 'detalhe', n.detalhe,
        'xp', n.xp, 'dados', n.dados, 'criada_em', n.criada_em, 'lida', n.lida_em is not null) order by n.id desc)
      from (select * from chamados.gam_notificacoes where pessoa_id = v_alvo order by id desc limit 30) n), '[]') end,
    'historico', case when v_priv or chamados.eh_gestor() then coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'valor', x.valor,
        'motivo', x.motivo, 'status', x.status, 'protocolo', c.protocolo, 'criado_em', x.criado_em) order by x.id desc)
      from (select * from chamados.gam_xp where pessoa_id = v_alvo order by id desc limit 50) x
      left join chamados.chamados c on c.id = x.chamado_id), '[]') end,
    'nao_lidas', case when v_priv then (select count(*) from chamados.gam_notificacoes where pessoa_id = v_alvo and lida_em is null) end);
end $fn$;

create function chamados.gam_marcar_lidas(p_ate bigint default null)
returns jsonb language sql volatile security definer set search_path = '' as $fn$
  with u as (
    update chamados.gam_notificacoes set lida_em = now()
     where pessoa_id = chamados.eu_pessoa_id() and lida_em is null and (p_ate is null or id <= p_ate)
    returning 1)
  select jsonb_build_object('lidas', count(*)) from u
$fn$;

-- Escolhe título e moldura entre as recompensas obtidas (nulo = nenhum).
create function chamados.gam_escolher_visual(p_titulo smallint, p_moldura smallint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id();
begin
  if not chamados.eh_dev() then raise exception 'Só o time.' using errcode = '42501'; end if;
  if p_titulo is not null and not exists (select 1 from chamados.gam_recompensas_pessoa rp join chamados.gam_recompensas r on r.id = rp.recompensa_id
                                           where rp.pessoa_id = eu and r.id = p_titulo and r.tipo = 'titulo') then
    raise exception 'Título não obtido.' using errcode = '22023';
  end if;
  if p_moldura is not null and not exists (select 1 from chamados.gam_recompensas_pessoa rp join chamados.gam_recompensas r on r.id = rp.recompensa_id
                                            where rp.pessoa_id = eu and r.id = p_moldura and r.tipo = 'moldura') then
    raise exception 'Moldura não obtida.' using errcode = '22023';
  end if;
  perform chamados.gam_atualizar_perfil(eu);
  update chamados.gam_perfis set titulo_id = p_titulo, moldura_id = p_moldura where pessoa_id = eu;
  return jsonb_build_object('ok', true);
end $fn$;

-- O front chama depois de uma ação para o feedback não esperar o agendador (idempotente).
create function chamados.gam_processar_agora()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not (chamados.eh_dev() or chamados.eh_gestor()) then raise exception 'Só o time.' using errcode = '42501'; end if;
  return chamados.gam_ciclo();
end $fn$;

-- ============ Central de Gamificação (gestor) ============
create function chamados.gam_admin_painel()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  perform chamados.gam_exigir_gestor();
  return jsonb_build_object(
    'config', (select jsonb_object_agg(chave, jsonb_build_object('valor', valor, 'descricao', descricao, 'atualizado_em', atualizado_em))
                 from chamados.gam_config),
    'regras', (select jsonb_agg(to_jsonb(r) order by r.ordem) from chamados.gam_regras r),
    'multiplicadores', (select jsonb_agg(to_jsonb(m) order by m.urgencia) from chamados.gam_multiplicadores m),
    'niveis', (select jsonb_agg(to_jsonb(n) order by n.nivel) from chamados.gam_niveis n),
    'conquistas', (select jsonb_agg(to_jsonb(c) || jsonb_build_object(
                     'tiers', (select jsonb_agg(to_jsonb(t) || jsonb_build_object('recompensa', (select codigo from chamados.gam_recompensas where id = t.recompensa_id),
                                 'desbloqueios', (select count(*) from chamados.gam_conquistas_pessoa cp where cp.tier_id = t.id))
                               order by t.tier) from chamados.gam_conquista_tiers t where t.conquista_id = c.id)) order by c.ordem)
                   from chamados.gam_conquistas c),
    'missoes', (select jsonb_agg(to_jsonb(m) || jsonb_build_object('recompensa', (select codigo from chamados.gam_recompensas where id = m.recompensa_id),
                  'conquista', (select c.codigo from chamados.gam_conquista_tiers t join chamados.gam_conquistas c on c.id = t.conquista_id where t.id = m.conquista_tier_id))
                  order by m.id) from chamados.gam_missoes m),
    'recompensas', (select jsonb_agg(to_jsonb(r) order by r.tipo, r.id) from chamados.gam_recompensas r),
    'temporadas', (select jsonb_agg(to_jsonb(t) order by t.inicio desc) from chamados.gam_temporadas t),
    'suspeitas', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'pessoa', p.nome, 'protocolo', c.protocolo, 'regra', s.regra,
                    'descricao', s.descricao, 'evidencia', s.evidencia, 'status', s.status, 'criada_em', s.criada_em, 'nota', s.nota,
                    'xp_retido', (select coalesce(sum(valor), 0) from chamados.gam_xp x where x.pessoa_id = s.pessoa_id and x.chamado_id = s.chamado_id and x.status = 'retido'))
                    order by (s.status = 'aberta') desc, s.id desc)
                  from (select * from chamados.gam_suspeitas order by id desc limit 100) s
                  join chamados.pessoas p on p.id = s.pessoa_id left join chamados.chamados c on c.id = s.chamado_id), '[]'),
    'fila', (select jsonb_build_object('pendentes', count(*) filter (where status = 'pendente'), 'erros', count(*) filter (where status = 'erro'),
               'processados', count(*) filter (where status = 'processado'), 'ignorados', count(*) filter (where status = 'ignorado'),
               'ultimo', max(processado_em),
               'ultimos_erros', (select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'erro', erro)) from
                                  (select * from chamados.gam_eventos where status = 'erro' order by id desc limit 5) z))
             from chamados.gam_eventos),
    'xp_pendente', (select coalesce(sum(valor), 0) from chamados.gam_xp where status = 'pendente'),
    'auditoria', coalesce((select jsonb_agg(jsonb_build_object('acao', a.acao, 'alvo', a.alvo, 'autor', p.nome, 'antes', a.antes,
                   'depois', a.depois, 'criado_em', a.criado_em) order by a.id desc)
                 from (select * from chamados.gam_auditoria order by id desc limit 50) a left join chamados.pessoas p on p.id = a.autor_id), '[]'));
end $fn$;

create function chamados.gam_admin_config(p_chave text, p_valor jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.gam_exigir_gestor(); c chamados.gam_config; w jsonb;
begin
  select * into c from chamados.gam_config where chave = p_chave for update;
  if c.chave is null or p_chave in ('ligada_em', 'semana_sla_proxima') then raise exception 'Configuração desconhecida ou interna.' using errcode = '22023'; end if;
  if jsonb_typeof(c.valor) <> jsonb_typeof(p_valor) then raise exception 'Tipo de valor inválido para %.', p_chave using errcode = '22023'; end if;
  if p_chave = 'score_pesos' then
    if (select count(*) from jsonb_each(p_valor) where key in ('qualidade', 'sla', 'satisfacao', 'produtividade', 'colaboracao')
          and jsonb_typeof(value) = 'number' and value::text::numeric >= 0) <> 5
       or (select sum(value::text::numeric) from jsonb_each(p_valor)) <= 0 then
      raise exception 'Pesos: qualidade, sla, satisfacao, produtividade e colaboracao, números ≥ 0 e soma > 0.' using errcode = '22023';
    end if;
  end if;
  if jsonb_typeof(p_valor) = 'number' and p_valor::text::numeric < 0 then raise exception 'Valor não pode ser negativo.' using errcode = '22023'; end if;
  update chamados.gam_config set valor = p_valor, atualizado_em = now(), atualizado_por = eu where chave = p_chave;
  if p_chave = 'ativo' and p_valor = 'true'::jsonb and (chamados.gam_cfg('ligada_em') = 'null'::jsonb) then
    update chamados.gam_config set valor = to_jsonb(now()), atualizado_em = now(), atualizado_por = eu where chave = 'ligada_em';
    -- Começa do zero: o que aconteceu antes de ligar não conta.
    update chamados.gam_eventos set status = 'ignorado', processado_em = now() where status in ('pendente', 'erro');
  end if;
  perform chamados.gam_auditar('config', p_chave, c.valor, p_valor);
  return jsonb_build_object('ok', true);
end $fn$;

create function chamados.gam_admin_regra(p_codigo text, p_xp integer, p_ativo boolean, p_limite_chamado smallint, p_limite_diario smallint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare r chamados.gam_regras; n chamados.gam_regras;
begin
  perform chamados.gam_exigir_gestor();
  select * into r from chamados.gam_regras where codigo = p_codigo for update;
  if r.codigo is null then raise exception 'Regra desconhecida.' using errcode = '22023'; end if;
  if (r.xp < 0) <> (p_xp < 0) or p_xp = 0 then raise exception 'Bônus continua positivo e penalidade negativa (diferente de zero).' using errcode = '22023'; end if;
  update chamados.gam_regras set xp = p_xp, ativo = coalesce(p_ativo, ativo), limite_por_chamado = coalesce(p_limite_chamado, limite_por_chamado),
         limite_diario = p_limite_diario where codigo = p_codigo returning * into n;
  perform chamados.gam_auditar('regra', p_codigo, to_jsonb(r), to_jsonb(n));
  return to_jsonb(n);
end $fn$;

create function chamados.gam_admin_multiplicador(p_urgencia smallint, p_fator numeric)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare r chamados.gam_multiplicadores;
begin
  perform chamados.gam_exigir_gestor();
  select * into r from chamados.gam_multiplicadores where urgencia = p_urgencia;
  update chamados.gam_multiplicadores set fator = p_fator where urgencia = p_urgencia;
  if not found then raise exception 'Urgência inválida.' using errcode = '22023'; end if;
  perform chamados.gam_auditar('multiplicador', p_urgencia::text, to_jsonb(r), jsonb_build_object('fator', p_fator));
  return jsonb_build_object('ok', true);
end $fn$;

-- Níveis: lista completa (nivel, nome, xp_minimo). XP mínimo cresce com o nível; níveis não são removidos
-- (só renomeados, ajustados ou acrescentados), para nenhum perfil apontar para um nível que deixou de existir.
create function chamados.gam_admin_niveis(p_niveis jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_antes jsonb := (select jsonb_agg(to_jsonb(n) order by n.nivel) from chamados.gam_niveis n); v_ok boolean; r record;
begin
  perform chamados.gam_exigir_gestor();
  with x as (select (e->>'nivel')::smallint nivel, btrim(e->>'nome') nome, (e->>'xp_minimo')::int xp from jsonb_array_elements(p_niveis) e)
  select count(*) >= 2 and count(*) = max(nivel) and count(distinct nivel) = count(*)
         and coalesce(bool_and(nome <> ''), false) and min(xp) filter (where nivel = 1) = 0
         and not exists (select 1 from x a join x b on a.nivel < b.nivel and a.xp >= b.xp)
    into v_ok from x;
  if not coalesce(v_ok, false) then
    raise exception 'Níveis 1..N sem lacunas, nível 1 com 0 XP, XP crescente e nomes preenchidos.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_niveis) < (select count(*) from chamados.gam_niveis) then
    raise exception 'Níveis não são removidos: renomeie ou ajuste o XP.' using errcode = '22023';
  end if;
  for r in select (e->>'nivel')::smallint nivel, btrim(e->>'nome') nome, (e->>'xp_minimo')::int xp
             from jsonb_array_elements(p_niveis) e order by (e->>'nivel')::int desc loop
    insert into chamados.gam_niveis (nivel, nome, xp_minimo) values (r.nivel, r.nome, r.xp)
    on conflict (nivel) do update set nome = excluded.nome, xp_minimo = excluded.xp_minimo;
  end loop;
  perform chamados.gam_auditar('niveis', 'gam_niveis', v_antes, p_niveis);
  perform chamados.gam_atualizar_perfil(p.pessoa_id) from chamados.gam_perfis p;
  return jsonb_build_object('ok', true);
end $fn$;

-- Conquista (cria ou altera pelo código), com tiers [{tier, nome, limite, xp, raridade, recompensa}].
create function chamados.gam_admin_conquista(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_id smallint; v_antes jsonb; t jsonb;
begin
  perform chamados.gam_exigir_gestor();
  if coalesce(btrim(p->>'codigo'), '') !~ '^[a-z0-9_]{3,40}$' or coalesce(btrim(p->>'nome'), '') = '' then
    raise exception 'Código (a-z, 0-9, _) e nome são obrigatórios.' using errcode = '22023';
  end if;
  select to_jsonb(c) into v_antes from chamados.gam_conquistas c where codigo = p->>'codigo';
  insert into chamados.gam_conquistas (codigo, nome, descricao, icone, raridade, metrica, ativo, ordem)
  values (p->>'codigo', btrim(p->>'nome'), coalesce(p->>'descricao', ''), coalesce(p->>'icone', 'medalha'),
          coalesce(p->>'raridade', 'comum')::chamados.gam_raridade_t, nullif(p->>'metrica', ''), coalesce((p->>'ativo')::boolean, true),
          coalesce((p->>'ordem')::smallint, 50))
  on conflict (codigo) do update set nome = excluded.nome, descricao = excluded.descricao, icone = excluded.icone,
    raridade = excluded.raridade, metrica = excluded.metrica, ativo = excluded.ativo, ordem = excluded.ordem
  returning id into v_id;
  for t in select * from jsonb_array_elements(coalesce(p->'tiers', '[]')) loop
    insert into chamados.gam_conquista_tiers (conquista_id, tier, nome, limite, xp, raridade, recompensa_id)
    values (v_id, (t->>'tier')::smallint, nullif(t->>'nome', ''), (t->>'limite')::int, coalesce((t->>'xp')::int, 0),
            nullif(t->>'raridade', '')::chamados.gam_raridade_t, (select id from chamados.gam_recompensas where codigo = t->>'recompensa'))
    on conflict (conquista_id, tier) do update set nome = excluded.nome, limite = excluded.limite, xp = excluded.xp,
      raridade = excluded.raridade, recompensa_id = excluded.recompensa_id;
  end loop;
  if not exists (select 1 from chamados.gam_conquista_tiers where conquista_id = v_id) then
    raise exception 'A conquista precisa de pelo menos um tier.' using errcode = '22023';
  end if;
  perform chamados.gam_auditar('conquista', p->>'codigo', v_antes, p);
  return jsonb_build_object('ok', true, 'id', v_id);
end $fn$;

create function chamados.gam_admin_missao(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_antes jsonb; v_id smallint;
begin
  perform chamados.gam_exigir_gestor();
  if coalesce(btrim(p->>'codigo'), '') !~ '^[a-z0-9_]{3,40}$' or coalesce(btrim(p->>'nome'), '') = '' then
    raise exception 'Código (a-z, 0-9, _) e nome são obrigatórios.' using errcode = '22023';
  end if;
  select to_jsonb(m) into v_antes from chamados.gam_missoes m where codigo = p->>'codigo';
  insert into chamados.gam_missoes (codigo, nome, descricao, periodo, alvo, metrica, meta, xp, especial, inicio, fim, ativo, conquista_tier_id, recompensa_id)
  values (p->>'codigo', btrim(p->>'nome'), coalesce(p->>'descricao', ''), p->>'periodo', coalesce(p->>'alvo', 'individual'), p->>'metrica',
          (p->>'meta')::numeric, coalesce((p->>'xp')::int, 0), coalesce((p->>'especial')::boolean, false),
          coalesce((p->>'inicio')::date, chamados.gam_dia(now())), nullif(p->>'fim', '')::date, coalesce((p->>'ativo')::boolean, true),
          (select t.id from chamados.gam_conquista_tiers t join chamados.gam_conquistas c on c.id = t.conquista_id where c.codigo = p->>'conquista' order by t.tier limit 1),
          (select id from chamados.gam_recompensas where codigo = p->>'recompensa'))
  on conflict (codigo) do update set nome = excluded.nome, descricao = excluded.descricao, periodo = excluded.periodo, alvo = excluded.alvo,
    metrica = excluded.metrica, meta = excluded.meta, xp = excluded.xp, especial = excluded.especial, inicio = excluded.inicio,
    fim = excluded.fim, ativo = excluded.ativo, conquista_tier_id = excluded.conquista_tier_id, recompensa_id = excluded.recompensa_id
  returning id into v_id;
  perform chamados.gam_auditar('missao', p->>'codigo', v_antes, p);
  return jsonb_build_object('ok', true, 'id', v_id);
end $fn$;

create function chamados.gam_admin_recompensa(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_antes jsonb;
begin
  perform chamados.gam_exigir_gestor();
  if coalesce(btrim(p->>'codigo'), '') !~ '^[a-z0-9_]{3,40}$' or coalesce(btrim(p->>'nome'), '') = '' then
    raise exception 'Código (a-z, 0-9, _) e nome são obrigatórios.' using errcode = '22023';
  end if;
  select to_jsonb(r) into v_antes from chamados.gam_recompensas r where codigo = p->>'codigo';
  insert into chamados.gam_recompensas (codigo, tipo, nome, descricao, raridade, ativo)
  values (p->>'codigo', p->>'tipo', btrim(p->>'nome'), coalesce(p->>'descricao', ''), coalesce(p->>'raridade', 'comum')::chamados.gam_raridade_t,
          coalesce((p->>'ativo')::boolean, true))
  on conflict (codigo) do update set tipo = excluded.tipo, nome = excluded.nome, descricao = excluded.descricao,
    raridade = excluded.raridade, ativo = excluded.ativo;
  perform chamados.gam_auditar('recompensa', p->>'codigo', v_antes, p);
  return jsonb_build_object('ok', true);
end $fn$;

-- Temporada: cria/edita (não encerrada) ou encerra agora (congela o ranking e abre a próxima).
create function chamados.gam_admin_temporada(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare t chamados.gam_temporadas; v_id smallint;
begin
  perform chamados.gam_exigir_gestor();
  if p->>'acao' = 'encerrar' then
    select * into t from chamados.gam_temporadas where id = (p->>'id')::smallint;
    -- Encerramento antecipado: a temporada termina ontem e a próxima começa hoje.
    if t.fim >= chamados.gam_dia(now()) and chamados.gam_dia(now()) - 1 > t.inicio then
      update chamados.gam_temporadas set fim = chamados.gam_dia(now()) - 1 where id = t.id;
    end if;
    perform chamados.gam_encerrar_temporada(t.id);
    perform chamados.gam_auditar('temporada_encerrar', t.nome, to_jsonb(t), null);
    return jsonb_build_object('ok', true);
  end if;
  if (p->>'fim')::date <= (p->>'inicio')::date then raise exception 'Fim depois do início.' using errcode = '22023'; end if;
  if exists (select 1 from chamados.gam_temporadas x where x.id is distinct from (p->>'id')::smallint and x.status <> 'encerrada'
               and daterange(x.inicio, x.fim, '[]') && daterange((p->>'inicio')::date, (p->>'fim')::date, '[]')) then
    raise exception 'Datas sobrepõem outra temporada.' using errcode = '22023';
  end if;
  if p ? 'id' then
    select * into t from chamados.gam_temporadas where id = (p->>'id')::smallint for update;
    if t.status = 'encerrada' then raise exception 'Temporada encerrada não muda.' using errcode = 'P0001'; end if;
    update chamados.gam_temporadas set nome = btrim(p->>'nome'), inicio = (p->>'inicio')::date, fim = (p->>'fim')::date where id = t.id;
    v_id := t.id;
  else
    insert into chamados.gam_temporadas (nome, inicio, fim, status) values (btrim(p->>'nome'), (p->>'inicio')::date, (p->>'fim')::date, 'futura')
    returning id into v_id;
  end if;
  perform chamados.gam_auditar('temporada', p->>'nome', to_jsonb(t), p);
  return jsonb_build_object('ok', true, 'id', v_id);
end $fn$;

-- Revisão de suspeita: aceitar (legítimo) libera o XP retido; rejeitar estorna e tira o chamado das estatísticas.
create function chamados.gam_admin_suspeita(p_id bigint, p_aceitar boolean, p_nota text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.gam_exigir_gestor(); s chamados.gam_suspeitas;
begin
  update chamados.gam_suspeitas set status = case when p_aceitar then 'aceita' else 'rejeitada' end, revisada_em = now(),
         revisor_id = eu, nota = left(chamados._limpar(p_nota), 500)
   where id = p_id and status = 'aberta' returning * into s;
  if s.id is null then raise exception 'Suspeita não encontrada ou já revisada.' using errcode = 'P0001'; end if;
  if s.chamado_id is not null and not exists (select 1 from chamados.gam_suspeitas where pessoa_id = s.pessoa_id and chamado_id = s.chamado_id and status = 'aberta') then
    if p_aceitar then
      update chamados.gam_xp set status = 'pendente', confirmar_em = coalesce(confirmar_em, now()), atualizado_em = now()
       where pessoa_id = s.pessoa_id and chamado_id = s.chamado_id and status = 'retido'
         and regra_codigo in ('resolvido', 'resolvido_sla', 'prioridade_alta', 'critico');
      update chamados.gam_xp set status = 'confirmado', atualizado_em = now()
       where pessoa_id = s.pessoa_id and chamado_id = s.chamado_id and status = 'retido';
    else
      update chamados.gam_xp set status = 'estornado', atualizado_em = now()
       where pessoa_id = s.pessoa_id and chamado_id = s.chamado_id and status in ('retido', 'pendente');
    end if;
  end if;
  perform chamados.gam_notificar(s.pessoa_id, 'revisao', case when p_aceitar then 'Revisão concluída: XP liberado' else 'Revisão concluída: XP estornado' end,
    s.descricao, null, jsonb_build_object('suspeita', s.id));
  perform chamados.gam_atualizar_perfil(s.pessoa_id);
  perform chamados.gam_auditar('suspeita', s.id::text, null, jsonb_build_object('aceita', p_aceitar, 'nota', p_nota));
  return jsonb_build_object('ok', true);
end $fn$;

create function chamados.gam_admin_reprocessar()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare n integer;
begin
  perform chamados.gam_exigir_gestor();
  update chamados.gam_eventos set status = 'pendente', tentativas = 0, erro = null where status = 'erro';
  get diagnostics n = row_count;
  perform chamados.gam_auditar('reprocessar', 'gam_eventos', null, jsonb_build_object('eventos', n));
  return chamados.gam_ciclo() || jsonb_build_object('reenfileirados', n);
end $fn$;

-- ============ Permissões ============
revoke execute on all functions in schema chamados from public, anon;
grant execute on function chamados.catalogo_publico(), chamados.consultar_chamado(text), chamados.ler_convite(text),
  chamados.abrir_chamado_publico(integer, text, text, text, integer, text, integer, text[]),
  chamados.abrir_chamado_por_convite(text, integer, text, integer, text, integer, text[]),
  chamados.avaliar_chamado(text, text, integer, boolean, text) to anon;
grant execute on function chamados.gam_ranking(text, text, smallint), chamados.gam_jornada(uuid), chamados.gam_marcar_lidas(bigint),
  chamados.gam_escolher_visual(smallint, smallint), chamados.gam_processar_agora(), chamados.gam_admin_painel(),
  chamados.gam_admin_config(text, jsonb), chamados.gam_admin_regra(text, integer, boolean, smallint, smallint),
  chamados.gam_admin_multiplicador(smallint, numeric), chamados.gam_admin_niveis(jsonb), chamados.gam_admin_conquista(jsonb),
  chamados.gam_admin_missao(jsonb), chamados.gam_admin_recompensa(jsonb), chamados.gam_admin_temporada(jsonb),
  chamados.gam_admin_suspeita(bigint, boolean, text), chamados.gam_admin_reprocessar() to authenticated;
-- Internas do motor: só o banco (pg_cron) e o service_role.
revoke execute on function chamados.gam_ciclo(), chamados.gam_processar(integer), chamados.gam_confirmar_pendentes(),
  chamados.gam_fechar_periodos(), chamados.gam_encerrar_temporada(smallint), chamados.gam_lancar(uuid, text, integer, text, chamados.gam_xp_status_t, bigint, uuid, text, smallint, bigint, timestamptz),
  chamados.gam_aplicar_regra(text, uuid, uuid, bigint, chamados.gam_xp_status_t, text, numeric, integer),
  chamados.gam_desbloquear(uuid, smallint, text), chamados.gam_dar_recompensa(uuid, smallint, text),
  chamados.gam_suspeitar(uuid, uuid, text, text, jsonb), chamados.gam_notificar(uuid, text, text, text, integer, jsonb),
  chamados.gam_atualizar_perfil(uuid), chamados.gam_sequencia(uuid, text, boolean) from authenticated;

notify pgrst, 'reload schema';

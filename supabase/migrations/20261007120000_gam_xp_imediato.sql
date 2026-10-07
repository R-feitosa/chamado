-- Gamificação: XP conta na hora (decisão do gestor, 07/10/2026 — caminho "Ousado").
--
-- Antes, nível, barra, selo e "XP" da Minha jornada usavam só o XP confirmado; o XP de resolução fica
-- 72 h "em validação" (horas_pendente) e a pontuação parecia não atualizar.
-- Agora o XP em validação (status pendente) já conta para nível, barra, selo e jornada. O ranking por XP já o somava.
-- Continua igual: reabrir dentro da validação estorna o pendente (e o nível pode voltar); XP retido por suspeita
-- só conta depois da revisão do gestor; bônus de confirmação ("sem reabertura", ajuda, conquistas) só após as 72 h.

create or replace function chamados.gam_atualizar_perfil(p_pessoa uuid)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare v_conf integer; v_pend integer; v_antes smallint; n jsonb;
begin
  select greatest(coalesce(sum(valor) filter (where status = 'confirmado'), 0), 0)::int,
         coalesce(sum(valor) filter (where status = 'pendente'), 0)::int
    into v_conf, v_pend from chamados.gam_xp where pessoa_id = p_pessoa;
  n := chamados.gam_nivel(greatest(v_conf + v_pend, 0));
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

create or replace function chamados.gam_jornada(p_pessoa uuid default null)
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
      'xp', coalesce(pf.xp_confirmado, 0) + coalesce(pf.xp_pendente, 0), 'xp_pendente', coalesce(pf.xp_pendente, 0),
      'xp_confirmado', coalesce(pf.xp_confirmado, 0),
      'nivel', chamados.gam_nivel(greatest(coalesce(pf.xp_confirmado, 0) + coalesce(pf.xp_pendente, 0), 0)),
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

-- Recalcula o nível de quem já tem XP.
select chamados.gam_atualizar_perfil(pessoa_id) from chamados.gam_perfis;

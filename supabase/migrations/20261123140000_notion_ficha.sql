-- Notion: cada tarefa de chamado ganha uma "Ficha do chamado" e um "Histórico" no topo da página, atualizados a cada
-- mudança (23/11/2026): tipo de demanda, urgência, quem abriu e por onde, responsável e contribuintes (desde quando),
-- prazos de assumir/resolver com "no prazo"/"com atraso", justificativa de atraso e a linha do tempo do chamado.
-- O banco monta os textos (datas no fuso de Fortaleza); a Edge Function só escreve.

create function chamados.notion_data(p timestamptz)
returns text language sql stable set search_path = '' as $fn$
  select to_char(p at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI')
$fn$;

create or replace function chamados.notion_item(p_chamado uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  c chamados.chamados; s chamados.sistemas; r chamados.pessoas; sol chamados.pessoas; ev chamados.eventos;
  v_setor text; v_andamento text; v_quem text; v_resumo text; v_ficha jsonb; v_hist jsonb;
begin
  select * into c from chamados.chamados where id = p_chamado;
  select * into s from chamados.sistemas where id = c.sistema_id;
  select * into r from chamados.pessoas where id = c.responsavel_id;
  select * into sol from chamados.pessoas where id = c.solicitante_id;
  select * into ev from chamados.eventos where chamado_id = c.id order by id desc limit 1;
  v_setor := coalesce((select nome from chamados.setores where id = c.setor_id), c.setor_outro);
  v_quem := (select split_part(nome, ' ', 1) from chamados.pessoas where id = ev.autor_id);
  v_andamento := case ev.acao::text
    when 'aberto' then 'Chamado aberto na Central'
    when 'assumido' then 'Assumido na Central' || coalesce(' por ' || v_quem, '')
    when 'resolvido' then 'Resolvido na Central' || coalesce(' por ' || v_quem, '')
    when 'reaberto' then 'Reaberto na Central' || coalesce(': ' || (ev.detalhe->>'texto'), coalesce(' (' || (ev.detalhe->>'motivo') || ')', ''))
    when 'desassumido' then 'Devolvido para a fila na Central' || coalesce(': ' || (ev.detalhe->>'motivo'), '')
    else null end;
  -- Ficha do chamado (página do Notion): pares rótulo → valor, datas já no fuso de Fortaleza.
  v_ficha := jsonb_build_array(
    jsonb_build_array('Tipo de demanda', case s.grupo when 'suporte' then 'Suporte técnico' else 'Desenvolvimento' end || ' · ' || coalesce(s.nome, '—')),
    jsonb_build_array('Urgência', (select nome || ' — ' || descricao from chamados.urgencias where nivel = c.urgencia)),
    jsonb_build_array('Solicitante', concat_ws(' · ', coalesce(c.solicitante_nome, sol.nome), c.solicitante_cargo, v_setor)),
    jsonb_build_array('Aberto por', case when c.origem = 'hub'
                                         then 'Botão "Abrir chamado" do ' || coalesce((select x.nome from chamados.sistemas x where x.hub_codigo = c.sistema_origem limit 1),
                                                                                    c.sistema_origem, 'hub')
                                         when c.origem = 'publico' then 'Formulário da Central (sem login)'
                                         else 'Central (time logado)' end || ' em ' || chamados.notion_data(c.criado_em)),
    jsonb_build_array('Responsável', case when c.responsavel_id is null then 'Ninguém assumiu ainda'
                                          else r.nome || coalesce(' · assumiu em ' || chamados.notion_data(c.assumido_em), '') end),
    jsonb_build_array('Contribuintes', coalesce((
      select string_agg(p.nome || ' (desde ' || chamados.notion_data(co.respondida_em) || ')', ', ' order by co.respondida_em)
        from chamados.colaboracoes co join chamados.pessoas p on p.id = co.ajudante_id
       where co.chamado_id = c.id and co.status = 'confirmada' and co.ajudante_id is distinct from c.responsavel_id), 'Nenhum')),
    jsonb_build_array('Prazo para assumir', coalesce(chamados.notion_data(c.prazo_assumir_em), '—') || case
      when c.assumido_em is null then ''
      when c.prazo_assumir_em is null or c.assumido_em <= c.prazo_assumir_em then ' · ✅ assumido no prazo'
      else ' · ⚠️ assumido com atraso' end),
    jsonb_build_array('Prazo para resolver', coalesce(chamados.notion_data(c.prazo_em), '—') || case
      when c.status <> 'resolvido' then ''
      when c.prazo_em is null or c.resolvido_em <= c.prazo_em then ' · ✅ resolvido no prazo em ' || chamados.notion_data(c.resolvido_em)
      else ' · ⚠️ resolvido com atraso em ' || chamados.notion_data(c.resolvido_em) end));
  if c.justificativa_atraso is not null then
    v_ficha := v_ficha || jsonb_build_array(jsonb_build_array('Justificativa de atraso', c.justificativa_atraso));
  end if;

  -- Histórico: eventos do chamado + entrada/saída de contribuintes, em ordem.
  select coalesce(jsonb_agg(jsonb_build_array(chamados.notion_data(h.quando), h.texto) order by h.quando, h.ordem), '[]'::jsonb)
    into v_hist
    from (
      select e.criado_em quando, 0 ordem, case e.acao::text
          when 'aberto' then 'Chamado aberto'
          when 'assumido' then 'Assumido por ' || a.nome
          when 'resolvido' then 'Resolvido por ' || a.nome
          when 'reaberto' then 'Reaberto por ' || a.nome || coalesce(': ' || nullif(e.detalhe->>'texto', ''), coalesce(' (' || (e.detalhe->>'motivo') || ')', ''))
          when 'desassumido' then coalesce((select nome from chamados.pessoas where id::text = e.detalhe->>'de'), a.nome)
                                  || ' devolveu para a fila' || coalesce(': ' || nullif(e.detalhe->>'motivo', ''), '')
          else e.acao::text end texto
        from chamados.eventos e left join chamados.pessoas a on a.id = e.autor_id
       where e.chamado_id = c.id
      union all
      select coalesce(co.respondida_em, co.criada_em), 1, p.nome || case co.status::text
          when 'confirmada' then ' entrou como contribuinte'
          when 'recusada' then ' saiu do chamado'
          else ' foi chamado para ajudar' end
        from chamados.colaboracoes co join chamados.pessoas p on p.id = co.ajudante_id
       where co.chamado_id = c.id
      union all
      select c.justificado_em, 2, 'Atraso justificado pelo responsável' where c.justificado_em is not null
    ) h;

  v_resumo := left(regexp_replace(split_part(btrim(c.descricao), E'\n', 1), '\s+', ' ', 'g'), 80);
  return jsonb_build_object(
    'chamado_id', c.id,
    'page_id', c.notion_page_id,
    'protocolo', c.protocolo,
    'titulo', c.protocolo || ' · ' || coalesce(s.nome, 'Sistema') || ' · ' || v_resumo,
    'status', case c.status::text when 'resolvido' then 'Concluída' when 'andamento' then 'Em andamento' else 'A fazer' end,
    'responsavel', case when c.responsavel_id is null then null else r.notion_responsavel end,
    'prioridade', (array['P3 · Baixa', 'P2 · Média', 'P1 · Alta', 'P0 · Crítica'])[c.urgencia + 1],
    'sistema_projeto', case s.nome
      when 'Atlas Consult' then 'Atlas Consult' when 'Atlas Cash' then 'Atlas Cash' when 'ATLAS RH' then 'Atlas RH'
      when 'CRM' then 'CRM' when 'ATLAS JURIS' then 'ATLAS JURIS' when 'R. Feitosa Ops' then 'RF OPS' else 'Outro' end,
    'solicitante', concat_ws(' · ', coalesce(c.solicitante_nome, sol.nome), c.solicitante_cargo, v_setor),
    'abertura', c.criado_em,
    'prazo', c.prazo_em,
    'conclusao', c.resolvido_em,
    'ultimo_andamento', v_andamento,
    'data_andamento', ev.criado_em,
    'link', (select valor from chamados.configuracao where chave = 'app_url'),
    -- A descrição só vai na criação da página (corpo). Prints nunca vão.
    'descricao', case when c.notion_page_id is null then c.descricao end,
    'sistema', s.nome,
    'urgencia', (array['Não urgente', 'Meio urgente', 'Urgente', 'Muito urgente'])[c.urgencia + 1],
    'contribuintes', coalesce((select jsonb_agg(p.notion_responsavel order by co.respondida_em)
                                 from chamados.colaboracoes co join chamados.pessoas p on p.id = co.ajudante_id
                                where co.chamado_id = c.id and co.status = 'confirmada' and p.notion_responsavel is not null
                                  and co.ajudante_id is distinct from c.responsavel_id), '[]'::jsonb),
    'ficha', v_ficha,
    'historico', v_hist);
end $fn$;

-- Justificar atraso também atualiza a ficha no Notion.
create function chamados.notion_ao_justificar()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  begin
    if new.justificado_em is distinct from old.justificado_em then
      perform chamados.notion_enfileirar(new.id, 'justificativa', false);
    end if;
  exception when others then
    raise warning 'notion: justificativa de % não enfileirada: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
create trigger notion_justificativa after update of justificado_em on chamados.chamados
  for each row execute function chamados.notion_ao_justificar();

revoke all on function chamados.notion_data(timestamptz), chamados.notion_item(uuid), chamados.notion_ao_justificar()
  from public, anon, authenticated;

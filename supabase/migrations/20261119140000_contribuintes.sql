-- Contribuintes: até 3 pessoas no mesmo chamado (responsável + 2), na Central e no Notion (decisão de 19/11/2026).
--
-- * O responsável (ou o gestor) adiciona um colega direto, sem aceite: a colaboração já nasce "confirmada"
--   (passa por "pedida" só para o motor da gamificação registrar, como no aceite). Remover = "recusada"; o próprio
--   contribuinte também pode sair. O fluxo antigo (pedir ajuda + aceite) continua valendo.
-- * Contribuinte escreve no chat do chamado e ganha o XP de ajuda na confirmação, como antes.
-- * Notion: nova coluna "Contribuintes" (multi-seleção) com quem ajuda; mudar contribuintes reenvia a tarefa.

create function chamados.adicionar_contribuinte(p_chamado uuid, p_pessoa uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados; r chamados.colaboracoes;
begin
  select * into c from chamados.chamados where id = p_chamado for update;
  if c.id is null or eu is null or not (coalesce(c.responsavel_id = eu, false) or chamados.eh_gestor()) then
    raise exception 'Só o responsável ou o gestor adiciona contribuintes.' using errcode = '42501';
  end if;
  if c.status = 'resolvido' or c.responsavel_id is null then
    raise exception 'Só dá para adicionar contribuintes com o chamado em andamento.' using errcode = 'P0001';
  end if;
  if p_pessoa is null or p_pessoa = c.responsavel_id
     or not exists (select 1 from chamados.pessoas where id = p_pessoa and ativo and papel = 'dev') then
    raise exception 'Escolha um colega do time.' using errcode = '22023';
  end if;
  if (select count(*) from chamados.colaboracoes where chamado_id = c.id and status = 'confirmada' and ajudante_id <> p_pessoa) >= 2 then
    raise exception 'Limite de 3 pessoas por chamado (responsável + 2 contribuintes).' using errcode = 'P0001';
  end if;
  insert into chamados.colaboracoes as co (chamado_id, responsavel_id, ajudante_id) values (c.id, c.responsavel_id, p_pessoa)
  on conflict (chamado_id, ajudante_id) do update
     set status = 'pedida', respondida_em = null, responsavel_id = excluded.responsavel_id
   where co.status <> 'confirmada'
  returning * into r;
  if r.id is null then raise exception 'Este colega já é contribuinte deste chamado.' using errcode = 'P0001'; end if;
  update chamados.colaboracoes set status = 'confirmada', respondida_em = now() where id = r.id returning * into r;
  return to_jsonb(r);
end $fn$;

create function chamados.remover_contribuinte(p_chamado uuid, p_pessoa uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados; r chamados.colaboracoes;
begin
  select * into c from chamados.chamados where id = p_chamado;
  if c.id is null or eu is null or not (coalesce(c.responsavel_id = eu, false) or p_pessoa = eu or chamados.eh_gestor()) then
    raise exception 'Só o responsável, o gestor ou o próprio contribuinte remove.' using errcode = '42501';
  end if;
  if c.status = 'resolvido' then raise exception 'Chamado resolvido: os contribuintes ficam registrados.' using errcode = 'P0001'; end if;
  update chamados.colaboracoes set status = 'recusada', respondida_em = now()
   where chamado_id = c.id and ajudante_id = p_pessoa and status in ('pedida', 'confirmada')
  returning * into r;
  if r.id is null then raise exception 'Esta pessoa não é contribuinte deste chamado.' using errcode = 'P0001'; end if;
  return to_jsonb(r);
end $fn$;

-- ============ Notion: um ponto só para enfileirar; contribuintes também disparam ============
create function chamados.notion_enfileirar(p_chamado uuid, p_motivo text, p_criar boolean)
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  if not chamados.notion_ativo() then return; end if;
  -- Só cria ao assumir; o resto só vale para chamados que já estão (ou vão estar) no Notion.
  if not p_criar and not exists (select 1 from chamados.chamados where id = p_chamado and notion_page_id is not null)
     and not exists (select 1 from chamados.notion_envios where chamado_id = p_chamado) then
    return;
  end if;
  insert into chamados.notion_envios (chamado_id, motivo) values (p_chamado, p_motivo)
  on conflict (chamado_id) where enviado_em is null and reservado_em is null do update set motivo = excluded.motivo;
  perform chamados.notion_disparar();
end $fn$;

create or replace function chamados.notion_ao_evento()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  begin
    if new.acao::text in ('assumido', 'resolvido', 'reaberto', 'desassumido') then
      perform chamados.notion_enfileirar(new.chamado_id, new.acao::text, new.acao::text = 'assumido');
    end if;
  exception when others then
    raise warning 'notion: evento % não enfileirado: %', new.id, sqlerrm;  -- nunca impede o fluxo do chamado
  end;
  return null;
end $fn$;

create function chamados.notion_ao_contribuinte()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  begin
    if tg_op = 'INSERT' or new.status is distinct from old.status then
      perform chamados.notion_enfileirar(new.chamado_id, 'contribuintes', false);
    end if;
  exception when others then
    raise warning 'notion: contribuintes de % não enfileirados: %', new.chamado_id, sqlerrm;
  end;
  return null;
end $fn$;
create trigger notion_contribuintes after insert or update of status on chamados.colaboracoes
  for each row execute function chamados.notion_ao_contribuinte();

create or replace function chamados.notion_item(p_chamado uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  c chamados.chamados; s chamados.sistemas; r chamados.pessoas; sol chamados.pessoas; ev chamados.eventos;
  v_setor text; v_andamento text; v_quem text; v_resumo text;
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
                                  and co.ajudante_id is distinct from c.responsavel_id), '[]'::jsonb));
end $fn$;

revoke all on function chamados.adicionar_contribuinte(uuid, uuid), chamados.remover_contribuinte(uuid, uuid),
  chamados.notion_enfileirar(uuid, text, boolean), chamados.notion_ao_evento(), chamados.notion_ao_contribuinte(),
  chamados.notion_item(uuid) from public, anon, authenticated;
grant execute on function chamados.adicionar_contribuinte(uuid, uuid), chamados.remover_contribuinte(uuid, uuid) to authenticated;

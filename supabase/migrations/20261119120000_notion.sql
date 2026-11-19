-- Integração Central → Notion (base "Acompanhamento de Tarefas · P&D"), caminho Balanceado aprovado em 19/11/2026.
--
-- * Quando alguém assume, cria uma tarefa no Notion (Tipo "Chamado", Responsável = quem assumiu, Status "Em andamento",
--   prioridade pela urgência, sistema, solicitante, abertura, prazo, link e a descrição no corpo da página).
-- * Depois, acompanha o chamado: resolver → "Concluída" (+ Conclusão); reabrir → "Em andamento"; desassumir → "A fazer"
--   sem responsável; outro assume → troca o Responsável. Só Central → Notion.
-- * Só chamados assumidos depois de ligar (configuracao.notion_ativo = 'true'). Começa desligada.
-- * Desenho igual ao do push: gatilho em eventos → fila notion_envios → notion_disparar() (pg_net) → Edge Function
--   chamados-notion (verify_jwt=false, autenticada pelo segredo do Vault) → notion_lote()/notion_confirmar().
--   O token do Notion fica só como segredo da Edge Function (NOTION_TOKEN), nunca no banco nem no repositório.

-- ============ Mapeamento e estado ============
alter table chamados.pessoas add column notion_responsavel text;
comment on column chamados.pessoas.notion_responsavel is 'Opção da coluna "Responsável" na base do Notion (ex.: KAIO).';
update chamados.pessoas set notion_responsavel = case nome
    when 'Aldo Júnior' then 'ALDO' when 'Ruan' then 'RUAN' when 'Brenno Azevedo' then 'BRENNO AZEVEDO'
    when 'Breno Magalhães' then 'BRENO MAGALHÃES' when 'João Pedro' then 'JOTINHA' when 'Kaio' then 'KAIO' end
 where papel = 'dev' and nome in ('Aldo Júnior', 'Ruan', 'Brenno Azevedo', 'Breno Magalhães', 'João Pedro', 'Kaio');

alter table chamados.chamados add column notion_page_id text;
comment on column chamados.chamados.notion_page_id is 'Página da tarefa no Notion (base Acompanhamento de Tarefas · P&D).';

insert into chamados.configuracao (chave, valor) values
  ('notion_ativo', 'false'),
  ('notion_database_id', '41d4ea8cd78c816085c4f72cce41562e')
on conflict (chave) do nothing;

create table chamados.notion_envios (
  id           bigint generated always as identity primary key,
  chamado_id   uuid not null references chamados.chamados (id) on delete cascade,
  motivo       text not null,
  criado_em    timestamptz not null default now(),
  reservado_em timestamptz,
  tentativas   smallint not null default 0,
  enviado_em   timestamptz,
  erro         text
);
-- Um pendente (ainda não reservado) por chamado: eventos seguidos viram um envio só, com o estado mais recente.
create unique index notion_envios_um_pendente on chamados.notion_envios (chamado_id) where enviado_em is null and reservado_em is null;
create index notion_envios_fila on chamados.notion_envios (id) where enviado_em is null;
alter table chamados.notion_envios enable row level security;
grant all on chamados.notion_envios to service_role;
comment on table chamados.notion_envios is 'Fila de sincronização com o Notion. A Edge Function lê o estado atual do chamado no envio.';

-- ============ Segredo de despacho ============
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'chamados_notion_dispatch_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'chamados_notion_dispatch_secret',
                                'Central de Chamados: segredo que o pg_net envia à Edge Function chamados-notion');
  end if;
end $$;

create function chamados.notion_ativo()
returns boolean language sql stable security definer set search_path = '' as $fn$
  select coalesce((select valor from chamados.configuracao where chave = 'notion_ativo'), 'false') = 'true'
$fn$;

create function chamados.notion_segredo_valido(p_segredo text)
returns boolean language plpgsql stable security definer set search_path = '' as $fn$
begin
  return p_segredo is not null and exists (
    select 1 from vault.decrypted_secrets where name = 'chamados_notion_dispatch_secret' and decrypted_secret = p_segredo);
end $fn$;

create function chamados.notion_disparar()
returns void language plpgsql security definer set search_path = '' as $fn$
declare v_segredo text;
begin
  select decrypted_secret into v_segredo from vault.decrypted_secrets where name = 'chamados_notion_dispatch_secret';
  if v_segredo is null then return; end if;
  perform net.http_post(
    url := 'https://ashxrwwlcarvqdigoxsi.supabase.co/functions/v1/chamados-notion',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-chamados-notion-secret', v_segredo),
    timeout_milliseconds := 20000);
end $fn$;

-- ============ Gatilho: eventos do chamado → fila ============
create function chamados.notion_ao_evento()
returns trigger language plpgsql security definer set search_path = '' as $fn$
declare c chamados.chamados;
begin
  begin
    if new.acao::text not in ('assumido', 'resolvido', 'reaberto', 'desassumido') or not chamados.notion_ativo() then
      return null;
    end if;
    select * into c from chamados.chamados where id = new.chamado_id;
    -- Só cria ao assumir; os demais eventos só valem para chamados que já estão (ou vão estar) no Notion.
    if new.acao::text <> 'assumido' and c.notion_page_id is null
       and not exists (select 1 from chamados.notion_envios where chamado_id = c.id) then
      return null;
    end if;
    insert into chamados.notion_envios (chamado_id, motivo) values (c.id, new.acao::text)
    on conflict (chamado_id) where enviado_em is null and reservado_em is null do update set motivo = excluded.motivo;
    perform chamados.notion_disparar();
  exception when others then
    raise warning 'notion: evento % não enfileirado: %', new.id, sqlerrm;  -- nunca impede o fluxo do chamado
  end;
  return null;
end $fn$;
create trigger notion_sync after insert on chamados.eventos for each row execute function chamados.notion_ao_evento();

-- ============ RPCs da Edge Function (service_role + segredo) ============
create function chamados.notion_lote(p_segredo text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_itens jsonb; v_agora timestamptz := now();
begin
  if not chamados.notion_segredo_valido(p_segredo) then
    raise exception 'Segredo de despacho inválido.' using errcode = '42501';
  end if;
  with alvo as (
    select distinct e.chamado_id from chamados.notion_envios e
     where e.enviado_em is null and e.tentativas < 5
       and (e.reservado_em is null or e.reservado_em < v_agora - interval '2 minutes')
     limit 20
  ), reservados as (
    update chamados.notion_envios e set reservado_em = v_agora, tentativas = e.tentativas + 1
      from alvo a
     where e.chamado_id = a.chamado_id and e.enviado_em is null and e.tentativas < 5
       and (e.reservado_em is null or e.reservado_em < v_agora - interval '2 minutes')
    returning e.id, e.chamado_id
  )
  select coalesce(jsonb_agg(chamados.notion_item(r.chamado_id) || jsonb_build_object('envio_ids', r.ids)), '[]'::jsonb)
    into v_itens
    from (select chamado_id, jsonb_agg(id order by id) ids from reservados group by chamado_id) r;
  return jsonb_build_object(
    'database_id', (select valor from chamados.configuracao where chave = 'notion_database_id'),
    'itens', v_itens);
end $fn$;

-- Estado atual do chamado já no formato da base do Notion.
create function chamados.notion_item(p_chamado uuid)
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
    'urgencia', (array['Não urgente', 'Meio urgente', 'Urgente', 'Muito urgente'])[c.urgencia + 1]);
end $fn$;

create function chamados.notion_confirmar(p_segredo text, p_resultados jsonb)
returns void language plpgsql security definer set search_path = '' as $fn$
declare x jsonb;
begin
  if not chamados.notion_segredo_valido(p_segredo) then
    raise exception 'Segredo de despacho inválido.' using errcode = '42501';
  end if;
  for x in select value from jsonb_array_elements(coalesce(p_resultados, '[]'::jsonb)) loop
    if (x->>'ok')::boolean then
      update chamados.notion_envios set enviado_em = now(), erro = null
       where id in (select (v)::bigint from jsonb_array_elements_text(x->'envio_ids') v);
      if x->>'page_id' is not null then
        update chamados.chamados set notion_page_id = x->>'page_id'
         where id = (x->>'chamado_id')::uuid and notion_page_id is distinct from x->>'page_id';
      end if;
    else
      -- Falha: libera para nova tentativa (até 5) no próximo minuto.
      update chamados.notion_envios set reservado_em = null, erro = left(x->>'erro', 500)
       where id in (select (v)::bigint from jsonb_array_elements_text(x->'envio_ids') v);
    end if;
  end loop;
end $fn$;

-- ============ Retentativa: o agendador do push (1 min) também dispara o Notion pendente ============
create or replace function chamados.push_agendar()
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_agora timestamptz := now();
  v_exp boolean := chamados.push_no_expediente(now());
  v_n integer := 0;
  c chamados.chamados;
  r chamados.push_regras;
  v_seq integer;
  v_cancel integer;
  v_chat integer;
begin
  if not pg_try_advisory_xact_lock(hashtext('chamados.push_agendar')) then
    return jsonb_build_object('ocupado', true);
  end if;

  update chamados.push_envios e set cancelado_em = v_agora
    from chamados.chamados ch
   where e.chamado_id = ch.id and e.enviado_em is null and e.cancelado_em is null
     and e.tipo in ('novo', 'lembrete', 'escalada_gestor')
     and (ch.responsavel_id is not null or ch.status = 'resolvido');
  get diagnostics v_cancel = row_count;
  update chamados.push_envios e set cancelado_em = v_agora
    from chamados.chamados ch
   where e.chamado_id = ch.id and e.enviado_em is null and e.cancelado_em is null
     and e.tipo in ('prazo_perto', 'prazo_vencido') and ch.status = 'resolvido';

  for c in select * from chamados.chamados where status <> 'resolvido' loop
    select * into r from chamados.push_regras where nivel = c.urgencia;
    if c.responsavel_id is null then
      if c.criado_em > v_agora - interval '10 minutes' then
        v_n := v_n + chamados.push_enfileirar(c, 'novo', 0, chamados.push_devs(c.solicitante_id), v_agora + interval '15 minutes');
      end if;
      if r.repetir_min is not null and (v_exp or not r.so_expediente) then
        v_seq := floor(extract(epoch from v_agora - c.criado_em) / 60 / r.repetir_min)::int;
        if v_seq >= 1 then
          v_n := v_n + chamados.push_enfileirar(c, 'lembrete', v_seq, chamados.push_devs(c.solicitante_id),
                                                 v_agora + make_interval(mins => r.repetir_min));
        end if;
      end if;
      if r.escalar_gestor and c.prazo_assumir_em is not null and v_agora >= c.prazo_assumir_em then
        v_n := v_n + chamados.push_enfileirar(c, 'escalada_gestor', 0, chamados.push_gestores(), v_agora + interval '12 hours');
      end if;
    elsif c.prazo_em is not null then
      if v_agora >= c.prazo_em then
        v_n := v_n + chamados.push_enfileirar(c, 'prazo_vencido', 0, array[c.responsavel_id], v_agora + interval '12 hours');
      elsif v_agora >= c.prazo_em - (c.prazo_em - c.criado_em) * 0.25 then
        v_n := v_n + chamados.push_enfileirar(c, 'prazo_perto', 0, array[c.responsavel_id], c.prazo_em);
      end if;
    end if;
  end loop;

  v_chat := chamados.chat_descartar();

  -- Integração com o Notion: reenvia o que ficou pendente (falha ou fila parada).
  if chamados.notion_ativo() and exists (select 1 from chamados.notion_envios
       where enviado_em is null and tentativas < 5 and (reservado_em is null or reservado_em < v_agora - interval '2 minutes')) then
    perform chamados.notion_disparar();
  end if;

  if exists (select 1 from chamados.push_envios e
              where e.enviado_em is null and e.cancelado_em is null and e.expira_em > v_agora and e.tentativas < 3
                and (e.reservado_em is null or e.reservado_em < v_agora - interval '2 minutes')) then
    perform chamados.push_disparar();
  end if;
  return jsonb_build_object('enfileirados', v_n, 'cancelados', v_cancel, 'expediente', v_exp, 'chat_apagadas', v_chat);
end $fn$;

-- ============ Permissões ============
revoke all on function chamados.notion_ativo(), chamados.notion_segredo_valido(text), chamados.notion_disparar(),
  chamados.notion_ao_evento(), chamados.notion_lote(text), chamados.notion_item(uuid), chamados.notion_confirmar(text, jsonb),
  chamados.push_agendar() from public, anon, authenticated;
grant execute on function chamados.notion_lote(text), chamados.notion_confirmar(text, jsonb) to service_role;

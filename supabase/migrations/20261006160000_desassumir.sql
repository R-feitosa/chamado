-- Desassumir: o responsável (ou o gestor) devolve o chamado em andamento para a fila.
--
-- * Volta a "aberto", sem responsável e sem assumido_em; os prazos continuam os da abertura (congelados).
-- * Motivo opcional, gravado no histórico (eventos.acao = 'desassumido').
-- * Pedidos de ajuda ainda não respondidos são cancelados (recusada); ajudas já confirmadas ficam.
-- * O XP de "Primeira resposta rápida" ainda em validação de quem saiu é estornado (assumir só para pontuar não compensa;
--   a chave do ledger impede pagar de novo se a mesma pessoa reassumir).
-- * Avisos de prazo de quem saiu ainda não enviados são cancelados; os lembretes de "sem responsável" voltam sozinhos
--   no agendador do push.

alter type chamados.acao_t add value if not exists 'desassumido';

-- Gamificação: 'desassumido' não é fato do motor (antes, qualquer ação fora da lista virava ticket.reopened).
create or replace function chamados.gam_publicar_evento()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if new.acao::text = 'desassumido' then return null; end if;
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

-- Estorno do XP de resposta rápida de quem desassumiu (só o que ainda está em validação).
create function chamados.gam_ao_desassumir(p_chamado uuid, p_pessoa uuid)
returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare v integer;
begin
  with x as (
    update chamados.gam_xp set status = 'estornado', atualizado_em = now()
     where chamado_id = p_chamado and pessoa_id = p_pessoa and regra_codigo = 'resposta_rapida' and status in ('pendente', 'retido')
    returning valor
  ) select coalesce(sum(valor), 0) into v from x;
  if v <> 0 then perform chamados.gam_atualizar_perfil(p_pessoa); end if;
  return v;
end $fn$;

create function chamados.desassumir_chamado(p_id uuid, p_motivo text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  eu uuid := chamados.eu_pessoa_id();
  v_gestor boolean := chamados.eh_gestor();
  c chamados.chamados;
  v_resp uuid;
  v_estorno integer := 0;
begin
  if eu is null or not (chamados.eh_dev() or v_gestor) then
    raise exception 'Só o time desassume chamados.' using errcode = '42501';
  end if;
  select * into c from chamados.chamados where id = p_id for update;
  if c.id is null then raise exception 'Chamado não encontrado.' using errcode = 'P0001'; end if;
  if c.status = 'resolvido' then raise exception 'Chamado resolvido não pode ser desassumido.' using errcode = 'P0001'; end if;
  if c.responsavel_id is null then raise exception 'Este chamado já está sem responsável.' using errcode = 'P0001'; end if;
  if c.responsavel_id <> eu and not v_gestor then
    raise exception 'Só o responsável ou o gestor desassume este chamado.' using errcode = '42501';
  end if;
  v_resp := c.responsavel_id;

  update chamados.chamados set responsavel_id = null, assumido_em = null, status = 'aberto', atualizado_em = now()
   where id = c.id
  returning * into c;
  update chamados.colaboracoes set status = 'recusada', respondida_em = now()
   where chamado_id = c.id and status = 'pedida';
  update chamados.push_envios set cancelado_em = now(), resultado = '{"cancelado": "desassumido"}'::jsonb
   where chamado_id = c.id and pessoa_id = v_resp and tipo in ('prazo_perto', 'prazo_vencido')
     and enviado_em is null and cancelado_em is null;
  insert into chamados.eventos (chamado_id, autor_id, acao, detalhe)
  values (c.id, eu, 'desassumido',
          jsonb_strip_nulls(jsonb_build_object('de', v_resp, 'motivo', nullif(left(chamados._limpar(p_motivo), 300), ''))));

  begin
    v_estorno := chamados.gam_ao_desassumir(c.id, v_resp);
  exception when others then
    raise warning 'gamificação: estorno ao desassumir %: %', c.id, sqlerrm;  -- nunca impede desassumir
  end;
  return to_jsonb(c) || jsonb_build_object('xp_estornado', v_estorno);
end $fn$;

revoke all on function chamados.gam_ao_desassumir(uuid, uuid), chamados.desassumir_chamado(uuid, text) from public, anon, authenticated;
grant execute on function chamados.desassumir_chamado(uuid, text) to authenticated;

notify pgrst, 'reload schema';

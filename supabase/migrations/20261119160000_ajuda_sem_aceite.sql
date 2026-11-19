-- "Ajuda" sem aceite (decisão do gestor, 19/11/2026): pedir ajuda adiciona o colega direto como contribuinte,
-- e ele vai na hora para a coluna "Contribuintes" da tarefa no Notion. Mesmas regras do adicionar_contribuinte
-- (responsável ou gestor, chamado em andamento, até 3 pessoas).

create or replace function chamados.pedir_ajuda(p_chamado uuid, p_ajudante uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  if not (chamados.eh_dev() or chamados.eh_gestor()) then raise exception 'Só o time pede ajuda.' using errcode = '42501'; end if;
  return chamados.adicionar_contribuinte(p_chamado, p_ajudante);
end $fn$;

-- Telas antigas ainda podem chamar "Vou ajudar"/"Recusar": aceitar o que já entrou não faz nada; recusar = sair.
create or replace function chamados.responder_ajuda(p_colaboracao bigint, p_aceitar boolean)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); r chamados.colaboracoes;
begin
  update chamados.colaboracoes set status = case when p_aceitar then 'confirmada' else 'recusada' end::chamados.colaboracao_t,
         respondida_em = now()
   where id = p_colaboracao and ajudante_id = eu
     and (status = 'pedida' or (status = 'confirmada' and not p_aceitar))
  returning * into r;
  if r.id is null then
    select * into r from chamados.colaboracoes where id = p_colaboracao and ajudante_id = eu and status = 'confirmada';
    if r.id is null then raise exception 'Pedido de ajuda não encontrado.' using errcode = 'P0001'; end if;
  end if;
  return to_jsonb(r);
end $fn$;

-- Pedidos que ainda esperavam aceite em chamados em andamento entram como contribuintes (limite de 3 pessoas).
update chamados.colaboracoes co set status = 'confirmada', respondida_em = now()
 where co.status = 'pedida'
   and exists (select 1 from chamados.chamados c where c.id = co.chamado_id and c.status <> 'resolvido' and c.responsavel_id is not null)
   and (select count(*) from chamados.colaboracoes x where x.chamado_id = co.chamado_id and x.status = 'confirmada') < 2;

revoke all on function chamados.pedir_ajuda(uuid, uuid), chamados.responder_ajuda(bigint, boolean) from public, anon;
grant execute on function chamados.pedir_ajuda(uuid, uuid), chamados.responder_ajuda(bigint, boolean) to authenticated;

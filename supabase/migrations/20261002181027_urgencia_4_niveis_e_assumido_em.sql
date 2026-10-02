-- ============================================================================
-- Urgência em 4 níveis e registro de quando o chamado foi assumido
-- ----------------------------------------------------------------------------
-- Urgência: 0 Não urgente · 1 Pouco urgente · 2 Urgente · 3 Muito urgente.
-- De-para dos 3 níveis antigos: Pode esperar(0)→0, Atrapalha(1)→2, Estou parado(2)→3.
-- assumido_em: base do indicador "tempo até assumir" (painel e analytics).
-- ============================================================================

alter table chamados.chamados drop constraint chamados_urgencia_check;
update chamados.chamados set urgencia = 3 where urgencia = 2;
update chamados.chamados set urgencia = 2 where urgencia = 1;
alter table chamados.chamados add constraint chamados_urgencia_check check (urgencia between 0 and 3);
comment on column chamados.chamados.urgencia is '0 Não urgente · 1 Pouco urgente · 2 Urgente · 3 Muito urgente';

alter table chamados.chamados add column assumido_em timestamptz;
update chamados.chamados c set assumido_em = e.primeiro
  from (select chamado_id, min(criado_em) primeiro from chamados.eventos where acao = 'assumido' group by chamado_id) e
 where e.chamado_id = c.id;
alter table chamados.chamados add constraint chamados_assumido_check check (status = 'aberto' or assumido_em is not null);

create or replace function chamados.assumir_chamado(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados;
begin
  if not chamados.eh_dev() then raise exception 'Só o time de desenvolvimento assume chamados.' using errcode = '42501'; end if;
  update chamados.chamados set responsavel_id = eu, status = 'andamento', assumido_em = now(), atualizado_em = now()
   where id = p_id and status <> 'resolvido' and responsavel_id is null
  returning * into c;
  if not found then raise exception 'Este chamado já foi assumido ou resolvido.' using errcode = 'P0001'; end if;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, eu, 'assumido');
  return to_jsonb(c);
end $$;

revoke execute on function chamados.assumir_chamado(uuid) from public, anon;
grant execute on function chamados.assumir_chamado(uuid) to authenticated;

notify pgrst, 'reload schema';

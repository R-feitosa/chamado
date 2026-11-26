-- "Assumir junto" (decisão do gestor, 26/11/2026): num chamado que já tem responsável, qualquer dev pode entrar
-- sozinho como contribuinte, sem precisar que o responsável o adicione. Mesmas regras dos contribuintes:
-- chamado em andamento, até 3 pessoas (responsável + 2), vai na hora para o Notion e ganha o XP de ajuda.
-- O gestor não assume (nem junto). O responsável continua o mesmo.
create function chamados.assumir_junto(p_chamado uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id(); c chamados.chamados; r chamados.colaboracoes;
begin
  if eu is null or not exists (select 1 from chamados.pessoas where id = eu and ativo and papel = 'dev' and not gestor) then
    raise exception 'Só o time de desenvolvimento assume chamados.' using errcode = '42501';
  end if;
  select * into c from chamados.chamados where id = p_chamado for update;
  if c.id is null then raise exception 'Chamado não encontrado.' using errcode = 'P0002'; end if;
  if c.status = 'resolvido' then raise exception 'Chamado resolvido: não dá para assumir junto.' using errcode = 'P0001'; end if;
  if c.responsavel_id is null then raise exception 'Este chamado está sem responsável: use "Assumir".' using errcode = 'P0001'; end if;
  if c.responsavel_id = eu then raise exception 'Você já é o responsável deste chamado.' using errcode = 'P0001'; end if;
  if exists (select 1 from chamados.colaboracoes where chamado_id = c.id and ajudante_id = eu and status = 'confirmada') then
    raise exception 'Você já está neste chamado.' using errcode = 'P0001';
  end if;
  if (select count(*) from chamados.colaboracoes where chamado_id = c.id and status = 'confirmada') >= 2 then
    raise exception 'Limite de 3 pessoas por chamado (responsável + 2 contribuintes).' using errcode = 'P0001';
  end if;
  -- Passa por "pedida" só para o motor da gamificação registrar a colaboração, como no aceite.
  insert into chamados.colaboracoes as co (chamado_id, responsavel_id, ajudante_id) values (c.id, c.responsavel_id, eu)
  on conflict (chamado_id, ajudante_id) do update
     set status = 'pedida', respondida_em = null, responsavel_id = excluded.responsavel_id
   where co.status <> 'confirmada'
  returning * into r;
  update chamados.colaboracoes set status = 'confirmada', respondida_em = now() where id = r.id returning * into r;
  return to_jsonb(r);
end $fn$;

revoke all on function chamados.assumir_junto(uuid) from public, anon;
grant execute on function chamados.assumir_junto(uuid) to authenticated;

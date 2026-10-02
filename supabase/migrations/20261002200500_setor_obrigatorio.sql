-- ============================================================================
-- Setor e nome do solicitante obrigatórios na abertura sem login
-- ----------------------------------------------------------------------------
-- abrir_chamado_publico passa a exigir o setor e confere se o nome escolhido
-- pertence a ele (compensa a falta de login). Troca a assinatura da função.
-- ============================================================================

drop function chamados.abrir_chamado_publico(uuid, integer, text, integer, text[]);

create function chamados.abrir_chamado_publico(
  p_setor_id integer, p_solicitante_id uuid, p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare c chamados.chamados; pr text;
begin
  if p_setor_id is null or not exists (select 1 from chamados.setores where id = p_setor_id) then
    raise exception 'Informe seu setor.' using errcode = '22023';
  end if;
  if p_solicitante_id is null or not exists (select 1 from chamados.pessoas where id = p_solicitante_id and ativo and papel = 'solicitante') then
    raise exception 'Escolha seu nome na lista.' using errcode = '22023';
  end if;
  if not exists (select 1 from chamados.pessoas where id = p_solicitante_id and setor_id = p_setor_id) then
    raise exception 'O nome escolhido não é do setor informado.' using errcode = '22023';
  end if;
  if (select count(*) from chamados.chamados where solicitante_id = p_solicitante_id and origem = 'publico'
        and criado_em > now() - interval '10 minutes') >= 5
     or (select count(*) from chamados.chamados where origem = 'publico' and criado_em > now() - interval '10 minutes') >= 30 then
    raise exception 'Muitos chamados em pouco tempo. Aguarde alguns minutos e tente de novo.' using errcode = 'P0001';
  end if;
  foreach pr in array coalesce(p_prints, '{}') loop
    if pr !~ '^publico/[0-9a-f-]{36}\.(png|jpg|webp|gif)$'
       or exists (select 1 from chamados.chamados x where pr = any (x.prints)) then
      raise exception 'Print inválido.' using errcode = '22023';
    end if;
  end loop;
  insert into chamados.chamados (descricao, solicitante_id, sistema_id, urgencia, prints, origem)
  values (btrim(p_descricao), p_solicitante_id, p_sistema_id, p_urgencia, coalesce(p_prints, '{}'), 'publico')
  returning * into c;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, p_solicitante_id, 'aberto');
  return jsonb_build_object('protocolo', c.protocolo, 'sistema_id', c.sistema_id, 'urgencia', c.urgencia,
    'prints', cardinality(c.prints), 'criado_em', c.criado_em, 'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em);
end $fn$;

revoke execute on function chamados.abrir_chamado_publico(integer, uuid, integer, text, integer, text[]) from public;
grant execute on function chamados.abrir_chamado_publico(integer, uuid, integer, text, integer, text[]) to anon, authenticated;

notify pgrst, 'reload schema';

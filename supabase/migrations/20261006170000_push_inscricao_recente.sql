-- Push: 404/410 logo depois de inscrever não desativa o aparelho.
-- O serviço de push (FCM) às vezes ainda não propagou a inscrição recém-criada e responde 410 nos primeiros segundos
-- (visto em produção: 410 no teste 2 s após inscrever, 201 no seguinte). Nos primeiros 10 min conta só como falha.

create or replace function chamados.push_confirmar(p_segredo text, p_resultados jsonb, p_ok uuid[] default '{}', p_expiradas uuid[] default '{}', p_falhas uuid[] default '{}')
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  if not chamados.push_segredo_valido(p_segredo) then
    raise exception 'Segredo de despacho inválido.' using errcode = '42501';
  end if;
  update chamados.push_envios e
     set enviado_em = case when (r.value->>'concluido')::boolean then now() else null end,
         reservado_em = case when (r.value->>'concluido')::boolean then e.reservado_em else null end,
         resultado = r.value->'detalhe'
    from jsonb_array_elements(coalesce(p_resultados, '[]'::jsonb)) r
   where e.id = (r.value->>'envio_id')::bigint;
  -- 404/410 do push service = inscrição morta (permissão revogada, navegador limpo), exceto se acabou de ser inscrita.
  update chamados.push_inscricoes set desativada_em = now()
   where id = any(p_expiradas) and desativada_em is null and atualizado_em < now() - interval '10 minutes';
  update chamados.push_inscricoes set falhas_consecutivas = least(falhas_consecutivas + 1, 1000)
   where id = any(p_expiradas) and desativada_em is null and atualizado_em >= now() - interval '10 minutes';
  update chamados.push_inscricoes set ultimo_envio_em = now(), falhas_consecutivas = 0 where id = any(p_ok);
  update chamados.push_inscricoes set falhas_consecutivas = least(falhas_consecutivas + 1, 1000),
         desativada_em = case when falhas_consecutivas + 1 >= 20 then coalesce(desativada_em, now()) else desativada_em end
   where id = any(p_falhas);
end $fn$;

revoke all on function chamados.push_confirmar(text, jsonb, uuid[], uuid[], uuid[]) from public, anon, authenticated;
grant execute on function chamados.push_confirmar(text, jsonb, uuid[], uuid[], uuid[]) to service_role;

-- Antiabuso "resolução relâmpago": passa a contar o tempo desde a ABERTURA do chamado, não desde assumir
-- (decisão do gestor, 26/10/2026). O time resolve primeiro e só depois clica em Assumir/Resolver, e 6 chamados legítimos
-- ficaram retidos. A chave de config continua `min_assumir_resolver_min` (3 min); "Muito urgente em menos de 5 min
-- desde a abertura" (critico_relampago) continua igual.

create or replace function chamados.gam_checar_resolucao(c chamados.chamados)
returns boolean language plpgsql volatile security definer set search_path = '' as $fn$
declare s jsonb := chamados.gam_cfg('suspeita'); v_min numeric; n integer;
begin
  -- Conta desde a ABERTURA (não desde assumir): o time costuma resolver e só depois clicar em Assumir/Resolver.
  v_min := extract(epoch from (c.resolvido_em - c.criado_em)) / 60;
  if v_min < (s->>'min_assumir_resolver_min')::numeric then
    perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'resolucao_relampago',
      'Resolvido ' || round(v_min, 1) || ' min depois da abertura.', jsonb_build_object('minutos', round(v_min, 1)));
  end if;
  if c.urgencia = 3 and extract(epoch from (c.resolvido_em - c.criado_em)) / 60 < (s->>'critico_min')::numeric then
    perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'critico_relampago',
      'Chamado muito urgente resolvido em menos de ' || (s->>'critico_min') || ' min desde a abertura.', '{}');
  end if;
  if c.solicitante_nome is not null then
    select count(*) into n from chamados.chamados x
     where x.responsavel_id = c.responsavel_id and x.status = 'resolvido'
       and chamados.gam_dia(x.resolvido_em) = chamados.gam_dia(c.resolvido_em)
       and chamados._chave_nome(x.solicitante_nome) = chamados._chave_nome(c.solicitante_nome);
    if n >= (s->>'mesmo_nome_dia')::int then
      perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'mesmo_solicitante_dia',
        n || ' chamados do mesmo nome resolvidos pelo mesmo técnico no dia.', jsonb_build_object('quantidade', n, 'nome', c.solicitante_nome));
    end if;
  end if;
  select count(*) into n from chamados.eventos where chamado_id = c.id and acao = 'reaberto';
  if n >= (s->>'reaberturas')::int then
    perform chamados.gam_suspeitar(c.responsavel_id, c.id, 'reabre_fecha', 'Chamado reaberto ' || n || ' vezes.', jsonb_build_object('reaberturas', n));
  end if;
  return chamados.gam_tem_suspeita(c.responsavel_id, c.id);
end $fn$;

-- Notion: quem escolhe Responsável/Contribuintes direto no Notion também aparece na coluna de cada pessoa do
-- quadro da equipe (23/11/2026). O agendador (push_agendar, 1 min) passa a chamar a Edge Function chamados-notion
-- a cada 2 minutos mesmo sem fila; ela acerta a coluna "Equipe" das páginas editadas nos últimos minutos.
-- Única mudança na função: a condição do bloco do Notion. Feita por substituição no texto da função em uso
-- (o corpo em produção difere do arquivo só em comentários), conferindo que o trecho aparece uma única vez.
do $do$
declare
  d text := pg_get_functiondef('chamados.push_agendar()'::regprocedure);
  antigo text := 'if chamados.notion_ativo() and exists (select 1 from chamados.notion_envios';
  novo text := 'if chamados.notion_ativo() and (extract(minute from v_agora)::int % 2 = 0 or exists (select 1 from chamados.notion_envios';
  fim_antigo text := E'interval ''2 minutes'')) then\n    perform chamados.notion_disparar();';
  fim_novo text := E'interval ''2 minutes''))) then\n    perform chamados.notion_disparar();';
begin
  if (length(d) - length(replace(d, antigo, ''))) / length(antigo) <> 1
     or (length(d) - length(replace(d, fim_antigo, ''))) / length(fim_antigo) <> 1 then
    raise exception 'push_agendar: trecho do Notion não encontrado (ou repetido); nada foi alterado.';
  end if;
  execute replace(replace(d, antigo, novo), fim_antigo, fim_novo);
end $do$;

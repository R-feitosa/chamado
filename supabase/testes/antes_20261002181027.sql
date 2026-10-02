-- Chamados no formato antigo (3 níveis), para testar o de-para da urgência.
insert into chamados.chamados (protocolo, descricao, solicitante_id, sistema_id, urgencia)
select 'LEGADO-' || u, 'legado', (select id from chamados.pessoas where nome = 'Tamira'), 1, u
from generate_series(0, 2) u;

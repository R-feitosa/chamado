-- ============================================================================
-- "Outro / não sei" também no bloco Suporte técnico (pedido do Roneely, 05/10)
-- ----------------------------------------------------------------------------
-- O nome é único na tabela e "Outro / não sei" já existe no bloco Sistemas;
-- o sufixo "(suporte)" separa os dois no Painel e no Analytics.
-- Prazos: os de Suporte técnico (chamados.prazos, grupo 'suporte').
-- ============================================================================
insert into chamados.sistemas (id, nome, ordem, ativo, grupo)
select coalesce(max(id), 0) + 1, 'Outro / não sei (suporte)', 98, true, 'suporte'
  from chamados.sistemas
having not exists (select 1 from chamados.sistemas where nome = 'Outro / não sei (suporte)');

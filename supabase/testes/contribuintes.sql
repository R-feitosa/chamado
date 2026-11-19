-- Testes de contribuintes (até 3 pessoas por chamado) e do reflexo no Notion. Rodam depois de notion.sql.
\set ON_ERROR_STOP on
create function pg_temp.como(u text) returns void language sql as $$ select set_config('teste.uid', u, false) $$;
create function pg_temp.falha(sqltxt text, trecho text) returns void language plpgsql as $f$
begin
  begin execute sqltxt; exception when others then
    if position(trecho in sqlerrm) = 0 then raise exception 'Erro inesperado em [%]: %', sqltxt, sqlerrm; end if;
    return;
  end;
  raise exception 'Deveria ter falhado: %', sqltxt;
end $f$;
create function pg_temp.checa(cond boolean, msg text) returns void language plpgsql as $f$
begin if cond is not true then raise exception 'FALHOU: %', msg; end if; end $f$;
create temp table x (chave text primary key, valor text);
grant select, insert, update on x to anon, authenticated, service_role;
create function pg_temp.v(k text) returns text language sql as $f$ select valor from x where chave = k $f$;
create function pg_temp.ch() returns uuid language sql security definer as $f$ select id from chamados.chamados where protocolo = (select valor from x where chave = 'p') $f$;
create function pg_temp.pid(n text) returns uuid language sql security definer as $f$ select id from chamados.pessoas where nome = n $f$;
create function pg_temp.st(n text) returns text language sql security definer as $f$
  select status::text from chamados.colaboracoes where chamado_id = pg_temp.ch() and ajudante_id = pg_temp.pid(n) $f$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
insert into x select 'seg', decrypted_secret from vault.decrypted_secrets where name = 'chamados_notion_dispatch_secret';
update chamados.configuracao set valor = 'true' where chave = 'notion_ativo';
-- Kaio: 0b · Aldo Júnior: 0c · Roneely (gestor): 0a

set role anon; select pg_temp.como('');
insert into x select 'p', chamados.abrir_chamado_publico(4, null, 'Pessoa Contribuintes', 'Analista', 1, 'Precisa de três pessoas', 1)->>'protocolo';
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select pg_temp.falha($$select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Aldo Júnior'))$$, 'Só o responsável ou o gestor');
select chamados.assumir_chamado(pg_temp.ch());
select pg_temp.falha($$select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Kaio'))$$, 'Escolha um colega');
-- 1. Responsável adiciona direto (sem aceite).
select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Aldo Júnior'));
select pg_temp.falha($$select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Aldo Júnior'))$$, 'já é contribuinte');
-- 2. Outro dev (não responsável) não adiciona.
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select pg_temp.falha($$select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Ruan'))$$, 'Só o responsável ou o gestor');
-- Contribuinte escreve no chat.
select chamados.chat_enviar_time(pg_temp.ch(), 'Entrei como contribuinte.');
-- 3. Gestor adiciona o terceiro; o quarto passa do limite.
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Ruan'));
select pg_temp.falha($$select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('João Pedro'))$$, 'Limite de 3 pessoas');
reset role;
select pg_temp.checa(pg_temp.st('Aldo Júnior') = 'confirmada' and pg_temp.st('Ruan') = 'confirmada', 'entram confirmados');
select pg_temp.checa(exists (select 1 from chamados.gam_eventos where tipo = 'collaboration.registered'
  and chave = 'co:' || (select id from chamados.colaboracoes where chamado_id = pg_temp.ch() and ajudante_id = pg_temp.pid('Aldo Júnior'))), 'gamificação registra a colaboração');

-- 4. Notion: a tarefa leva os contribuintes.
set role service_role;
insert into x select 'lote', chamados.notion_lote(pg_temp.v('seg'))::text;
reset role;
do $$ declare i jsonb := (select e from jsonb_array_elements((pg_temp.v('lote'))::jsonb->'itens') e where e->>'protocolo' = pg_temp.v('p')); begin
  perform pg_temp.checa(i->>'responsavel' = 'KAIO', 'responsável');
  perform pg_temp.checa(i->'contribuintes' = '["ALDO", "RUAN"]'::jsonb, 'contribuintes: ' || coalesce((i->'contribuintes')::text, 'nulo'));
  insert into x values ('ids', (i->'envio_ids')::text);
end $$;
set role service_role;
select chamados.notion_confirmar(pg_temp.v('seg'), jsonb_build_array(jsonb_build_object('ok', true, 'chamado_id', pg_temp.ch(),
  'page_id', 'pagina-contrib', 'envio_ids', (pg_temp.v('ids'))::jsonb)));
reset role;

-- 5. Contribuinte sai sozinho; mudar contribuintes reenvia a tarefa ao Notion.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.remover_contribuinte(pg_temp.ch(), pg_temp.pid('Aldo Júnior'));
select pg_temp.falha($$select chamados.chat_enviar_time(pg_temp.ch(), 'saí')$$, 'Só o responsável e quem ajuda');
reset role;
select pg_temp.checa(pg_temp.st('Aldo Júnior') = 'recusada', 'removido');
select pg_temp.checa((select count(*) from chamados.notion_envios where chamado_id = pg_temp.ch() and enviado_em is null) = 1, 'remoção reenvia ao Notion');
set role service_role;
select pg_temp.checa((select e->'contribuintes' from jsonb_array_elements(chamados.notion_lote(pg_temp.v('seg'))->'itens') e
  where e->>'protocolo' = pg_temp.v('p')) = '["RUAN"]'::jsonb, 'Notion fica só com quem ficou');
reset role;
-- 6. Pode voltar; o outro dev não remove ninguém; resolvido trava.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Aldo Júnior'));
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select pg_temp.falha($$select chamados.remover_contribuinte(pg_temp.ch(), pg_temp.pid('Ruan'))$$, 'Só o responsável, o gestor ou o próprio');
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.resolver_chamado(pg_temp.ch());
select pg_temp.falha($$select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('João Pedro'))$$, 'em andamento');
select pg_temp.falha($$select chamados.remover_contribuinte(pg_temp.ch(), pg_temp.pid('Ruan'))$$, 'ficam registrados');
reset role;
select pg_temp.checa(pg_temp.st('Aldo Júnior') = 'confirmada', 'voltou como contribuinte');
set role anon;
select pg_temp.falha($$select chamados.adicionar_contribuinte(pg_temp.ch(), pg_temp.pid('Ruan'))$$, 'permission denied');
reset role;
-- 7. Fluxo antigo "Ajuda" (pedido + aceite) também vai para o Notion quando o colega aceita.
set role anon; select pg_temp.como('');
insert into x select 'p2', chamados.abrir_chamado_publico(4, null, 'Pessoa Ajuda', 'Analista', 1, 'Pedido de ajuda antigo', 1)->>'protocolo';
reset role;
create function pg_temp.ch2() returns uuid language sql security definer as $f$ select id from chamados.chamados where protocolo = (select valor from x where chave = 'p2') $f$;
grant execute on function pg_temp.ch2() to authenticated, service_role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.ch2());
reset role;
set role service_role;
insert into x select 'l2', chamados.notion_lote(pg_temp.v('seg'))::text;
select chamados.notion_confirmar(pg_temp.v('seg'), jsonb_build_array(jsonb_build_object('ok', true, 'chamado_id', pg_temp.ch2(),
  'page_id', 'pagina-ajuda', 'envio_ids', (select e->'envio_ids' from jsonb_array_elements((pg_temp.v('l2'))::jsonb->'itens') e where e->>'protocolo' = pg_temp.v('p2')))));
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
-- "Ajuda" entra direto, sem aceite: já é contribuinte e já vai para o Notion.
select chamados.pedir_ajuda(pg_temp.ch2(), pg_temp.pid('Aldo Júnior'));
select pg_temp.falha(format('select chamados.pedir_ajuda(%L, %L)', pg_temp.ch2(), pg_temp.pid('Aldo Júnior')), 'já é contribuinte');
reset role;
select pg_temp.checa((select status::text from chamados.colaboracoes where chamado_id = pg_temp.ch2()) = 'confirmada', 'ajuda sem aceite');
set role service_role;
select pg_temp.checa((select e->'contribuintes' from jsonb_array_elements(chamados.notion_lote(pg_temp.v('seg'))->'itens') e
  where e->>'protocolo' = pg_temp.v('p2')) = '["ALDO"]'::jsonb, 'ajuda aparece no Notion sem aceite');
reset role;
-- Tela antiga: "Vou ajudar" não quebra; "Recusar" = sair do chamado.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.responder_ajuda((select id from chamados.colaboracoes where chamado_id = pg_temp.ch2()), true);
select chamados.responder_ajuda((select id from chamados.colaboracoes where chamado_id = pg_temp.ch2()), false);
reset role;
select pg_temp.checa((select status::text from chamados.colaboracoes where chamado_id = pg_temp.ch2()) = 'recusada', 'recusar = sair');

update chamados.configuracao set valor = 'false' where chave = 'notion_ativo';
\echo CONTRIBUINTES: TODOS OS TESTES PASSARAM

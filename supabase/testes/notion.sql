-- Testes da integração com o Notion (rodam depois de desassumir.sql, no mesmo banco).
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
create function pg_temp.ch(k text) returns uuid language sql security definer as $f$ select id from chamados.chamados where protocolo = (select valor from x where chave = k) $f$;
create function pg_temp.pend(k text) returns bigint language sql security definer as $f$
  select count(*) from chamados.notion_envios where chamado_id = pg_temp.ch(k) and enviado_em is null $f$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
insert into x select 'seg', decrypted_secret from vault.decrypted_secrets where name = 'chamados_notion_dispatch_secret';
-- Kaio: 0b · Aldo Júnior: 0c · Roneely (gestor): 0a

select pg_temp.checa((select notion_responsavel from chamados.pessoas where nome = 'Kaio') = 'KAIO', 'mapeamento Kaio → KAIO');
select pg_temp.checa((select notion_responsavel from chamados.pessoas where nome = 'João Pedro') = 'JOTINHA', 'João Pedro → JOTINHA');
select pg_temp.checa(pg_temp.v('seg') is not null, 'segredo de despacho criado');

-- 1. Desligada: assumir não vai para o Notion.
set role anon; select pg_temp.como('');
insert into x select 'a', chamados.abrir_chamado_publico(4, null, 'Pessoa Notion A', 'Analista', 1, 'Antes de ligar', 1)->>'protocolo';
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.ch('a'));
reset role;
select pg_temp.checa(pg_temp.pend('a') = 0, 'desligada não enfileira');

-- 2. Ligada: assumir cria envio e dispara a Edge Function.
update chamados.configuracao set valor = 'true' where chave = 'notion_ativo';
set role anon; select pg_temp.como('');
insert into x select 'b', chamados.abrir_chamado_publico(4, null, 'Pessoa Notion B', 'Advogada', 3, E'Tela de intimações não carrega\nDesde hoje cedo.', 2)->>'protocolo';
reset role;
select pg_temp.checa(pg_temp.pend('b') = 0, 'abrir não enfileira (só ao assumir)');
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.ch('b'));
reset role;
select pg_temp.checa(pg_temp.pend('b') = 1, 'assumir enfileira');
select pg_temp.checa(exists (select 1 from net.chamadas where url like '%/functions/v1/chamados-notion'
  and headers->>'x-chamados-notion-secret' = pg_temp.v('seg')), 'dispara a Edge Function com o segredo');
-- O chamado antigo (assumido antes de ligar) não entra ao ser resolvido.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.resolver_chamado(pg_temp.ch('a'));
reset role;
select pg_temp.checa(pg_temp.pend('a') = 0, 'chamado de antes de ligar não vai');

-- 3. Lote: só service_role com o segredo; item no formato da base.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select pg_temp.falha($$select chamados.notion_lote('x')$$, 'permission denied');
reset role;
set role service_role;
select pg_temp.falha($$select chamados.notion_lote('errado')$$, 'Segredo de despacho inválido');
insert into x select 'lote1', chamados.notion_lote(pg_temp.v('seg'))::text;
reset role;
do $$ declare i jsonb := (select e from jsonb_array_elements((pg_temp.v('lote1'))::jsonb->'itens') e where e->>'protocolo' = pg_temp.v('b')); begin
  perform pg_temp.checa(((pg_temp.v('lote1'))::jsonb->>'database_id') = '41d4ea8cd78c816085c4f72cce41562e', 'database id');
  perform pg_temp.checa(i->>'responsavel' = 'KAIO' and i->>'status' = 'Em andamento', 'responsável e status: ' || i::text);
  perform pg_temp.checa(i->>'prioridade' = 'P1 · Alta' and i->>'sistema_projeto' is not null, 'prioridade pela urgência');
  perform pg_temp.checa(i->>'descricao' like 'Tela de intimações%' and i->>'titulo' like '%Tela de intimações não carrega', 'descrição e título');
  perform pg_temp.checa(i->>'solicitante' like 'Pessoa Notion B · Advogada%', 'solicitante com cargo e setor');
  perform pg_temp.checa(i->>'ultimo_andamento' like 'Assumido na Central por Kaio', 'último andamento');
  perform pg_temp.checa(jsonb_array_length(i->'envio_ids') = 1, 'ids do envio');
end $$;
set role service_role;
select pg_temp.checa(jsonb_array_length(chamados.notion_lote(pg_temp.v('seg'))->'itens') = 0, 'reservado não volta no lote seguinte');
select chamados.notion_confirmar(pg_temp.v('seg'), jsonb_build_array(jsonb_build_object('ok', true, 'chamado_id', pg_temp.ch('b'),
  'page_id', 'pagina-b', 'envio_ids', ((pg_temp.v('lote1'))::jsonb #> '{itens,0,envio_ids}'))));
reset role;
select pg_temp.checa((select notion_page_id from chamados.chamados where id = pg_temp.ch('b')) = 'pagina-b', 'guarda a página');
select pg_temp.checa(pg_temp.pend('b') = 0, 'envio concluído');

-- 4. Resolver → Concluída, sem descrição de novo.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.resolver_chamado(pg_temp.ch('b'));
reset role;
set role service_role;
insert into x select 'lote2', chamados.notion_lote(pg_temp.v('seg'))::text;
reset role;
do $$ declare i jsonb := (pg_temp.v('lote2'))::jsonb #> '{itens,0}'; begin
  perform pg_temp.checa(i->>'page_id' = 'pagina-b' and i->>'status' = 'Concluída' and i->>'conclusao' is not null, 'concluída: ' || i::text);
  perform pg_temp.checa(i->'descricao' = 'null'::jsonb, 'descrição só na criação');
end $$;
-- Falha: libera para nova tentativa e guarda o erro.
set role service_role;
select chamados.notion_confirmar(pg_temp.v('seg'), jsonb_build_array(jsonb_build_object('ok', false, 'chamado_id', pg_temp.ch('b'),
  'erro', '502: Notion fora do ar', 'envio_ids', ((pg_temp.v('lote2'))::jsonb #> '{itens,0,envio_ids}'))));
reset role;
select pg_temp.checa((select erro from chamados.notion_envios where chamado_id = pg_temp.ch('b') and enviado_em is null) like '502%', 'erro guardado');
set role service_role;
select pg_temp.checa(jsonb_array_length(chamados.notion_lote(pg_temp.v('seg'))->'itens') = 1, 'tenta de novo');
reset role;

-- 5. Assumir e desassumir antes do envio: um envio só, com o estado final (A fazer, sem responsável).
set role anon; select pg_temp.como('');
insert into x select 'c', chamados.abrir_chamado_publico(4, null, 'Pessoa Notion C', 'Analista', 1, 'Desassumir rápido', 0)->>'protocolo';
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.assumir_chamado(pg_temp.ch('c'));
select chamados.desassumir_chamado(pg_temp.ch('c'), 'Engano');
reset role;
select pg_temp.checa(pg_temp.pend('c') = 1, 'eventos seguidos viram um envio');
set role service_role;
insert into x select 'lote3', chamados.notion_lote(pg_temp.v('seg'))::text;
reset role;
do $$ declare i jsonb := (select e from jsonb_array_elements((pg_temp.v('lote3'))::jsonb->'itens') e where e->>'protocolo' = pg_temp.v('c')); begin
  perform pg_temp.checa(i->>'status' = 'A fazer' and i->'responsavel' = 'null'::jsonb and i->>'prioridade' = 'P3 · Baixa', 'desassumido: ' || i::text);
  perform pg_temp.checa(i->>'ultimo_andamento' = 'Devolvido para a fila na Central: Engano', 'andamento do desassumir');
end $$;

-- 6. Agendador do push reenvia pendentes do Notion sem erro.
select chamados.push_agendar();
update chamados.configuracao set valor = 'false' where chave = 'notion_ativo';
\echo NOTION: TODOS OS TESTES PASSARAM

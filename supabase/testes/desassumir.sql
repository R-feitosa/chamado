-- Testes do Desassumir (rodam depois de chat.sql, no mesmo banco).
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
grant select, insert, update on x to anon, authenticated;
create function pg_temp.v(k text) returns text language sql as $f$ select valor from x where chave = k $f$;
create function pg_temp.id() returns uuid language sql security definer as $f$ select id from chamados.chamados where protocolo = (select valor from x where chave = 'prot') $f$;
grant execute on all functions in schema pg_temp to anon, authenticated;
-- Kaio: 0b · Aldo: 0c · Roneely (gestor): 0a

-- Gamificação ligada (a resposta rápida precisa pontuar para testar o estorno).
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select chamados.gam_admin_config('ativo', 'true');
select chamados.gam_admin_config('horas_pendente', '72');
reset role;
-- Os testes anteriores já esgotaram o limite diário de resposta rápida do Kaio.
update chamados.gam_regras set limite_diario = null where codigo = 'resposta_rapida';

-- 1. Chamado público; Kaio assume rápido e ganha "resposta rápida" (pendente).
set role anon; select pg_temp.como('');
insert into x select 'prot', chamados.abrir_chamado_publico(4, null, 'Pessoa Desassumir', 'Analista', 1, 'Tela trava', 2)->>'protocolo';
select pg_temp.falha($$select chamados.desassumir_chamado(pg_temp.id())$$, 'permission denied');
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select pg_temp.falha($$select chamados.desassumir_chamado(pg_temp.id())$$, 'já está sem responsável');
select chamados.assumir_chamado(pg_temp.id());
select chamados.pedir_ajuda(pg_temp.id(), (select id from chamados.pessoas where nome = 'Aldo'));
reset role;
select chamados.gam_ciclo();
select pg_temp.checa(exists (select 1 from chamados.gam_xp where chamado_id = pg_temp.id() and regra_codigo = 'resposta_rapida' and status = 'pendente'), 'resposta rápida pendente');

-- 2. Outro dev não desassume; o responsável sim, com motivo.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select pg_temp.falha($$select chamados.desassumir_chamado(pg_temp.id())$$, 'Só o responsável ou o gestor');
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
insert into x select 'r', chamados.desassumir_chamado(pg_temp.id(), '  Vou ficar fora amanhã  ')::text;
reset role;
select pg_temp.checa((pg_temp.v('r'))::jsonb->>'status' = 'aberto' and (pg_temp.v('r'))::jsonb->'responsavel_id' = 'null'::jsonb
  and (pg_temp.v('r'))::jsonb->'assumido_em' = 'null'::jsonb, 'volta para a fila');
select pg_temp.checa(((pg_temp.v('r'))::jsonb->>'xp_estornado')::int = 5, 'estornou a resposta rápida');
select pg_temp.checa((select status from chamados.gam_xp where chamado_id = pg_temp.id() and regra_codigo = 'resposta_rapida') = 'estornado', 'ledger estornado');
select pg_temp.checa((select status::text from chamados.colaboracoes where chamado_id = pg_temp.id()) = 'recusada', 'pedido de ajuda cancelado');
select pg_temp.checa((select detalhe->>'motivo' from chamados.eventos where chamado_id = pg_temp.id() and acao = 'desassumido') = 'Vou ficar fora amanhã', 'motivo no histórico');
select pg_temp.checa((select prazo_assumir_em from chamados.chamados where id = pg_temp.id()) is not null, 'prazo mantido');

-- 3. Desassumir não vira reabertura na gamificação; reassumir não paga a resposta rápida de novo.
select chamados.gam_ciclo();
select pg_temp.checa(not exists (select 1 from chamados.gam_eventos where chamado_id = pg_temp.id() and tipo = 'ticket.reopened'), 'não é reabertura');
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.id());
reset role;
select chamados.gam_ciclo();
select pg_temp.checa(not exists (select 1 from chamados.gam_xp where chamado_id = pg_temp.id() and regra_codigo = 'resposta_rapida' and status <> 'estornado'), 'sem pagar de novo');

-- 4. Gestor desassume qualquer chamado; sem motivo também vale. Resolvido não desassume.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select chamados.desassumir_chamado(pg_temp.id());
select pg_temp.checa((select responsavel_id from chamados.chamados where id = pg_temp.id()) is null, 'gestor desassumiu');
select pg_temp.checa((select detalhe from chamados.eventos where chamado_id = pg_temp.id() and acao = 'desassumido' order by id desc limit 1) ? 'de', 'histórico guarda quem saiu');
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.assumir_chamado(pg_temp.id());
select chamados.resolver_chamado(pg_temp.id());
select pg_temp.falha($$select chamados.desassumir_chamado(pg_temp.id())$$, 'resolvido não pode ser desassumido');
reset role;
select chamados.gam_ciclo();
select pg_temp.checa((select count(*) from chamados.gam_eventos where status = 'erro') = 0, 'sem erros no motor');
\echo DESASSUMIR: TODOS OS TESTES PASSARAM

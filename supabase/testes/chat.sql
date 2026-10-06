-- Testes do chat descartável (rodam depois de notificacoes.sql, no mesmo banco).
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

-- 1. Abertura sem login devolve o código; a conversa só abre com ele; anon não lê a tabela.
set role anon; select pg_temp.como('');
insert into x select 'ab', chamados.abrir_chamado_publico(4, null, 'Pessoa Chat', 'Analista', 1, 'Erro ao salvar', 2)::text;
insert into x select 'prot', (pg_temp.v('ab'))::jsonb->>'protocolo';
insert into x select 'cod', (pg_temp.v('ab'))::jsonb->>'codigo_avaliacao';
select pg_temp.falha($$select chamados.chat_ler(pg_temp.v('prot'), 'errado')$$, 'Link da conversa inválido');
select pg_temp.falha($$select chamados.chat_enviar(pg_temp.v('prot'), 'errado', 'oi')$$, 'Link da conversa inválido');
select pg_temp.falha($$select count(*) from chamados.chat_mensagens$$, 'permission denied');
select pg_temp.falha($$select chamados.chat_resumo()$$, 'permission denied');
select pg_temp.checa(chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod'))->>'estado' = 'aberto', 'conversa aberta');
select pg_temp.falha($$select chamados.chat_enviar(pg_temp.v('prot'), pg_temp.v('cod'), '   ')$$, 'Escreva uma mensagem');
select chamados.chat_enviar(pg_temp.v('prot'), upper(pg_temp.v('cod')), 'Olá, o botão Salvar dá erro.');
reset role;

-- 2. Push "chat" para o time (sem responsável → devs inscritos), sem o texto.
select pg_temp.checa((select count(*) from chamados.push_envios where tipo = 'chat' and chamado_id = pg_temp.id()) >= 1, 'push de chat enfileirado');
select pg_temp.checa(not exists (select 1 from chamados.push_envios where tipo = 'chat' and payload::text like '%Salvar%'), 'push sem o texto');

-- 3. Antes de assumir, qualquer dev responde; depois, só o responsável e quem ajuda. Gestor só lê.
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000c'); -- Aldo
select chamados.chat_enviar_time(pg_temp.id(), 'Oi! Já vamos olhar.');
select pg_temp.como('00000000-0000-0000-0000-00000000000b'); -- Kaio
select chamados.assumir_chamado(pg_temp.id());
select chamados.chat_enviar_time(pg_temp.id(), 'Assumi. Qual tela?');
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select pg_temp.falha($$select chamados.chat_enviar_time(pg_temp.id(), 'eu de novo')$$, 'Só o responsável e quem ajuda');
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select pg_temp.falha($$select chamados.chat_enviar_time(pg_temp.id(), 'gestor aqui')$$, 'Só o responsável e quem ajuda');
select pg_temp.checa((select count(*) from chamados.chat_mensagens where chamado_id = pg_temp.id()) = 3, 'gestor lê a conversa');
-- Ajuda confirmada libera o colega.
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.pedir_ajuda(pg_temp.id(), (select id from chamados.pessoas where nome = 'Aldo'));
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.responder_ajuda((select id from chamados.colaboracoes where chamado_id = pg_temp.id()), true);
select chamados.chat_enviar_time(pg_temp.id(), 'Ajudando aqui.');
reset role;

-- 4. Quem abriu lê tudo (primeiro nome do time); não lidas do time e marcar como lido.
set role anon; select pg_temp.como('');
select pg_temp.checa(jsonb_array_length(chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod'))->'mensagens') = 4, '4 mensagens');
select pg_temp.checa((chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod')) #>> '{mensagens,2,nome}') = 'Kaio', 'nome do técnico');
select pg_temp.checa(jsonb_array_length(chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod'),
  ((chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod')) #>> '{mensagens,2,id}')::bigint))->'mensagens') = 1, 'só as novas');
select chamados.chat_enviar(pg_temp.v('prot'), pg_temp.v('cod'), 'É a tela de intimações.');
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select pg_temp.checa((chamados.chat_resumo() -> pg_temp.id()::text ->> 'nao_lidas')::int = 1, 'Kaio tem 1 não lida (responder marca como lido)');
select chamados.chat_marcar_lido(pg_temp.id());
select pg_temp.checa((chamados.chat_resumo() -> pg_temp.id()::text ->> 'nao_lidas')::int = 0, 'lidas');
reset role;

-- 5. Resolvido: fecha (só leitura). 24 h depois o texto some (update, sem delete). Reabrir reabre.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.resolver_chamado(pg_temp.id());
reset role;
set role anon; select pg_temp.como('');
select pg_temp.checa(chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod'))->>'estado' = 'fechado', 'fechado ao resolver');
select pg_temp.falha($$select chamados.chat_enviar(pg_temp.v('prot'), pg_temp.v('cod'), 'mais uma')$$, 'encerrada');
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select pg_temp.falha($$select chamados.chat_enviar_time(pg_temp.id(), 'mais uma')$$, 'encerrada');
reset role;
select chamados.push_agendar();
select pg_temp.checa((select count(*) from chamados.chat_mensagens where chamado_id = pg_temp.id() and texto is not null) = 5, 'ainda não apagou (< 24 h)');
update chamados.chamados set resolvido_em = now() - interval '25 hours' where id = pg_temp.id();
select pg_temp.checa((chamados.push_agendar()->>'chat_apagadas')::int = 5, 'apagou as 5 mensagens');
select pg_temp.checa(not exists (select 1 from chamados.chat_mensagens where chamado_id = pg_temp.id() and (texto is not null or apagada_em is null)), 'texto apagado');
set role anon; select pg_temp.como('');
select pg_temp.checa(chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod'))->>'estado' = 'apagado', 'estado apagado');
reset role;
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.reabrir_chamado(pg_temp.id(), 'recorrente', null);
reset role;
set role anon; select pg_temp.como('');
select pg_temp.checa(chamados.chat_ler(pg_temp.v('prot'), pg_temp.v('cod'))->>'estado' = 'aberto', 'reabrir reabre a conversa');
select chamados.chat_enviar(pg_temp.v('prot'), pg_temp.v('cod'), 'Voltou a dar erro.');

-- 6. Limite: 10 mensagens por minuto de quem abriu.
select chamados.chat_enviar(pg_temp.v('prot'), pg_temp.v('cod'), 'msg ' || g) from generate_series(1, 7) g; -- + 3 já enviadas neste minuto = 10
select pg_temp.falha($$select chamados.chat_enviar(pg_temp.v('prot'), pg_temp.v('cod'), 'mais')$$, 'Muitas mensagens');
reset role;
\echo CHAT: TODOS OS TESTES PASSARAM

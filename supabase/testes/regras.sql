-- Testes de permissão e transição. Cada bloco falha com exceção se a regra quebrar.
\set ON_ERROR_STOP on
insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'roneely@teste.com'),
  ('00000000-0000-0000-0000-00000000000b', 'kaio@teste.com'),
  ('00000000-0000-0000-0000-00000000000c', 'aldo@teste.com'),
  ('00000000-0000-0000-0000-00000000000d', 'intruso@teste.com'),
  ('00000000-0000-0000-0000-00000000000e', 'tamira@teste.com');
update chamados.pessoas set email = 'roneely@teste.com' where nome = 'Roneely Feitosa';
update chamados.pessoas set email = 'kaio@teste.com' where nome = 'Kaio';
update chamados.pessoas set email = 'aldo@teste.com' where nome = 'Aldo';
update chamados.pessoas set email = 'tamira@teste.com' where nome = 'Tamira';

create function pg_temp.como(u text) returns void language sql as $$ select set_config('teste.uid', u, false) $$;
create function pg_temp.espera_erro(sqltxt text, trecho text) returns void language plpgsql as $$
begin
  begin execute sqltxt; exception when others then
    if position(trecho in sqlerrm) = 0 then raise exception 'Erro inesperado em [%]: %', sqltxt, sqlerrm; end if;
    raise notice 'ok (bloqueado): %', trecho; return;
  end;
  raise exception 'Deveria ter falhado: %', sqltxt;
end $$;
grant execute on all functions in schema pg_temp to authenticated;

set role authenticated;

-- 1. Intruso (e-mail não cadastrado) não vincula e não vê nada
select pg_temp.como('00000000-0000-0000-0000-00000000000d');
do $$ begin
  if (chamados.vincular_minha_conta()) is not null then raise exception 'intruso vinculou'; end if;
  if (select count(*) from chamados.pessoas) <> 0 then raise exception 'intruso vê pessoas'; end if;
  if (select count(*) from chamados.sistemas) <> 0 then raise exception 'intruso vê sistemas'; end if;
end $$;
select pg_temp.espera_erro($$select chamados.abrir_chamado(1, 'x', 0)$$, 'não está liberado');

-- 2. Vínculos
select pg_temp.como('00000000-0000-0000-0000-00000000000a'); select chamados.vincular_minha_conta()->>'nome';
select pg_temp.como('00000000-0000-0000-0000-00000000000b'); select chamados.vincular_minha_conta()->>'nome';
select pg_temp.como('00000000-0000-0000-0000-00000000000c'); select chamados.vincular_minha_conta()->>'nome';
select pg_temp.como('00000000-0000-0000-0000-00000000000e'); select chamados.vincular_minha_conta()->>'nome';

-- 3. Solicitante abre chamado; protocolo vem do banco
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
do $$ declare c chamados.chamados; begin
  c := jsonb_populate_record(null::chamados.chamados, chamados.abrir_chamado(1, '  Tela de intimações vazia  ', 2, array['00000000-0000-0000-0000-00000000000a/p1.png']));
  if c.protocolo <> 'TI-0421' then raise exception 'protocolo %', c.protocolo; end if;
  if c.descricao <> 'Tela de intimações vazia' then raise exception 'trim'; end if;
  c := jsonb_populate_record(null::chamados.chamados, chamados.abrir_chamado(2, 'CRM lento', 0));
  if c.protocolo <> 'TI-0422' then raise exception 'protocolo2 %', c.protocolo; end if;
end $$;
select pg_temp.espera_erro($$select chamados.abrir_chamado(1, 'x', 0, array['outro-usuario/p.png'])$$, 'Print inválido');
select pg_temp.espera_erro($$select chamados.abrir_chamado(1, '   ', 0)$$, 'chamados_descricao_check');
select pg_temp.espera_erro($$select chamados.abrir_chamado(1, 'x', 3)$$, 'chamados_urgencia_check');
select pg_temp.espera_erro($$select chamados.abrir_chamado(1, 'x', 0, array['00000000-0000-0000-0000-00000000000a/1','00000000-0000-0000-0000-00000000000a/2','00000000-0000-0000-0000-00000000000a/3','00000000-0000-0000-0000-00000000000a/4'])$$, 'chamados_prints_check');
-- Escrita direta é proibida
select pg_temp.espera_erro($$update chamados.chamados set status = 'resolvido'$$, 'permission denied');
select pg_temp.espera_erro($$insert into chamados.chamados (descricao, solicitante_id, sistema_id, urgencia) values ('x', chamados.eu_pessoa_id(), 1, 0)$$, 'permission denied');
-- Solicitante não assume
select pg_temp.espera_erro($$select chamados.assumir_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))$$, 'Só o time');

-- 4. Outro solicitante não vê chamados alheios
select pg_temp.como('00000000-0000-0000-0000-00000000000e');
do $$ begin if (select count(*) from chamados.chamados) <> 0 then raise exception 'Tamira vê chamados do Roneely'; end if; end $$;

-- 5. Dev vê tudo, assume; segundo dev não consegue assumir nem resolver
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
do $$ begin if (select count(*) from chamados.chamados) <> 2 then raise exception 'Kaio não vê tudo'; end if; end $$;
select chamados.assumir_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))->>'status';
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select pg_temp.espera_erro($$select chamados.assumir_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))$$, 'já foi assumido');
select pg_temp.espera_erro($$select chamados.resolver_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))$$, 'Só o responsável');
select pg_temp.espera_erro($$select chamados.reabrir_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))$$, 'não está resolvido');

-- 6. Responsável resolve; qualquer dev reabre; histórico registra tudo
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.resolver_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))->>'status';
select pg_temp.espera_erro($$select chamados.assumir_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))$$, 'já foi assumido');
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.reabrir_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))->>'status';
do $$ declare a text; begin
  select string_agg(acao::text, ',' order by e.id) into a from chamados.eventos e join chamados.chamados c on c.id = e.chamado_id where c.protocolo = 'TI-0421';
  if a <> 'aberto,assumido,resolvido,reaberto' then raise exception 'histórico %', a; end if;
end $$;

-- 7. Solicitante vê o próprio histórico, intruso não
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
do $$ begin if (select count(*) from chamados.eventos) <> 5 then raise exception 'Roneely não vê histórico'; end if; end $$;

-- 8. Storage: grava só na própria pasta; dev lê, outro solicitante não
insert into storage.objects (bucket_id, name) values ('chamados-prints', '00000000-0000-0000-0000-00000000000a/p1.png');
select pg_temp.espera_erro($$insert into storage.objects (bucket_id, name) values ('chamados-prints', '00000000-0000-0000-0000-00000000000b/p.png')$$, 'row-level security');
select pg_temp.como('00000000-0000-0000-0000-00000000000e');
do $$ begin if (select count(*) from storage.objects) <> 0 then raise exception 'Tamira vê prints alheios'; end if; end $$;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
do $$ begin if (select count(*) from storage.objects) <> 1 then raise exception 'dev não vê prints'; end if; end $$;
select pg_temp.como('00000000-0000-0000-0000-00000000000d');
select pg_temp.espera_erro($$insert into storage.objects (bucket_id, name) values ('chamados-prints', '00000000-0000-0000-0000-00000000000d/p.png')$$, 'row-level security');

-- 9. anon não acessa nada
reset role; set role anon;
select pg_temp.espera_erro($$select * from chamados.chamados$$, 'permission denied');
select pg_temp.espera_erro($$select chamados.vincular_minha_conta()$$, 'permission denied');
reset role;
-- 10. E-mail e vínculo das pessoas não são legíveis pelo front
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
set role authenticated;
select pg_temp.espera_erro($$select email from chamados.pessoas$$, 'permission denied');
select pg_temp.espera_erro($$select * from chamados.pessoas$$, 'permission denied');
do $$ begin if (select count(*) from (select id, nome, papel from chamados.pessoas) x) <> 22 then raise exception 'colunas públicas'; end if; end $$;

-- 11. Print já usado em chamado não pode ser apagado; órfão do próprio usuário pode
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
insert into storage.objects (bucket_id, name) values ('chamados-prints', '00000000-0000-0000-0000-00000000000a/orfao.png');
do $$ declare n int; begin
  delete from storage.objects where name = '00000000-0000-0000-0000-00000000000a/p1.png'; get diagnostics n = row_count;
  if n <> 0 then raise exception 'apagou print em uso'; end if;
  delete from storage.objects where name = '00000000-0000-0000-0000-00000000000a/orfao.png'; get diagnostics n = row_count;
  if n <> 1 then raise exception 'não apagou órfão'; end if;
end $$;
reset role;
\echo TODOS OS TESTES PASSARAM

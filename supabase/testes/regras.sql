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
select pg_temp.espera_erro($$select chamados.abrir_chamado(1, 'x', 4)$$, 'Urgência inválida');
-- Prazos: desenvolvimento muito urgente = assumir 30 min / resolver 2 h; suporte não urgente = 8 h / 48 h
do $$ declare c chamados.chamados; begin
  c := jsonb_populate_record(null::chamados.chamados, chamados.abrir_chamado(1, 'ATLAS JURIS fora do ar', 3));
  if c.prazo_assumir_em - c.criado_em <> interval '30 minutes' or c.prazo_em - c.criado_em <> interval '2 hours' then raise exception 'prazo dev muito urgente'; end if;
  c := jsonb_populate_record(null::chamados.chamados, chamados.abrir_chamado(14, 'Impressora', 0));
  if c.prazo_assumir_em - c.criado_em <> interval '8 hours' or c.prazo_em - c.criado_em <> interval '48 hours' then raise exception 'prazo suporte não urgente'; end if;
  if (select count(*) from chamados.urgencias) <> 4 or (select count(*) from chamados.prazos) <> 8 then raise exception 'solicitante não lê urgências/prazos'; end if;
  if (select count(*) from chamados.sistemas where grupo = 'suporte') <> 3 then raise exception 'suporte técnico'; end if;
end $$;
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
do $$ begin if (select count(*) from chamados.chamados) <> 4 then raise exception 'Kaio não vê tudo'; end if; end $$;
do $$ begin if (select assumido_em from chamados.chamados where protocolo = 'TI-0421') is not null then raise exception 'assumido_em antes de assumir'; end if; end $$;
select chamados.assumir_chamado((select id from chamados.chamados where protocolo = 'TI-0421'))->>'status';
do $$ begin if (select assumido_em from chamados.chamados where protocolo = 'TI-0421') is null then raise exception 'assumido_em não gravado'; end if; end $$;
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
do $$ begin if (select count(*) from chamados.eventos) <> 7 then raise exception 'Roneely não vê histórico'; end if; end $$;

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
-- 12. Abertura sem login (anon)
reset role;
insert into chamados.pessoas (nome, setor_id, papel, ativo) values ('Inativo Teste', 4, 'solicitante', false);
set role anon;
select pg_temp.como('');
create function pg_temp.falha(sqltxt text, trecho text) returns void language plpgsql as $f$
begin
  begin execute sqltxt; exception when others then
    if position(trecho in sqlerrm) = 0 then raise exception 'Erro inesperado: %', sqlerrm; end if;
    raise notice 'ok (bloqueado): %', trecho; return;
  end;
  raise exception 'Deveria ter falhado: %', sqltxt;
end $f$;
do $$ declare cat jsonb; tam uuid; aldo uuid; ina uuid; c jsonb; i int; begin
  cat := chamados.catalogo_publico();
  if jsonb_array_length(cat->'pessoas') <> 16 then raise exception 'catálogo deve ter os 16 solicitantes ativos: %', jsonb_array_length(cat->'pessoas'); end if;
  if (cat->'pessoas'->0) ? 'email' then raise exception 'catálogo expõe e-mail'; end if;
  if jsonb_array_length(cat->'prazos') <> 8 or jsonb_array_length(cat->'sistemas') <> 15 then raise exception 'catálogo incompleto'; end if;
  select (p->>'id')::uuid into tam from jsonb_array_elements(cat->'pessoas') p where p->>'nome' = 'Tamira';
  -- ids de dev e de inativo (lidos como superusuário no reset abaixo seriam outra sessão; aqui vêm de função própria)
  c := chamados.abrir_chamado_publico(tam, 13, 'Sem login: notebook', 1, array['publico/0b5f8e1e-1111-4a2b-9c3d-000000000001.png']);
  if c->>'protocolo' is null or (c ? 'descricao') then raise exception 'retorno público'; end if;
  if (c->>'prazo_assumir_em')::timestamptz - (c->>'criado_em')::timestamptz <> interval '4 hours' then raise exception 'prazo suporte meio urgente'; end if;
  c := chamados.consultar_chamado(' ' || lower(c->>'protocolo') || ' ');
  if c->>'status' <> 'aberto' or (c ? 'descricao') or (c ? 'prints') or c->>'sistema' <> 'Computador / notebook' then raise exception 'consulta: %', c; end if;
  if chamados.consultar_chamado('TI-9999') is not null then raise exception 'consulta inexistente'; end if;
  perform pg_temp.falha(format('select chamados.abrir_chamado_publico(%L, 1, %L, 0, array[%L])', tam, 'x', 'publico/0b5f8e1e-1111-4a2b-9c3d-000000000001.png'), 'Print inválido');
  perform pg_temp.falha(format('select chamados.abrir_chamado_publico(%L, 1, %L, 0, array[%L])', tam, 'x', '00000000-0000-0000-0000-00000000000a/p1.png'), 'Print inválido');
  for i in 1..4 loop perform chamados.abrir_chamado_publico(tam, 1, 'spam ' || i, 0); end loop;
  perform pg_temp.falha(format('select chamados.abrir_chamado_publico(%L, 1, %L, 0)', tam, 'sexto'), 'Muitos chamados');
end $$;
reset role;
select pg_temp.como('');
create temp table ids as select (select id from chamados.pessoas where nome = 'Aldo') aldo, (select id from chamados.pessoas where nome = 'Inativo Teste') ina;
grant select on ids to anon;
set role anon;
select pg_temp.falha(format('select chamados.abrir_chamado_publico(%L, 1, %L, 0)', (select aldo from ids), 'x'), 'Escolha seu nome');
select pg_temp.falha(format('select chamados.abrir_chamado_publico(%L, 1, %L, 0)', (select ina from ids), 'x'), 'Escolha seu nome');
select pg_temp.falha($q$select count(*) from chamados.chamados$q$, 'permission denied');
select pg_temp.falha($q$select count(*) from chamados.pessoas$q$, 'permission denied');
select pg_temp.falha($q$select chamados.abrir_chamado(1, 'x', 0)$q$, 'permission denied');
-- Storage sem login: só publico/<uuid>.<ext>
insert into storage.objects (bucket_id, name) values ('chamados-prints', 'publico/0b5f8e1e-1111-4a2b-9c3d-000000000002.jpg');
select pg_temp.falha($q$insert into storage.objects (bucket_id, name) values ('chamados-prints', 'publico/../x.png')$q$, 'row-level security');
select pg_temp.falha($q$insert into storage.objects (bucket_id, name) values ('chamados-prints', '00000000-0000-0000-0000-00000000000a/x.png')$q$, 'row-level security');
do $$ begin if (select count(*) from storage.objects) <> 0 then raise exception 'anon lê prints'; end if; end $$;
reset role;
-- Dev logado lê o print público
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
do $$ begin if not exists (select 1 from storage.objects where name like 'publico/%') then raise exception 'dev não lê print público'; end if; end $$;
reset role;
\echo TODOS OS TESTES PASSARAM

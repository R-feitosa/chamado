-- Testes das notificações push (rodam depois de gamificacao.sql, no mesmo banco).
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
create function pg_temp.envios(prot text, tipo text, nome text default null) returns integer language sql as $f$
  select count(*)::int from chamados.push_envios e join chamados.chamados c on c.id = e.chamado_id join chamados.pessoas p on p.id = e.pessoa_id
   where c.protocolo = prot and e.tipo = $2 and ($3 is null or p.nome = $3) and e.cancelado_em is null $f$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
create temp table n (chave text primary key, valor text);
grant select, insert, update on n to anon, authenticated;
-- Chaves de teste no formato real (base64url).
create function pg_temp.chave(len int, semente text) returns text language sql security definer as $f$
  select left(translate(encode(extensions.digest(semente, 'sha512') || extensions.digest(semente || 'x', 'sha512'), 'base64'), '+/=' || chr(10), '-_'), len) $f$;
grant execute on function pg_temp.chave(int, text) to authenticated;

-- 0. Segredo de despacho criado pela migration; nenhum chamado antigo fica pendente.
select pg_temp.checa(exists (select 1 from vault.secrets where name = 'chamados_push_dispatch_secret'), 'segredo de despacho no Vault');
update chamados.chamados set status = 'resolvido', responsavel_id = coalesce(responsavel_id, (select id from chamados.pessoas where nome = 'Kaio')),
       resolvido_em = coalesce(resolvido_em, now()), assumido_em = coalesce(assumido_em, now()) where status <> 'resolvido';

-- 1. Permissões: anon e solicitante fora; endpoint fora dos push services oficiais é recusado.
set role anon;
select pg_temp.falha($$select chamados.push_config()$$, 'permission denied');
select pg_temp.falha($$select chamados.push_lote('x')$$, 'permission denied');
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000e'); -- Tamira (solicitante)
select pg_temp.falha($$select chamados.push_config()$$, 'só para o time');
select pg_temp.como('00000000-0000-0000-0000-00000000000b'); -- Kaio
select pg_temp.falha($$select chamados.push_inscrever('https://evil.example.com/x', pg_temp.chave(87, 'k'), pg_temp.chave(22, 'k'))$$, 'push_inscricoes_endpoint_check');
select pg_temp.falha($$select chamados.push_lote('x')$$, 'permission denied');
select pg_temp.falha($$select count(*) from chamados.push_inscricoes$$, 'permission denied');
select chamados.push_inscrever('https://fcm.googleapis.com/fcm/send/kaio-1', pg_temp.chave(87, 'kaio'), pg_temp.chave(22, 'kaio'), 'teste');
select pg_temp.checa((chamados.push_config()->>'aparelhos')::int = 1, 'config conta o aparelho');
select pg_temp.checa(jsonb_array_length(chamados.push_config()->'regras') = 4, 'config devolve as 4 regras');
select pg_temp.como('00000000-0000-0000-0000-00000000000c'); -- Aldo
select chamados.push_inscrever('https://web.push.apple.com/aldo-1', pg_temp.chave(87, 'aldo'), pg_temp.chave(22, 'aldo'));
select pg_temp.como('00000000-0000-0000-0000-00000000000a'); -- Roneely (gestor)
select chamados.push_inscrever('https://updates.push.services.mozilla.com/wpush/v2/ron', pg_temp.chave(87, 'ron'), pg_temp.chave(22, 'ron'));
reset role;

-- 2. Abertura (sem login, muito urgente): aviso imediato para os devs inscritos, não para o gestor; chama a Edge Function.
delete from net.chamadas where true;
set role anon; select pg_temp.como('');
insert into n select 'mu', chamados.abrir_chamado_publico(4, null, 'Pessoa Push Um', 'Analista', 1, 'Sistema fora do ar', 3)->>'protocolo';
reset role;
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'novo') = 2, 'novo para Kaio e Aldo');
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'novo', 'Roneely Feitosa') = 0, 'gestor não recebe o novo');
select pg_temp.checa((select count(*) from net.chamadas where url like '%/functions/v1/chamados-push' and headers ? 'x-chamados-push-secret') = 1, 'disparou a Edge Function');
select pg_temp.checa((select payload->>'titulo' from chamados.push_envios where tipo = 'novo' order by id desc limit 1) like '%Novo chamado · Muito urgente', 'título do aviso');
select pg_temp.checa((select payload ? 'descricao' or payload::text like '%fora do ar%' from chamados.push_envios where tipo = 'novo' order by id desc limit 1) = false, 'payload sem descrição');

-- 3. Lembretes a cada 5 min (muito urgente): 12 min sem responsável → seq 2; rodar de novo não duplica.
update chamados.chamados set criado_em = now() - interval '12 minutes', prazo_assumir_em = now() + interval '18 minutes' where protocolo = (select valor from n where chave = 'mu');
select chamados.push_agendar(); select chamados.push_agendar();
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'lembrete') = 2, 'um lembrete por dev');
select pg_temp.checa((select max(seq) from chamados.push_envios where tipo = 'lembrete') = 2, 'sequência 2 aos 12 min');
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'escalada_gestor') = 0, 'ainda dentro do prazo de assumir');

-- 4. Prazo de assumir vencido → escalada ao gestor, uma vez.
update chamados.chamados set criado_em = now() - interval '41 minutes', prazo_assumir_em = now() - interval '11 minutes' where protocolo = (select valor from n where chave = 'mu');
select chamados.push_agendar(); select chamados.push_agendar();
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'escalada_gestor', 'Roneely Feitosa') = 1, 'escalada ao gestor 1×');
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'lembrete') = 4, 'lembrete seq 8 para os 2 devs');

-- 5. Kaio assume: avisos pendentes de "assumir" são cancelados e os lembretes param.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado((select id from chamados.chamados where protocolo = (select valor from n where chave = 'mu')));
reset role;
update chamados.chamados set criado_em = now() - interval '60 minutes' where protocolo = (select valor from n where chave = 'mu');
select chamados.push_agendar();
select pg_temp.checa((select count(*) from chamados.push_envios e join chamados.chamados c on c.id = e.chamado_id
                      where c.protocolo = (select valor from n where chave = 'mu') and e.tipo in ('novo', 'lembrete', 'escalada_gestor')
                        and e.enviado_em is null and e.cancelado_em is null) = 0, 'pendentes cancelados ao assumir');
select pg_temp.checa((select max(seq) from chamados.push_envios where tipo = 'lembrete') = 8, 'sem lembrete novo depois de assumir');

-- 6. Prazo de resolver: perto (últimos 25%) e vencido, só para o responsável, uma vez cada.
update chamados.chamados set prazo_em = now() + interval '5 minutes' where protocolo = (select valor from n where chave = 'mu');
select chamados.push_agendar(); select chamados.push_agendar();
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'prazo_perto', 'Kaio') = 1, 'prazo perto para o responsável');
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'prazo_perto', 'Aldo') = 0, 'só o responsável');
update chamados.chamados set prazo_em = now() - interval '1 minute' where protocolo = (select valor from n where chave = 'mu');
select chamados.push_agendar(); select chamados.push_agendar();
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'mu'), 'prazo_vencido', 'Kaio') = 1, 'prazo vencido 1×');

-- 7. Expediente: meio urgente só lembra no expediente; muito urgente lembra a qualquer hora.
update chamados.gam_config set valor = '{"dias": [], "inicio": "08:00", "fim": "18:00"}' where chave = 'expediente';
set role anon; select pg_temp.como('');
insert into n select 'me', chamados.abrir_chamado_publico(4, null, 'Pessoa Push Dois', 'Analista', 1, 'Lento', 1)->>'protocolo';
insert into n select 'm2', chamados.abrir_chamado_publico(4, null, 'Pessoa Push Tres', 'Analista', 1, 'Parado', 3)->>'protocolo';
reset role;
update chamados.chamados set criado_em = now() - interval '70 minutes' where protocolo in ((select valor from n where chave = 'me'), (select valor from n where chave = 'm2'));
select chamados.push_agendar();
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'me'), 'lembrete') = 0, 'meio urgente não lembra fora do expediente');
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'm2'), 'lembrete') = 2, 'muito urgente lembra fora do expediente');
update chamados.gam_config set valor = '{"dias": [1, 2, 3, 4, 5, 6, 7], "inicio": "00:00", "fim": "24:00"}' where chave = 'expediente';
select chamados.push_agendar();
select pg_temp.checa(pg_temp.envios((select valor from n where chave = 'me'), 'lembrete') = 2, 'meio urgente lembra no expediente (seq 1)');
update chamados.gam_config set valor = '{"dias": [1, 2, 3, 4, 5], "inicio": "08:00", "fim": "18:00"}' where chave = 'expediente';

-- 8. Edge Function: só com o segredo; gera VAPID uma vez; lote reserva e confirma.
insert into n select 'seg', decrypted_secret from vault.decrypted_secrets where name = 'chamados_push_dispatch_secret';
grant select, insert on n to service_role;
set role service_role;
select pg_temp.falha($$select chamados.push_lote('errado')$$, 'Segredo de despacho inválido');
select pg_temp.checa((chamados.push_lote((select valor from n where chave = 'seg'))->'vapid') = 'null'::jsonb, 'sem VAPID antes do primeiro envio');
reset role;
update chamados.push_envios set reservado_em = null where true;
set role service_role;
select pg_temp.falha($$select chamados.push_salvar_vapid((select valor from n where chave = 'seg'), 'curta', 'curta')$$, 'malformado');
select chamados.push_salvar_vapid((select valor from n where chave = 'seg'), pg_temp.chave(87, 'pub'), pg_temp.chave(43, 'priv'));
select chamados.push_salvar_vapid((select valor from n where chave = 'seg'), pg_temp.chave(87, 'outra'), pg_temp.chave(43, 'outra'));
insert into n select 'lote', chamados.push_lote((select valor from n where chave = 'seg'))::text;
reset role;
select pg_temp.checa((select count(*) from vault.secrets where name like 'chamados_push_vapid_%') = 2, 'par VAPID salvo uma vez');
select pg_temp.checa(((select valor from n where chave = 'lote')::jsonb #>> '{vapid,publicKey}') = pg_temp.chave(87, 'pub'), 'mantém o primeiro par');
select pg_temp.checa(jsonb_array_length((select valor from n where chave = 'lote')::jsonb->'envios') > 0, 'lote com envios');
select pg_temp.checa(jsonb_array_length((select valor from n where chave = 'lote')::jsonb #> '{envios,0,inscricoes}') = 1, 'envio leva os aparelhos da pessoa');
set role service_role;
select chamados.push_confirmar((select valor from n where chave = 'seg'),
  (select jsonb_agg(jsonb_build_object('envio_id', (e->>'id')::bigint, 'concluido', true, 'detalhe', '{}'::jsonb))
     from jsonb_array_elements((select valor from n where chave = 'lote')::jsonb->'envios') e),
  array(select id from chamados.push_inscricoes where endpoint like '%kaio%'),
  array(select id from chamados.push_inscricoes where endpoint like '%aldo%'));
reset role;
select pg_temp.checa((select count(*) from chamados.push_envios where enviado_em is not null) > 0, 'confirmados');
select pg_temp.checa((select desativada_em is not null from chamados.push_inscricoes where endpoint like '%aldo%'), 'inscrição expirada (410) desativada');
select pg_temp.checa((select ultimo_envio_em is not null from chamados.push_inscricoes where endpoint like '%kaio%'), 'último envio registrado');

-- 9. Teste do próprio aparelho: 1 por minuto; quem não tem aparelho recebe orientação.
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.push_testar();
select pg_temp.falha($$select chamados.push_testar()$$, 'Aguarde');
select pg_temp.como('00000000-0000-0000-0000-00000000000c'); -- Aldo (inscrição removida)
select pg_temp.falha($$select chamados.push_testar()$$, 'Ative as notificações');
select chamados.push_cancelar('https://fcm.googleapis.com/fcm/send/kaio-1'); -- não é dele: não apaga
reset role;
select pg_temp.checa((select desativada_em is null from chamados.push_inscricoes where endpoint like '%kaio%'), 'não cancela aparelho alheio');
set role authenticated; select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.push_cancelar('https://fcm.googleapis.com/fcm/send/kaio-1');
select pg_temp.checa((chamados.push_config()->>'aparelhos')::int = 0, 'cancelar desativa o aparelho');
select chamados.push_inscrever('https://fcm.googleapis.com/fcm/send/kaio-1', pg_temp.chave(87, 'kaio'), pg_temp.chave(22, 'kaio'));
select pg_temp.checa((chamados.push_config()->>'aparelhos')::int = 1, 'reativar ao inscrever de novo');
reset role;

-- 10. A abertura nunca quebra por causa do push (ex.: regra apagada).
alter table chamados.push_regras disable row level security;
delete from chamados.push_regras where nivel = 0;
set role anon; select pg_temp.como('');
select pg_temp.checa(chamados.abrir_chamado_publico(4, null, 'Pessoa Push Quatro', 'Analista', 1, 'Dúvida', 0)->>'protocolo' is not null, 'abre mesmo sem regra');
reset role;
insert into chamados.push_regras (nivel, repetir_min, so_expediente, vibrar, exigir_interacao) values (0, 240, true, '{120}', false);
alter table chamados.push_regras enable row level security;
\echo NOTIFICACOES: TODOS OS TESTES PASSARAM

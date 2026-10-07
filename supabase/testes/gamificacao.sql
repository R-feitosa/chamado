-- Testes da gamificação (rodam depois de regras.sql, no mesmo banco). Cada bloco falha com exceção se a regra quebrar.
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
create function pg_temp.xp(nome text, st text default 'confirmado') returns integer language sql as $f$
  select coalesce(sum(x.valor), 0)::int from chamados.gam_xp x join chamados.pessoas p on p.id = x.pessoa_id where p.nome = $1 and x.status::text = $2 $f$;
create function pg_temp.ciclo() returns void language sql as $f$ select chamados.gam_ciclo() $f$;
create function pg_temp.ch(p text) returns uuid language sql as $f$ select id from chamados.chamados where protocolo = p $f$;
-- Envelhece um chamado assumido (para não cair na regra de "resolução relâmpago").
create function pg_temp.envelhecer(p text, minutos int) returns void language sql as $f$
  update chamados.chamados set criado_em = criado_em - make_interval(mins => minutos + 5), assumido_em = assumido_em - make_interval(mins => minutos)
   where protocolo = p $f$;
grant execute on all functions in schema pg_temp to anon, authenticated;
create temp table t (chave text primary key, valor text);
grant select, insert, update on t to anon, authenticated;

-- 0. Cadastro: Roneely vira gestor (não pontua). Chave desligada: nada é processado.
update chamados.pessoas set gestor = true where nome = 'Roneely Feitosa';
select pg_temp.checa(not chamados.gam_ativo(), 'começa desligada');

-- 1. Só o gestor liga; liga e registra o lançamento.
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b'); -- Kaio (dev)
select pg_temp.falha($$select chamados.gam_admin_config('ativo', 'true')$$, 'Só o gestor');
select pg_temp.checa((chamados.gam_jornada()->>'ativo')::boolean = false, 'time não vê com a chave desligada');
select pg_temp.como('00000000-0000-0000-0000-00000000000a'); -- Roneely (gestor)
select pg_temp.checa((chamados.vincular_minha_conta()->>'gestor')::boolean, 'vincular devolve gestor');
select chamados.gam_admin_config('ativo', 'true');
select pg_temp.falha($$select chamados.gam_admin_regra('reaberto', 5, true, null, null)$$, 'penalidade negativa');
select pg_temp.falha($$select chamados.gam_admin_config('score_pesos', '{"qualidade": 1}')$$, 'Pesos');
select pg_temp.checa((chamados.gam_jornada()->>'participa')::boolean = false, 'gestor não participa');
select pg_temp.checa((chamados.gam_admin_painel()->'fila') is not null, 'painel do gestor');
reset role;
select pg_temp.checa(chamados.gam_ativo() and chamados.gam_cfg('ligada_em') <> 'null', 'ligada');
-- Lançamento no passado para os chamados envelhecidos continuarem elegíveis.
update chamados.gam_config set valor = to_jsonb(now() - interval '1 day') where chave = 'ligada_em';
select pg_temp.checa((select count(*) from chamados.gam_eventos where status = 'pendente') = 0, 'eventos de antes do lançamento foram ignorados');

-- 2. Abertura sem login devolve código de avaliação; anon não chega no motor.
set role anon;
select pg_temp.como('');
insert into t select 'p1', (chamados.abrir_chamado_publico(4, null, 'Maria Teste', 'Analista', 1, 'P1 muito urgente', 3))::text;
select pg_temp.checa(length((select valor::jsonb->>'codigo_avaliacao' from t where chave = 'p1')) = 24, 'código de avaliação');
select pg_temp.falha($$select chamados.gam_ciclo()$$, 'permission denied');
select pg_temp.falha($$select chamados.gam_jornada()$$, 'permission denied');
select pg_temp.falha($$select count(*) from chamados.gam_xp$$, 'permission denied');
reset role;
update t set valor = valor::jsonb->>'protocolo' || '|' || (valor::jsonb->>'codigo_avaliacao') where chave = 'p1';

-- 3. Kaio assume e resolve um muito urgente dentro do SLA: base × 2,0 + SLA + crítico + resposta rápida.
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.ch(split_part((select valor from t where chave = 'p1'), '|', 1)));
reset role;
select pg_temp.envelhecer(split_part((select valor from t where chave = 'p1'), '|', 1), 20);
update chamados.chamados set assumido_em = criado_em + interval '4 minutes' where protocolo = split_part((select valor from t where chave = 'p1'), '|', 1);
set role authenticated;
select chamados.resolver_chamado(pg_temp.ch(split_part((select valor from t where chave = 'p1'), '|', 1)));
reset role;
select pg_temp.ciclo();
do $$ begin
  perform pg_temp.checa(pg_temp.xp('Kaio', 'pendente') = 40 + 10 + 30 + 5, 'XP pendente do P1: ' || pg_temp.xp('Kaio', 'pendente'));
  perform pg_temp.checa(pg_temp.xp('Kaio') = 0, 'nada confirmado ainda');
end $$;
-- Idempotência: reprocessar o mesmo evento não duplica.
update chamados.gam_eventos set status = 'pendente' where tipo in ('ticket.resolved', 'ticket.assigned');
select pg_temp.ciclo();
select pg_temp.checa(pg_temp.xp('Kaio', 'pendente') = 85, 'reprocessar não duplica');
select pg_temp.checa((select count(*) from chamados.gam_xp where regra_codigo = 'resolvido') = 1, 'uma linha de resolução');

-- 4. Validação: sem reabertura no prazo → confirma, sem_reabertura, sequências e Primeiro Passo.
update chamados.gam_xp set confirmar_em = now() - interval '1 second' where status = 'pendente';
select pg_temp.ciclo();
do $$ begin
  perform pg_temp.checa(pg_temp.xp('Kaio') = 85 + 10 + 10, 'confirmado + sem reabertura + Primeiro Passo: ' || pg_temp.xp('Kaio'));
  perform pg_temp.checa((select xp_confirmado from chamados.gam_perfis p join chamados.pessoas x on x.id = p.pessoa_id where x.nome = 'Kaio') = 105, 'perfil = ledger');
  perform pg_temp.checa((select atual from chamados.gam_sequencias s join chamados.pessoas x on x.id = s.pessoa_id where x.nome = 'Kaio' and tipo = 'sla') = 1, 'sequência SLA');
  perform pg_temp.checa(exists (select 1 from chamados.gam_conquistas_pessoa cp join chamados.gam_conquista_tiers tr on tr.id = cp.tier_id
                                 join chamados.gam_conquistas c on c.id = tr.conquista_id where c.codigo = 'primeiro_passo'), 'Primeiro Passo');
  perform pg_temp.checa(exists (select 1 from chamados.gam_notificacoes where tipo = 'conquista'), 'notificação de conquista');
end $$;

-- 5. Avaliação: só com o código, 1 vez; 5 estrelas + elogio.
set role anon;
select pg_temp.falha(format('select chamados.avaliar_chamado(%L, %L, 5)', split_part((select valor from t where chave = 'p1'), '|', 1), 'errado'), 'Código de avaliação inválido');
select chamados.avaliar_chamado(split_part((select valor from t where chave = 'p1'), '|', 1), split_part((select valor from t where chave = 'p1'), '|', 2), 5, true, 'Muito bom');
select pg_temp.falha(format('select chamados.avaliar_chamado(%L, %L, 4)', split_part((select valor from t where chave = 'p1'), '|', 1), split_part((select valor from t where chave = 'p1'), '|', 2)), 'já foi avaliado');
select pg_temp.checa((chamados.consultar_chamado(split_part((select valor from t where chave = 'p1'), '|', 1))->>'avaliado')::boolean, 'consulta mostra avaliado');
reset role;
select pg_temp.ciclo();
select pg_temp.checa(pg_temp.xp('Kaio') = 105 + 25 + 20, 'avaliação 5 + elogio: ' || pg_temp.xp('Kaio'));

-- 6. Reabertura: estorna o pendente e penaliza; resolver de novo não dá XP de novo.
set role anon;
insert into t values ('p2', (chamados.abrir_chamado_publico(4, null, 'Joao Teste', 'Assistente', 13, 'P2 notebook', 0))->>'protocolo');
reset role;
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p2')));
reset role;
select pg_temp.envelhecer((select valor from t where chave = 'p2'), 30);
set role authenticated;
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p2')));
reset role;
select pg_temp.ciclo();
select pg_temp.checa(pg_temp.xp('Kaio', 'pendente') = 20 + 10 + 5, 'P2 pendente (baixa: 1,0× + resposta rápida): ' || pg_temp.xp('Kaio', 'pendente'));
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000c'); -- Aldo reabre
select pg_temp.falha(format('select chamados.reabrir_chamado(%L)', pg_temp.ch((select valor from t where chave = 'p2'))), 'permission denied');
select pg_temp.falha(format('select chamados.reabrir_chamado(%L, null)', pg_temp.ch((select valor from t where chave = 'p2'))), 'motivo');
select chamados.reabrir_chamado(pg_temp.ch((select valor from t where chave = 'p2')), 'incompleto', 'Usuário diz que não funcionou');
reset role;
select pg_temp.ciclo();
do $$ begin
  perform pg_temp.checa(pg_temp.xp('Kaio', 'pendente') = 5 and pg_temp.xp('Kaio', 'estornado') = 30, 'estorno da resolução (resposta rápida continua)');
  perform pg_temp.checa(pg_temp.xp('Kaio') = 150 - 10 - 20, 'penalidades: ' || pg_temp.xp('Kaio'));
  perform pg_temp.checa((select atual from chamados.gam_sequencias s join chamados.pessoas x on x.id = s.pessoa_id where x.nome = 'Kaio' and tipo = 'sem_reabertura') = 0, 'sequência zerada');
end $$;
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p2')));
reset role;
select pg_temp.ciclo();
select pg_temp.checa(pg_temp.xp('Kaio', 'pendente') = 5, 'resolver de novo não paga de novo');

-- 7. Antiabuso: resolução relâmpago fica retida; gestor rejeita (estorna) ou aceita (libera).
set role anon;
insert into t values ('p3', (chamados.abrir_chamado_publico(3, null, 'Ana Teste', 'Analista', 2, 'P3 relâmpago', 1))->>'protocolo');
insert into t values ('p4', (chamados.abrir_chamado_publico(3, null, 'Bia Teste', 'Analista', 2, 'P4 relâmpago legítimo', 1))->>'protocolo');
reset role;
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p3')));
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p3')));
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p4')));
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p4')));
reset role;
select pg_temp.ciclo();
select pg_temp.checa((select count(*) from chamados.gam_suspeitas where regra = 'resolucao_relampago' and status = 'aberta') = 2, 'duas suspeitas');
select pg_temp.checa(pg_temp.xp('Kaio', 'retido') > 0 and pg_temp.xp('Kaio', 'pendente') = 5, 'XP retido (só a resposta rápida do P2 segue pendente): ' || pg_temp.xp('Kaio', 'pendente'));
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select pg_temp.checa((select count(*) from chamados.gam_suspeitas) = 0, 'técnico não vê suspeitas');
select pg_temp.falha($$select chamados.gam_admin_suspeita(1, true)$$, 'Só o gestor');
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select chamados.gam_admin_suspeita((select s.id from chamados.gam_suspeitas s join chamados.chamados c on c.id = s.chamado_id where c.descricao = 'P3 relâmpago'), false, 'Fechou sem resolver');
select chamados.gam_admin_suspeita((select s.id from chamados.gam_suspeitas s join chamados.chamados c on c.id = s.chamado_id where c.descricao = 'P4 relâmpago legítimo'), true, 'Era só reiniciar o serviço');
reset role;
do $$ begin
  perform pg_temp.checa(pg_temp.xp('Kaio', 'retido') = 0, 'nada retido depois da revisão');
  perform pg_temp.checa((select count(*) from chamados.gam_xp x join chamados.chamados c on c.id = x.chamado_id where c.descricao = 'P3 relâmpago' and x.status = 'estornado') > 0, 'rejeitada estorna');
  perform pg_temp.checa((select count(*) from chamados.gam_xp x join chamados.chamados c on c.id = x.chamado_id where c.descricao = 'P4 relâmpago legítimo' and x.status = 'pendente') > 0, 'aceita volta para validação');
end $$;

-- 8. Elegibilidade: chamado aberto pelo próprio time não pontua.
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
insert into t values ('p5', (chamados.abrir_chamado(1, 'P5 aberto pelo Kaio', 1))->>'protocolo');
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p5')));
reset role;
select pg_temp.envelhecer((select valor from t where chave = 'p5'), 30);
set role authenticated;
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p5')));
reset role;
select pg_temp.ciclo();
select pg_temp.checa(pg_temp.xp('Aldo', 'pendente') = 0 and chamados.gam_inelegivel(pg_temp.ch((select valor from t where chave = 'p5'))) = 'aberto pelo próprio time', 'chamado do time não pontua');

-- 9. Colaboração: só o responsável pede; o colega confirma; XP do colega na validação.
set role anon;
insert into t values ('p6', (chamados.abrir_chamado_publico(2, null, 'Carla Teste', 'Financeiro', 3, 'P6 com ajuda', 2))->>'protocolo');
reset role;
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p6')));
select pg_temp.falha(format('select chamados.pedir_ajuda(%L, %L)', pg_temp.ch((select valor from t where chave = 'p6')), '00000000-0000-0000-0000-000000000000'), 'colega');
select chamados.pedir_ajuda(pg_temp.ch((select valor from t where chave = 'p6')), (select id from chamados.pessoas where nome = 'Aldo'));
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select pg_temp.falha(format('select chamados.pedir_ajuda(%L, %L)', pg_temp.ch((select valor from t where chave = 'p6')), (select id from chamados.pessoas where nome = 'Kaio')), 'Só o responsável');
select chamados.responder_ajuda((select id from chamados.colaboracoes order by id desc limit 1), true);
reset role;
select pg_temp.envelhecer((select valor from t where chave = 'p6'), 60);
-- atrasado: o prazo de resolver já passou; Kaio justifica antes da validação
update chamados.chamados set prazo_em = now() - interval '1 minute' where protocolo = (select valor from t where chave = 'p6');
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p6')));
select chamados.justificar_atraso(pg_temp.ch((select valor from t where chave = 'p6')), 'Dependia do fornecedor do sistema');
reset role;
-- outro atrasado, sem justificativa
set role anon;
insert into t values ('p7', (chamados.abrir_chamado_publico(2, null, 'Davi Teste', 'Financeiro', 3, 'P7 atrasado', 1))->>'protocolo');
reset role;
set role authenticated;
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p7')));
reset role;
select pg_temp.envelhecer((select valor from t where chave = 'p7'), 60);
update chamados.chamados set prazo_em = now() - interval '1 minute' where protocolo = (select valor from t where chave = 'p7');
set role authenticated;
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p7')));
reset role;
select pg_temp.ciclo();
update chamados.gam_xp set confirmar_em = now() - interval '1 second' where status = 'pendente';
select pg_temp.ciclo();
do $$ begin
  perform pg_temp.checa(pg_temp.xp('Aldo') = 10, 'Aldo ganhou pela ajuda: ' || pg_temp.xp('Aldo'));
  perform pg_temp.checa(not exists (select 1 from chamados.gam_xp x join chamados.chamados c on c.id = x.chamado_id where c.descricao = 'P6 com ajuda' and x.regra_codigo = 'sla_sem_justificativa'), 'justificado não penaliza');
  perform pg_temp.checa(exists (select 1 from chamados.gam_xp x join chamados.chamados c on c.id = x.chamado_id where c.descricao = 'P7 atrasado' and x.regra_codigo = 'sla_sem_justificativa' and x.valor = -10), 'atraso sem justificativa penaliza');
  perform pg_temp.checa(not exists (select 1 from chamados.gam_xp where status = 'pendente' and regra_codigo = 'resolvido'), 'tudo validado');
end $$;

-- 10. Retorno decrescente e teto diário.
update chamados.gam_config set valor = '{"a_partir": 0, "fator": 0.5, "urgencia_max": 0}' where chave = 'retorno_decrescente';
set role anon;
insert into t values ('p8', (chamados.abrir_chamado_publico(1, null, 'Eva Teste', 'Sócia', 4, 'P8 simples', 0))->>'protocolo');
reset role;
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p8')));
reset role;
select pg_temp.envelhecer((select valor from t where chave = 'p8'), 30);
set role authenticated;
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p8')));
reset role;
select pg_temp.ciclo();
select pg_temp.checa((select valor from chamados.gam_xp x join chamados.chamados c on c.id = x.chamado_id where c.descricao = 'P8 simples' and x.regra_codigo = 'resolvido') = 10, 'retorno decrescente: 20 × 0,5');
update chamados.gam_config set valor = '{"a_partir": 8, "fator": 0.5, "urgencia_max": 0}' where chave = 'retorno_decrescente';
update chamados.gam_config set valor = '5' where chave = 'teto_diario_resolucao';
set role anon;
insert into t values ('p9', (chamados.abrir_chamado_publico(1, null, 'Gil Teste', 'Sócio', 4, 'P9 no teto', 3))->>'protocolo');
reset role;
set role authenticated;
select chamados.assumir_chamado(pg_temp.ch((select valor from t where chave = 'p9')));
reset role;
select pg_temp.envelhecer((select valor from t where chave = 'p9'), 30);
set role authenticated;
select chamados.resolver_chamado(pg_temp.ch((select valor from t where chave = 'p9')));
reset role;
select pg_temp.ciclo();
select pg_temp.checa((select count(*) from chamados.gam_xp x join chamados.chamados c on c.id = x.chamado_id where c.descricao = 'P9 no teto' and x.regra_codigo in ('resolvido', 'resolvido_sla', 'prioridade_alta', 'critico')) = 0, 'teto diário já atingido: sem XP de resolução');
update chamados.gam_config set valor = '400' where chave = 'teto_diario_resolucao';

-- 11. Missões: progresso ao vivo e fechamento do período (depois da validação).
select pg_temp.checa(chamados.gam_metrica_missao('resolvidos_sla', (select id from chamados.pessoas where nome = 'Kaio'), now() - interval '1 day', now(), true) >= 2, 'progresso ao vivo');
update chamados.gam_xp set criado_em = criado_em - interval '2 days';
update chamados.gam_config set valor = to_jsonb(now() - interval '3 days') where chave = 'ligada_em';
update chamados.gam_config set valor = '0' where chave = 'horas_pendente';
select chamados.gam_fechar_periodos();
do $$ declare r record; begin
  perform pg_temp.checa(exists (select 1 from chamados.gam_missoes_resultado mr join chamados.gam_missoes m on m.id = mr.missao_id where m.codigo = 'diaria_sla'), 'missão diária fechada');
  for r in select mr.* from chamados.gam_missoes_resultado mr loop
    perform pg_temp.checa(r.concluida = (r.valor >= r.meta), 'concluída = valor ≥ meta');
    if r.concluida and r.pessoa_id is not null then
      perform pg_temp.checa(exists (select 1 from chamados.gam_xp where missao_resultado_id = r.id), 'recompensa de missão concluída');
    end if;
  end loop;
end $$;
select chamados.gam_fechar_periodos(); -- idempotente
select pg_temp.checa((select count(*) from chamados.gam_missoes_resultado) = (select count(distinct (missao_id, periodo_inicio, pessoa_id)) from chamados.gam_missoes_resultado), 'fechar de novo não duplica');

-- 12. Jornada, ranking e RLS do time.
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
do $$ declare j jsonb := chamados.gam_jornada(); r jsonb; begin
  perform pg_temp.checa((j->>'participa')::boolean and (j->'perfil'->>'xp')::int = pg_temp.xp('Kaio') + pg_temp.xp('Kaio', 'pendente')
    and (j->'perfil'->>'xp_confirmado')::int = pg_temp.xp('Kaio'), 'jornada = ledger (XP conta na hora)');
  perform pg_temp.checa((j->'perfil'->'nivel'->>'nivel')::int = 1 and (j->'perfil'->'nivel'->>'xp_proximo')::int = 500, 'nível 1 até 500');
  perform pg_temp.checa(jsonb_array_length(j->'conquistas') >= 15 and jsonb_array_length(j->'missoes') >= 4, 'conquistas e missões');
  perform pg_temp.checa((j->>'nao_lidas')::int > 0 and jsonb_array_length(j->'feed') > 0 and jsonb_array_length(j->'historico') > 0, 'feed e histórico');
  r := chamados.gam_ranking('geral', 'xp');
  perform pg_temp.checa(r->'linhas'->0->>'nome' = 'Kaio' and (r->'linhas'->0->>'eu')::boolean, 'Kaio lidera em XP');
  r := chamados.gam_ranking('temporada', 'score');
  perform pg_temp.checa(jsonb_array_length(r->'linhas') = (select count(*) from chamados.pessoas where papel = 'dev' and ativo and not gestor), 'ranking com o time todo');
  perform pg_temp.checa((select count(*) from chamados.gam_xp x where x.pessoa_id <> chamados.eu_pessoa_id()) = 0, 'só o próprio ledger');
  perform pg_temp.checa((chamados.gam_jornada((select id from chamados.pessoas where nome = 'Aldo'))->'historico') = 'null'::jsonb, 'histórico alheio é privado');
end $$;
select pg_temp.falha($$select chamados.gam_ranking('geral', 'quantidade')$$, 'Critério inválido');
select chamados.gam_marcar_lidas();
select pg_temp.checa((chamados.gam_jornada()->>'nao_lidas')::int = 0, 'marcar lidas');
select pg_temp.falha($$select chamados.gam_escolher_visual(1::smallint, null)$$, 'Título não obtido');
reset role;

-- 13. Nível: fonte única e níveis acima do último cadastrado.
do $$ begin
  perform pg_temp.checa((chamados.gam_nivel(0)->>'nivel')::int = 1 and (chamados.gam_nivel(499)->>'nivel')::int = 1 and (chamados.gam_nivel(500)->>'nivel')::int = 2, 'limites');
  perform pg_temp.checa((chamados.gam_nivel(2840)->>'nivel')::int = 4 and (chamados.gam_nivel(2840)->>'faltam')::int = 2160, '2840 XP → nível 4, faltam 2160');
  perform pg_temp.checa((chamados.gam_nivel(20000)->>'nivel')::int = 7 and (chamados.gam_nivel(32500)->>'nivel')::int = 8, 'acima do Master: +12.500 (10.000 × 1,25)');
end $$;

-- 14. Gestão: níveis, conquista, missão e temporada (encerrar congela o ranking e abre a próxima).
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select pg_temp.falha($$select chamados.gam_admin_niveis('[{"nivel":1,"nome":"A","xp_minimo":0},{"nivel":2,"nome":"B","xp_minimo":0}]')$$, 'XP crescente');
select pg_temp.falha($$select chamados.gam_admin_niveis('[{"nivel":1,"nome":"A","xp_minimo":0},{"nivel":2,"nome":"B","xp_minimo":10}]')$$, 'não são removidos');
select chamados.gam_admin_niveis('[{"nivel":1,"nome":"Novato","xp_minimo":0},{"nivel":2,"nome":"Aprendiz","xp_minimo":500},{"nivel":3,"nome":"Operador","xp_minimo":1200},{"nivel":4,"nome":"Especialista","xp_minimo":2500},{"nivel":5,"nome":"Expert","xp_minimo":5000},{"nivel":6,"nome":"Elite","xp_minimo":10000},{"nivel":7,"nome":"Master","xp_minimo":20000},{"nivel":8,"nome":"Lenda","xp_minimo":40000}]');
select chamados.gam_admin_conquista('{"codigo":"teste_conquista","nome":"Teste","descricao":"x","raridade":"rara","metrica":"resolvidos","tiers":[{"tier":1,"limite":2,"xp":5}]}');
select chamados.gam_admin_missao('{"codigo":"teste_missao","nome":"Teste","descricao":"x","periodo":"semana","alvo":"individual","metrica":"resolvidos","meta":2,"xp":10}');
select chamados.gam_admin_temporada(jsonb_build_object('acao', 'encerrar', 'id', (select id from chamados.gam_temporadas where status = 'ativa')));
reset role;
do $$ declare r jsonb; begin
  perform pg_temp.checa((select count(*) from chamados.gam_ranking_temporada) > 0, 'ranking congelado');
  perform pg_temp.checa((select count(*) from chamados.gam_temporadas where status = 'ativa') = 1, 'próxima temporada ativa');
  perform pg_temp.checa((select count(*) from chamados.gam_auditoria) >= 5, 'auditoria');
end $$;
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
select pg_temp.checa((chamados.gam_ranking(null, 'score', (select id from chamados.gam_temporadas where status = 'encerrada' limit 1))->>'congelado')::boolean, 'ranking da temporada encerrada');
reset role;

-- 15. Integridade: perfil sempre igual à soma do ledger; nenhuma chave repetida.
do $$ begin
  perform chamados.gam_atualizar_perfil(id) from chamados.pessoas where papel = 'dev';
  perform pg_temp.checa(not exists (select 1 from chamados.gam_perfis p where p.xp_confirmado <>
      greatest((select coalesce(sum(valor), 0) from chamados.gam_xp x where x.pessoa_id = p.pessoa_id and x.status = 'confirmado'), 0)), 'perfil = ledger');
  perform pg_temp.checa((select count(*) from chamados.gam_eventos where status = 'erro') = 0,
    'eventos com erro: ' || coalesce((select string_agg(tipo || ': ' || erro, ' | ') from chamados.gam_eventos where status = 'erro'), ''));
end $$;

-- 15b. XP em validação já conta para o nível; estorno devolve.
do $$ declare a uuid := (select id from chamados.pessoas where nome = 'Aldo'); antes int; begin
  perform chamados.gam_atualizar_perfil(a);
  antes := (select nivel from chamados.gam_perfis where pessoa_id = a);
  perform chamados.gam_lancar(a, 'teste:xp-imediato', 2000, 'Teste', 'pendente', null, null, null, null, null, now() + interval '72 hours');
  perform chamados.gam_atualizar_perfil(a);
  perform pg_temp.checa((select nivel from chamados.gam_perfis where pessoa_id = a) > antes, 'pendente sobe o nível na hora');
  update chamados.gam_xp set status = 'estornado' where pessoa_id = a and chave = 'teste:xp-imediato';
  perform chamados.gam_atualizar_perfil(a);
  perform pg_temp.checa((select nivel from chamados.gam_perfis where pessoa_id = a) = antes, 'estorno devolve o nível');
end $$;

-- 16. Desligar: eventos novos são ignorados.
set role authenticated;
select pg_temp.como('00000000-0000-0000-0000-00000000000a');
select chamados.gam_admin_config('ativo', 'false');
reset role;
set role anon;
select chamados.abrir_chamado_publico(4, null, 'Depois Teste', 'Analista', 1, 'Depois de desligar', 1);
reset role;
select pg_temp.ciclo();
select pg_temp.checa((select status from chamados.gam_eventos order by id desc limit 1) = 'ignorado', 'desligada ignora');
\echo GAMIFICACAO: TODOS OS TESTES PASSARAM

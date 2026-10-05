-- ============================================================================
-- Gamificação · parte 2: estrutura, configuração e dados iniciais
-- ----------------------------------------------------------------------------
-- Tudo no schema `chamados`, prefixo gam_. Valores de XP, níveis, conquistas,
-- missões, temporadas e pesos do score ficam em tabelas (Central de
-- Gamificação); nada é fixo no código. Chave geral: gam_config.ativo (começa
-- desligada; ao ligar, só eventos a partir daquele momento contam).
-- Ledger (gam_xp) é a fonte da verdade do XP: cada linha tem chave única por
-- pessoa (idempotência) e status pendente → confirmado | estornado | retido.
-- ============================================================================

create type chamados.gam_evento_t as enum (
  'ticket.created', 'ticket.assigned', 'ticket.resolved', 'ticket.reopened', 'ticket.confirmed',
  'rating.received', 'collaboration.registered');
create type chamados.gam_xp_status_t as enum ('pendente', 'retido', 'confirmado', 'estornado');
create type chamados.gam_raridade_t as enum ('comum', 'incomum', 'rara', 'epica', 'lendaria');

-- ============ Configuração ============
create table chamados.gam_config (
  chave          text primary key,
  valor          jsonb not null,
  descricao      text not null,
  atualizado_em  timestamptz not null default now(),
  atualizado_por uuid references chamados.pessoas (id)
);

create table chamados.gam_regras (
  codigo             text primary key,
  nome               text not null,
  descricao          text not null,
  evento             chamados.gam_evento_t not null,
  xp                 integer not null check (xp between -1000 and 1000),
  ativo              boolean not null default true,
  limite_por_chamado smallint not null default 1 check (limite_por_chamado between 1 and 10),
  limite_diario      smallint check (limite_diario is null or limite_diario > 0),
  usa_multiplicador  boolean not null default false,
  ordem              smallint not null default 0
);
comment on table chamados.gam_regras is 'XP por fato. Penalidade = xp negativo. limite_diario: quantas vezes por pessoa/dia (fuso de Brasília).';

create table chamados.gam_multiplicadores (
  urgencia smallint primary key references chamados.urgencias (nivel),
  rotulo   text not null,
  fator    numeric(3,2) not null check (fator between 1 and 3)
);
comment on table chamados.gam_multiplicadores is 'Complexidade = urgência do chamado (definida por quem abre). Aplicado só ao XP de resolução, com teto em gam_config.multiplicador_max.';

create table chamados.gam_niveis (
  nivel     smallint primary key check (nivel >= 1),
  nome      text not null,
  xp_minimo integer not null unique check (xp_minimo >= 0),
  check ((nivel = 1) = (xp_minimo = 0))
);

create table chamados.gam_recompensas (
  id        smallint generated always as identity primary key,
  codigo    text not null unique,
  tipo      text not null check (tipo in ('titulo', 'moldura', 'tema', 'icone', 'destaque')),
  nome      text not null,
  descricao text not null,
  raridade  chamados.gam_raridade_t not null default 'comum',
  ativo     boolean not null default true
);

create table chamados.gam_conquistas (
  id        smallint generated always as identity primary key,
  codigo    text not null unique,
  nome      text not null,
  descricao text not null,
  icone     text not null default 'medalha',
  raridade  chamados.gam_raridade_t not null,
  metrica   text check (metrica is null or metrica in (
              'resolvidos', 'resolvidos_sla', 'criticos', 'avaliacoes_5', 'ajudas', 'velocista', 'madrugador',
              'seq_sem_reabertura', 'seq_sla', 'seq_cinco_estrelas', 'seq_semanas_sla')),
  ativo     boolean not null default true,
  ordem     smallint not null default 0
);
comment on column chamados.gam_conquistas.metrica is 'Contador que libera a conquista; nulo = concedida por missão/temporada.';

create table chamados.gam_conquista_tiers (
  id           smallint generated always as identity primary key,
  conquista_id smallint not null references chamados.gam_conquistas (id) on delete cascade,
  tier         smallint not null check (tier between 1 and 5),
  nome         text check (nome is null or nome in ('Bronze', 'Prata', 'Ouro', 'Platina', 'Diamante')),
  limite       integer not null check (limite > 0),
  xp           integer not null default 0 check (xp between 0 and 5000),
  raridade     chamados.gam_raridade_t,
  recompensa_id smallint references chamados.gam_recompensas (id),
  unique (conquista_id, tier)
);

create table chamados.gam_temporadas (
  id            smallint generated always as identity primary key,
  nome          text not null unique,
  inicio        date not null,
  fim           date not null,
  status        text not null default 'futura' check (status in ('futura', 'ativa', 'encerrada')),
  encerrada_em  timestamptz,
  check (fim > inicio)
);
create unique index gam_temporadas_uma_ativa on chamados.gam_temporadas ((true)) where status = 'ativa';

create table chamados.gam_missoes (
  id                smallint generated always as identity primary key,
  codigo            text not null unique,
  nome              text not null,
  descricao         text not null,
  periodo           text not null check (periodo in ('dia', 'semana', 'mes')),
  alvo              text not null default 'individual' check (alvo in ('individual', 'equipe')),
  metrica           text not null check (metrica in (
                      'resolvidos', 'resolvidos_sla', 'resolvidos_sem_reabertura', 'avaliados_ge4', 'ajudas',
                      'sla_equipe_pct', 'satisfacao_equipe_pct')),
  meta              numeric(7,2) not null check (meta > 0),
  xp                integer not null default 0 check (xp between 0 and 5000),
  conquista_tier_id smallint references chamados.gam_conquista_tiers (id),
  recompensa_id     smallint references chamados.gam_recompensas (id),
  especial          boolean not null default false,
  inicio            date not null default current_date,
  fim               date,
  ativo             boolean not null default true,
  check (alvo = 'equipe' or metrica not like '%equipe%'),
  check (fim is null or fim >= inicio)
);
comment on table chamados.gam_missoes is 'Missões diárias/semanais/mensais, individuais ou de equipe. Avaliadas quando o período termina e o XP do período já foi confirmado.';

-- ============ Estado ============
create table chamados.gam_eventos (
  id           bigint generated always as identity primary key,
  tipo         chamados.gam_evento_t not null,
  chave        text not null unique,
  chamado_id   uuid references chamados.chamados (id) on delete cascade,
  pessoa_id    uuid references chamados.pessoas (id),
  dados        jsonb not null default '{}',
  status       text not null default 'pendente' check (status in ('pendente', 'processado', 'ignorado', 'erro')),
  tentativas   smallint not null default 0,
  erro         text,
  criado_em    timestamptz not null default now(),
  processado_em timestamptz
);
create index gam_eventos_fila_idx on chamados.gam_eventos (id) where status in ('pendente', 'erro');
comment on table chamados.gam_eventos is 'Fila de eventos publicados pelo sistema de chamados. chave = idempotência (o mesmo fato nunca entra duas vezes).';

create table chamados.gam_missoes_resultado (
  id             bigint generated always as identity primary key,
  missao_id      smallint not null references chamados.gam_missoes (id) on delete cascade,
  periodo_inicio date not null,
  pessoa_id      uuid references chamados.pessoas (id),
  valor          numeric(9,2) not null,
  meta           numeric(7,2) not null,
  concluida      boolean not null,
  fechado_em     timestamptz not null default now(),
  unique nulls not distinct (missao_id, periodo_inicio, pessoa_id)
);
comment on column chamados.gam_missoes_resultado.pessoa_id is 'Nulo = resultado da equipe.';

create table chamados.gam_xp (
  id                  bigint generated always as identity primary key,
  pessoa_id           uuid not null references chamados.pessoas (id),
  chave               text not null,
  valor               integer not null check (valor <> 0),
  motivo              text not null,
  status              chamados.gam_xp_status_t not null,
  evento_id           bigint references chamados.gam_eventos (id),
  chamado_id          uuid references chamados.chamados (id) on delete set null,
  regra_codigo        text references chamados.gam_regras (codigo),
  conquista_tier_id   smallint references chamados.gam_conquista_tiers (id),
  missao_resultado_id bigint references chamados.gam_missoes_resultado (id),
  temporada_id        smallint references chamados.gam_temporadas (id),
  confirmar_em        timestamptz,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  unique (pessoa_id, chave),
  check (status <> 'pendente' or confirmar_em is not null)
);
create index gam_xp_pessoa_idx on chamados.gam_xp (pessoa_id, status, criado_em);
create index gam_xp_chamado_idx on chamados.gam_xp (chamado_id);
create index gam_xp_confirmar_idx on chamados.gam_xp (confirmar_em) where status = 'pendente';
comment on table chamados.gam_xp is 'Ledger de XP: nunca se soma em coluna; o total é a soma das linhas confirmadas. chave única por pessoa impede XP duplicado.';

create table chamados.gam_perfis (
  pessoa_id     uuid primary key references chamados.pessoas (id),
  xp_confirmado integer not null default 0,
  xp_pendente   integer not null default 0,
  nivel         smallint not null default 1,
  titulo_id     smallint references chamados.gam_recompensas (id),
  moldura_id    smallint references chamados.gam_recompensas (id),
  atualizado_em timestamptz not null default now()
);
comment on table chamados.gam_perfis is 'Cache recalculável a partir do ledger (gam_atualizar_perfil).';

create table chamados.gam_conquistas_pessoa (
  id              bigint generated always as identity primary key,
  pessoa_id       uuid not null references chamados.pessoas (id),
  tier_id         smallint not null references chamados.gam_conquista_tiers (id) on delete cascade,
  desbloqueada_em timestamptz not null default now(),
  unique (pessoa_id, tier_id)
);

create table chamados.gam_recompensas_pessoa (
  pessoa_id     uuid not null references chamados.pessoas (id),
  recompensa_id smallint not null references chamados.gam_recompensas (id),
  obtida_em     timestamptz not null default now(),
  origem        text not null,
  primary key (pessoa_id, recompensa_id)
);

create table chamados.gam_sequencias (
  pessoa_id     uuid not null references chamados.pessoas (id),
  tipo          text not null check (tipo in ('sem_reabertura', 'sla', 'cinco_estrelas', 'semanas_sla')),
  atual         integer not null default 0 check (atual >= 0),
  recorde       integer not null default 0 check (recorde >= atual),
  atualizado_em timestamptz not null default now(),
  primary key (pessoa_id, tipo)
);

create table chamados.gam_ranking_temporada (
  temporada_id smallint not null references chamados.gam_temporadas (id),
  pessoa_id    uuid not null references chamados.pessoas (id),
  posicao      smallint not null,
  score        numeric(5,1),
  xp           integer not null,
  resolvidos   integer not null,
  sla          numeric(5,4),
  satisfacao   numeric(5,4),
  qualidade    numeric(5,4),
  elegivel     boolean not null,
  primary key (temporada_id, pessoa_id)
);
comment on table chamados.gam_ranking_temporada is 'Ranking congelado ao encerrar a temporada.';

create table chamados.gam_notificacoes (
  id        bigint generated always as identity primary key,
  pessoa_id uuid not null references chamados.pessoas (id),
  tipo      text not null check (tipo in ('xp', 'nivel', 'conquista', 'missao', 'sequencia', 'temporada', 'ajuda', 'revisao')),
  titulo    text not null,
  detalhe   text,
  xp        integer,
  dados     jsonb not null default '{}',
  criada_em timestamptz not null default now(),
  lida_em   timestamptz
);
create index gam_notificacoes_pessoa_idx on chamados.gam_notificacoes (pessoa_id, id desc);

create table chamados.gam_suspeitas (
  id          bigint generated always as identity primary key,
  pessoa_id   uuid not null references chamados.pessoas (id),
  chamado_id  uuid references chamados.chamados (id) on delete cascade,
  regra       text not null,
  descricao   text not null,
  evidencia   jsonb not null default '{}',
  status      text not null default 'aberta' check (status in ('aberta', 'aceita', 'rejeitada')),
  criada_em   timestamptz not null default now(),
  revisada_em timestamptz,
  revisor_id  uuid references chamados.pessoas (id),
  nota        text,
  unique nulls not distinct (pessoa_id, chamado_id, regra)
);
comment on table chamados.gam_suspeitas is 'Eventos suspeitos: o XP do chamado fica retido até o gestor aceitar (libera) ou rejeitar (estorna).';

create table chamados.gam_auditoria (
  id        bigint generated always as identity primary key,
  autor_id  uuid references chamados.pessoas (id),
  acao      text not null,
  alvo      text not null,
  antes     jsonb,
  depois    jsonb,
  criado_em timestamptz not null default now()
);

-- ============ Permissões (leitura; escrita só por funções) ============
do $$ declare t text; begin
  foreach t in array array['gam_config','gam_regras','gam_multiplicadores','gam_niveis','gam_recompensas','gam_conquistas',
    'gam_conquista_tiers','gam_temporadas','gam_missoes','gam_eventos','gam_missoes_resultado','gam_xp','gam_perfis',
    'gam_conquistas_pessoa','gam_recompensas_pessoa','gam_sequencias','gam_ranking_temporada','gam_notificacoes',
    'gam_suspeitas','gam_auditoria'] loop
    execute format('alter table chamados.%I enable row level security', t);
    execute format('grant select on chamados.%I to authenticated', t);
    execute format('grant all on chamados.%I to service_role', t);
  end loop;
  -- Time e gestor: configuração e o que é público entre o time (perfis, conquistas, ranking).
  foreach t in array array['gam_config','gam_regras','gam_multiplicadores','gam_niveis','gam_recompensas','gam_conquistas',
    'gam_conquista_tiers','gam_temporadas','gam_missoes','gam_missoes_resultado','gam_perfis','gam_conquistas_pessoa',
    'gam_recompensas_pessoa','gam_sequencias','gam_ranking_temporada'] loop
    execute format('create policy %I on chamados.%I for select to authenticated using (chamados.eh_dev() or chamados.eh_gestor())', t || '_ler', t);
  end loop;
  -- Cada um vê o próprio ledger e as próprias notificações; o gestor vê tudo.
  foreach t in array array['gam_xp','gam_notificacoes'] loop
    execute format('create policy %I on chamados.%I for select to authenticated using (pessoa_id = chamados.eu_pessoa_id() or chamados.eh_gestor())', t || '_ler', t);
  end loop;
  -- Só o gestor: fila, suspeitas e auditoria.
  foreach t in array array['gam_eventos','gam_suspeitas','gam_auditoria'] loop
    execute format('create policy %I on chamados.%I for select to authenticated using (chamados.eh_gestor())', t || '_ler', t);
  end loop;
end $$;

-- ============ Dados iniciais (ajustáveis na Central de Gamificação) ============
insert into chamados.gam_config (chave, valor, descricao) values
  ('ativo', 'false', 'Chave geral. Desligada: eventos são ignorados e o time não vê a gamificação.'),
  ('ligada_em', 'null', 'Quando a chave foi ligada; eventos anteriores não contam.'),
  ('horas_pendente', '72', 'Horas que o XP de resolução fica em validação; reabertura nesse prazo estorna.'),
  ('janela_reabertura_dias', '14', 'Reabertura depois disso não gera penalidade.'),
  ('teto_diario_resolucao', '400', 'Máximo de XP por dia vindo de resolução (base + SLA + prioridade).'),
  ('retorno_decrescente', '{"a_partir": 8, "fator": 0.5, "urgencia_max": 0}', 'A partir do N-ésimo chamado do dia com urgência até urgencia_max, o XP de resolução é multiplicado pelo fator.'),
  ('multiplicador_max', '2.0', 'Teto do multiplicador de complexidade.'),
  ('resposta_rapida_fracao', '0.5', 'Assumir dentro desta fração do prazo de assumir vale "Primeira resposta rápida".'),
  ('expediente', '{"dias": [1, 2, 3, 4, 5], "inicio": "08:00", "fim": "18:00"}', 'Expediente (fuso de Brasília). Nenhuma regra premia atividade fora dele.'),
  ('madrugador_horas', '2', 'Horas iniciais do expediente que contam para "Madrugador".'),
  ('score_pesos', '{"qualidade": 30, "sla": 25, "satisfacao": 20, "produtividade": 15, "colaboracao": 10}', 'Pesos do Performance Score.'),
  ('score_k', '5', 'Suavização bayesiana: quantos chamados "fictícios" na média do time cada taxa recebe.'),
  ('ranking_minimo', '5', 'Mínimo de chamados resolvidos no período para entrar no ranking por score.'),
  ('equipe_minimo', '2', 'Chamados resolvidos no período para participar da recompensa de missão de equipe.'),
  ('sequencia_semana_minimo', '3', 'Chamados resolvidos na semana para a semana contar na sequência de SLA.'),
  ('temporada_xp', '[300, 200, 100]', 'XP ao 1º, 2º e 3º lugares ao encerrar a temporada.'),
  ('niveis_extra_fator', '1.25', 'Depois do último nível cadastrado, cada nível exige o intervalo anterior × fator.'),
  ('suspeita', '{"min_assumir_resolver_min": 3, "critico_min": 5, "mesmo_nome_dia": 5, "reaberturas": 2, "reciprocidade": 0.5, "reciprocidade_min": 4, "avaliacoes_mesmo_nome_7d": 3, "reaberturas_alheias_7d": 3}', 'Limites que marcam um chamado para revisão (XP retido).');

insert into chamados.gam_regras (codigo, nome, descricao, evento, xp, limite_por_chamado, limite_diario, usa_multiplicador, ordem) values
  ('resolvido', 'Chamado resolvido', 'Resolução confirmada (sem reabertura no prazo de validação).', 'ticket.resolved', 20, 1, null, true, 1),
  ('resolvido_sla', 'Resolvido dentro do SLA', 'Resolvido até o prazo de resolver.', 'ticket.resolved', 10, 1, null, false, 2),
  ('prioridade_alta', 'Chamado urgente resolvido', 'Urgência "Urgente".', 'ticket.resolved', 15, 1, null, false, 3),
  ('critico', 'Chamado muito urgente resolvido', 'Urgência "Muito urgente".', 'ticket.resolved', 30, 1, null, false, 4),
  ('resposta_rapida', 'Primeira resposta rápida', 'Assumiu dentro da metade do prazo de assumir.', 'ticket.assigned', 5, 1, 10, false, 5),
  ('sem_reabertura', 'Resolvido sem reabertura', 'Passou pela validação sem ser reaberto.', 'ticket.confirmed', 10, 1, null, false, 6),
  ('ajuda', 'Ajudou um colega', 'Colaboração confirmada em chamado resolvido.', 'ticket.confirmed', 10, 1, 5, false, 7),
  ('avaliacao_5', 'Avaliação 5 estrelas', 'Nota 5 de quem abriu.', 'rating.received', 25, 1, null, false, 8),
  ('avaliacao_4', 'Avaliação 4 estrelas', 'Nota 4 de quem abriu.', 'rating.received', 10, 1, null, false, 9),
  ('elogio', 'Elogio do usuário', 'Quem abriu marcou "Quero elogiar".', 'rating.received', 20, 1, null, false, 10),
  ('reaberto', 'Chamado reaberto', 'Penalidade: reaberto dentro da janela de reabertura.', 'ticket.reopened', -10, 3, null, false, 11),
  ('encerrado_incorreto', 'Encerrado incorretamente', 'Penalidade: reaberto com motivo "não estava resolvido".', 'ticket.reopened', -20, 1, null, false, 12),
  ('sla_sem_justificativa', 'SLA estourado sem justificativa', 'Penalidade: resolvido após o prazo sem justificativa até a validação.', 'ticket.confirmed', -10, 1, null, false, 13);

insert into chamados.gam_multiplicadores (urgencia, rotulo, fator) values
  (0, 'Baixa', 1.0), (1, 'Média', 1.2), (2, 'Alta', 1.5), (3, 'Crítica', 2.0);

insert into chamados.gam_niveis (nivel, nome, xp_minimo) values
  (1, 'Novato', 0), (2, 'Aprendiz', 500), (3, 'Operador', 1200), (4, 'Especialista', 2500),
  (5, 'Expert', 5000), (6, 'Elite', 10000), (7, 'Master', 20000);

insert into chamados.gam_recompensas (codigo, tipo, nome, descricao, raridade) values
  ('titulo_guardiao_sla', 'titulo', 'Guardião do SLA', 'Título por 50 chamados resolvidos no prazo.', 'rara'),
  ('titulo_solucionador', 'titulo', 'Solucionador', 'Título por 100 chamados resolvidos.', 'rara'),
  ('titulo_veterano', 'titulo', 'Veterano do Suporte', 'Título por 500 chamados resolvidos.', 'epica'),
  ('titulo_criticos', 'titulo', 'Especialista em Críticos', 'Título por 10 chamados muito urgentes resolvidos.', 'rara'),
  ('titulo_heroi', 'titulo', 'Herói do Cliente', 'Título por 25 avaliações 5 estrelas.', 'rara'),
  ('titulo_campeao', 'titulo', 'Campeão da Temporada', 'Título do 1º lugar de uma temporada.', 'lendaria'),
  ('moldura_ouro', 'moldura', 'Moldura Ouro', 'Pódio de temporada: 1º lugar.', 'lendaria'),
  ('moldura_prata', 'moldura', 'Moldura Prata', 'Pódio de temporada: 2º lugar.', 'epica'),
  ('moldura_bronze', 'moldura', 'Moldura Bronze', 'Pódio de temporada: 3º lugar.', 'rara'),
  ('moldura_lenda', 'moldura', 'Moldura Lenda', 'Moldura da conquista Lenda do Suporte.', 'lendaria'),
  ('destaque_semana', 'destaque', 'Semana Impecável', 'Destaque no perfil pela missão especial.', 'epica');

create function pg_temp.conquista(p_codigo text, p_nome text, p_desc text, p_icone text, p_rar chamados.gam_raridade_t, p_metrica text, p_ordem int, p_tiers jsonb)
returns void language plpgsql as $f$
declare v_id smallint; t jsonb; i int := 0;
begin
  insert into chamados.gam_conquistas (codigo, nome, descricao, icone, raridade, metrica, ordem)
  values (p_codigo, p_nome, p_desc, p_icone, p_rar, p_metrica, p_ordem) returning id into v_id;
  for t in select * from jsonb_array_elements(p_tiers) loop
    i := i + 1;
    insert into chamados.gam_conquista_tiers (conquista_id, tier, nome, limite, xp, raridade, recompensa_id)
    values (v_id, i, t->>'nome', (t->>'limite')::int, (t->>'xp')::int, (t->>'raridade')::chamados.gam_raridade_t,
            (select id from chamados.gam_recompensas where codigo = t->>'recompensa'));
  end loop;
end $f$;

select pg_temp.conquista('primeiro_passo', 'Primeiro Passo', 'Resolva seu primeiro chamado.', 'passo', 'comum', 'resolvidos', 1, '[{"limite":1,"xp":10}]');
select pg_temp.conquista('aquecendo', 'Aquecendo', 'Resolva 10 chamados.', 'chama', 'comum', 'resolvidos', 2, '[{"limite":10,"xp":25}]');
select pg_temp.conquista('maquina', 'Máquina de Resolver', 'Resolva 100 chamados.', 'engrenagem', 'rara', 'resolvidos', 3, '[{"limite":100,"xp":100,"recompensa":"titulo_solucionador"}]');
select pg_temp.conquista('centuriao', 'Centurião', 'Resolva 500 chamados.', 'escudo', 'epica', 'resolvidos', 4, '[{"limite":500,"xp":250,"recompensa":"titulo_veterano"}]');
select pg_temp.conquista('lenda', 'Lenda do Suporte', 'Resolva 1.000 chamados.', 'coroa', 'lendaria', 'resolvidos', 5, '[{"limite":1000,"xp":500,"recompensa":"moldura_lenda"}]');
select pg_temp.conquista('velocista', 'Velocista', 'Resolva um chamado em menos de 10 minutos depois de assumir (sem reabertura e sem retenção).', 'raio', 'incomum', 'velocista', 6, '[{"limite":1,"xp":20}]');
select pg_temp.conquista('precisao', 'Precisão Cirúrgica', 'Resolva 25 chamados seguidos sem reabertura.', 'alvo', 'epica', 'seq_sem_reabertura', 7, '[{"limite":25,"xp":150}]');
select pg_temp.conquista('guardiao_sla', 'Guardião do SLA', 'Resolva chamados dentro do SLA.', 'escudo', 'rara', 'resolvidos_sla', 8,
  '[{"nome":"Bronze","limite":10,"xp":25,"raridade":"comum"},{"nome":"Prata","limite":50,"xp":100,"raridade":"incomum","recompensa":"titulo_guardiao_sla"},{"nome":"Ouro","limite":100,"xp":200,"raridade":"rara"},{"nome":"Platina","limite":250,"xp":400,"raridade":"epica"},{"nome":"Diamante","limite":500,"xp":800,"raridade":"lendaria"}]');
select pg_temp.conquista('sla_impecavel', 'SLA Impecável', 'Resolva 100 chamados seguidos dentro do SLA.', 'diamante', 'lendaria', 'seq_sla', 9, '[{"limite":100,"xp":500}]');
select pg_temp.conquista('favorito', 'Favorito dos Usuários', 'Receba 25 avaliações 5 estrelas.', 'estrela', 'rara', 'avaliacoes_5', 10, '[{"limite":25,"xp":150,"recompensa":"titulo_heroi"}]');
select pg_temp.conquista('atendimento_lendario', 'Atendimento Lendário', 'Receba 100 avaliações 5 estrelas.', 'estrela', 'lendaria', 'avaliacoes_5', 11, '[{"limite":100,"xp":500}]');
select pg_temp.conquista('bombeiro', 'Bombeiro', 'Resolva chamados muito urgentes.', 'sirene', 'rara', 'criticos', 12,
  '[{"nome":"Bronze","limite":10,"xp":100,"raridade":"incomum","recompensa":"titulo_criticos"},{"nome":"Prata","limite":25,"xp":200,"raridade":"rara"},{"nome":"Ouro","limite":50,"xp":400,"raridade":"epica"}]');
select pg_temp.conquista('madrugador', 'Madrugador', 'Resolva 20 chamados nas primeiras horas do expediente.', 'sol', 'incomum', 'madrugador', 13, '[{"limite":20,"xp":50}]');
select pg_temp.conquista('equipe', 'Trabalho em Equipe', 'Ajude colegas em chamados (colaboração confirmada).', 'pessoas', 'epica', 'ajudas', 14,
  '[{"nome":"Bronze","limite":5,"xp":50,"raridade":"incomum"},{"nome":"Prata","limite":25,"xp":150,"raridade":"rara"},{"nome":"Ouro","limite":50,"xp":300,"raridade":"epica"}]');
select pg_temp.conquista('imparavel', 'Imparável', 'Semanas seguidas com SLA ≥ 95% (mínimo de chamados na semana; semana sem chamados não quebra).', 'foguete', 'epica', 'seq_semanas_sla', 15,
  '[{"nome":"Bronze","limite":4,"xp":100,"raridade":"rara"},{"nome":"Prata","limite":8,"xp":200,"raridade":"epica"},{"nome":"Ouro","limite":12,"xp":400,"raridade":"lendaria"}]');
select pg_temp.conquista('cinco_estrelas', 'Sequência 5 Estrelas', '5 avaliações 5 estrelas seguidas.', 'estrela', 'incomum', 'seq_cinco_estrelas', 16, '[{"limite":5,"xp":50}]');
select pg_temp.conquista('semana_impecavel', 'Semana Impecável', 'Missão especial: 20 chamados na semana sem nenhuma reabertura.', 'medalha', 'epica', null, 17, '[{"limite":1,"xp":0,"recompensa":"destaque_semana"}]');

insert into chamados.gam_missoes (codigo, nome, descricao, periodo, alvo, metrica, meta, xp, especial, conquista_tier_id, inicio) values
  ('diaria_sla', 'No prazo hoje', 'Resolver 3 chamados dentro do SLA.', 'dia', 'individual', 'resolvidos_sla', 3, 30, false, null, '2026-10-01'),
  ('semanal_avaliacao', 'Bem avaliado', 'Resolver 15 chamados com avaliação ≥ 4 na semana.', 'semana', 'individual', 'avaliados_ge4', 15, 150, false, null, '2026-10-01'),
  ('zero_reopen_week', 'Zero Reopen Week', 'Completar 20 chamados na semana sem nenhuma reabertura.', 'semana', 'individual', 'resolvidos_sem_reabertura', 20, 300, true,
    (select t.id from chamados.gam_conquista_tiers t join chamados.gam_conquistas c on c.id = t.conquista_id where c.codigo = 'semana_impecavel'), '2026-10-01'),
  ('operacao_sla', 'Operação SLA', '95% dos chamados da semana dentro do SLA (time todo).', 'semana', 'equipe', 'sla_equipe_pct', 95, 200, false, null, '2026-10-01');

insert into chamados.gam_temporadas (nome, inicio, fim, status) values ('Temporada 1 · T4 2026', '2026-10-01', '2026-12-31', 'ativa');

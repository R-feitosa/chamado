-- ============================================================================
-- Suporte técnico, "Meio urgente" como padrão e prazos (SLA) de assumir e resolver
-- ----------------------------------------------------------------------------
-- * chamados.sistemas.grupo: 'sistema' (demanda de desenvolvimento) | 'suporte' (suporte técnico).
-- * chamados.urgencias: nome e explicação de cada nível.
-- * chamados.prazos: minutos para ASSUMIR e para RESOLVER, por tipo de demanda × nível.
-- * chamados.chamados.prazo_assumir_em / prazo_em: calculados pelo banco na abertura
--   (criado_em + prazo) e congelados; mudar chamados.prazos só afeta chamados novos.
-- ============================================================================

-- Tipo de demanda: sistemas existentes = desenvolvimento; novas categorias = suporte técnico.
alter table chamados.sistemas add column grupo text not null default 'sistema' check (grupo in ('sistema', 'suporte'));
comment on column chamados.sistemas.grupo is 'sistema = demanda de desenvolvimento (software do grupo); suporte = suporte técnico (equipamento, e-mail, acessos).';
insert into chamados.sistemas (id, nome, ordem, grupo) values
  (13, 'Computador / notebook', 13, 'suporte'),
  (14, 'Impressora / scanner', 14, 'suporte'),
  (15, 'E-mail, senha e acessos', 15, 'suporte');

create table chamados.urgencias (
  nivel     smallint primary key check (nivel between 0 and 3),
  nome      text not null unique,
  descricao text not null
);
comment on table chamados.urgencias is 'Níveis de urgência e quando usar cada um.';
insert into chamados.urgencias (nivel, nome, descricao) values
  (0, 'Não urgente',   'Dúvida, ajuste ou melhoria. Dá para trabalhar normalmente enquanto isso.'),
  (1, 'Meio urgente',  'Atrapalha parte do trabalho, mas existe um jeito provisório de seguir.'),
  (2, 'Urgente',       'Impede uma tarefa importante ou com prazo hoje, e não há alternativa.'),
  (3, 'Muito urgente', 'Você ou o setor está parado, ou há risco de perder prazo de cliente, processo ou pagamento.');

create table chamados.prazos (
  grupo        text not null check (grupo in ('sistema', 'suporte')),
  nivel        smallint not null references chamados.urgencias(nivel),
  assumir_min  integer not null check (assumir_min > 0),
  resolver_min integer not null check (resolver_min > 0),
  primary key (grupo, nivel),
  check (assumir_min < resolver_min)
);
comment on table chamados.prazos is 'SLA em minutos corridos desde a abertura: prazo para assumir e para resolver, por tipo de demanda e urgência.';
insert into chamados.prazos (grupo, nivel, assumir_min, resolver_min) values
  ('sistema', 0, 1440, 7200), ('sistema', 1, 480, 2880), ('sistema', 2, 120, 480), ('sistema', 3, 30, 120),
  ('suporte', 0,  480, 2880), ('suporte', 1, 240, 1440), ('suporte', 2, 60, 240), ('suporte', 3, 15, 60);

alter table chamados.urgencias enable row level security;
alter table chamados.prazos enable row level security;
create policy urgencias_ler on chamados.urgencias for select to authenticated using (chamados.eu_pessoa_id() is not null);
create policy prazos_ler on chamados.prazos for select to authenticated using (chamados.eu_pessoa_id() is not null);
grant select on chamados.urgencias, chamados.prazos to authenticated;
grant all on chamados.urgencias, chamados.prazos to service_role;

alter table chamados.chamados alter column urgencia set default 1;
alter table chamados.chamados add constraint chamados_urgencia_fk foreign key (urgencia) references chamados.urgencias(nivel);

alter table chamados.chamados add column prazo_assumir_em timestamptz, add column prazo_em timestamptz;
comment on column chamados.chamados.prazo_assumir_em is 'Prazo para alguém do time assumir.';
comment on column chamados.chamados.prazo_em is 'Prazo para resolver.';

create function chamados.definir_prazos()
returns trigger language plpgsql set search_path = '' as $$
declare p chamados.prazos;
begin
  select pz.* into p
    from chamados.prazos pz join chamados.sistemas s on s.grupo = pz.grupo
   where s.id = new.sistema_id and pz.nivel = new.urgencia;
  if p.nivel is null then raise exception 'Urgência inválida.' using errcode = '22023'; end if;
  new.prazo_assumir_em := new.criado_em + p.assumir_min * interval '1 minute';
  new.prazo_em := new.criado_em + p.resolver_min * interval '1 minute';
  return new;
end $$;
revoke execute on function chamados.definir_prazos() from public, anon;

create trigger chamados_definir_prazos before insert or update of urgencia, sistema_id on chamados.chamados
  for each row execute function chamados.definir_prazos();

-- Dispara o gatilho nos existentes (com WHERE: o projeto usa a extensão safeupdate).
update chamados.chamados set urgencia = urgencia where prazo_em is null;
alter table chamados.chamados alter column prazo_assumir_em set not null, alter column prazo_em set not null;
create index chamados_prazo_idx on chamados.chamados (prazo_em) where status <> 'resolvido';

notify pgrst, 'reload schema';

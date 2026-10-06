-- Chat descartável entre quem abriu o chamado e o time.
--
-- * Quem abriu não faz login: entra com protocolo + código secreto gerado na abertura (o mesmo da avaliação;
--   o banco guarda só o SHA-256 em chamados.codigo_avaliacao_hash). Só RPCs, nunca a tabela.
-- * Do time escrevem o responsável e quem aceitou ajudar; antes de alguém assumir, qualquer dev. Gestor e demais só leem.
-- * Fecha quando o chamado é resolvido (só leitura) e o texto é apagado 24 h depois (update, nada é deletado);
--   reabrir reabre a conversa.
-- * Mensagem nova de quem abriu avisa o time por push (tipo 'chat', sem o texto da mensagem).

create table chamados.chat_mensagens (
  id         bigint generated always as identity primary key,
  chamado_id uuid not null references chamados.chamados(id) on delete cascade,
  autor      text not null check (autor in ('solicitante', 'time')),
  pessoa_id  uuid references chamados.pessoas(id),
  texto      text check (texto is null or char_length(texto) between 1 and 1000),
  criada_em  timestamptz not null default now(),
  apagada_em timestamptz,
  check ((texto is null) = (apagada_em is not null)),
  check ((autor = 'time') = (pessoa_id is not null))
);
create index chat_mensagens_chamado_idx on chamados.chat_mensagens (chamado_id, id);
create index chat_mensagens_descarte_idx on chamados.chat_mensagens (chamado_id) where apagada_em is null;
comment on table chamados.chat_mensagens is 'Chat do chamado. Texto apagado (texto nulo, apagada_em) 24 h depois de resolvido.';

-- Até onde cada pessoa do time já leu (contador de não lidas no painel).
create table chamados.chat_leituras (
  chamado_id uuid not null references chamados.chamados(id) on delete cascade,
  pessoa_id  uuid not null references chamados.pessoas(id) on delete cascade,
  lido_ate   bigint not null default 0,
  primary key (chamado_id, pessoa_id)
);

alter table chamados.chat_mensagens enable row level security;
alter table chamados.chat_leituras enable row level security;
create policy chat_ler on chamados.chat_mensagens for select to authenticated using (chamados.eh_dev() or chamados.eh_gestor());
create policy chat_leituras_minhas on chamados.chat_leituras for select to authenticated using (pessoa_id = chamados.eu_pessoa_id());
grant select on chamados.chat_mensagens, chamados.chat_leituras to authenticated;
grant all on chamados.chat_mensagens, chamados.chat_leituras to service_role;
alter publication supabase_realtime add table chamados.chat_mensagens;

-- Avisos de chat entram na mesma fila do push.
alter table chamados.push_envios drop constraint push_envios_tipo_check,
  add constraint push_envios_tipo_check check (tipo in ('novo', 'lembrete', 'escalada_gestor', 'prazo_perto', 'prazo_vencido', 'teste', 'chat'));

-- ============ Regras ============
create function chamados.chat_estado(p_c chamados.chamados)
returns text language sql stable set search_path = '' as $fn$
  select case when p_c.status <> 'resolvido' then 'aberto'
              when p_c.resolvido_em < now() - interval '24 hours' then 'apagado'
              else 'fechado' end
$fn$;

-- Chamado pelo protocolo + código secreto de quem abriu (mesma conferência da avaliação).
create function chamados.chat_chamado_do_codigo(p_protocolo text, p_codigo text)
returns chamados.chamados language plpgsql stable security definer set search_path = '' as $fn$
declare c chamados.chamados;
begin
  select * into c from chamados.chamados where protocolo = upper(btrim(p_protocolo));
  if c.id is null or c.codigo_avaliacao_hash is null
     or c.codigo_avaliacao_hash <> extensions.digest(coalesce(lower(btrim(p_codigo)), ''), 'sha256') then
    raise exception 'Link da conversa inválido.' using errcode = '42501';
  end if;
  return c;
end $fn$;

create function chamados.chat_pode_escrever(p_c chamados.chamados, p_pessoa uuid)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select p_c.status <> 'resolvido'
     and exists (select 1 from chamados.pessoas where id = p_pessoa and ativo and papel = 'dev')
     and (p_c.responsavel_id is null or p_c.responsavel_id = p_pessoa
          or exists (select 1 from chamados.colaboracoes where chamado_id = p_c.id and ajudante_id = p_pessoa and status = 'confirmada'))
$fn$;

create function chamados.chat_lista(p_chamado uuid, p_depois bigint)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'autor', m.autor, 'texto', m.texto, 'criada_em', m.criada_em, 'apagada', m.apagada_em is not null,
           'nome', case when m.autor = 'time' then split_part(p.nome, ' ', 1) end) order by m.id), '[]'::jsonb)
    from chamados.chat_mensagens m left join chamados.pessoas p on p.id = m.pessoa_id
   where m.chamado_id = p_chamado and m.id > coalesce(p_depois, 0)
$fn$;

-- ============ Quem abriu (sem login) ============
create function chamados.chat_ler(p_protocolo text, p_codigo text, p_depois bigint default 0)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare c chamados.chamados := chamados.chat_chamado_do_codigo(p_protocolo, p_codigo);
begin
  return jsonb_build_object(
    'protocolo', c.protocolo,
    'estado', chamados.chat_estado(c),
    'apaga_em', case when c.status = 'resolvido' then c.resolvido_em + interval '24 hours' end,
    'responsavel', (select split_part(nome, ' ', 1) from chamados.pessoas where id = c.responsavel_id),
    'mensagens', chamados.chat_lista(c.id, p_depois));
end $fn$;

create function chamados.chat_enviar(p_protocolo text, p_codigo text, p_texto text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  c chamados.chamados := chamados.chat_chamado_do_codigo(p_protocolo, p_codigo);
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id bigint;
  v_para uuid[];
begin
  if c.status = 'resolvido' then raise exception 'A conversa foi encerrada: o chamado já foi resolvido.' using errcode = 'P0001'; end if;
  if char_length(v_texto) not between 1 and 1000 then raise exception 'Escreva uma mensagem de até 1.000 caracteres.' using errcode = '22023'; end if;
  if (select count(*) from chamados.chat_mensagens where chamado_id = c.id and autor = 'solicitante' and criada_em > now() - interval '1 minute') >= 10
     or (select count(*) from chamados.chat_mensagens where chamado_id = c.id) >= 200 then
    raise exception 'Muitas mensagens. Aguarde um pouco para enviar de novo.' using errcode = 'P0001';
  end if;
  insert into chamados.chat_mensagens (chamado_id, autor, texto) values (c.id, 'solicitante', v_texto) returning id into v_id;

  -- Push para quem cuida (responsável + ajudantes); sem responsável, para o time. Sem o texto (LGPD).
  v_para := case when c.responsavel_id is null then chamados.push_devs(c.solicitante_id)
                 else array_append(array(select ajudante_id from chamados.colaboracoes where chamado_id = c.id and status = 'confirmada'), c.responsavel_id) end;
  begin
    insert into chamados.push_envios (pessoa_id, chamado_id, tipo, seq, payload, expira_em)
    select p.id, c.id, 'chat', v_id,
           jsonb_build_object('titulo', '💬 Nova mensagem · ' || c.protocolo, 'corpo', 'Quem abriu o chamado escreveu no chat. Abra a Central para ler e responder.',
                              'tipo', 'chat', 'protocolo', c.protocolo, 'urgencia', c.urgencia, 'tag', 'chat-' || c.protocolo, 'url', '/',
                              'vibrar', '[120,60,120]'::jsonb, 'exigirInteracao', false),
           now() + interval '2 hours'
      from chamados.pessoas p
     where p.id = any(v_para) and p.ativo
       and exists (select 1 from chamados.push_inscricoes i where i.pessoa_id = p.id and i.desativada_em is null)
    on conflict (pessoa_id, chamado_id, tipo, seq) where chamado_id is not null do nothing;
    if found then perform chamados.push_disparar(); end if;
  exception when others then
    raise warning 'chat push: %', sqlerrm;  -- o aviso nunca impede a mensagem
  end;
  return jsonb_build_object('id', v_id);
end $fn$;

-- ============ Time ============
create function chamados.chat_enviar_time(p_chamado uuid, p_texto text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  eu uuid := chamados.eu_pessoa_id();
  c chamados.chamados;
  v_texto text := btrim(coalesce(p_texto, ''));
  v_id bigint;
begin
  select * into c from chamados.chamados where id = p_chamado;
  if c.id is null or eu is null or not (chamados.eh_dev() or chamados.eh_gestor()) then
    raise exception 'Chamado não encontrado.' using errcode = '42501';
  end if;
  if c.status = 'resolvido' then raise exception 'A conversa foi encerrada: o chamado já foi resolvido.' using errcode = 'P0001'; end if;
  if not chamados.chat_pode_escrever(c, eu) then
    raise exception 'Só o responsável e quem ajuda escrevem nesta conversa.' using errcode = '42501';
  end if;
  if char_length(v_texto) not between 1 and 1000 then raise exception 'Escreva uma mensagem de até 1.000 caracteres.' using errcode = '22023'; end if;
  if (select count(*) from chamados.chat_mensagens where chamado_id = c.id and pessoa_id = eu and criada_em > now() - interval '1 minute') >= 20
     or (select count(*) from chamados.chat_mensagens where chamado_id = c.id) >= 200 then
    raise exception 'Muitas mensagens. Aguarde um pouco para enviar de novo.' using errcode = 'P0001';
  end if;
  insert into chamados.chat_mensagens (chamado_id, autor, pessoa_id, texto) values (c.id, 'time', eu, v_texto) returning id into v_id;
  insert into chamados.chat_leituras (chamado_id, pessoa_id, lido_ate) values (c.id, eu, v_id)
  on conflict (chamado_id, pessoa_id) do update set lido_ate = greatest(chamados.chat_leituras.lido_ate, excluded.lido_ate);
  return jsonb_build_object('id', v_id);
end $fn$;

create function chamados.chat_marcar_lido(p_chamado uuid)
returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id();
begin
  if eu is null or not (chamados.eh_dev() or chamados.eh_gestor()) then raise exception 'Só o time.' using errcode = '42501'; end if;
  insert into chamados.chat_leituras (chamado_id, pessoa_id, lido_ate)
  select p_chamado, eu, coalesce(max(id), 0) from chamados.chat_mensagens where chamado_id = p_chamado
  on conflict (chamado_id, pessoa_id) do update set lido_ate = greatest(chamados.chat_leituras.lido_ate, excluded.lido_ate);
end $fn$;

-- Resumo por chamado para o painel: total, não lidas (de quem abriu) e se eu posso escrever.
create function chamados.chat_resumo()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare eu uuid := chamados.eu_pessoa_id();
begin
  if eu is null or not (chamados.eh_dev() or chamados.eh_gestor()) then raise exception 'Só o time.' using errcode = '42501'; end if;
  return (select coalesce(jsonb_object_agg(x.chamado_id, jsonb_build_object('total', x.total, 'nao_lidas', x.nao_lidas, 'ultima_em', x.ultima_em)), '{}'::jsonb)
            from (select m.chamado_id, count(*) as total,
                         count(*) filter (where m.autor = 'solicitante' and m.id > coalesce(l.lido_ate, 0)) as nao_lidas,
                         max(m.criada_em) as ultima_em
                    from chamados.chat_mensagens m
                    left join chamados.chat_leituras l on l.chamado_id = m.chamado_id and l.pessoa_id = eu
                   group by m.chamado_id) x);
end $fn$;

-- ============ Descarte (chamado pelo agendador do push, a cada minuto) ============
create function chamados.chat_descartar()
returns integer language plpgsql volatile security definer set search_path = '' as $fn$
declare v integer;
begin
  update chamados.chat_mensagens m set texto = null, apagada_em = now()
    from chamados.chamados c
   where m.chamado_id = c.id and m.apagada_em is null
     and c.status = 'resolvido' and c.resolvido_em < now() - interval '24 hours';
  get diagnostics v = row_count;
  return v;
end $fn$;

-- O agendador do push passa a chamar o descarte do chat.
create or replace function chamados.push_agendar()
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_agora timestamptz := now();
  v_exp boolean := chamados.push_no_expediente(now());
  v_n integer := 0;
  c chamados.chamados;
  r chamados.push_regras;
  v_seq integer;
  v_cancel integer;
  v_chat integer;
begin
  if not pg_try_advisory_xact_lock(hashtext('chamados.push_agendar')) then
    return jsonb_build_object('ocupado', true);
  end if;

  update chamados.push_envios e set cancelado_em = v_agora
    from chamados.chamados ch
   where e.chamado_id = ch.id and e.enviado_em is null and e.cancelado_em is null
     and e.tipo in ('novo', 'lembrete', 'escalada_gestor')
     and (ch.responsavel_id is not null or ch.status = 'resolvido');
  get diagnostics v_cancel = row_count;
  update chamados.push_envios e set cancelado_em = v_agora
    from chamados.chamados ch
   where e.chamado_id = ch.id and e.enviado_em is null and e.cancelado_em is null
     and e.tipo in ('prazo_perto', 'prazo_vencido') and ch.status = 'resolvido';

  for c in select * from chamados.chamados where status <> 'resolvido' loop
    select * into r from chamados.push_regras where nivel = c.urgencia;
    if c.responsavel_id is null then
      if c.criado_em > v_agora - interval '10 minutes' then
        v_n := v_n + chamados.push_enfileirar(c, 'novo', 0, chamados.push_devs(c.solicitante_id), v_agora + interval '15 minutes');
      end if;
      if r.repetir_min is not null and (v_exp or not r.so_expediente) then
        v_seq := floor(extract(epoch from v_agora - c.criado_em) / 60 / r.repetir_min)::int;
        if v_seq >= 1 then
          v_n := v_n + chamados.push_enfileirar(c, 'lembrete', v_seq, chamados.push_devs(c.solicitante_id),
                                                 v_agora + make_interval(mins => r.repetir_min));
        end if;
      end if;
      if r.escalar_gestor and c.prazo_assumir_em is not null and v_agora >= c.prazo_assumir_em then
        v_n := v_n + chamados.push_enfileirar(c, 'escalada_gestor', 0, chamados.push_gestores(), v_agora + interval '12 hours');
      end if;
    elsif c.prazo_em is not null then
      if v_agora >= c.prazo_em then
        v_n := v_n + chamados.push_enfileirar(c, 'prazo_vencido', 0, array[c.responsavel_id], v_agora + interval '12 hours');
      elsif v_agora >= c.prazo_em - (c.prazo_em - c.criado_em) * 0.25 then
        v_n := v_n + chamados.push_enfileirar(c, 'prazo_perto', 0, array[c.responsavel_id], c.prazo_em);
      end if;
    end if;
  end loop;

  v_chat := chamados.chat_descartar();

  if exists (select 1 from chamados.push_envios e
              where e.enviado_em is null and e.cancelado_em is null and e.expira_em > v_agora and e.tentativas < 3
                and (e.reservado_em is null or e.reservado_em < v_agora - interval '2 minutes')) then
    perform chamados.push_disparar();
  end if;
  return jsonb_build_object('enfileirados', v_n, 'cancelados', v_cancel, 'expediente', v_exp, 'chat_apagadas', v_chat);
end $fn$;

-- ============ Permissões ============
revoke all on function chamados.chat_estado(chamados.chamados), chamados.chat_chamado_do_codigo(text, text),
  chamados.chat_pode_escrever(chamados.chamados, uuid), chamados.chat_lista(uuid, bigint), chamados.chat_ler(text, text, bigint),
  chamados.chat_enviar(text, text, text), chamados.chat_enviar_time(uuid, text), chamados.chat_marcar_lido(uuid),
  chamados.chat_resumo(), chamados.chat_descartar(), chamados.push_agendar() from public, anon, authenticated;
grant execute on function chamados.chat_ler(text, text, bigint), chamados.chat_enviar(text, text, text) to anon, authenticated;
grant execute on function chamados.chat_enviar_time(uuid, text), chamados.chat_marcar_lido(uuid), chamados.chat_resumo() to authenticated;

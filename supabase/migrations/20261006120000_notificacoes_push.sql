-- Notificações push do time (dev/suporte e gestor), com frequência por urgência.
--
-- Mesmo desenho do push do Atlas Ponto (ponto_atlas.push_*, Edge Function send-punch-reminder):
--   * o BANCO decide quando avisar: gatilho na abertura (aviso "novo") + chamados.push_agendar() pelo pg_cron
--     a cada minuto (lembretes enquanto ninguém assume, escalada ao gestor, prazo de resolver perto/vencido);
--   * os avisos vão para a fila chamados.push_envios; chamados.push_disparar() chama a Edge Function
--     chamados-push pelo pg_net com o segredo de despacho guardado no Vault;
--   * a Edge Function pega o lote (push_lote), criptografa e entrega (Web Push/VAPID) e confirma (push_confirmar).
-- Segredos ficam no Vault (exceção autorizada à regra "tudo no schema chamados"): chamados_push_dispatch_secret
-- e o par VAPID chamados_push_vapid_public/private, gerado pela própria Edge Function no primeiro envio.
-- O payload leva só protocolo, sistema, urgência e prazos (nunca descrição, prints ou nomes).

-- ============ Regras por urgência ============
create table chamados.push_regras (
  nivel            smallint primary key check (nivel between 0 and 3),
  repetir_min      integer check (repetir_min is null or repetir_min >= 1),
  so_expediente    boolean not null,
  vibrar           integer[] not null default '{200}',
  exigir_interacao boolean not null default false,
  escalar_gestor   boolean not null default true
);
comment on table chamados.push_regras is
  'Frequência dos avisos enquanto o chamado está sem responsável. repetir_min nulo = só o primeiro aviso. so_expediente: lembretes só no expediente (gam_config.expediente).';
insert into chamados.push_regras (nivel, repetir_min, so_expediente, vibrar, exigir_interacao) values
  (0, 240, true,  '{120}',                         false),
  (1,  60, true,  '{150,80,150}',                  false),
  (2,  15, false, '{250,100,250,100,250}',         true),
  (3,   5, false, '{400,150,400,150,400,150,400}', true);

-- ============ Aparelhos inscritos ============
create table chamados.push_inscricoes (
  id                  uuid primary key default gen_random_uuid(),
  pessoa_id           uuid not null references chamados.pessoas(id) on delete cascade,
  user_id             uuid not null,
  endpoint            text not null unique
    check (endpoint ~ '^https://(fcm\.googleapis\.com|([a-z0-9-]+\.)*push\.apple\.com|([a-z0-9-]+\.)*push\.services\.mozilla\.com|([a-z0-9-]+\.)*notify\.windows\.com)/'
           and char_length(endpoint) <= 1000),
  p256dh              text not null check (p256dh ~ '^[A-Za-z0-9_-]{80,100}$'),
  auth                text not null check (auth ~ '^[A-Za-z0-9_-]{16,32}$'),
  user_agent          text,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  ultimo_envio_em     timestamptz,
  falhas_consecutivas integer not null default 0,
  desativada_em       timestamptz
);
create index push_inscricoes_pessoa_idx on chamados.push_inscricoes (pessoa_id);
comment on table chamados.push_inscricoes is 'Navegadores/aparelhos do time que aceitaram notificações (Web Push). Cancelada/expirada = desativada_em preenchido (nada é apagado).';

-- ============ Fila de envios ============
create table chamados.push_envios (
  id           bigint generated always as identity primary key,
  pessoa_id    uuid not null references chamados.pessoas(id) on delete cascade,
  chamado_id   uuid references chamados.chamados(id) on delete cascade,
  tipo         text not null check (tipo in ('novo', 'lembrete', 'escalada_gestor', 'prazo_perto', 'prazo_vencido', 'teste')),
  seq          integer not null default 0,
  payload      jsonb not null,
  expira_em    timestamptz not null,
  criado_em    timestamptz not null default now(),
  reservado_em timestamptz,
  tentativas   integer not null default 0,
  enviado_em   timestamptz,
  cancelado_em timestamptz,
  resultado    jsonb
);
create unique index push_envios_unico on chamados.push_envios (pessoa_id, chamado_id, tipo, seq) where chamado_id is not null;
create index push_envios_pendentes on chamados.push_envios (id) where enviado_em is null and cancelado_em is null;
comment on table chamados.push_envios is 'Fila de avisos. Idempotente por (pessoa, chamado, tipo, seq).';

alter table chamados.push_regras enable row level security;
alter table chamados.push_inscricoes enable row level security;
alter table chamados.push_envios enable row level security;
grant all on chamados.push_regras, chamados.push_inscricoes, chamados.push_envios to service_role;

-- ============ Utilitários ============
create function chamados.push_no_expediente(p_ts timestamptz)
returns boolean language sql stable security definer set search_path = '' as $fn$
  with e as (select coalesce(chamados.gam_cfg('expediente'), '{"dias":[1,2,3,4,5],"inicio":"08:00","fim":"18:00"}'::jsonb) as v)
  select extract(isodow from p_ts at time zone 'America/Fortaleza')::int in (select jsonb_array_elements_text(e.v->'dias')::int)
     and (p_ts at time zone 'America/Fortaleza')::time >= (e.v->>'inicio')::time
     and (p_ts at time zone 'America/Fortaleza')::time <  (e.v->>'fim')::time
    from e
$fn$;

create function chamados.push_segredo_valido(p_segredo text)
returns boolean language plpgsql stable security definer set search_path = '' as $fn$
begin
  return p_segredo is not null and exists (
    select 1 from vault.decrypted_secrets where name = 'chamados_push_dispatch_secret' and decrypted_secret = p_segredo);
end $fn$;

-- Texto do aviso. Nada de descrição, prints ou nomes de pessoas.
create function chamados.push_payload(p_c chamados.chamados, p_tipo text)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_urg text := (array['Não urgente', 'Meio urgente', 'Urgente', 'Muito urgente'])[p_c.urgencia + 1];
  v_ico text := (array['🟢', '🔵', '🟠', '🔴'])[p_c.urgencia + 1];
  v_sis text := (select nome from chamados.sistemas where id = p_c.sistema_id);
  v_min integer := greatest(0, floor(extract(epoch from now() - p_c.criado_em) / 60))::int;
  v_espera text := case when v_min < 60 then v_min || ' min' else (v_min / 60) || ' h' || case when v_min % 60 > 0 and v_min < 600 then ' ' || (v_min % 60) || ' min' else '' end end;
  v_hora text := to_char(p_c.prazo_assumir_em at time zone 'America/Fortaleza', 'HH24:MI');
  v_hres text := to_char(p_c.prazo_em at time zone 'America/Fortaleza', 'DD/MM HH24:MI');
  v_r chamados.push_regras;
  v_tit text; v_corpo text;
begin
  select * into v_r from chamados.push_regras where nivel = p_c.urgencia;
  case p_tipo
    when 'novo' then
      v_tit := v_ico || ' Novo chamado · ' || v_urg;
      v_corpo := p_c.protocolo || ' · ' || v_sis || '. Assumir até ' || v_hora || '.';
    when 'lembrete' then
      v_tit := v_ico || ' Sem responsável há ' || v_espera;
      v_corpo := p_c.protocolo || ' · ' || v_sis || ' · ' || v_urg || '. Assumir até ' || v_hora || '.';
    when 'escalada_gestor' then
      v_tit := v_ico || ' Prazo de assumir vencido';
      v_corpo := p_c.protocolo || ' · ' || v_sis || ' · ' || v_urg || ': ninguém assumiu até ' || v_hora || '.';
    when 'prazo_perto' then
      v_tit := v_ico || ' Prazo perto · ' || p_c.protocolo;
      v_corpo := v_sis || ' · ' || v_urg || '. Resolver até ' || v_hres || '.';
    when 'prazo_vencido' then
      v_tit := v_ico || ' Prazo de resolver vencido · ' || p_c.protocolo;
      v_corpo := v_sis || ' · ' || v_urg || '. Venceu em ' || v_hres || '. Se houver motivo, justifique o atraso.';
    else
      v_tit := 'Central de Chamados'; v_corpo := p_c.protocolo;
  end case;
  return jsonb_build_object(
    'titulo', v_tit, 'corpo', v_corpo, 'tipo', p_tipo, 'protocolo', p_c.protocolo, 'urgencia', p_c.urgencia,
    'tag', 'chamado-' || p_c.protocolo, 'url', '/',
    'vibrar', to_jsonb(coalesce(v_r.vibrar, '{200}')),
    'exigirInteracao', coalesce(v_r.exigir_interacao, false) and p_tipo in ('novo', 'lembrete', 'escalada_gestor', 'prazo_vencido'));
end $fn$;

-- Enfileira um aviso para cada destinatário (só quem tem aparelho inscrito). Devolve quantos entraram.
create function chamados.push_enfileirar(p_c chamados.chamados, p_tipo text, p_seq integer, p_pessoas uuid[], p_expira timestamptz)
returns integer language plpgsql security definer set search_path = '' as $fn$
declare v_n integer;
begin
  insert into chamados.push_envios (pessoa_id, chamado_id, tipo, seq, payload, expira_em)
  select p.id, p_c.id, p_tipo, p_seq, chamados.push_payload(p_c, p_tipo), p_expira
    from chamados.pessoas p
   where p.id = any(p_pessoas) and p.ativo
     and exists (select 1 from chamados.push_inscricoes i where i.pessoa_id = p.id and i.desativada_em is null)
  on conflict (pessoa_id, chamado_id, tipo, seq) where chamado_id is not null do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $fn$;

create function chamados.push_devs(p_exceto uuid default null)
returns uuid[] language sql stable security definer set search_path = '' as $fn$
  select coalesce(array_agg(id), '{}') from chamados.pessoas
   where ativo and papel = 'dev' and not gestor and id is distinct from p_exceto
$fn$;

create function chamados.push_gestores()
returns uuid[] language sql stable security definer set search_path = '' as $fn$
  select coalesce(array_agg(id), '{}') from chamados.pessoas where ativo and gestor
$fn$;

-- Chama a Edge Function (assíncrono, pg_net). Sem segredo no Vault, não faz nada.
create function chamados.push_disparar()
returns void language plpgsql security definer set search_path = '' as $fn$
declare v_segredo text;
begin
  select decrypted_secret into v_segredo from vault.decrypted_secrets where name = 'chamados_push_dispatch_secret';
  if v_segredo is null then return; end if;
  perform net.http_post(
    url := 'https://ashxrwwlcarvqdigoxsi.supabase.co/functions/v1/chamados-push',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-chamados-push-secret', v_segredo),
    timeout_milliseconds := 20000);
end $fn$;

-- ============ Aviso imediato na abertura ============
create function chamados.push_ao_abrir()
returns trigger language plpgsql security definer set search_path = '' as $fn$
declare v_r chamados.push_regras;
begin
  begin
    select * into v_r from chamados.push_regras where nivel = new.urgencia;
    if chamados.push_enfileirar(new, 'novo', 0, chamados.push_devs(new.solicitante_id),
         now() + make_interval(mins => greatest(coalesce(v_r.repetir_min, 240), 15))) > 0 then
      perform chamados.push_disparar();
    end if;
  exception when others then
    -- Notificação nunca pode impedir a abertura do chamado.
    raise warning 'push_ao_abrir: %', sqlerrm;
  end;
  return null;
end $fn$;
create trigger chamados_push_novo after insert on chamados.chamados
  for each row execute function chamados.push_ao_abrir();

-- ============ Agendador (pg_cron, 1 min) ============
create function chamados.push_agendar()
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_agora timestamptz := now();
  v_exp boolean := chamados.push_no_expediente(now());
  v_n integer := 0;
  c chamados.chamados;
  r chamados.push_regras;
  v_seq integer;
  v_cancel integer;
begin
  if not pg_try_advisory_xact_lock(hashtext('chamados.push_agendar')) then
    return jsonb_build_object('ocupado', true);
  end if;

  -- Avisos de "assumir" que ficaram velhos: alguém já assumiu ou o chamado foi resolvido.
  update chamados.push_envios e set cancelado_em = v_agora
    from chamados.chamados ch
   where e.chamado_id = ch.id and e.enviado_em is null and e.cancelado_em is null
     and e.tipo in ('novo', 'lembrete', 'escalada_gestor')
     and (ch.responsavel_id is not null or ch.status = 'resolvido');
  get diagnostics v_cancel = row_count;
  -- Prazo de resolver: cancela se já resolvido.
  update chamados.push_envios e set cancelado_em = v_agora
    from chamados.chamados ch
   where e.chamado_id = ch.id and e.enviado_em is null and e.cancelado_em is null
     and e.tipo in ('prazo_perto', 'prazo_vencido') and ch.status = 'resolvido';

  for c in select * from chamados.chamados where status <> 'resolvido' loop
    select * into r from chamados.push_regras where nivel = c.urgencia;
    if c.responsavel_id is null then
      -- Novo que escapou do gatilho (ex.: falha momentânea): manda em até 10 min da abertura.
      if c.criado_em > v_agora - interval '10 minutes' then
        v_n := v_n + chamados.push_enfileirar(c, 'novo', 0, chamados.push_devs(c.solicitante_id), v_agora + interval '15 minutes');
      end if;
      -- Lembretes: seq = quantos intervalos já passaram desde a abertura. Fora do expediente, só os de 24 h.
      if r.repetir_min is not null and (v_exp or not r.so_expediente) then
        v_seq := floor(extract(epoch from v_agora - c.criado_em) / 60 / r.repetir_min)::int;
        if v_seq >= 1 then
          v_n := v_n + chamados.push_enfileirar(c, 'lembrete', v_seq, chamados.push_devs(c.solicitante_id),
                                                 v_agora + make_interval(mins => r.repetir_min));
        end if;
      end if;
      -- Escalada: prazo de assumir vencido → avisa o gestor uma vez.
      if r.escalar_gestor and c.prazo_assumir_em is not null and v_agora >= c.prazo_assumir_em then
        v_n := v_n + chamados.push_enfileirar(c, 'escalada_gestor', 0, chamados.push_gestores(), v_agora + interval '12 hours');
      end if;
    elsif c.prazo_em is not null then
      -- Responsável: avisa uma vez nos últimos 25% do prazo de resolver e uma vez ao vencer.
      if v_agora >= c.prazo_em then
        v_n := v_n + chamados.push_enfileirar(c, 'prazo_vencido', 0, array[c.responsavel_id], v_agora + interval '12 hours');
      elsif v_agora >= c.prazo_em - (c.prazo_em - c.criado_em) * 0.25 then
        v_n := v_n + chamados.push_enfileirar(c, 'prazo_perto', 0, array[c.responsavel_id], c.prazo_em);
      end if;
    end if;
  end loop;

  if exists (select 1 from chamados.push_envios e
              where e.enviado_em is null and e.cancelado_em is null and e.expira_em > v_agora and e.tentativas < 3
                and (e.reservado_em is null or e.reservado_em < v_agora - interval '2 minutes')) then
    perform chamados.push_disparar();
  end if;
  return jsonb_build_object('enfileirados', v_n, 'cancelados', v_cancel, 'expediente', v_exp);
end $fn$;

-- ============ RPCs do time ============
create function chamados.push_exigir_time()
returns uuid language plpgsql stable security definer set search_path = '' as $fn$
declare v uuid := chamados.eu_pessoa_id();
begin
  if v is null or not (chamados.eh_dev() or chamados.eh_gestor()) then
    raise exception 'Notificações são só para o time.' using errcode = '42501';
  end if;
  return v;
end $fn$;

create function chamados.push_config()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  perform chamados.push_exigir_time();
  return jsonb_build_object(
    'vapid_public_key', (select decrypted_secret from vault.decrypted_secrets where name = 'chamados_push_vapid_public'),
    'expediente', chamados.gam_cfg('expediente'),
    'regras', (select jsonb_agg(to_jsonb(r) order by r.nivel desc) from chamados.push_regras r),
    'aparelhos', (select count(*) from chamados.push_inscricoes where pessoa_id = chamados.eu_pessoa_id() and desativada_em is null));
end $fn$;

create function chamados.push_inscrever(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_pessoa uuid := chamados.push_exigir_time(); v_id uuid;
begin
  -- A inscrição pertence ao navegador: se outra pessoa do time logar no mesmo aparelho, passa a ser dela.
  insert into chamados.push_inscricoes as i (pessoa_id, user_id, endpoint, p256dh, auth, user_agent)
  values (v_pessoa, auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_user_agent, 300))
  on conflict (endpoint) do update
     set pessoa_id = excluded.pessoa_id, user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
         user_agent = excluded.user_agent, atualizado_em = now(), falhas_consecutivas = 0, desativada_em = null
  returning i.id into v_id;
  -- Até 10 aparelhos ativos por pessoa (desativa os mais antigos).
  update chamados.push_inscricoes set desativada_em = now()
   where pessoa_id = v_pessoa and desativada_em is null
     and id not in (select id from chamados.push_inscricoes where pessoa_id = v_pessoa and desativada_em is null order by atualizado_em desc limit 10);
  return jsonb_build_object('id', v_id);
end $fn$;

create function chamados.push_cancelar(p_endpoint text)
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  update chamados.push_inscricoes set desativada_em = now() where endpoint = p_endpoint and pessoa_id = chamados.push_exigir_time();
end $fn$;

-- Aviso de teste para os aparelhos de quem pediu (máx. 1 por minuto).
create function chamados.push_testar()
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_pessoa uuid := chamados.push_exigir_time(); v_n integer;
begin
  if not exists (select 1 from chamados.push_inscricoes where pessoa_id = v_pessoa and desativada_em is null) then
    raise exception 'Ative as notificações neste aparelho primeiro.' using errcode = '22023';
  end if;
  if exists (select 1 from chamados.push_envios where pessoa_id = v_pessoa and tipo = 'teste' and criado_em > now() - interval '1 minute') then
    raise exception 'Aguarde um minuto para testar de novo.' using errcode = '22023';
  end if;
  insert into chamados.push_envios (pessoa_id, tipo, payload, expira_em)
  values (v_pessoa, 'teste', jsonb_build_object('titulo', '🔔 Notificações ativadas', 'corpo', 'É assim que os chamados novos vão chegar neste aparelho.',
          'tipo', 'teste', 'urgencia', 1, 'tag', 'teste', 'url', '/', 'vibrar', '[150,80,150]'::jsonb, 'exigirInteracao', false),
          now() + interval '10 minutes');
  get diagnostics v_n = row_count;
  perform chamados.push_disparar();
  return jsonb_build_object('enfileirado', v_n);
end $fn$;

-- ============ RPCs da Edge Function (service_role + segredo) ============
create function chamados.push_lote(p_segredo text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_envios jsonb;
begin
  if not chamados.push_segredo_valido(p_segredo) then
    raise exception 'Segredo de despacho inválido.' using errcode = '42501';
  end if;
  with candidatos as (
    select e.id from chamados.push_envios e
     where e.enviado_em is null and e.cancelado_em is null and e.expira_em > now() and e.tentativas < 3
       and (e.reservado_em is null or e.reservado_em < now() - interval '2 minutes')
     order by e.id limit 200
     for update skip locked
  ), reservados as (
    update chamados.push_envios e set reservado_em = now(), tentativas = e.tentativas + 1
      from candidatos c where e.id = c.id
    returning e.id, e.pessoa_id, e.tipo, e.payload, e.expira_em
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'tipo', r.tipo, 'payload', r.payload, 'expira_em', r.expira_em,
           'inscricoes', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'endpoint', i.endpoint, 'p256dh', i.p256dh, 'auth', i.auth))
                                     from chamados.push_inscricoes i where i.pessoa_id = r.pessoa_id and i.desativada_em is null), '[]'::jsonb)
         ) order by r.id), '[]'::jsonb)
    into v_envios from reservados r;
  return jsonb_build_object(
    'vapid', (select case when pub.decrypted_secret is null or priv.decrypted_secret is null then null
                     else jsonb_build_object('publicKey', pub.decrypted_secret, 'privateKey', priv.decrypted_secret,
                                             'subject', coalesce((select valor from chamados.configuracao where chave = 'app_url'), 'https://chamado-jdc5.vercel.app')) end
                from (select 1) x
                left join vault.decrypted_secrets pub on pub.name = 'chamados_push_vapid_public'
                left join vault.decrypted_secrets priv on priv.name = 'chamados_push_vapid_private'),
    'envios', v_envios);
end $fn$;

create function chamados.push_salvar_vapid(p_segredo text, p_publica text, p_privada text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if not chamados.push_segredo_valido(p_segredo) then
    raise exception 'Segredo de despacho inválido.' using errcode = '42501';
  end if;
  if p_publica !~ '^[A-Za-z0-9_-]{86,88}$' or p_privada !~ '^[A-Za-z0-9_-]{42,44}$' then
    raise exception 'Par VAPID malformado.' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('chamados.push_vapid'));
  if not exists (select 1 from vault.secrets where name = 'chamados_push_vapid_private') then
    perform vault.create_secret(p_publica, 'chamados_push_vapid_public', 'Central de Chamados: chave pública VAPID');
    perform vault.create_secret(p_privada, 'chamados_push_vapid_private', 'Central de Chamados: chave privada VAPID (P-256)');
  end if;
  return (select jsonb_build_object('publicKey', pub.decrypted_secret, 'privateKey', priv.decrypted_secret,
                                    'subject', coalesce((select valor from chamados.configuracao where chave = 'app_url'), 'https://chamado-jdc5.vercel.app'))
            from vault.decrypted_secrets pub
            join vault.decrypted_secrets priv on priv.name = 'chamados_push_vapid_private'
           where pub.name = 'chamados_push_vapid_public');
end $fn$;

create function chamados.push_confirmar(p_segredo text, p_resultados jsonb, p_ok uuid[] default '{}', p_expiradas uuid[] default '{}', p_falhas uuid[] default '{}')
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  if not chamados.push_segredo_valido(p_segredo) then
    raise exception 'Segredo de despacho inválido.' using errcode = '42501';
  end if;
  update chamados.push_envios e
     set enviado_em = case when (r.value->>'concluido')::boolean then now() else null end,
         reservado_em = case when (r.value->>'concluido')::boolean then e.reservado_em else null end,
         resultado = r.value->'detalhe'
    from jsonb_array_elements(coalesce(p_resultados, '[]'::jsonb)) r
   where e.id = (r.value->>'envio_id')::bigint;
  -- 404/410 do push service = inscrição morta (permissão revogada, navegador limpo).
  update chamados.push_inscricoes set desativada_em = now() where id = any(p_expiradas) and desativada_em is null;
  update chamados.push_inscricoes set ultimo_envio_em = now(), falhas_consecutivas = 0 where id = any(p_ok);
  update chamados.push_inscricoes set falhas_consecutivas = least(falhas_consecutivas + 1, 1000),
         desativada_em = case when falhas_consecutivas + 1 >= 20 then coalesce(desativada_em, now()) else desativada_em end
   where id = any(p_falhas);
end $fn$;

-- ============ Permissões ============
revoke all on function chamados.push_no_expediente(timestamptz), chamados.push_segredo_valido(text),
  chamados.push_payload(chamados.chamados, text), chamados.push_enfileirar(chamados.chamados, text, integer, uuid[], timestamptz),
  chamados.push_devs(uuid), chamados.push_gestores(), chamados.push_disparar(), chamados.push_ao_abrir(), chamados.push_agendar(),
  chamados.push_exigir_time(), chamados.push_config(), chamados.push_inscrever(text, text, text, text), chamados.push_cancelar(text),
  chamados.push_testar(), chamados.push_lote(text), chamados.push_salvar_vapid(text, text, text),
  chamados.push_confirmar(text, jsonb, uuid[], uuid[], uuid[]) from public, anon, authenticated;
grant execute on function chamados.push_config(), chamados.push_inscrever(text, text, text, text), chamados.push_cancelar(text),
  chamados.push_testar() to authenticated;
grant execute on function chamados.push_lote(text), chamados.push_salvar_vapid(text, text, text),
  chamados.push_confirmar(text, jsonb, uuid[], uuid[], uuid[]) to service_role;

-- ============ Segredo de despacho e agendamento ============
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'chamados_push_dispatch_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'chamados_push_dispatch_secret',
                                'Central de Chamados: segredo que o pg_net envia à Edge Function chamados-push');
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('chamados-push', '* * * * *', 'select chamados.push_agendar()');
  end if;
end $$;

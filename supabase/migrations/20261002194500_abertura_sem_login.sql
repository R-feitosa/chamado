-- ============================================================================
-- Abertura de chamado sem login (login só para o time de dev/suporte)
-- ----------------------------------------------------------------------------
-- * catalogo_publico(): listas do formulário (setores, nomes de solicitantes,
--   sistemas, urgências, prazos). Só nome e setor; nunca e-mail ou vínculo.
-- * abrir_chamado_publico(): abre em nome de um solicitante da lista, com limite
--   contra abuso (5 por pessoa e 30 no total a cada 10 min, só abertura pública).
-- * consultar_chamado(): acompanhamento pelo protocolo; devolve situação, sistema,
--   urgência, prazos e o primeiro nome do responsável. Nunca descrição nem prints.
-- * Prints sem login: pasta publico/ do bucket; ninguém de fora lê. Limite 5 MB.
-- * A tabela chamados continua sem leitura para anon (a fila só aparece com login).
-- ============================================================================

alter table chamados.chamados add column origem text not null default 'login' check (origem in ('login', 'publico'));
comment on column chamados.chamados.origem is 'login = aberto por usuário logado (time); publico = aberto sem login.';
create index chamados_origem_criado_idx on chamados.chamados (origem, criado_em);

create function chamados.catalogo_publico()
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object(
    'setores',   coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome, 'ordem', ordem) order by ordem) from chamados.setores), '[]'),
    'pessoas',   coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome, 'setor_id', setor_id) order by nome)
                             from chamados.pessoas where ativo and papel = 'solicitante'), '[]'),
    'sistemas',  coalesce((select jsonb_agg(jsonb_build_object('id', id, 'nome', nome, 'ordem', ordem, 'ativo', ativo, 'grupo', grupo) order by ordem)
                             from chamados.sistemas where ativo), '[]'),
    'urgencias', coalesce((select jsonb_agg(to_jsonb(u) order by nivel) from chamados.urgencias u), '[]'),
    'prazos',    coalesce((select jsonb_agg(to_jsonb(p)) from chamados.prazos p), '[]'))
$fn$;

create function chamados.abrir_chamado_publico(
  p_solicitante_id uuid, p_sistema_id integer, p_descricao text, p_urgencia integer, p_prints text[] default '{}'
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare c chamados.chamados; pr text;
begin
  if not exists (select 1 from chamados.pessoas where id = p_solicitante_id and ativo and papel = 'solicitante') then
    raise exception 'Escolha seu nome na lista.' using errcode = '22023';
  end if;
  if (select count(*) from chamados.chamados where solicitante_id = p_solicitante_id and origem = 'publico'
        and criado_em > now() - interval '10 minutes') >= 5
     or (select count(*) from chamados.chamados where origem = 'publico' and criado_em > now() - interval '10 minutes') >= 30 then
    raise exception 'Muitos chamados em pouco tempo. Aguarde alguns minutos e tente de novo.' using errcode = 'P0001';
  end if;
  foreach pr in array coalesce(p_prints, '{}') loop
    if pr !~ '^publico/[0-9a-f-]{36}\.(png|jpg|webp|gif)$'
       or exists (select 1 from chamados.chamados x where pr = any (x.prints)) then
      raise exception 'Print inválido.' using errcode = '22023';
    end if;
  end loop;
  insert into chamados.chamados (descricao, solicitante_id, sistema_id, urgencia, prints, origem)
  values (btrim(p_descricao), p_solicitante_id, p_sistema_id, p_urgencia, coalesce(p_prints, '{}'), 'publico')
  returning * into c;
  insert into chamados.eventos (chamado_id, autor_id, acao) values (c.id, p_solicitante_id, 'aberto');
  return jsonb_build_object('protocolo', c.protocolo, 'sistema_id', c.sistema_id, 'urgencia', c.urgencia,
    'prints', cardinality(c.prints), 'criado_em', c.criado_em, 'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em);
end $fn$;

create function chamados.consultar_chamado(p_protocolo text)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object(
    'protocolo', c.protocolo, 'status', c.status, 'sistema', s.nome, 'grupo', s.grupo, 'urgencia', c.urgencia,
    'criado_em', c.criado_em, 'assumido_em', c.assumido_em, 'resolvido_em', c.resolvido_em,
    'prazo_assumir_em', c.prazo_assumir_em, 'prazo_em', c.prazo_em,
    'responsavel', split_part(r.nome, ' ', 1))
  from chamados.chamados c
  join chamados.sistemas s on s.id = c.sistema_id
  left join chamados.pessoas r on r.id = c.responsavel_id
  where c.protocolo = upper(btrim(p_protocolo))
$fn$;

revoke execute on function chamados.catalogo_publico(), chamados.abrir_chamado_publico(uuid, integer, text, integer, text[]),
  chamados.consultar_chamado(text) from public;
grant usage on schema chamados to anon;
grant execute on function chamados.catalogo_publico(), chamados.abrir_chamado_publico(uuid, integer, text, integer, text[]),
  chamados.consultar_chamado(text) to anon, authenticated;

-- Prints sem login: só imagem, só na pasta publico/, nome aleatório. Leitura continua só do time.
create policy chamados_prints_publico on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'chamados-prints' and name ~ '^publico/[0-9a-f-]{36}\.(png|jpg|webp|gif)$');
update storage.buckets set file_size_limit = 5242880 where id = 'chamados-prints';

notify pgrst, 'reload schema';

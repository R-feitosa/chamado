-- De-para: Pode esperar(0)→0, Atrapalha(1)→2, Estou parado(2)→3. Depois limpa.
do $$ declare r text; begin
  select string_agg(protocolo || '=' || urgencia, ',' order by protocolo) into r from chamados.chamados where protocolo like 'LEGADO-%';
  if r <> 'LEGADO-0=0,LEGADO-1=2,LEGADO-2=3' then raise exception 'de-para urgência: %', r; end if;
  delete from chamados.chamados where protocolo like 'LEGADO-%';
  raise notice 'ok: de-para da urgência';
end $$;

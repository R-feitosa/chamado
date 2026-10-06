#!/usr/bin/env bash
# Sobe um Postgres temporário, aplica stub + migrations e roda os testes de regras.
# Para testar uma migration de dados, crie antes_<versão>.sql / depois_<versão>.sql nesta pasta.
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN=$(ls -d /usr/lib/postgresql/*/bin | tail -1)
DIR=$(mktemp -d); PORT=55439
trap '"$BIN/pg_ctl" -D "$DIR/db" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DIR"' EXIT
"$BIN/initdb" -D "$DIR/db" -U postgres -A trust >/dev/null
"$BIN/pg_ctl" -D "$DIR/db" -o "-p $PORT -k $DIR" -l "$DIR/log" start >/dev/null
P="psql -h $DIR -p $PORT -U postgres -d postgres -q -v ON_ERROR_STOP=1"
$P -f supabase/testes/stub_supabase.sql 2>&1 | grep -v -e wal_level -e HINT || true
for f in supabase/migrations/*.sql; do
  v=$(basename "$f" | cut -d_ -f1)
  [ -f "supabase/testes/antes_$v.sql" ] && $P -f "supabase/testes/antes_$v.sql"
  $P -f "$f"
  [ -f "supabase/testes/depois_$v.sql" ] && $P -f "supabase/testes/depois_$v.sql"
done
$P -o /dev/null -f supabase/testes/regras.sql
$P -o /dev/null -f supabase/testes/gamificacao.sql
$P -o /dev/null -f supabase/testes/notificacoes.sql
$P -o /dev/null -f supabase/testes/chat.sql

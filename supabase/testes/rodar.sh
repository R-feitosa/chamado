#!/usr/bin/env bash
# Sobe um Postgres temporário, aplica stub + migrations e roda os testes de regras.
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN=$(ls -d /usr/lib/postgresql/*/bin | tail -1)
DIR=$(mktemp -d); PORT=55439
trap '"$BIN/pg_ctl" -D "$DIR/db" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$DIR"' EXIT
"$BIN/initdb" -D "$DIR/db" -U postgres -A trust >/dev/null
"$BIN/pg_ctl" -D "$DIR/db" -o "-p $PORT -k $DIR" -l "$DIR/log" start >/dev/null
P="psql -h $DIR -p $PORT -U postgres -d postgres -q -v ON_ERROR_STOP=1"
$P -f supabase/testes/stub_supabase.sql
for f in supabase/migrations/*.sql; do $P -f "$f"; done
$P -o /dev/null -f supabase/testes/regras.sql

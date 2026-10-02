# Central de Chamados RFG

Sistema interno de chamados de sistemas do R. Feitosa Group: colaboradores abrem chamados, o time de desenvolvimento assume e resolve.

Stack: React 18 + Vite + TypeScript, Supabase (projeto ATLAS - INTEGRADO, schema `chamados`) e Vercel.

## Rodar localmente

```bash
npm install
npm run dev
```

Entre com o mesmo e-mail e senha dos sistemas ATLAS. O acesso só é liberado para quem tem o e-mail preenchido em `chamados.pessoas`.

## Verificações

```bash
npm run typecheck            # TypeScript
npm test                     # regras de fila e formatação (Vitest)
npm run build                # build de produção
./supabase/testes/rodar.sh   # permissões e regras do banco num Postgres local (rodar como usuário postgres)
```

## Publicar na Vercel

1. Importar o repositório na Vercel (framework: Vite; build `npm run build`; saída `dist`).
2. Variáveis de ambiente são opcionais: o código já aponta para o projeto ATLAS - INTEGRADO (valores em `.env.example`).
3. No Supabase, em Authentication → URL Configuration, incluir o domínio da Vercel em *Redirect URLs*.

## Liberar uma pessoa

```sql
update chamados.pessoas set email = 'nome@rfeitosa.com.br' where nome = 'Nome da lista';
```

No primeiro login com esse e-mail, a conta é vinculada automaticamente.

# Central de Chamados RFG

## O que é
Sistema interno de chamados de sistemas do R. Feitosa Group.
Colaboradores abrem chamados quando um sistema dá problema; o time de desenvolvimento assume e resolve.

## Pessoas
- Time de desenvolvimento (quem resolve): Aldo, Brenno Magalhães, Breno Azevedo, João Pedro, Ruan, Kaio.
- Solicitantes (quem abre), por setor:
  - Sócios: Roneely Feitosa, Anderson Mesquita, Fábio Mendes
  - Administrativo e Financeiro: Tayse Feitosa
  - Controladoria: Raissa, Amanda, Sarah, Julia, Sophia
  - Jurídico: Tamira, Lanna, Flávia Luquélia, Suhiane, Joana Cláudia, Nicoly Sobral, Carlos Brandão

## Perfis e telas
Dois tipos de usuário (`chamados.pessoas.papel`): **Solicitante** e **Dev/Suporte** (`dev`).
- **Abrir chamado** (todos): nome (vem do login), sistema, descrição, prints (até 3: clicar, arrastar ou Ctrl+V), urgência.
- **Meus chamados** (solicitante): os próprios chamados com situação (Aguardando o time / Em andamento com X / Resolvido) e tempo.
- **Painel do time** (dev/suporte): contagens (em aberto, sem responsável, muito urgente, meus), tempos (espera média sem responsável, mais antigo em aberto, tempo até assumir e até resolver nos últimos 30 dias), fila com coluna "Aberto há" (vermelho após 24 h), botões Assumir / Resolver / Reabrir, prints com ampliação.
- **Analytics** (dev/suporte): período (7/30/90 dias/tudo); resolvidos por técnico (barras + em andamento + tempo médio); mapas de calor técnico × sistema e técnico × setor de quem abriu.

## Sistemas atendidos
ATLAS JURIS, CRM, ATLAS RH, Atlas Consult, ATLAS Empresas, Atlas Trib, Rfast Mail, Agente WhatsApp, App Connect Valley, Site Feitosa Imóveis, Site do escritório, Outro / não sei.

## Arquivos
- `prototipo/index.html`: protótipo original (página única, referência visual e funcional).
- `src/`: sistema de produção (React 18 + Vite + TypeScript).
  - `lib/supabase.ts` cliente (schema `chamados`); `lib/api.ts` chamadas ao banco; `lib/fila.ts` e `lib/formato.ts` regras puras (com testes).
  - `lib/analytics.ts` cálculos de tempo e produtividade (com testes).
  - `telas/` Acesso, AbrirChamado, MeusChamados, Painel, Analytics, SemCadastro; `componentes/` prints, ampliação, urgência.
- `supabase/migrations/`: banco. `supabase/testes/rodar.sh` testa permissões e regras num Postgres local.

## Regras
- Toda a interface em português do Brasil.
- Visual: fonte Geist (Geist Mono para protocolos), fundo #f6f7f9, cor principal azul #2b4bee; suportar tema claro e escuro.
- Urgência em 4 níveis, sempre com cor + texto: verde (Não urgente), azul (Pouco urgente), âmbar (Urgente), vermelho (Muito urgente). No banco: 0 a 3.
- Não alterar a lista de pessoas ou de sistemas sem confirmar comigo.
- Antes de mudanças grandes, mostrar o plano e esperar aprovação.

## Banco (Supabase)
- Projeto **ATLAS - INTEGRADO** (`ashxrwwlcarvqdigoxsi`), compartilhado com os outros sistemas do grupo.
- Tudo da Central fica no schema **`chamados`**. Não criar nada em `public` nem em outros schemas.
  Únicas exceções, exigidas pelo Supabase: bucket privado `chamados-prints` (+ policies em `storage.objects`
  filtradas por esse bucket) e `chamados.chamados` na publicação `supabase_realtime`.
- Tabelas: `setores`, `pessoas` (nome, setor, papel solicitante/dev, e-mail de login), `sistemas`, `chamados`, `eventos` (histórico).
- Login: o mesmo `auth.users` dos sistemas ATLAS. A pessoa é ligada à conta pelo e-mail no primeiro acesso
  (`chamados.vincular_minha_conta`). Para liberar alguém: preencher `chamados.pessoas.email`.
- Escrita só por RPC `security definer` (`abrir_chamado`, `assumir_chamado`, `resolver_chamado`, `reabrir_chamado`),
  com `search_path = ''` e retorno `jsonb` (padrão do projeto). O front só lê, filtrado por RLS.
- Protocolo `TI-0421`, `TI-0422`… gerado pelo banco (sequência `chamados.protocolo_seq`).
- E-mails de pessoas são dado pessoal: ficam só no banco, nunca em migration ou commit.
- Antes de aplicar migration: rodar `supabase/testes/rodar.sh` (precisa de Postgres local).

## Regras de negócio
- Solicitante vê só os próprios chamados; dev vê todos e tem o Painel do time.
- Assumir: dev, chamado sem responsável e não resolvido (grava `assumido_em`, base do "tempo até assumir"). Resolver: só o responsável. Reabrir: qualquer dev; volta para "em andamento" com o mesmo responsável.
- Até 3 prints por chamado (PNG, JPG, WEBP, GIF; até 20 MB), gravados em `chamados-prints/<user_id>/…`.

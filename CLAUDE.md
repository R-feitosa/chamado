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

## Telas
- **Abrir chamado**: nome (lista por setor), sistema, descrição, prints (até 3: clicar, arrastar ou Ctrl+V), urgência (Pode esperar / Atrapalha / Estou parado).
- **Painel do time**: indicadores (em aberto, sem responsável, alguém parado, meus), fila com filtros, botões Assumir / Resolver / Reabrir, prints em miniatura com ampliação.

## Sistemas atendidos
ATLAS JURIS, CRM, ATLAS RH, Atlas Consult, ATLAS Empresas, Atlas Trib, Rfast Mail, Agente WhatsApp, App Connect Valley, Site Feitosa Imóveis, Site do escritório, Outro / não sei.

## Arquivos
- `index.html`: protótipo atual, página única sem build (HTML + CSS + JS no mesmo arquivo).

## Regras
- Toda a interface em português do Brasil.
- Visual: fonte Geist (Geist Mono para protocolos), fundo #f6f7f9, cor principal azul #2b4bee; suportar tema claro e escuro.
- Urgência sempre com cor + texto: verde (Pode esperar), âmbar (Atrapalha), vermelho (Estou parado).
- Não alterar a lista de pessoas ou de sistemas sem confirmar comigo.
- Antes de mudanças grandes, mostrar o plano e esperar aprovação.

## Próximo passo previsto
Transformar o protótipo em sistema de produção com login, na stack do grupo: React 18 + Vite + TypeScript + Supabase + Vercel.

## Observação técnica
O protótipo foi feito para rodar como página publicada no Claude, onde usa `window.claude.use('db')` e `window.claude.use('assets')` para salvar chamados e prints.
Aberto direto no navegador, sem esse ambiente, ele entra em "modo demonstração": tudo funciona, mas os chamados ficam só na tela e somem ao recarregar.
Para produção, trocar essas duas chamadas por Supabase (tabela `chamados` e bucket de Storage `prints`).

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
- **Painel do time** (dev/suporte): contagens (em aberto, sem responsável, muito urgente, meus), tempos (espera média sem responsável, mais antigo em aberto, tempo até resolver e % resolvidos no prazo nos últimos 30 dias), contagem de atrasados, fila com coluna "Prazo" (etapa atual: assumir em X / resolver em X / atrasado X, e há quanto tempo está aberto), botões Assumir / Resolver / Reabrir, prints com ampliação.
- **Analytics** (dev/suporte): período (7/30/90 dias/tudo); % assumidos e resolvidos no prazo; comparação Desenvolvimento × Suporte técnico; resolvidos por técnico (barras + em andamento + tempo médio); mapas de calor técnico × sistema e técnico × setor de quem abriu.

## Sistemas atendidos
- **Sistemas:** ATLAS JURIS, CRM, ATLAS RH, Atlas Consult, ATLAS Empresas, Atlas Trib, Rfast Mail, Agente WhatsApp, App Connect Valley, Site Feitosa Imóveis, Site do escritório, Outro / não sei.
- **Suporte técnico:** Computador / notebook, Impressora / scanner, E-mail, senha e acessos.
- Ficam em `chamados.sistemas`; a coluna `grupo` (`sistema` | `suporte`) separa os dois blocos no formulário.

## Arquivos
- `prototipo/index.html`: protótipo original (página única, referência visual e funcional).
- `src/`: sistema de produção (React 18 + Vite + TypeScript).
  - `lib/supabase.ts` cliente (schema `chamados`); `lib/api.ts` chamadas ao banco; `lib/fila.ts` e `lib/formato.ts` regras puras (com testes).
  - `lib/analytics.ts` cálculos de tempo e produtividade; `lib/sla.ts` situação do prazo (com testes).
  - `telas/` Acesso, AbrirChamado, MeusChamados, Painel, Analytics, SemCadastro; `componentes/` prints, ampliação, urgência.
- `supabase/migrations/`: banco. `supabase/testes/rodar.sh` testa permissões e regras num Postgres local.

## Regras
- Toda a interface em português do Brasil.
- Visual: fonte Geist (Geist Mono para protocolos), fundo #f6f7f9, cor principal azul #2b4bee; suportar tema claro e escuro.
- Urgência em 4 níveis, sempre com cor + texto: verde (Não urgente), azul (Meio urgente), âmbar (Urgente), vermelho (Muito urgente). No banco: 0 a 3.
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

### Urgência e prazos (SLA)
**Meio urgente é o padrão** do formulário. Cada chamado tem **dois prazos**, contados em tempo corrido a partir da abertura: **assumir** (alguém do time pegar) e **resolver**. Eles dependem do **tipo de demanda**: Desenvolvimento (sistemas) ou Suporte técnico (computador, impressora, e-mail e acessos).

| Nível | Quando usar | Dev: assumir | Dev: resolver | Suporte: assumir | Suporte: resolver |
|---|---|---|---|---|---|
| Não urgente (0) | Dúvida, ajuste ou melhoria; dá para trabalhar normalmente. | 24 h | 120 h (5 dias) | 8 h | 48 h (2 dias) |
| **Meio urgente (1) · padrão** | Atrapalha parte do trabalho, mas há um jeito provisório de seguir. | 8 h | 48 h (2 dias) | 4 h | 24 h (1 dia) |
| Urgente (2) | Impede tarefa importante ou com prazo hoje, sem alternativa. | 2 h | 8 h | 1 h | 4 h |
| Muito urgente (3) | A pessoa ou o setor está parado, ou há risco de perder prazo de cliente, processo ou pagamento. | 30 min | 2 h | 15 min | 1 h |

- Fontes únicas: `chamados.urgencias` (nome e explicação) e `chamados.prazos` (`grupo` × `nivel` → `assumir_min`, `resolver_min`). O tipo de demanda vem de `chamados.sistemas.grupo` (`sistema` = Desenvolvimento, `suporte` = Suporte técnico).
- O banco grava `prazo_assumir_em` e `prazo_em` (resolver) na abertura (gatilho `chamados_definir_prazos`, também ao trocar urgência ou sistema). Os prazos ficam congelados no chamado: mudar `chamados.prazos` só vale para chamados novos.
- Etapa que está correndo: sem responsável → **assumir**; com responsável → **resolver**. Situação: **no prazo**; **perto** (últimos 25%, âmbar); **atrasado** (vermelho). Concluída: **no prazo** se `assumido_em <= prazo_assumir_em` / `resolvido_em <= prazo_em`.
- "Atrasados" (painel) = abertos com a etapa atual vencida. Assumir com atraso não torna o chamado atrasado se o prazo de resolver ainda não venceu (mas conta contra "Assumidos no prazo").
- A fila do time ordena: sem responsável primeiro (pelo prazo de assumir), depois pelo prazo de resolver.
- Indicadores: "Assumidos no prazo" e "Resolvidos no prazo" (%) no painel (30 dias) e no Analytics (geral, por tipo de demanda e, para resolver, por técnico).

### Fluxo
- Solicitante vê só os próprios chamados; dev vê todos e tem o Painel do time.
- Assumir: dev, chamado sem responsável e não resolvido (grava `assumido_em`, base do "tempo até assumir"). Resolver: só o responsável. Reabrir: qualquer dev; volta para "em andamento" com o mesmo responsável.
- Até 3 prints por chamado (PNG, JPG, WEBP, GIF; até 20 MB), gravados em `chamados-prints/<user_id>/…`.

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
**Login só para o time de dev/suporte.** Quem abre chamado não faz login: o app abre direto no formulário.
- **Abrir chamado** (sem login): **setor e nome obrigatórios**: primeiro o setor, depois o nome numa lista filtrada por ele (o navegador lembra a última escolha), onde está o problema, descrição, prints (até 3, 5 MB cada: clicar, arrastar ou Ctrl+V), urgência. Ao enviar, mostra o protocolo e os prazos.
- **Acompanhar** (sem login): consulta pelo protocolo (aceita "TI-0422" ou "422"); mostra situação, onde, urgência, responsável (primeiro nome) e prazos. Nunca a descrição nem os prints.
- **"É dev/suporte? Entrar"** no topo: login com a conta dos sistemas ATLAS. Conta que não é dev/suporte vê "O login é só para o time".
- **Painel do time** (dev/suporte, tela inicial após o login): contagens (em aberto, sem responsável, atrasados, meus), tempos (espera média sem responsável, mais antigo em aberto, % assumidos e % resolvidos no prazo nos últimos 30 dias), fila com coluna "Prazo" (etapa atual: assumir em X / resolver em X / atrasado X, e há quanto tempo está aberto), botões Assumir / Resolver / Reabrir, prints com ampliação.
- **Analytics** (dev/suporte): período (7/30/90 dias/tudo); % assumidos e resolvidos no prazo; comparação Desenvolvimento × Suporte técnico; resolvidos por técnico (barras + % no prazo + tempo médio); mapas de calor técnico × sistema e técnico × setor de quem abriu.
- Dev logado também pode abrir chamado (em nome próprio).

## Sistemas atendidos
- **Sistemas:** ATLAS JURIS, CRM, ATLAS RH, Atlas Consult, ATLAS Empresas, Atlas Trib, Rfast Mail, Agente WhatsApp, App Connect Valley, Site Feitosa Imóveis, Site do escritório, Outro / não sei.
- **Suporte técnico:** Computador / notebook, Impressora / scanner, E-mail, senha e acessos.
- Ficam em `chamados.sistemas`; a coluna `grupo` (`sistema` | `suporte`) separa os dois blocos no formulário.

## Arquivos
- `prototipo/index.html`: protótipo original (página única, referência visual e funcional).
- `src/`: sistema de produção (React 18 + Vite + TypeScript).
  - `lib/supabase.ts` cliente (schema `chamados`); `lib/api.ts` chamadas ao banco; `lib/fila.ts` e `lib/formato.ts` regras puras (com testes).
  - `lib/analytics.ts` cálculos de tempo e produtividade; `lib/sla.ts` situação do prazo (com testes).
  - `telas/` AbrirChamado, Acompanhar, Acesso (login do time), Painel, Analytics, SemCadastro; `componentes/` prints, ampliação, urgência.
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
- Login (só dev/suporte): o mesmo `auth.users` dos sistemas ATLAS, ligado à pessoa pelo e-mail no primeiro acesso
  (`chamados.vincular_minha_conta`). Para liberar um dev: preencher `chamados.pessoas.email`.
- Sem login (papel `anon`), só três funções, nenhuma tabela:
  - `catalogo_publico()`: setores, nome e setor dos solicitantes ativos, sistemas, urgências e prazos (nunca e-mail);
  - `abrir_chamado_publico(setor, solicitante, …)`: setor e nome obrigatórios e coerentes (o nome tem de ser do setor informado), só solicitante ativo; limite de 5 por pessoa e 30 no total a cada 10 min; grava `origem = 'publico'`;
  - `consultar_chamado(protocolo)`: situação, prazos e primeiro nome do responsável.
  Prints sem login vão para `chamados-prints/publico/<uuid>.<ext>` (só gravação; leitura só do time). Limite do bucket: 5 MB.
- Escrita só por RPC `security definer` (`abrir_chamado`, `abrir_chamado_publico`, `assumir_chamado`, `resolver_chamado`, `reabrir_chamado`),
  com `search_path = ''` e retorno `jsonb` (padrão do projeto). O front logado só lê, filtrado por RLS.
- `update`/`delete` sempre com `where`: o projeto usa a extensão `safeupdate`.
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
- Solicitante não faz login: informa setor e nome (obrigatórios, conferidos pelo banco), abre pelo formulário e acompanha pelo protocolo. Dev/suporte faz login e vê todos os chamados.
- Assumir: dev, chamado sem responsável e não resolvido (grava `assumido_em`, base do "tempo até assumir"). Resolver: só o responsável. Reabrir: qualquer dev; volta para "em andamento" com o mesmo responsável.
- Até 3 prints por chamado (PNG, JPG, WEBP, GIF; até 5 MB), gravados em `chamados-prints/publico/…` (sem login) ou `chamados-prints/<user_id>/…` (dev logado).

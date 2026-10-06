# Central de Chamados RFG — contexto completo para uma nova sessão

> Cole este texto no início de um chat novo com o Claude (ou peça: "leia docs/CONTEXTO.md").
> As regras do projeto ficam em `CLAUDE.md` — leia os dois antes de mexer em qualquer coisa.

## 1. Começar
```bash
git clone https://github.com/R-feitosa/chamado.git
cd chamado
git checkout claude/intelligent-volta-xt92bs   # branch único e padrão; a Vercel publica a partir dele
npm install
npm run dev            # já aponta para o Supabase de produção (URL e chave publicável no código)
```
Verificações (rodar todas antes de qualquer push):
```bash
npx tsc -b             # tipos
npm test               # Vitest: regras de fila, prazos, analytics, convite, quem abriu (57 testes)
npm run build
./supabase/testes/rodar.sh   # permissões e regras do banco num Postgres local (rodar como usuário postgres)
```

## 2. O que é
Sistema interno de chamados do R. Feitosa Group: colaboradores abrem chamados quando um sistema ou equipamento
dá problema; o time de desenvolvimento/suporte (6 pessoas) assume e resolve, com prazos (SLA) e indicadores.
Dono do produto: Roneely Feitosa (sócio). Tudo em português do Brasil.

| Onde | Endereço |
|---|---|
| Produção (Central) | https://chamado-jdc5.vercel.app |
| Botão "Abrir chamado" no Atlas Hub | https://hub.rfeitosa.com.br (barra superior) |
| Código | https://github.com/R-feitosa/chamado |
| Vercel | equipe "R-feitosa's projects", projeto `chamado` (o conector do Claude **não** enxerga este projeto) |
| Supabase | projeto **ATLAS - INTEGRADO** `ashxrwwlcarvqdigoxsi` (compartilhado com os outros sistemas do grupo), schema **`chamados`** |
| Atlas Hub (outro repo) | https://github.com/Rfeitosagroup/atlas-hub — botão em `src/components/layout/Layout.jsx` + `src/lib/abrirChamado.js` |
| CRM (outro repo) | https://github.com/Rfeitosagroup/crm-rfeitosa (produção = branch `developer`, crm.rfeitosa.com.br) — botão em `src/components/layout/Header.jsx` + `src/lib/abrirChamado.js` |

## 3. Stack e estrutura
React 18 + Vite + TypeScript (sem framework de UI; CSS próprio em `src/styles.css`, fonte Geist, cor #2b4bee,
tema claro/escuro) + Supabase (Postgres, Auth, Storage, Realtime) + Vercel.
```
src/App.tsx            roteamento por abas; modos Público (sem login) e Dev (logado); lê token ?t= do botão do hub
src/hooks/useSessao.ts sessão: publico | dev | sem-acesso | nova-senha
src/hooks/useChamados.ts lista + tempo real (canal postgres_changes em chamados.chamados)
src/lib/supabase.ts    cliente (db.schema = 'chamados'); URL/chave publicável com padrão no código
src/lib/api.ts         todas as chamadas ao banco (RPCs, storage, catálogo)
src/lib/sla.ts         situação do prazo (assumir/resolver)     ┐
src/lib/fila.ts        filtros, ordenação, contagens do painel   │ funções puras
src/lib/analytics.ts   tempos médios, por técnico, mapas         │ com testes *.test.ts
src/lib/formato.ts     textos, validação de prints, mensagens    │
src/lib/convite.ts     token da URL do botão do hub              ┘
src/lib/gamificacao.ts nível/progresso (espelha gam_nivel), formatação (com testes); apiGam.ts; hooks/useGamificacao.ts
src/telas/Jornada, Ranking, CentralGamificacao; componentes/gam/ (Motion, carregados sob demanda)
docs/GAMIFICACAO.md    arquitetura de eventos, XP, score, antiabuso, operação
src/telas/             AbrirChamado, Acompanhar, Acesso (login do time), Painel, Analytics, SemCadastro
src/componentes/       prints (anexar, miniaturas com link assinado, ampliar), urgência, ícones
integracao/            abrir-chamado.ts + README: como instalar o botão em outro sistema do hub
supabase/migrations/   12 migrations (todas já aplicadas em produção; 4 da gamificação: 20261005140000…170000)
supabase/testes/       stub do Supabase + regras.sql + antes_/depois_<versão>.sql + rodar.sh
prototipo/index.html   protótipo original (referência visual)
```

## 4. Perfis e telas
- **Sem login (qualquer colaborador)** — o app abre direto em "Abrir chamado":
  setor (lista + "Outro"), nome e cargo obrigatórios em texto livre (quem não está cadastrado também abre; nada é cadastrado), onde está o problema
  (Sistemas de desenvolvimento ou Suporte técnico), descrição, até 3 prints de 5 MB (clicar/arrastar/Ctrl+V),
  urgência (padrão "Meio urgente"). Recebe protocolo `TI-0423…` e os prazos.
  Aba **Acompanhar**: consulta pelo protocolo (situação, responsável, prazos; nunca a descrição).
- **Pelo botão do hub** (`?t=<token>`): nome travado (vem do login do hub), setor travado se o departamento do RH
  tem de-para (senão escolhe), sistema de origem pré-selecionado. Token apagado da URL ao abrir; vale também
  com alguém do time logado no navegador.
- **Dev/Suporte** ("É dev/suporte? Entrar", mesmo e-mail/senha dos sistemas ATLAS): Painel do time (fila,
  Assumir/Resolver/Reabrir, prazos, atrasados, % no prazo, selo "via <sistema>" com página/navegador/cargo/e-mail)
  e Analytics (período; % no prazo; Desenvolvimento × Suporte; por técnico; mapas técnico × sistema/setor).
  Conta que não é dev vê "O login é só para o time".

## 5. Regras de negócio
Urgência (0–3, sempre cor + texto): Não urgente (verde) · **Meio urgente (azul, padrão)** · Urgente (âmbar) · Muito urgente (vermelho).
Dois prazos por chamado, horas corridas desde a abertura, congelados na abertura:

| Nível | Desenvolvimento: assumir / resolver | Suporte técnico: assumir / resolver |
|---|---|---|
| Não urgente | 24 h / 5 dias | 8 h / 2 dias |
| Meio urgente | 8 h / 2 dias | 4 h / 1 dia |
| Urgente | 2 h / 8 h | 1 h / 4 h |
| Muito urgente | 30 min / 2 h | 15 min / 1 h |

- Etapa que corre: sem responsável → assumir; com responsável → resolver. "Perto" = últimos 25% (âmbar); "atrasado" = etapa vencida.
- Fila: sem responsável primeiro (pelo prazo de assumir), depois pelo prazo de resolver.
- Assumir: qualquer dev, se sem responsável. Resolver: só o responsável. Reabrir: qualquer dev (volta a "em andamento").

## 6. Banco (schema `chamados`)
Tabelas: `setores` (4), `pessoas` (nome, setor, papel `solicitante|dev`, e-mail, `user_id`, `origem_cadastro manual|hub`),
`sistemas` (23; `grupo sistema|suporte`, `hub_codigo`), `urgencias`, `prazos` (grupo × nível → minutos),
`chamados` (protocolo, status, urgência, prazos, `assumido_em`, prints, `origem`, `sistema_origem`, `contexto`,
`solicitante_nome`, `solicitante_cargo`, `setor_id`, `setor_outro`; `solicitante_id` nulo = quem abriu não tem cadastro),
`eventos` (histórico), `convites` (tokens do hub, só hash), `setor_departamento` (de-para RH → setor), `configuracao` (`app_url`).

Funções (todas `security definer`, `search_path = ''`, retorno `jsonb`):
- **Sem login (anon):** `catalogo_publico` (sem nomes de pessoas), `abrir_chamado_publico(setor_id|null, setor_outro, nome, cargo, sistema, descricao, urgencia, prints)`
  (limite 5/nome e 30/total a cada 10 min; liga ao cadastro se o nome bater no mesmo setor), `consultar_chamado(protocolo)`, `ler_convite(token)`,
  `abrir_chamado_por_convite(token, setor, cargo, …)` (cargo só quando o RH não tem).
- **Logado:** `vincular_minha_conta`, `abrir_chamado`, `assumir_chamado`, `resolver_chamado`, `reabrir_chamado`;
  `gerar_link_chamado(sistema, url, contexto)` (usado pelos sistemas do hub; exige `acessos.eh_usuario_ativo()`, 20 links/h).
- Gatilho `chamados_definir_prazos` calcula os prazos. Protocolo pela sequência `protocolo_seq`.
- Leitura direta de tabelas só para `authenticated` vinculado, filtrada por RLS; anon não lê tabela nenhuma.
- Storage: bucket privado `chamados-prints` (sem login grava em `publico/<uuid>.<ext>`; só o time lê). Limite 5 MB.
- Realtime: `chamados.chamados` na publicação `supabase_realtime`.
- Fora do schema, só **leitura**: `acessos.usuarios`, `hub.pessoas`, `rh.vw_vinculos_atuais`, `auth.users`.

## 7. Armadilhas já conhecidas (leia antes de mexer no banco)
- **Schema exposto na API:** `chamados` precisa estar em `pgrst.db_schemas` (Settings → Data API → Exposed schemas). Se sumir, o app dá **406**.
- **`safeupdate`:** `update`/`delete` sem `where` são recusados.
- **Conector do Supabase:** comandos destrutivos (`drop`, `delete`, `truncate`) pedem confirmação humana e **expiram** (timeout de 60 s) numa sessão sem confirmação. Prefira `revoke`/desativar ou peça ao Roneely para rodar no SQL Editor. `apply_migration` também expirou várias vezes: aplicar em **blocos pequenos via `execute_sql`** e registrar em `supabase_migrations.schema_migrations`.
- **Testar no banco real sem sujar:** bloco `do $$ … raise exception 'RESULTADO %', r; $$` (o erro desfaz tudo). Depois reajustar a sequência: `select setval('chamados.protocolo_seq', (select coalesce(max(substring(protocolo from 4)::int), 420) + 1 from chamados.chamados), false);`
- **E-mails de pessoas** nunca em migration ou commit (só no banco).
- **Vercel:** o conector não vê o projeto `chamado`; deploy é automático a cada push no branch. O endereço oficial foi descoberto pelos logs do Supabase (referer).
- **Pré-visualização de telas:** criar `src/_previa.tsx` + `previa.html` simulando `supabase.rpc`/`auth`, subir `vite` e tirar print com Playwright (Chromium em `/opt/pw-browsers`); apagar os dois arquivos depois.

## 8. Situação em 03/10/2026
- Chamados: TI-0421 (real, resolvido), TI-0422 (teste, resolvido — falta apagar no SQL Editor:
  `delete from chamados.chamados where protocolo = 'TI-0422' and descricao like '[TESTE]%';`), TI-0423 (teste pelo botão do hub, aberto).
- 16 solicitantes, 6 devs (Kaio, Aldo, Ruan e João Pedro com login; **Brenno Magalhães e Breno Azevedo sem e-mail ainda**).
- Botão do hub instalado no **Atlas Hub** (PR Rfeitosagroup/atlas-hub#27) e no **CRM** (PR Rfeitosagroup/crm-rfeitosa#93).

## 9. Próximos passos combinados
1. Botão "Abrir chamado" nos outros sistemas do hub (próximo sugerido: Juris) seguindo `integracao/README.md`.
2. Liberar Brenno e Breno; confirmar o de-para RH → setor com o Roneely.
3. Domínio `chamados.rfeitosa.com.br` e aviso ao time (e-mail/push) em chamados Urgente/Muito urgente.
4. Limpeza periódica de prints órfãos em `chamados-prints/publico/`.

## 10. Como o Roneely trabalha
Advogado e gestor; quer acurácia, rastreabilidade (de onde veio cada conclusão), PT-BR, respostas objetivas.
Antes de mudança grande: mostrar o plano e esperar aprovação. Não alterar listas de pessoas/sistemas sem confirmar.
Decisões com opções: apresentar caminhos (Conservador | Balanceado | Ousado) com recomendação.

## 11. Gamificação (05/10/2026)
Ver `docs/GAMIFICACAO.md`. Motor por eventos no banco (fila `gam_eventos` → ledger `gam_xp` idempotente), XP de resolução em
validação por 72 h, Performance Score composto, antiabuso com revisão do gestor, missões, temporadas e Central de Gamificação.
**Ligada em 05/10/2026** (Temporada 1 · T4 2026; só conta o que aconteceu depois disso). Gestor: Roneely. Técnicos com login: Aldo, Breno Azevedo, João Pedro, Kaio e Ruan; **Brenno Magalhães ainda sem e-mail de login**. Testes: `supabase/testes/gamificacao.sql`.

## 12. Identidade visual (05/10/2026)
- Aplicado o Manual de Marca RF Group (nov/25): logo do grupo (p. 3 do manual) no topo, ampulheta como favicon (`public/`), faixa degradê da marca sob o topo e paleta marinho #212965 (principal), vinho #6d0001 (destaque) e cinza #727272. Tokens em `src/styles.css` (`--accent*`, `--brand-*`). Urgências e raridades mantêm as cores próprias.

## 13. Notificações push (06/10/2026)
- No ar: migration `20261006120000_notificacoes_push.sql` (aplicada em 3 partes pelo conector), Edge Function `chamados-push` (verify_jwt=false, autenticada pelo segredo do Vault), cron `chamados-push` (1 min), par VAPID gerado no Vault. Cada pessoa do time precisa clicar no sino → "Ativar neste aparelho" (e "Enviar teste"). Testes: `supabase/testes/notificacoes.sql`.

## 14. Chat descartável (06/10/2026)
- No ar: migration `20261006140000_chat.sql` (aplicada em 2 partes: `chat_push_tipo`, que troca o check de `push_envios.tipo` para aceitar `chat`, e `chat`). Testes: `supabase/testes/chat.sql`.
- Tabelas `chat_mensagens` (RLS: time lê; anon nunca lê a tabela; realtime ligado) e `chat_leituras` (não lidas por pessoa). Escrita só por RPC: `chat_ler`/`chat_enviar` (anon, protocolo + código secreto da abertura), `chat_enviar_time`, `chat_marcar_lido`, `chat_resumo` (time).
- Descarte: `chat_descartar()` roda dentro de `push_agendar()` (cron `chamados-push`, 1 min) e zera o texto 24 h após resolver.
- Front: `src/lib/chat.ts` (+ testes), `src/componentes/Chat.tsx` (`ChatSolicitante` consulta a cada 5 s/30 s em segundo plano; `ChatTime` em tempo real), Acompanhar e gaveta 💬 no Painel.
- Sem o código (outro navegador, link perdido) quem abriu só consulta o protocolo, sem chat.

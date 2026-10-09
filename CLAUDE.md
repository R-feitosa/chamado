# Central de Chamados RFG

## O que é
Sistema interno de chamados de sistemas do R. Feitosa Group.
Colaboradores abrem chamados quando um sistema dá problema; o time de desenvolvimento assume e resolve.

## Pessoas
- Time de desenvolvimento (quem resolve): Aldo, Brenno Azevedo, Breno Magalhães, João Pedro, Ruan, Kaio.
- Solicitantes (quem abre), por setor:
  - Sócios: Roneely Feitosa, Anderson Mesquita, Fábio Mendes
  - Administrativo e Financeiro: Tayse Feitosa
  - Controladoria: Raissa, Amanda, Sarah, Julia, Sophia
  - Jurídico: Tamira, Lanna, Flávia Luquélia, Suhiane, Joana Cláudia, Nicoly Sobral, Carlos Brandão

## Perfis e telas
**Login só para o time de dev/suporte.** Quem abre chamado não faz login: o app abre direto no formulário.
- **Abrir chamado** (sem login): **setor, nome e cargo obrigatórios**: setor numa lista (4 setores + "Outro", aí digita qual), nome e cargo em texto livre, para quem não está cadastrado também abrir (o navegador lembra o último preenchimento), onde está o problema, descrição, prints (até 3, 5 MB cada: clicar, arrastar ou Ctrl+V), urgência. Ao enviar, mostra o protocolo e os prazos.
- **Abrir pelo botão do hub** (sem login, com token): todo sistema do hub pode ter um botão "Abrir chamado" que leva para a Central já identificado. Nome travado (do login do hub), setor travado quando o departamento do RH tem correspondência (senão a pessoa escolhe), cargo do RH (se o RH não tiver, a pessoa digita), sistema de origem pré-selecionado. Token tirado da barra de endereço ao abrir; vale 2 h e uma vez. Link vencido → aviso + formulário comum.
- **Acompanhar** (sem login): consulta pelo protocolo (aceita "TI-0422" ou "422"); mostra situação, onde, urgência, responsável (primeiro nome) e prazos. Nunca a descrição nem os prints.
- **"É dev/suporte? Entrar"** no topo: login com a conta dos sistemas ATLAS. Conta que não é dev/suporte vê "O login é só para o time".
- **Painel do time** (dev/suporte, tela inicial após o login): contagens (em aberto, sem responsável, atrasados, meus), tempos (espera média sem responsável, mais antigo em aberto, % assumidos e % resolvidos no prazo nos últimos 30 dias), fila com coluna "Prazo" (etapa atual: assumir em X / resolver em X / atrasado X, e há quanto tempo está aberto), botões Assumir / Resolver / Desassumir / Reabrir, prints com ampliação.
- **Analytics** (dev/suporte): período (7/30/90 dias/tudo); % assumidos e resolvidos no prazo; comparação Desenvolvimento × Suporte técnico; resolvidos por técnico (barras + % no prazo + tempo médio); mapas de calor técnico × sistema e técnico × setor de quem abriu.
- Dev logado também pode abrir chamado (em nome próprio).
- **Gamificação** (detalhes em `docs/GAMIFICACAO.md`; chave geral na Central, começa desligada):
  - **Minha jornada** (dev): nível/XP (o XP conta na hora; a parte "em validação" é estornada se o chamado for reaberto em 72 h), ranking, Performance Score, sequências, missões, conquistas próximas, medalhas, feed, histórico de XP, títulos/molduras.
  - **Ranking** (dev e gestor): período × critério (padrão: score composto), temporadas encerradas congeladas; perfil de cada técnico.
  - **Central de Gamificação** (só gestor): chave, regras de XP, multiplicadores, score e limites, níveis, conquistas, missões, temporadas, recompensas, revisão de suspeitas, auditoria.
  - **Gestor** (`pessoas.gestor`, hoje Roneely): entra com a conta ATLAS; vê Painel do time (só lê e desassume), Ranking, Analytics e a Central; não assume nem pontua.
- **Notificações** (dev/suporte e gestor): sino no topo → "Ativar neste aparelho" (Web Push; no iPhone só com a Central instalada na tela de início).
  Enquanto o push não estiver ativo no aparelho, uma faixa no topo pede "Ativar agora" (ou explica como desbloquear). Com a permissão já dada,
  o navegador é inscrito/reinscrito sozinho ao entrar (exceto quem desativou de propósito). Sem push, a própria aba mostra o aviso do sistema sempre que a Central não estiver em foco.
  Aviso **imediato** de chamado novo e **repetição enquanto ninguém assume**: Muito urgente a cada 5 min e Urgente a cada 15 min (24 h);
  Meio urgente a cada 1 h e Não urgente a cada 4 h (só no expediente, `gam_config.expediente`). Prazo de assumir vencido → avisa o gestor (1×).
  Responsável: aviso com prazo de resolver perto (últimos 25%) e vencido. Com a Central aberta toca **som por urgência** (Web Audio, `src/lib/som.ts`);
  fora dela, o som padrão do aparelho. Regras em `chamados.push_regras` (espelho em `src/lib/alertas.ts`). Payload sem descrição nem nomes.
  Motor: gatilho `chamados_push_novo` + `chamados.push_agendar()` (pg_cron 1 min) → fila `push_envios` → `push_disparar()` (pg_net) →
  Edge Function `chamados-push` (`supabase/functions/`, Web Push/VAPID próprio, mesmo desenho do Atlas Ponto). Inscrições canceladas/expiradas
  ficam desativadas (`desativada_em`), nada é apagado.
- **Chat descartável** (quem abriu ↔ time): quem abriu entra em **Acompanhar** com o código secreto da abertura (o mesmo da avaliação,
  guardado no navegador e no link "acompanhar e conversar"); o time abre pelo 💬 de cada linha do Painel (contador de não lidas, tempo real).
  Escrevem o responsável e quem aceitou ajudar (antes de alguém assumir, qualquer dev); gestor e demais só leem. Fecha ao resolver (só leitura),
  o **texto é apagado 24 h depois** (`texto` nulo + `apagada_em`, nada é deletado) e reabrir reabre. Mensagem de quem abriu → push `chat`
  (sem o texto) para o responsável + ajudantes ou, sem responsável, para o time. Aviso fixo: não enviar senhas nem dados pessoais.
- Fluxo novo usado pela gamificação: **avaliação** (1–5 estrelas + elogio) com código secreto gerado na abertura sem login (link "avaliar depois"), **pedir ajuda** a colega (o colega confirma), **justificar atraso**, **reabrir com motivo** (não estava resolvido / voltou / outro).

## Sistemas atendidos
- **Sistemas:** ATLAS JURIS, CRM, ATLAS RH, Atlas Consult, ATLAS Empresas, Atlas Trib, Rfast Mail, Agente WhatsApp, App Connect Valley, Site Feitosa Imóveis, Site do escritório, Connect Academy, Atlas Cash, Atlas Hub, Atlas Imóveis, Legal Ops, Atlas Ponto, R. Feitosa Ops, Outro / não sei.
- **Suporte técnico:** Computador / notebook, Impressora / scanner, E-mail, senha e acessos, Outro / não sei (suporte).
- Ficam em `chamados.sistemas`; a coluna `grupo` (`sistema` | `suporte`) separa os dois blocos no formulário e `hub_codigo` liga ao código em `hub.sistemas` (pré-seleção no botão do hub).

## Arquivos
- `docs/CONTEXTO.md`: visão completa do app para uma nova sessão (clone, URLs, arquitetura, banco, armadilhas, situação e próximos passos).
- `prototipo/index.html`: protótipo original (página única, referência visual e funcional).
- `src/`: sistema de produção (React 18 + Vite + TypeScript).
  - `lib/supabase.ts` cliente (schema `chamados`); `lib/api.ts` chamadas ao banco; `lib/fila.ts` e `lib/formato.ts` regras puras (com testes).
  - `lib/analytics.ts` cálculos de tempo e produtividade; `lib/sla.ts` situação do prazo (com testes).
  - `telas/` AbrirChamado, Acompanhar, Acesso (login do time), Painel, Analytics, SemCadastro; `componentes/` prints, ampliação, urgência.
- `integracao/`: `abrir-chamado.ts` (função para o botão "Abrir chamado" dos sistemas do hub) e README de instalação.
- `supabase/migrations/`: banco. `supabase/testes/rodar.sh` testa permissões e regras num Postgres local.

## Regras
- Toda a interface em português do Brasil.
- Visual (Manual de Marca RF Group, nov/25): logo do grupo no topo (`public/logo-rfg.png`, numa pastilha branca) e ampulheta como favicon; faixa degradê cinza → vinho → marinho sob o topo; cor principal marinho #212965, vinho #6d0001 de destaque (pílula do hero, protocolo, selo de nível), cinza #727272; fonte Geist (Geist Mono para protocolos), fundo #f6f7f9; suportar tema claro e escuro.
- Urgência em 4 níveis, sempre com cor + texto: verde (Não urgente), azul (Meio urgente), âmbar (Urgente), vermelho (Muito urgente). No banco: 0 a 3.
- Não alterar a lista de pessoas ou de sistemas sem confirmar comigo.
- Antes de mudanças grandes, mostrar o plano e esperar aprovação.

## Banco (Supabase)
- Projeto **ATLAS - INTEGRADO** (`ashxrwwlcarvqdigoxsi`), compartilhado com os outros sistemas do grupo.
- Tudo da Central fica no schema **`chamados`**. Não criar nada em `public` nem em outros schemas.
  Únicas exceções, exigidas pelo Supabase: bucket privado `chamados-prints` (+ policies em `storage.objects`
  filtradas por esse bucket), `chamados.chamados` e `chamados.chat_mensagens` na publicação `supabase_realtime` e os dois agendamentos do `pg_cron`
  (`chamados-gam-ciclo`, `chamados-gam-periodos`, em `cron.job`) que rodam o motor da gamificação; o agendamento `chamados-push`
  (notificações) e os segredos do push no **Vault** (`chamados_push_dispatch_secret`, `chamados_push_vapid_public/private`).
- Tabelas: `setores`, `pessoas` (nome, setor, papel solicitante/dev, `gestor`, e-mail de login), `sistemas`, `chamados`, `eventos` (histórico, `detalhe`), `avaliacoes`, `colaboracoes`, `chat_mensagens`, `chat_leituras`.
- Gamificação: tabelas `gam_*` (config, regras, multiplicadores, níveis, conquistas/tiers, missões, temporadas, recompensas, fila `gam_eventos`, ledger `gam_xp`, perfis, sequências, resultados de missão, ranking congelado, notificações, suspeitas, auditoria). Escrita só pelo motor/RPCs `gam_*`; `pg_cron` roda `gam_ciclo` (1 min) e `gam_fechar_periodos` (15 min).
- Login (só dev/suporte): o mesmo `auth.users` dos sistemas ATLAS, ligado à pessoa pelo e-mail no primeiro acesso
  (`chamados.vincular_minha_conta`). Para liberar um dev: preencher `chamados.pessoas.email`.
- Sem login (papel `anon`), só estas funções, nenhuma tabela:
  - `catalogo_publico()`: setores, sistemas, urgências e prazos (**sem nomes de pessoas**; `pessoas` vem vazio);
  - `abrir_chamado_publico(setor_id|null, setor_outro, nome, cargo, …)`: setor (ou "Outro" com texto), nome (3–80) e cargo (2–60) obrigatórios; grava o que foi digitado no chamado (`solicitante_nome`, `solicitante_cargo`, `setor_id`, `setor_outro`) e **não cadastra ninguém**; se o nome bater (sem acento/maiúsculas) com solicitante ativo do mesmo setor, liga `solicitante_id` a ele (senão fica nulo); limite de 5 por nome e 30 no total a cada 10 min; grava `origem = 'publico'`;
  - `consultar_chamado(protocolo)`: situação, prazos e primeiro nome do responsável;
  - `ler_convite(token)` e `abrir_chamado_por_convite(token, setor, cargo, …)`: fluxo do botão do hub (abaixo).
  - `avaliar_chamado(protocolo, codigo, nota, elogio, comentario)`: só com o código secreto devolvido na abertura (o banco guarda só o hash); 1 vez, chamado resolvido, até 14 dias.
  - `chat_ler(protocolo, codigo, depois)` e `chat_enviar(protocolo, codigo, texto)`: chat com o mesmo código secreto; 10 mensagens/min e 200 por chamado.
- **Botão do hub (padrão DISC):** `gerar_link_chamado(sistema, url, contexto)` só para `authenticated` com conta ativa
  (`acessos.eh_usuario_ativo()`); lê nome (`hub.pessoas`), e-mail (`auth.users`), departamento e cargo (`rh.vw_vinculos_atuais`,
  vínculo mais recente) no servidor; grava em `chamados.convites` só o hash SHA-256 do token (32 bytes); limite 20 links/h;
  devolve `chamados.configuracao.app_url` + `/?t=<token>`. Ao abrir, a pessoa é achada por `user_id`/e-mail em `chamados.pessoas`
  ou cadastrada (`origem_cadastro = 'hub'`). O chamado guarda `sistema_origem` e `contexto` (página, navegador, cargo,
  departamento, e-mail), visíveis só para o time.
- **De-para departamento → setor:** `chamados.setor_departamento`. Jurídico ← Cível, Trabalhista, Previdenciário, Tributário,
  Execução, Judicial/NUJI/CAC; Controladoria ← Controladoria; Administrativo e Financeiro ← Administrativo, Financeiro, RH.
  Departamento fora da tabela ou sem vínculo no RH: a pessoa escolhe o setor.
  Prints sem login vão para `chamados-prints/publico/<uuid>.<ext>` (só gravação; leitura só do time). Limite do bucket: 5 MB.
- Escrita só por RPC `security definer` (`abrir_chamado`, `abrir_chamado_publico`, `assumir_chamado`, `desassumir_chamado`, `resolver_chamado`, `reabrir_chamado`),
  com `search_path = ''` e retorno `jsonb` (padrão do projeto). O front logado só lê, filtrado por RLS.
- `update`/`delete` sempre com `where`: o projeto usa a extensão `safeupdate`.
- Comandos destrutivos (`drop`, `delete`, `truncate`) pelo conector do Supabase exigem confirmação humana e expiram em sessão sem confirmação: preferir `revoke`/desativar, ou rodar no SQL Editor do Supabase.
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
- Solicitante não faz login: informa setor, nome e cargo (obrigatórios, conferidos pelo banco), abre pelo formulário e acompanha pelo protocolo. Dev/suporte faz login e vê todos os chamados.
- Assumir: dev, chamado sem responsável e não resolvido (grava `assumido_em`, base do "tempo até assumir"). Resolver: só o responsável. Desassumir: o responsável ou o gestor, motivo opcional; volta para "aberto" sem responsável e com os mesmos prazos, cancela pedidos de ajuda sem resposta e estorna o XP de resposta rápida ainda em validação (evento `desassumido`, ignorado pelo motor da gamificação). Reabrir: qualquer dev, **com motivo**; volta para "em andamento" com o mesmo responsável.
- Pedir ajuda: só o responsável, chamado em andamento; o colega aceita ou recusa. Justificar atraso: só o responsável, com o prazo de resolver vencido.
- Até 3 prints por chamado (PNG, JPG, WEBP, GIF; até 5 MB), gravados em `chamados-prints/publico/…` (sem login) ou `chamados-prints/<user_id>/…` (dev logado).

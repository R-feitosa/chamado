# Gamificação da Central de Chamados RFG

Transforma o atendimento em progressão (XP, níveis, conquistas, missões, temporadas) **premiando qualidade, SLA,
satisfação, colaboração e consistência** — nunca só velocidade ou volume. Tudo é configurável na
**Central de Gamificação** (gestor) e auditado.

## 1. Arquitetura

```
RPCs de chamado (abrir/assumir/resolver/reabrir)      avaliar_chamado      responder_ajuda
          │ insert chamados.eventos                          │ insert            │ update
          ▼                                                  ▼                   ▼
   gatilho gam_publicar ──────── só ENFILEIRA em chamados.gam_eventos (chave única = idempotência) ────────
                                                     │
                       gam_ciclo()  (pg_cron a cada 1 min + sob demanda pelo front)
                                                     │
   gam_processar → tratador do evento → elegibilidade → regras de XP (ledger gam_xp) → antiabuso (gam_suspeitas)
                → sequências → conquistas → perfil/nível → notificações (gam_notificacoes)
   gam_confirmar_pendentes → XP "pendente" vencido vira "confirmado" e publica ticket.confirmed
   gam_fechar_periodos (pg_cron 15 min) → missões, sequência semanal de SLA, temporadas
```

- O sistema de chamados **não conhece** a gamificação; ela só reage aos fatos. Falha do motor nunca derruba um chamado
  (o gatilho só enfileira, com tratamento de erro; eventos com erro ficam na fila para reprocessar).
- Motores (funções SQL, `supabase/migrations/20261005160000_gamificacao_3_motor.sql`): Pontuação (`gam_aplicar_regra`,
  `gam_lancar`), Conquistas (`gam_metricas`, `gam_avaliar_conquistas`), Sequências (`gam_sequencia`), Missões
  (`gam_metrica_missao`, `gam_fechar_periodos`), Ranking/Score (`gam_estatisticas`, `gam_scores`, `gam_ranking`),
  Temporadas (`gam_encerrar_temporada`), Notificações (`gam_notificar`), Antiabuso (`gam_checar_resolucao`, `gam_suspeitar`).
- Leitura do time: `gam_jornada(pessoa?)`, `gam_ranking(periodo, criterio, temporada?)`. Gestão: `gam_admin_*`.
- Front: `src/lib/gamificacao.ts` (regras puras + testes), `src/lib/apiGam.ts`, `src/hooks/useGamificacao.ts`,
  telas `Jornada`, `Ranking`, `CentralGamificacao`, componentes em `src/componentes/gam/` (carregados sob demanda).

### Eventos
| Evento | Origem | O que dispara |
|---|---|---|
| `ticket.created` | `eventos.acao = aberto` | só registro |
| `ticket.assigned` | `assumido` | Primeira resposta rápida |
| `ticket.resolved` | `resolvido` | XP de resolução (pendente), SLA cumprido/estourado (`sla.met/breached` é derivado aqui), prioridade, suspeitas |
| `ticket.reopened` | `reaberto` (com motivo) | estorno do pendente, penalidades, zera sequência |
| `ticket.confirmed` | interno, após `horas_pendente` sem reabertura | sem reabertura, SLA sem justificativa, ajuda, sequências, conquistas |
| `rating.received` | `avaliacoes` | 4/5 estrelas, elogio, sequência 5★ |
| `collaboration.registered` | colaboração confirmada | registro (XP do colega na confirmação do chamado) |

Nova regra = linha em `gam_regras` + (se for um fato novo) um tratador em `gam_processar`. O fluxo de chamados não muda.

## 2. XP e ledger
- Valores padrão (editáveis): resolvido +20 (× multiplicador), no SLA +10, urgente +15, muito urgente +30, resposta rápida +5,
  sem reabertura +10, ajuda +10, 5★ +25, 4★ +10, elogio +20; penalidades: reaberto −10, encerrado incorretamente −20,
  SLA estourado sem justificativa −10. Cada regra tem ON/OFF, limite por chamado e limite diário.
- **Ledger `gam_xp`**: cada linha tem pessoa, evento, chamado, regra/conquista/missão, valor, motivo, status e `chave`
  única por pessoa → o mesmo fato nunca paga duas vezes. XP exibido e nível = soma das linhas `confirmado` + `pendente` (o XP **conta na hora**, decisão de 07/10/2026);
  `retido` só entra depois da revisão do gestor (`gam_perfis` é cache; guarda confirmado e pendente separados).
- **Status**: `pendente` (72 h de validação) → `confirmado`; `estornado` (reaberto na validação ou suspeita rejeitada);
  `retido` (suspeita em revisão).
- Resolver de novo um chamado reaberto **não paga de novo** (as chaves já existem).

## 3. Níveis
`gam_nivel(xp)` é a fonte única (o front espelha em `nivelDe`, com teste de paridade). Padrão: 1 Novato 0 · 2 Aprendiz 500 ·
3 Operador 1.200 · 4 Especialista 2.500 · 5 Expert 5.000 · 6 Elite 10.000 · 7 Master 20.000; acima disso cada nível exige o
intervalo anterior × 1,25 (Master 2 = 32.500…).

## 4. Performance Score (0–100)
```
Score = (30·Qualidade + 25·SLA + 20·Satisfação + 15·Produtividade + 10·Colaboração) / 100 × 100
Qualidade     = 1 − reabertos / resolvidos
SLA           = 0,4 · assumidos no prazo + 0,6 · resolvidos no prazo
Satisfação    = (nota − 1) / 4
Produtividade = √(Σ multiplicadores dos resolvidos) / √(maior do time)     ← raiz amortece volume de chamados simples
Colaboração   = ajudas confirmadas / maior do time
Taxas suavizadas (bayes): (acertos + k · média do time) / (n + k), k = 5
```
- Quem tem menos de 5 resolvidos no período aparece "em formação" (não classificado).
- O ranking principal é o score; também há XP, resolvidos, satisfação, SLA, qualidade e eficiência
  (eficiência = 1 − fração média do prazo consumida).
- Períodos: hoje, semana, mês, trimestre, ano, temporada, geral (fuso de Brasília; nada antes do lançamento conta).

## 5. Balanceamento e antiabuso
| Risco | Proteção |
|---|---|
| Fechar rápido para pontuar | XP de resolução pendente 72 h; reabertura estorna e penaliza; resolução < 3 min após assumir → revisão |
| Chamado falso / próprio | Sem XP se aberto por dev/gestor (`origem = login`), solicitante do time ou chamado próprio |
| Fechar/reabrir repetidamente | 1 pagamento por chamado; ≥ 2 reaberturas → revisão; reaberturas de chamados de colegas (≥ 3/7 dias) → revisão |
| Muitos chamados triviais | Multiplicador só na resolução (1,0/1,2/1,5/2,0, teto 2,0); retorno decrescente (do 9º "Não urgente" do dia: 50%); teto diário de 400 XP de resolução; produtividade com raiz |
| Muito urgente "relâmpago" | resolvido < 5 min da abertura → revisão |
| Mesmo solicitante abrindo muitos | ≥ 5 chamados/dia do mesmo nome para o mesmo técnico → revisão |
| Avaliação manipulada | Código secreto (hash no banco), 1 por chamado, só resolvido, até 14 dias; ≥ 3 notas 5 do mesmo nome em 7 dias → revisão |
| Colaboração falsa | Só o responsável pede; o colega confirma; paga só quando o chamado é validado; limite 5/dia; reciprocidade A↔B > 50% → revisão |
| Transferir chamado | Não existe transferência no fluxo |
| XP duplicado | Chave única no ledger e na fila de eventos |

Revisão (Central → Revisão): **Legítimo** libera o XP retido; **Rejeitar** estorna e tira o chamado das estatísticas.

## 6. Conquistas, missões, sequências, temporadas, recompensas
- 17 conquistas (Primeiro Passo, Aquecendo, Máquina de Resolver, Centurião, Lenda do Suporte, Velocista, Precisão Cirúrgica,
  Guardião do SLA [Bronze→Diamante], SLA Impecável, Favorito dos Usuários, Atendimento Lendário, Bombeiro [tiers],
  Madrugador, Trabalho em Equipe [tiers], Imparável [tiers], Sequência 5 Estrelas, Semana Impecável). Raridade:
  Comum, Incomum, Rara, Épica, Lendária. Progresso calculado só com XP **confirmado**.
- Missões: diária "No prazo hoje" (3 no SLA, +30), semanal "Bem avaliado" (15 com nota ≥ 4, +150), especial
  "Zero Reopen Week" (20 sem reabertura, +300 + Semana Impecável), equipe "Operação SLA" (95% no SLA, +200 para quem
  resolveu ≥ 2 na semana). Progresso ao vivo; recompensa quando o período fecha e o XP já foi validado.
- Sequências por chamado/avaliação/semana — **nunca por presença diária**; semana com menos de 3 chamados não conta nem quebra.
  Expediente configurável (seg–sex 8h–18h) só para "Madrugador" (primeiras 2 h do expediente).
- Temporadas trimestrais (T1 = T4 2026). No fim (após a validação): ranking congelado em `gam_ranking_temporada`, pódio
  ganha XP (300/200/100), molduras Ouro/Prata/Bronze e título "Campeão da Temporada"; a próxima temporada abre sozinha.
  XP permanente não zera.
- Recompensas simbólicas: títulos (Guardião do SLA, Solucionador, Veterano do Suporte, Especialista em Críticos,
  Herói do Cliente, Campeão da Temporada), molduras e destaque no perfil.

## 7. Operação
- Chave geral: Central → Visão geral. Desligada, o time não vê nada e os eventos são ignorados. Ao ligar, tudo começa do zero.
- Gestor: `chamados.pessoas.gestor = true` (hoje: Roneely). Não assume, não pontua e vê Ranking, Analytics e a Central.
- `pg_cron`: `chamados-gam-ciclo` (1 min) e `chamados-gam-periodos` (15 min).
- Testes: `supabase/testes/gamificacao.sql` (16 blocos: idempotência, estorno, penalidades, suspeitas, elegibilidade,
  colaboração, justificativa, teto, retorno decrescente, missões, ranking, RLS, temporada, integridade do ledger).

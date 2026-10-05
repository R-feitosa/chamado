# Brag — Central de Chamados RFG

## O que é
Central interna de chamados do R. Feitosa Group: quem tem problema num sistema ou equipamento abre o chamado **sem login**, em menos de 1 minuto. O time de dev/suporte assume e resolve, e cada etapa tem prazo próprio (SLA). Resolver bem e no prazo rende XP.

- **Para quem:** colaboradores (abrem) e o time de dev/suporte (resolve).
- **Diferencial:** prazos de assumir e resolver calculados na hora, conforme a urgência e o tipo de demanda; gamificação que premia qualidade, e não só velocidade.
- **Claim mais forte (copy real do app):** "Leva menos de 1 minuto" · "Algum sistema ou equipamento deu problema?"
- **Gancho visual:** a pílula azul #2b4bee e o título do hero, em escala grande.

## Ângulo
Um chamado, do começo ao fim, em 20 segundos: **abriu → protocolo e prazos → o time assume → XP no prazo.**

## Tom
`polished` com ritmo de `app-store`: um filme de produto limpo e confiante, na identidade do próprio app (Geist, fundo #f6f7f9, azul #2b4bee).

## Identidade visual (de `src/styles.css`)
- Fundo `#f6f7f9`; superfície `#fff`; linhas `#e6e7ec`; texto `#0e1116` e `#4a5160`; destaque `#2b4bee`.
- Fontes: Geist (texto) e Geist Mono (protocolo).
- Raridades: épica `#6d3fd1`, lendária `#9a6a00`.
- Composição reaproveita o CSS real (`src/styles.css`), a marcação das telas (AbrirChamado, Painel, Toasts, Selo de XP) e os ícones da gamificação.

## Dados fictícios (LGPD)
- Nomes reais de pessoas foram trocados por dados fictícios: a solicitante é **"Ana Souza · Advogada · Jurídico"** e o técnico é **"Lucas Mota"**.
- Datas e horários são ilustrativos.
- Nenhuma URL interna, e-mail, token ou código de avaliação aparece.
- **Números reais das regras:**
  - Urgente em Desenvolvimento: assumir em 2 h, resolver em 8 h.
  - XP de um Urgente resolvido no prazo: 20 × 1,5 + 10 + 15 = 55.
  - Guardião do SLA · Bronze: +25 XP.
  - Nível 4 · Especialista: 2.500 XP.

## Storyboard (1920×1080, 30 fps, 21,5 s; música vol-12, ~110 BPM; cortes nos beats)
| # | Tempo | Cena | Texto em tela | Som |
|---|---|---|---|---|
| 1 | 0,00–2,73 | **Gancho.** A pílula "Leva menos de 1 minuto" entra e o título "Algum sistema ou equipamento deu problema?" sobe palavra a palavra. | copy real do hero | entrada da música, um impacto suave em 0,1 s |
| 2 | 2,73–7,64 | **Abrir.** O formulário real (setor, nome e cargo já preenchidos). O cursor clica em ATLAS JURIS, a descrição é digitada, o cursor clica em "Urgente" e aparece a explicação "o time assume em até 2 h e resolve em até 8 h". A barra "Seu chamado" enche e o cursor clica em Enviar. A câmera acompanha. | legenda: "Sem login. Diga onde, o quê e a urgência." | cliques suaves, digitação baixa |
| 3 | 7,64–10,37 | **Protocolo.** Cartão "Recebemos seu chamado" com TI-0425 em mono, mais "Assumir até" e "Resolver até" em destaque. | legenda: "Protocolo e prazos na hora." | impacto suave no corte |
| 4 | 10,37–14,20 | **Painel do time.** O TI-0425 entra no topo da fila ("assumir em 1 h 58 min"). O cursor clica em Assumir e a linha muda para Lucas Mota · Em andamento · "resolver em 7 h 59 min". | legenda: "O time vê na hora. Cada etapa com prazo." | clique e um tom curto |
| 5 | 14,20–18,56 | **Gamificação.** O selo de XP enche (2.440 → 2.520) e passa de Nv 3 para Nv 4. Três toasts reais aparecem em fila: "+55 XP Chamado resolvido no prazo", "Conquista desbloqueada: Guardião do SLA · Bronze", "Level up: Nível 4 · Especialista". | legenda: "Qualidade e prazo valem XP. Reabrir desconta." | três acentos suaves em sequência |
| 6 | 18,56–21,50 | **Fecho.** Marca RFG, "Central de Chamados RFG" e "Abriu. Assumiu. Resolveu. No prazo." | — | sino suave em 18,56; a música desce até o fim |

## Poster
Cena 3 assentada (~9,3 s): o cartão com TI-0425 e os prazos.

## Legenda (share-copy)
Escrita em `share-copy.txt`.

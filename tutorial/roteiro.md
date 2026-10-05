# Tutorial — Como abrir um chamado (colaboradores)

Vídeo de ~86 s, 1920×1080, 30 fps, sem narração (legendas + trilha baixa), feito gravando o app real
(`npm run build` + `vite preview`) com dados fictícios e RPCs simulados. Nada toca o banco.

| Passo | Tempo | Legenda |
|---|---|---|
| Abertura | 0–5 s | Como abrir um chamado · Central de Chamados RFG · leva menos de 1 minuto |
| 1 | 5–12 s | Abra a Central no navegador. Não precisa de login. Nos sistemas do hub, use o botão Abrir chamado. |
| 2 | 12–22 s | Setor, nome e cargo são obrigatórios. O navegador lembra para a próxima vez. |
| 3 | 22–30 s | Erro em sistema → bloco de cima. Computador, impressora, e-mail ou senha → Suporte técnico. Na dúvida: Outro / não sei. |
| 4 | 30–41 s | Diga o que, onde e desde quando. Até 3 prints: clique, arraste ou Ctrl+V. |
| 5 | 41–55 s | Meio urgente é o padrão. Muito urgente só se você ou o setor está parado, ou há prazo de cliente, processo ou pagamento em risco. |
| 6 | 55–64 s | Anote o protocolo. Os prazos para assumir e resolver aparecem na hora. |
| 7 | 64–73 s | Em Acompanhar, digite o protocolo (TI-0425 ou só 425). |
| 8 | 73–81 s | Resolvido? Avalie o atendimento. Leva 5 segundos. |
| Fecho | 81–86 s | Setor, nome e cargo · Onde está o problema · O que aconteceu + print · A urgência certa |

Dados fictícios: Ana Souza (Advogada, Jurídico), responsável "Lucas", print ilustrativo gerado no script.

## Regravar
```bash
npm run build && npx vite preview --port 4173 &
node tutorial/gravar.cjs                 # quadros em tutorial/work/quadros (ou: stills 12 30 55)
python3 tutorial/mix.py                  # trilha em tutorial/work/trilha.wav
ffmpeg -framerate 30 -i tutorial/work/quadros/q%05d.jpg -i tutorial/work/trilha.wav \
  -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p -c:a aac -b:a 160k -shortest -movflags +faststart tutorial/tutorial.mp4
```
Se mudar o formulário, ajuste os seletores e tempos em `gravar.cjs` (CAPS, MOVES, ACOES, DESTAQUES).
A trilha usa a música da skill brag (`.agents/`, não versionada; licença a verificar antes de divulgar fora do grupo).

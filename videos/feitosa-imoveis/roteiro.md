# Vídeo de lançamento — Feitosa Imóveis (rfeitosaimoveis.online)

22 s, 1920×1080, 30 fps. Gravado quadro a quadro a partir do próprio site (repo `R-feitosa/site-catalogo-feitosaimoveis`,
servido localmente; o domínio é bloqueado pela rede do ambiente de gravação). Só conteúdo já publicado no site:
copy, fotos, preços, endereço e WhatsApp. A conversa de WhatsApp da cena 5 é ilustrativa (mesma mensagem pré-preenchida do site).

| Cena | Tempo | Conteúdo |
|---|---|---|
| Gancho | 0–3,3 s | Hero real: logo, "Conheça nossos imóveis", 8 imóveis · 3 cidades · 3 categorias (zoom lento) |
| Catálogo | 3,3–7,6 s | Rola até o catálogo; clique em "Temporada" filtra Varanda Atlântica e Casa de Madeira 700 |
| Imóvel | 7,6–12 s | "Ver detalhes" da Casa de Madeira 700: descrição, foto, o que está incluso, diária R$ 500 — R$ 600 |
| Galeria | 12–16,4 s | Abre a galeria (lightbox) e passa 3 fotos |
| Contato | 16,4–18,6 s | "Falar no WhatsApp" + mensagem de interesse |
| Fecho | 18,6–22 s | Logo, "Conheça nossos imóveis", rfeitosaimoveis.online, WhatsApp (88) 99328-0165 |

Regravar: `python3 -m http.server 4180` na pasta do site; `SITE=http://localhost:4180/ FONTES=<g.css+woff2> OUT=<trabalho> node gravar.cjs`;
`python3 mix.py <assets da skill brag> <trabalho>/trilha.wav`; ffmpeg como no `tutorial/roteiro.md`.
Música: pacote da skill brag (ende.app "Happy Beats / Business Moves") — **verificar a licença antes de publicar nas redes**.

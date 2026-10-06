// Vídeo de lançamento do catálogo Feitosa Imóveis (rfeitosaimoveis.online), gravado quadro a quadro a partir do
// próprio site (repo R-feitosa/site-catalogo-feitosaimoveis servido localmente). Só conteúdo já publicado no site.
// Uso: SITE=http://localhost:4180/ FONTES=<pasta com g.css + woff2> OUT=<pasta de trabalho> node gravar.cjs [stills t1 t2 ...]
const path = require('path'), fs = require('fs');
const { chromium } = require(path.join(require('child_process').execSync('npm root -g').toString().trim(), 'playwright'));

const SITE = process.env.SITE || 'http://localhost:4180/';
const FONTES = process.env.FONTES;
const OUT = process.env.OUT || path.join(__dirname, 'work');
const FPS = 30, DUR = 22;

// legendas: [início, fim, html] (copy do próprio site)
const CAPS = [
  [3.9, 7.4, 'Temporada, residenciais e comerciais em <b>Sobral, Camocim e Meruoca</b>.'],
  [8.9, 11.8, 'Fotos, o que está incluso e <b>preço</b> na mesma página.'],
  [12.5, 16.1, 'Galeria completa de cada imóvel.'],
  [16.5, 18.4, 'Agende sua visita <b>direto pelo WhatsApp</b>.'],
];
// rolagem: [t0, t1, alvo, deslocamento do topo da janela]
const ROLAGENS = [[3.3, 4.3, '#catalogo', 70], [8.5, 9.3, '#madeira', 70], [10.4, 11.2, '#madeira .panel', 150]];
const MOVES = [[4.5, 5.2, '.chip[data-filter="temporada"]'], [7.6, 8.3, '#grid .card:nth-child(2) .btn--ghost'],
  [9.4, 10.2, { x: 1100, y: 520 }], [11.9, 12.4, '#madeira .gal__item >> nth=0'], [12.8, 13.3, '#lbNext'], [16.0, 16.3, '#lbClose'],
  [16.4, 17.0, '#madeira .pricebox .btn--wa']];
const CLIQUES = [5.3, 8.4, 12.5, 13.5, 14.5, 15.5, 16.3, 17.1];
const ACOES = [
  [5.3, (p) => p.click('.chip[data-filter="temporada"]')],
  [12.5, (p) => p.click('#madeira .gal__item >> nth=0')],
  [13.5, (p) => p.click('#lbNext')], [14.5, (p) => p.click('#lbNext')], [15.5, (p) => p.click('#lbNext')],
  [16.3, (p) => p.click('#lbClose')],
];

const OVERLAY = `(() => {
  const css = document.createElement('style');
  css.textContent = \`*{transition:none!important;animation:none!important} html{scroll-behavior:auto!important;scrollbar-width:none} ::-webkit-scrollbar{display:none}
  #ov{position:fixed;inset:0;pointer-events:none;z-index:99999;font-family:Inter,system-ui,sans-serif}
  #ov-cur{position:absolute;left:0;top:0;width:30px;height:30px;transform-origin:5px 3px;filter:drop-shadow(0 2px 4px rgba(0,0,0,.3))}
  #ov-ring{position:absolute;width:56px;height:56px;margin:-28px 0 0 -28px;border-radius:999px;border:3px solid #C9A227}
  #ov-cap{position:absolute;left:50%;bottom:34px;white-space:nowrap;background:rgba(27,46,99,.95);color:#fff;font-size:27px;font-weight:500;padding:14px 28px;border-radius:999px;box-shadow:0 14px 40px rgba(0,0,0,.25)}
  #ov-cap b{color:#f3d36b;font-weight:600}
  #ov-wa{position:absolute;right:56px;bottom:120px;width:420px;background:#e7ffdb;color:#16223F;border-radius:18px 18px 4px 18px;padding:16px 18px 10px;font-size:18px;line-height:1.4;box-shadow:0 18px 50px rgba(0,0,0,.25)}
  #ov-wa small{display:block;text-align:right;color:#4a7a52;font-size:13px;margin-top:4px}
  #ov-wa .top{display:flex;align-items:center;gap:10px;margin:-16px -18px 12px;padding:12px 16px;background:#075e54;color:#fff;border-radius:18px 18px 0 0;font-weight:600;font-size:16px}
  #ov-card{position:absolute;inset:0;background:radial-gradient(1200px 700px at 50% 40%,#2c4a9a,#1B2E63);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:24px;text-align:center;color:#fff}
  #ov-card img{width:620px;height:auto}
  #ov-card h1{margin:6px 0 0;font-family:'Playfair Display',serif;font-weight:600;font-size:76px;letter-spacing:.04em;text-transform:uppercase}
  #ov-card .linha{width:110px;height:3px;background:#C9A227;border-radius:3px}
  #ov-card p{margin:0;font-size:30px;opacity:.92}
  #ov-card .url{font-size:40px;font-weight:600;letter-spacing:.01em;color:#f3d36b}
  #ov-card .wa{display:inline-flex;align-items:center;gap:12px;background:#25D366;color:#0b2a17;font-weight:700;font-size:28px;padding:14px 30px;border-radius:999px}\`;
  document.head.appendChild(css);
  const ov = document.createElement('div'); ov.id = 'ov';
  ov.innerHTML = '<div id="ov-wa"><div class="top">Feitosa Imóveis · WhatsApp</div>Olá! Tenho interesse em <b>Casa de Madeira 700</b>. Gostaria de agendar uma visita.<small>agora ✓✓</small></div>'
    + '<div id="ov-cap"></div><div id="ov-ring"></div>'
    + '<svg id="ov-cur" viewBox="0 0 24 24"><path d="M5 3l14 7.5-6.2 1.6L10 18.5z" fill="#16223F" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>'
    + '<div id="ov-card"><img data-k="0" src="img/feitosa-participacoes-imobiliarias-1.webp" alt=""><div class="linha" data-k="0.2"></div>'
    + '<h1 data-k="0.3">Conheça nossos imóveis</h1><p class="url" data-k="0.7">rfeitosaimoveis.online</p>'
    + '<span class="wa" data-k="1.0">WhatsApp (88) 99328-0165</span></div>';
  document.body.appendChild(ov);
  const $ = (id) => document.getElementById(id);
  window.__ov = (s) => {
    const c = $('ov-cur'); c.style.opacity = s.cur.o; c.style.transform = 'translate(' + (s.cur.x - 5) + 'px,' + (s.cur.y - 3) + 'px) scale(' + (1 - 0.18 * s.cur.press) + ')';
    const r = $('ov-ring'); r.style.opacity = s.ring.o; r.style.left = s.ring.x + 'px'; r.style.top = s.ring.y + 'px'; r.style.transform = 'scale(' + s.ring.s + ')';
    const cap = $('ov-cap'); cap.style.opacity = s.cap.o; cap.style.transform = 'translate(-50%,' + s.cap.dy + 'px)'; if (cap.innerHTML !== s.cap.html) cap.innerHTML = s.cap.html;
    const w = $('ov-wa'); w.style.opacity = s.wa.o; w.style.transform = 'translateY(' + s.wa.dy + 'px) scale(' + s.wa.s + ')'; w.style.transformOrigin = '100% 100%';
    const k = $('ov-card'); k.style.opacity = s.card.o; k.style.display = s.card.o > 0 ? 'flex' : 'none';
    k.querySelectorAll('[data-k]').forEach((el) => { const v = Math.max(0, Math.min(1, (s.card.k - +el.dataset.k) / 0.4));
      el.style.opacity = v; el.style.transform = 'translateY(' + (1 - v) * 22 + 'px)'; });
    document.body.style.transformOrigin = '50% 0'; document.body.style.transform = s.zoom === 1 ? '' : 'scale(' + s.zoom + ')';
  };
})();`;

const cl = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const P = (t, a, b) => cl((t - a) / (b - a));
const eio = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const eo = (x) => 1 - Math.pow(1 - x, 3);
const eback = (x) => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); };

async function caixa(page, alvo) {
  return page.locator(alvo).first().boundingBox({ timeout: 150 }).catch(() => null);
}

(async () => {
  const [modo, ...tempos] = process.argv.slice(2);
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1536, height: 864 }, deviceScaleFactor: 1.25, locale: 'pt-BR' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[erro na página]', e.message));
  if (FONTES) {
    await page.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: fs.readFileSync(path.join(FONTES, 'g.css'), 'utf8') }));
    await page.route('https://fonts.gstatic.com/**', (r) => r.fulfill({ contentType: 'font/woff2', body: fs.readFileSync(path.join(FONTES, path.basename(new URL(r.request().url()).pathname))) }));
  }
  await page.route('https://wa.me/**', (r) => r.abort());
  await page.goto(SITE);
  await page.evaluate(() => document.fonts.ready);
  // carrega todas as imagens preguiçosas antes de gravar
  await page.evaluate(async () => { document.querySelectorAll('img[loading=lazy]').forEach((i) => { i.loading = 'eager'; });
    await Promise.all([...document.images].map((i) => i.complete ? 0 : new Promise((r) => { i.onload = i.onerror = r; }))); });
  await page.evaluate(OVERLAY);

  const stills = modo === 'stills' ? tempos.map(Number).sort((a, b) => a - b) : null;
  const dirQ = path.join(OUT, stills ? 'stills' : 'quadros');
  fs.rmSync(dirQ, { recursive: true, force: true }); fs.mkdirSync(dirQ, { recursive: true });
  let feitas = 0, rolIni = {}, cur = { x: 1100, y: 560 }, moveIni = {};
  for (let i = 0; i < Math.round(DUR * FPS); i++) {
    const t = i / FPS;
    if (stills && t > stills[stills.length - 1] + 0.01) break;
    while (feitas < ACOES.length && ACOES[feitas][0] <= t) { await ACOES[feitas][1](page); feitas++; }
    for (const [a, b, alvo, off] of ROLAGENS) if (t >= a && t <= b + 1 / FPS) {
      if (!rolIni[a]) { const y0 = await page.evaluate(() => scrollY); const bx = await caixa(page, alvo); rolIni[a] = { y0, y1: bx ? y0 + bx.y - off : y0 }; }
      await page.evaluate((y) => scrollTo(0, y), rolIni[a].y0 + (rolIni[a].y1 - rolIni[a].y0) * eio(P(t, a, b)));
    }
    const mv = MOVES.filter((m) => m[0] <= t).pop();
    if (mv) {
      const [a, b, alvo] = mv; let d = alvo;
      if (typeof alvo === 'string') { const bx = await caixa(page, alvo); d = bx ? { x: bx.x + Math.min(bx.width * 0.5, 70), y: bx.y + bx.height * 0.55 } : cur; }
      if (!moveIni[a]) moveIni[a] = { ...cur };
      const k = eio(P(t, a, b)); cur = { x: moveIni[a].x + (d.x - moveIni[a].x) * k, y: moveIni[a].y + (d.y - moveIni[a].y) * k };
    }
    let press = 0, ring = { o: 0, s: 1, x: cur.x, y: cur.y };
    for (const c of CLIQUES) { press = Math.max(press, cl(1 - Math.abs(t - c) / 0.09)); if (t >= c && t < c + 0.45) { const p = (t - c) / 0.45; ring = { o: (1 - p) * 0.85, s: 0.3 + 0.9 * eo(p), x: cur.x, y: cur.y }; } }
    let cap = { o: 0, dy: 0, html: '' };
    for (const [a, b, html] of CAPS) if (t >= a && t <= b) cap = { o: Math.min(P(t, a, a + 0.3), 1 - P(t, b - 0.3, b)), dy: (1 - eo(P(t, a, a + 0.4))) * 24, html };
    const wk = eback(P(t, 17.25, 17.7));
    const wa = { o: Math.min(P(t, 17.25, 17.45), 1 - P(t, 18.3, 18.56)), dy: (1 - wk) * 30, s: 0.9 + 0.1 * wk };
    const card = t >= 18.4 ? { o: P(t, 18.4, 18.7), k: (t - 18.6) * 1.1 } : { o: 0, k: 0 };
    const zoom = t < 3.3 ? 1.07 - 0.07 * eo(P(t, 0, 3.27)) : 1;
    const curO = Math.min(P(t, 4.3, 4.6), 1 - P(t, 17.6, 17.9));
    await page.evaluate((s) => window.__ov(s), { cur: { ...cur, o: curO, press }, ring: { ...ring, o: ring.o * curO }, cap, wa, card, zoom });
    if (!stills || stills.some((s) => Math.abs(s - t) < 0.5 / FPS))
      await page.screenshot({ path: path.join(dirQ, stills ? `t${t.toFixed(2)}.png` : `q${String(i).padStart(4, '0')}.jpg`), ...(stills ? {} : { type: 'jpeg', quality: 92 }) });
  }
  await browser.close();
})();

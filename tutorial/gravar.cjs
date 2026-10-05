// Grava o tutorial "Como abrir um chamado" pilotando o app real (build local) quadro a quadro.
// Dados 100% fictícios; RPCs e upload simulados (nada toca o banco). Uso: node tutorial/gravar.cjs [stills t1 t2 ...]
const path = require('path'), fs = require('fs');
const { chromium } = require(require.resolve('playwright', { paths: [process.cwd(), ...module.paths, require('child_process').execSync('npm root -g').toString().trim()] }));

const URL_APP = process.env.URL_APP || 'http://localhost:4173/';
const OUT = path.join(__dirname, 'work');
const FPS = 30, DUR = 86;
const FONTES = path.join(__dirname, '..', 'brag-output', 'composition', 'fonts');

// ---------- dados fictícios ----------
const SIS = ['ATLAS JURIS', 'CRM', 'ATLAS RH', 'Atlas Consult', 'ATLAS Empresas', 'Atlas Trib', 'Rfast Mail', 'Agente WhatsApp', 'App Connect Valley', 'Site Feitosa Imóveis', 'Site do escritório', 'Connect Academy', 'Atlas Cash', 'Atlas Hub', 'Atlas Imóveis', 'Legal Ops', 'Atlas Ponto', 'R. Feitosa Ops', 'Outro / não sei']
  .map((nome, i) => ({ id: i + 1, nome, ordem: i, ativo: true, grupo: 'sistema' }))
  .concat(['Computador / notebook', 'Impressora / scanner', 'E-mail, senha e acessos', 'Outro / não sei (suporte)'].map((nome, i) => ({ id: 30 + i, nome, ordem: 90 + i, ativo: true, grupo: 'suporte' })));
const PZ = { sistema: [[1440, 7200], [480, 2880], [120, 480], [30, 120]], suporte: [[480, 2880], [240, 1440], [60, 240], [15, 60]] };
const CATALOGO = {
  setores: [{ id: 1, nome: 'Sócios', ordem: 1 }, { id: 2, nome: 'Administrativo e Financeiro', ordem: 2 }, { id: 3, nome: 'Controladoria', ordem: 3 }, { id: 4, nome: 'Jurídico', ordem: 4 }],
  sistemas: SIS,
  urgencias: [
    ['Não urgente', 'Dúvida, ajuste ou melhoria; dá para trabalhar normalmente.'],
    ['Meio urgente', 'Atrapalha parte do trabalho, mas há um jeito provisório de seguir.'],
    ['Urgente', 'Impede tarefa importante ou com prazo hoje, sem alternativa.'],
    ['Muito urgente', 'A pessoa ou o setor está parado, ou há risco de perder prazo de cliente, processo ou pagamento.'],
  ].map(([nome, descricao], nivel) => ({ nivel, nome, descricao })),
  prazos: Object.entries(PZ).flatMap(([grupo, l]) => l.map(([a, r], nivel) => ({ grupo, nivel, assumir_min: a, resolver_min: r }))),
};
const AGORA = Date.now(), MIN = 60e3;
const iso = (ms) => new Date(ms).toISOString();
let fase = 'andamento'; // andamento → resolvido → avaliado
function consulta() {
  const criado = AGORA - (fase === 'andamento' ? 25 : 190) * MIN;
  return {
    protocolo: 'TI-0425', status: fase === 'andamento' ? 'andamento' : 'resolvido', sistema: 'ATLAS JURIS', grupo: 'sistema', urgencia: 2,
    criado_em: iso(criado), assumido_em: iso(criado + 18 * MIN), resolvido_em: fase === 'andamento' ? null : iso(criado + 170 * MIN),
    prazo_assumir_em: iso(criado + 120 * MIN), prazo_em: iso(criado + 480 * MIN), responsavel: 'Lucas',
    avaliado: fase === 'avaliado', avaliavel: fase === 'resolvido',
  };
}

// ---------- roteiro ----------
const CAPS = [ // [início, fim, passo, html]
  [5.3, 11.8, 'Passo 1 de 8', 'Abra a Central no navegador. <b>Não precisa de login.</b><br>Nos sistemas do hub, use o botão <b>Abrir chamado</b>.'],
  [12.3, 21.8, 'Passo 2 de 8', 'Setor, nome e cargo são obrigatórios.<br><b>O navegador lembra</b> para a próxima vez.'],
  [22.3, 29.8, 'Passo 3 de 8', 'Erro em sistema → bloco de cima. Computador, impressora, e-mail ou senha → <b>Suporte técnico</b>.<br>Na dúvida: <b>Outro / não sei</b>.'],
  [30.3, 40.8, 'Passo 4 de 8', 'Diga <b>o que</b>, <b>onde</b> e <b>desde quando</b>.<br>Até 3 prints: clique, arraste ou <b>Ctrl+V</b>.'],
  [41.3, 54.8, 'Passo 5 de 8', '<b>Meio urgente</b> é o padrão. <b>Muito urgente</b> só se você ou o setor está parado,<br>ou há prazo de cliente, processo ou pagamento em risco.'],
  [55.3, 63.8, 'Passo 6 de 8', 'Anote o <b>protocolo</b>. Os prazos para assumir e resolver aparecem na hora.'],
  [64.3, 72.8, 'Passo 7 de 8', 'Em <b>Acompanhar</b>, digite o protocolo (TI-0425 ou só 425).'],
  [73.3, 80.8, 'Passo 8 de 8', 'Resolvido? <b>Avalie o atendimento.</b> Leva 5 segundos.'],
];
const DESC = 'Abri o ATLAS JURIS e a tela de intimações está vazia desde hoje cedo. Já tentei sair e entrar de novo.';
// rolagem: [t0, t1, alvo (seletor ou 'topo'), deslocamento do alvo em relação ao topo da janela]
const ROLAGENS = [[12.0, 12.8, '#setor', 150], [22.0, 22.8, 'text=Onde está o problema?', 90], [30.0, 30.8, '#desc', 170], [41.0, 41.8, '.seg.urg', 230], [54.9, 55.4, '.foot', 430],
  [56.3, 57.0, '.card.done', 90], [64.0, 64.5, 'topo', 0], [73.8, 74.4, '.aval', 130]];
// cursor: [t0, t1, alvo] (move de onde está até o alvo); cliques em CLIQUES
const MOVES = [[6.0, 6.01, { x: 900, y: 520 }], [12.6, 13.3, '#setor'], [14.0, 14.6, '#nome'], [16.1, 16.7, '#cargo'],
  [27.0, 27.8, 'button.tile:has-text("ATLAS JURIS")'], [30.6, 31.2, '#desc'], [35.8, 36.5, 'label.drop'],
  [42.0, 42.6, '.seg.urg button >> nth=0'], [44.2, 44.6, '.seg.urg button >> nth=1'], [46.4, 46.9, '.seg.urg button >> nth=3'], [49.2, 49.7, '.seg.urg button >> nth=2'],
  [55.0, 55.7, 'button[type=submit]'], [56.1, 56.8, { x: 1250, y: 430 }], [64.3, 65.0, '.tab:has-text("Acompanhar")'], [65.6, 66.2, '#protocolo'], [67.2, 67.7, 'button:has-text("Consultar")'],
  [74.5, 75.1, '.estrelas button >> nth=4'], [75.6, 76.1, 'text=Quero elogiar'], [76.7, 77.3, 'button:has-text("Enviar avaliação")']];
const CLIQUES = [13.4, 14.7, 16.8, 27.9, 31.3, 36.6, 42.7, 44.7, 47.0, 49.8, 55.8, 65.1, 66.3, 67.8, 73.4, 75.2, 76.2, 77.4];
const DIGITA = [[14.8, 15.9, '#nome', 'Ana Souza'], [16.9, 17.8, '#cargo', 'Advogada'], [31.4, 35.4, '#desc', DESC], [66.4, 67.0, '#protocolo', '425']];
const DESTAQUES = [[6.0, 8.6, '.hero .pill'], [8.8, 11.6, '.top .tabs'], [18.2, 21.8, 'aside.side'], [23.0, 25.0, '.sis >> nth=0'], [25.2, 27.0, '.sis >> nth=1'],
  [37.0, 40.6, '.thumbs'], [50.2, 54.6, '.explica'], [57.4, 59.4, ['dt:has-text("Protocolo")', 'dd.protocolo']], [59.6, 61.5, ['dt:has-text("Assumir até")', 'dt:has-text("Resolver até") + dd']],
  [61.7, 63.7, '.done .banner'], [68.3, 72.6, 'dl:has(dt:has-text("Aberto em"))'], [77.9, 80.6, '.banner[role=status]']];
const ACOES = [
  [13.6, async (p) => p.selectOption('#setor', '4')],
  [27.9, async (p) => p.click('button.tile:has-text("ATLAS JURIS")')],
  [36.7, async (p) => p.setInputFiles('#arq', path.join(OUT, 'print-exemplo.png'))],
  [42.7, async (p) => p.click('.seg.urg button >> nth=0')], [44.7, async (p) => p.click('.seg.urg button >> nth=1')],
  [47.0, async (p) => p.click('.seg.urg button >> nth=3')], [49.8, async (p) => p.click('.seg.urg button >> nth=2')],
  [55.8, async (p) => { await p.click('button[type=submit]'); await p.waitForSelector('.card.done');
    await p.evaluate(() => { const i = document.querySelector('.done input.field'); if (i) i.value = 'https://chamado-jdc5.vercel.app/?avaliar=TI-0425.••••••••'; }); }],
  [65.1, async (p) => { await p.click('.tab:has-text("Acompanhar")'); await p.waitForSelector('#protocolo'); }],
  [67.8, async (p) => { await p.click('button:has-text("Consultar")'); await p.waitForSelector('dt:has-text("Aberto em")'); }],
  [73.4, async (p) => { fase = 'resolvido'; await p.click('button:has-text("Consultar")'); await p.waitForSelector('.aval'); }],
  [75.2, async (p) => p.click('.estrelas button >> nth=4')], [76.2, async (p) => p.click('text=Quero elogiar')],
  [77.4, async (p) => { fase = 'avaliado'; await p.click('button:has-text("Enviar avaliação")'); await p.waitForSelector('.banner[role=status]'); }],
];

// ---------- sobreposição (injetada na página) ----------
const OVERLAY = `
(() => {
  const css = document.createElement('style');
  css.textContent = \`*{transition:none!important;animation:none!important;caret-color:transparent!important}
  html{scrollbar-width:none} #root{padding-bottom:380px} ::-webkit-scrollbar{display:none}
  #ov{position:fixed;inset:0;pointer-events:none;z-index:9999;font-family:Geist,system-ui,sans-serif}
  #ov-cur{position:absolute;left:0;top:0;width:30px;height:30px;transform-origin:5px 3px;filter:drop-shadow(0 2px 4px rgba(0,0,0,.25))}
  #ov-ring{position:absolute;width:56px;height:56px;margin:-28px 0 0 -28px;border-radius:999px;border:3px solid #212965}
  #ov-hl{position:absolute;border-radius:16px;box-shadow:0 0 0 3px #6d0001,0 0 0 9999px rgba(14,17,22,.28)}
  #ov-cap{position:absolute;left:50%;bottom:26px;transform:translateX(-50%);display:flex;flex-direction:column;align-items:center;gap:8px;}
  #ov-step{background:#6d0001;color:#fff;font-size:15px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;padding:5px 14px;border-radius:999px}
  #ov-txt{white-space:nowrap;background:rgba(14,17,22,.94);color:#fff;font-size:24px;line-height:1.35;font-weight:500;text-align:center;padding:14px 26px;border-radius:18px;box-shadow:0 14px 40px rgba(0,0,0,.25)}
  #ov-txt b{color:#c5caf6;font-weight:700}
  #ov-card{position:absolute;inset:0;background:#f6f7f9;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:26px;text-align:center}
  #ov-card::after{content:"";position:absolute;left:0;right:0;bottom:0;height:8px;background:linear-gradient(90deg,#7a7a7a 0,#cfcfcf 32.8%,#6d0001 32.8%,#e3000f 85.4%,#1b1f4f 85.4%,#2f43a6 100%)}
  #ov-card .chip{background:#fff;border-radius:22px;padding:14px 22px;box-shadow:0 0 0 1px #e6e7ec,0 20px 50px rgba(33,41,101,.12)}
  #ov-card .chip img{height:76px;display:block}
  #ov-card h1{margin:0;font-size:58px;font-weight:600;letter-spacing:-.03em;color:#0e1116}
  #ov-card p{margin:0;font-size:24px;color:#4a5160}
  #ov-card ul{list-style:none;margin:6px 0 0;padding:0;display:grid;grid-template-columns:repeat(2,minmax(0,360px));gap:14px 22px;text-align:left}
  #ov-card li{display:flex;gap:12px;align-items:center;font-size:22px;font-weight:500;color:#0e1116;background:#fff;border:1px solid #e6e7ec;border-radius:14px;padding:14px 18px}
  #ov-card li i{width:30px;height:30px;border-radius:999px;background:#212965;color:#fff;font-style:normal;font-size:15px;font-weight:700;display:inline-flex;align-items:center;justify-content:center;flex:none}\`;
  document.head.appendChild(css);
  const ov = document.createElement('div'); ov.id = 'ov';
  ov.innerHTML = '<div id="ov-hl"></div><div id="ov-cap"><span id="ov-step"></span><div id="ov-txt"></div></div><div id="ov-ring"></div>'
    + '<svg id="ov-cur" viewBox="0 0 24 24"><path d="M5 3l14 7.5-6.2 1.6L10 18.5z" fill="#0e1116" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg><div id="ov-card"></div>';
  document.body.appendChild(ov);
  const $ = (id) => document.getElementById(id);
  window.__ov = (s) => {
    const c = $('ov-cur'); c.style.opacity = s.cur.o; c.style.transform = 'translate(' + (s.cur.x - 5) + 'px,' + (s.cur.y - 3) + 'px) scale(' + (1 - 0.18 * s.cur.press) + ')';
    const r = $('ov-ring'); r.style.opacity = s.ring.o; r.style.left = s.ring.x + 'px'; r.style.top = s.ring.y + 'px'; r.style.transform = 'scale(' + s.ring.s + ')';
    const h = $('ov-hl'); h.style.opacity = s.hl.o; Object.assign(h.style, { left: s.hl.x + 'px', top: s.hl.y + 'px', width: s.hl.w + 'px', height: s.hl.h + 'px' });
    const cap = $('ov-cap'); cap.style.opacity = s.cap.o; cap.style.transform = 'translate(-50%,' + s.cap.dy + 'px)';
    if ($('ov-txt').innerHTML !== s.cap.html) $('ov-txt').innerHTML = s.cap.html;
    $('ov-step').textContent = s.cap.step;
    const k = $('ov-card'); k.style.opacity = s.card.o; k.style.display = s.card.o > 0 ? 'flex' : 'none';
    if (k.dataset.modo !== s.card.modo) { k.dataset.modo = s.card.modo; k.innerHTML = s.card.html; }
    k.querySelectorAll('[data-k]').forEach((el) => { const v = Math.max(0, Math.min(1, (s.card.k - +el.dataset.k) / 0.35));
      el.style.opacity = v; el.style.transform = 'translateY(' + (1 - v) * 16 + 'px)'; });
  };
})();`;

const ABERTURA = `<div class="chip" data-k="0"><img src="/logo-rfg.png" alt=""></div><h1 data-k="0.25">Como abrir um chamado</h1>
<p data-k="0.6">Central de Chamados RFG · leva menos de 1 minuto</p>`;
const FECHO = `<div class="chip" data-k="0"><img src="/logo-rfg.png" alt=""></div><h1 data-k="0.2">Pronto. É só isso.</h1>
<ul><li data-k="0.5"><i>1</i>Setor, nome e cargo</li><li data-k="0.8"><i>2</i>Onde está o problema</li>
<li data-k="1.1"><i>3</i>O que aconteceu + print</li><li data-k="1.4"><i>4</i>A urgência certa</li></ul>
<p data-k="1.9">Guarde o protocolo e acompanhe em <b>Acompanhar</b>.</p>`;

// ---------- utilidades ----------
const cl = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const P = (t, a, b) => cl((t - a) / (b - a));
const eio = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const eo = (x) => 1 - Math.pow(1 - x, 3);

async function caixa(page, alvo) {
  const lista = Array.isArray(alvo) ? alvo : [alvo];
  const bs = [];
  for (const s of lista) { const b = await page.locator(s).first().boundingBox({ timeout: 150 }).catch(() => null); if (b) bs.push(b); }
  if (!bs.length) return null;
  const x = Math.min(...bs.map((b) => b.x)), y = Math.min(...bs.map((b) => b.y));
  const x2 = Math.max(...bs.map((b) => b.x + b.width)), y2 = Math.max(...bs.map((b) => b.y + b.height));
  return { x, y, width: x2 - x, height: y2 - y };
}

async function gerarPrint(browser) {
  const p = await browser.newPage({ viewport: { width: 1200, height: 720 } });
  await p.setContent(`<body style="margin:0;font-family:system-ui;background:#eef1f5">
    <div style="background:#5b1a1a;color:#fff;padding:16px 24px;font-size:20px;font-weight:600">ATLAS JURIS · Intimações</div>
    <div style="padding:28px 24px;display:flex;gap:16px"><div style="width:220px;height:560px;background:#fff;border-radius:10px"></div>
    <div style="flex:1;background:#fff;border-radius:10px;display:flex;align-items:center;justify-content:center;color:#7a8190;font-size:26px">Nenhuma intimação encontrada</div></div></body>`);
  fs.mkdirSync(OUT, { recursive: true });
  await p.screenshot({ path: path.join(OUT, 'print-exemplo.png') });
  await p.close();
}

(async () => {
  const [modo, ...tempos] = process.argv.slice(2);
  const browser = await chromium.launch();
  await gerarPrint(browser);
  const ctx = await browser.newContext({ viewport: { width: 1536, height: 864 }, deviceScaleFactor: 1.25, colorScheme: 'light', locale: 'pt-BR', timezoneId: 'America/Fortaleza' });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => console.log('[erro na página]', e.message));
  // fontes Geist servidas localmente
  await page.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: fs.readFileSync(path.join(FONTES, 'g.css'), 'utf8') }));
  await page.route('https://fonts.gstatic.com/**', (r) => r.fulfill({ contentType: 'font/woff2', body: fs.readFileSync(path.join(FONTES, path.basename(new URL(r.request().url()).pathname))) }));
  await page.route('**/auth/v1/**', (r) => r.fulfill({ status: 401, json: {} }));
  await page.route('**/storage/v1/object/**', (r) => r.fulfill({ json: { Key: 'chamados-prints/publico/exemplo.png', Id: 'exemplo' } }));
  await page.route('**/rest/v1/rpc/**', async (r) => {
    const u = r.request().url();
    if (u.includes('catalogo_publico')) return r.fulfill({ json: CATALOGO });
    if (u.includes('abrir_chamado_publico')) return r.fulfill({ json: { protocolo: 'TI-0425', sistema_id: 1, urgencia: 2, prints: 1, prazo_assumir_em: iso(AGORA + 120 * MIN), prazo_em: iso(AGORA + 480 * MIN), codigo_avaliacao: 'exemplo-de-codigo' } });
    if (u.includes('consultar_chamado')) return r.fulfill({ json: consulta() });
    if (u.includes('avaliar_chamado')) return r.fulfill({ json: { ok: true } });
    return r.fulfill({ json: null });
  });
  await page.goto(URL_APP);
  await page.waitForSelector('#setor');
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(OVERLAY);

  const stills = modo === 'stills' ? tempos.map(Number).sort((a, b) => a - b) : null;
  const dirQ = path.join(OUT, stills ? 'stills' : 'quadros');
  fs.rmSync(dirQ, { recursive: true, force: true }); fs.mkdirSync(dirQ, { recursive: true });
  const n = Math.round(DUR * FPS);
  let feitas = 0, rolInicio = {}, cur = { x: 900, y: 520 }, moveIni = {};
  for (let i = 0; i < n; i++) {
    const t = i / FPS;
    if (stills && !stills.some((s) => Math.abs(s - t) < 0.5 / FPS) && t > stills[stills.length - 1]) break;
    // ações discretas
    while (feitas < ACOES.length && ACOES[feitas][0] <= t) { await ACOES[feitas][1](page); feitas++; }
    // digitação
    for (const [a, b, sel, txt] of DIGITA) if (t >= a && t <= b + 1 / FPS) {
      const k = Math.round(txt.length * P(t, a, b)); const atual = await page.inputValue(sel, { timeout: 150 }).catch(() => null);
      if (atual !== null && atual !== txt.slice(0, k)) await page.fill(sel, txt.slice(0, k));
    }
    // rolagem
    for (const [a, b, alvo, off] of ROLAGENS) if (t >= a && t <= b + 1 / FPS) {
      const chave = a;
      if (!rolInicio[chave]) {
        const y0 = await page.evaluate(() => scrollY);
        let y1 = 0;
        if (alvo !== 'topo') { const bx = await caixa(page, alvo); y1 = bx ? Math.max(0, y0 + bx.y - off) : y0; }
        const max = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
        rolInicio[chave] = { y0, y1: Math.min(y1, max) };
      }
      const { y0, y1 } = rolInicio[chave];
      await page.evaluate((y) => scrollTo(0, y), y0 + (y1 - y0) * eio(P(t, a, b)));
    }
    // cursor
    const mv = MOVES.filter((m) => m[0] <= t).pop();
    if (mv) {
      const [a, b, alvo] = mv;
      let destino = alvo;
      if (typeof alvo === 'string') { const bx = await caixa(page, alvo); destino = bx ? { x: bx.x + Math.min(bx.width * 0.5, 60), y: bx.y + bx.height * 0.55 } : cur; }
      if (!moveIni[a]) moveIni[a] = { ...cur };
      const k = eio(P(t, a, b)); // depois do fim, segue o alvo (ex.: durante a rolagem)
      cur = { x: moveIni[a].x + (destino.x - moveIni[a].x) * k, y: moveIni[a].y + (destino.y - moveIni[a].y) * k };
    }
    let press = 0, ring = { o: 0, s: 1, x: cur.x, y: cur.y };
    for (const c of CLIQUES) { press = Math.max(press, cl(1 - Math.abs(t - c) / 0.09)); if (t >= c && t < c + 0.45) { const p = (t - c) / 0.45; ring = { o: (1 - p) * 0.8, s: 0.3 + 0.9 * eo(p), x: cur.x, y: cur.y }; } }
    const curO = Math.min(P(t, 5.8, 6.1), 1 - P(t, 80.6, 81.0));
    // destaque
    let hl = { o: 0, x: 0, y: 0, w: 0, h: 0 };
    for (const [a, b, alvo] of DESTAQUES) if (t >= a && t <= b) {
      const bx = await caixa(page, alvo);
      if (bx) hl = { o: Math.min(P(t, a, a + 0.3), 1 - P(t, b - 0.3, b)), x: bx.x - 8, y: bx.y - 8, w: bx.width + 16, h: bx.height + 16 };
    }
    // legenda
    let cap = { o: 0, dy: 0, html: '', step: '' };
    for (const [a, b, step, html] of CAPS) if (t >= a && t <= b) cap = { o: Math.min(P(t, a, a + 0.3), 1 - P(t, b - 0.3, b)), dy: (1 - eo(P(t, a, a + 0.4))) * 24, html, step };
    // abertura / fecho
    let card = { o: 0, modo: '', html: '', k: 0 };
    if (t < 5) card = { o: 1 - P(t, 4.6, 5.0), modo: 'abertura', html: ABERTURA, k: P(t, 0.2, 5) * 4.8 };
    else if (t >= 81) card = { o: P(t, 81.0, 81.4), modo: 'fecho', html: FECHO, k: (t - 81.3) };
    await page.evaluate((s) => window.__ov(s), { cur: { ...cur, o: curO, press }, ring, hl, cap, card });
    if (!stills || stills.some((s) => Math.abs(s - t) < 0.5 / FPS)) {
      await page.screenshot({ path: path.join(dirQ, stills ? `t${t.toFixed(2)}.png` : `q${String(i).padStart(5, '0')}.jpg`), ...(stills ? {} : { type: 'jpeg', quality: 92 }) });
    }
    if (!stills && i % 300 === 0) console.log('quadro', i, '/', n);
  }
  await browser.close();
})();

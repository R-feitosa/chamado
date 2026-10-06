import type { Urgencia } from './tipos';

/** Nota do alerta: frequência (Hz), início e duração (s), volume (0–1) e forma de onda. */
export interface Nota { f: number; ini: number; dur: number; vol: number; onda: OscillatorType }

/**
 * Som por urgência, sintetizado (sem arquivo de áudio): quanto mais urgente, mais toques e mais insistente.
 * Não urgente: 1 toque suave · Meio urgente: 2 toques · Urgente: 3 toques subindo · Muito urgente: alarme de 2 tons, 3×.
 */
export function padraoSom(u: Urgencia): Nota[] {
  switch (u) {
    case 0: return [{ f: 880, ini: 0, dur: 0.35, vol: 0.16, onda: 'sine' }];
    case 1: return [{ f: 660, ini: 0, dur: 0.18, vol: 0.2, onda: 'sine' }, { f: 880, ini: 0.2, dur: 0.3, vol: 0.2, onda: 'sine' }];
    case 2: return [523, 659, 784].map((f, i) => ({ f, ini: i * 0.16, dur: 0.2, vol: 0.26, onda: 'triangle' as const }));
    case 3: return Array.from({ length: 6 }, (_, i) => ({ f: i % 2 ? 660 : 988, ini: i * 0.22, dur: 0.2, vol: 0.3, onda: 'square' as const }));
  }
}

let ctx: AudioContext | null = null;

/** Navegadores só liberam áudio depois de um gesto: chame no primeiro clique/toque. */
export function prepararAudio() {
  try {
    const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) return;
    ctx ??= new AC();
    if (ctx.state === 'suspended') void ctx.resume();
  } catch { /* sem áudio: só o aviso visual */ }
}

export function tocarSom(u: Urgencia) {
  if (!ctx || ctx.state !== 'running') return;
  const t0 = ctx.currentTime + 0.02;
  for (const n of padraoSom(u)) {
    const osc = ctx.createOscillator(), g = ctx.createGain();
    osc.type = n.onda; osc.frequency.value = n.f;
    // Envelope curto (ataque 10 ms, queda exponencial) para não estalar.
    g.gain.setValueAtTime(0.0001, t0 + n.ini);
    g.gain.exponentialRampToValueAtTime(n.vol * (n.onda === 'square' ? 0.35 : 1), t0 + n.ini + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + n.ini + n.dur);
    osc.connect(g).connect(ctx.destination);
    osc.start(t0 + n.ini); osc.stop(t0 + n.ini + n.dur + 0.05);
  }
}

const CHAVE = 'chamados.som';
export function somLigado(): boolean { try { return localStorage.getItem(CHAVE) !== 'off'; } catch { return true; } }
export function definirSom(ligado: boolean) { try { localStorage.setItem(CHAVE, ligado ? 'on' : 'off'); } catch { /* sem armazenamento */ } }

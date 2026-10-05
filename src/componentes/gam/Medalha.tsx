import { RARIDADES, type Raridade } from '../../lib/gamificacao';
import { IconeGam } from './IconeGam';

/**
 * Medalha com identidade por raridade: comum (borda simples) → incomum → rara (acabamento) →
 * épica (brilho sutil) → lendária (gradiente discreto). Bloqueada: cinza + cadeado + texto.
 */
export function Medalha({ icone, raridade, bloqueada, tamanho = 44, rotulo }: { icone: string; raridade: Raridade; bloqueada?: boolean; tamanho?: number; rotulo: string }) {
  const texto = `${rotulo} · ${RARIDADES[raridade]}${bloqueada ? ' · bloqueada' : ''}`;
  return (
    <span className={`medalha rar-${raridade}${bloqueada ? ' bloq' : ''}`} style={{ width: tamanho, height: tamanho }} title={texto} role="img" aria-label={texto}>
      <IconeGam nome={bloqueada ? 'cadeado' : icone} tamanho={Math.round(tamanho * 0.48)} />
    </span>
  );
}

export function SeloRaridade({ r }: { r: Raridade }) {
  return <span className={`pill rarp rar-${r}`}>{RARIDADES[r]}</span>;
}

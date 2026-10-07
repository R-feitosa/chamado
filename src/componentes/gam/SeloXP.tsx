import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { fmtXp, sinalXp, type Jornada } from '../../lib/gamificacao';

/** Selo no cabeçalho: nível + barra + XP; "+25 XP" sobe e some quando o XP muda. */
export function SeloXP({ jornada, ganho, onAbrir }: { jornada: Jornada; ganho: { id: number; valor: number } | null; onAbrir: () => void }) {
  const reduzir = useReducedMotion();
  const p = jornada.perfil;
  if (!p) return null;
  const n = p.nivel;
  const texto = `Nível ${n.nivel} (${n.nome}) · ${fmtXp(n.xp)} de ${fmtXp(n.xp_proximo)} XP${p.xp_pendente ? ` (${fmtXp(p.xp_pendente)} ainda em validação)` : ''}`;
  return (
    <button type="button" className="selo" onClick={onAbrir} title={texto} aria-label={`${texto}. Abrir Minha jornada`}>
      <span className="selo-n">Nv {n.nivel}</span>
      <span className="selo-bar" aria-hidden="true"><i style={{ width: `${n.progresso * 100}%` }} /></span>
      <span className="selo-xp mono">{fmtXp(n.xp)}</span>
      {!!jornada.nao_lidas && <span className="selo-dot" aria-hidden="true" />}
      <AnimatePresence>
        {ganho && ganho.valor !== 0 && (
          <motion.span key={ganho.id} className={`flutua ${ganho.valor < 0 ? 'neg' : ''}`} aria-hidden="true"
            initial={{ opacity: 0, y: reduzir ? 0 : 6 }} animate={{ opacity: 1, y: reduzir ? 0 : -18 }} exit={{ opacity: 0, y: reduzir ? 0 : -30 }}
            transition={{ duration: reduzir ? 0.2 : 0.9, ease: 'easeOut' }}>
            {sinalXp(ganho.valor)}
          </motion.span>
        )}
      </AnimatePresence>
    </button>
  );
}

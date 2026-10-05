import { useEffect } from 'react';
import { AnimatePresence, motion, useReducedMotion } from 'motion/react';
import { sinalXp, type Notificacao, type Raridade } from '../../lib/gamificacao';
import { Medalha } from './Medalha';
import { IconeGam } from './IconeGam';

/**
 * Fila de avisos da gamificação. Conquista e nível têm cartão especial; XP e missão, cartão discreto.
 * Some sozinho (6 s; conquista 9 s), pode ser fechado, e anuncia para leitores de tela (aria-live).
 */
export function Toasts({ itens, onFechar }: { itens: Notificacao[]; onFechar: (id: number) => void }) {
  const reduzir = useReducedMotion();
  const visiveis = itens.slice(0, 3);
  useEffect(() => {
    const timers = visiveis.map((n) => window.setTimeout(() => onFechar(n.id), n.tipo === 'conquista' || n.tipo === 'nivel' ? 9000 : 6000));
    return () => timers.forEach(clearTimeout);
  }, [visiveis.map((n) => n.id).join(',')]); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="toasts" aria-live="polite" aria-relevant="additions">
      <AnimatePresence initial={false}>
        {visiveis.map((n) => {
          const especial = n.tipo === 'conquista' || n.tipo === 'nivel';
          const rar = (n.dados.raridade as Raridade | undefined) ?? 'rara';
          return (
            <motion.div key={n.id} layout={!reduzir} className={`toast ${especial ? `especial rar-${rar}` : ''}`} role="status"
              initial={reduzir ? { opacity: 0 } : { opacity: 0, y: 16, scale: 0.97 }}
              animate={reduzir ? { opacity: 1 } : { opacity: 1, y: 0, scale: 1 }}
              exit={reduzir ? { opacity: 0 } : { opacity: 0, x: 24 }}
              transition={{ duration: reduzir ? 0.15 : 0.35, ease: [0.22, 1, 0.36, 1] }}>
              {n.tipo === 'conquista' ? (
                <motion.span initial={reduzir ? false : { rotate: -12, scale: 0.6 }} animate={{ rotate: 0, scale: 1 }} transition={{ type: 'spring', stiffness: 260, damping: 16, delay: 0.1 }}>
                  <Medalha icone={(n.dados.icone as string) ?? 'trofeu'} raridade={rar} rotulo={n.titulo} tamanho={48} />
                </motion.span>
              ) : (
                <span className={`ticon t-${n.tipo}`}><IconeGam nome={n.tipo === 'nivel' ? 'nivel' : n.tipo === 'missao' ? 'missao' : n.tipo === 'revisao' ? 'revisao' : n.tipo === 'temporada' ? 'trofeu' : n.tipo === 'sequencia' ? 'chama' : 'estrela'} /></span>
              )}
              <div className="tcorpo">
                <small>{n.tipo === 'conquista' ? 'Conquista desbloqueada' : n.tipo === 'nivel' ? 'Level up' : n.tipo === 'missao' ? 'Missão concluída'
                  : n.tipo === 'sequencia' ? 'Sequência' : n.tipo === 'temporada' ? 'Temporada' : n.tipo === 'revisao' ? 'Revisão' : 'XP'}</small>
                <b>{n.titulo}</b>
                {n.detalhe && <span>{n.detalhe}</span>}
                {n.xp ? <span className={`txp ${n.xp < 0 ? 'neg' : ''}`}>{sinalXp(n.xp)}</span> : null}
              </div>
              <button type="button" className="tfechar" aria-label="Fechar aviso" onClick={() => onFechar(n.id)}>×</button>
            </motion.div>
          );
        })}
      </AnimatePresence>
    </div>
  );
}

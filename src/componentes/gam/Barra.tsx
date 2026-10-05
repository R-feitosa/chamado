import { motion } from 'motion/react';

/** Barra de progresso acessível (o valor também vai em texto ao lado, nunca só na cor). */
export function Barra({ valor, max = 1, rotulo, tom = 'accent', fina }: { valor: number; max?: number; rotulo: string; tom?: 'accent' | 'ok' | 'warn' | 'epic'; fina?: boolean }) {
  const p = Math.max(0, Math.min(1, max ? valor / max : 0));
  return (
    <div className={`gbar${fina ? ' fina' : ''}`} role="progressbar" aria-label={rotulo} aria-valuemin={0} aria-valuemax={max} aria-valuenow={Math.min(valor, max)}>
      <motion.i className={`t-${tom}`} initial={{ width: 0 }} animate={{ width: `${p * 100}%` }} transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }} />
    </div>
  );
}

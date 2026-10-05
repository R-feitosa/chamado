import { lazy, Suspense, type ComponentProps, type ComponentType } from 'react';
import type { Jornada as JornadaT } from '../../telas/Jornada';
import type { Ranking as RankingT } from '../../telas/Ranking';
import type { Toasts as ToastsT } from './Toasts';
import type { SeloXP as SeloT } from './SeloXP';

/**
 * Telas e efeitos da gamificação carregam sob demanda (com o Motion), para o formulário público
 * continuar leve. MotionConfig "user" respeita prefers-reduced-motion em todas as animações.
 */
function comMotion<P extends object>(carregar: () => Promise<ComponentType<P>>) {
  return lazy(async () => {
    const [{ MotionConfig }, C] = await Promise.all([import('motion/react'), carregar()]);
    return { default: (p: P) => <MotionConfig reducedMotion="user"><C {...p} /></MotionConfig> };
  });
}

const J = comMotion<ComponentProps<typeof JornadaT>>(() => import('../../telas/Jornada').then((m) => m.Jornada));
const R = comMotion<ComponentProps<typeof RankingT>>(() => import('../../telas/Ranking').then((m) => m.Ranking));
const C = comMotion<Record<string, never>>(() => import('../../telas/CentralGamificacao').then((m) => m.CentralGamificacao as ComponentType<Record<string, never>>));
const T = comMotion<ComponentProps<typeof ToastsT>>(() => import('./Toasts').then((m) => m.Toasts));
const S = comMotion<ComponentProps<typeof SeloT>>(() => import('./SeloXP').then((m) => m.SeloXP));

const carregando = <div className="carregando">Carregando…</div>;
export const JornadaL = (p: ComponentProps<typeof JornadaT>) => <Suspense fallback={carregando}><J {...p} /></Suspense>;
export const RankingL = (p: ComponentProps<typeof RankingT>) => <Suspense fallback={carregando}><R {...p} /></Suspense>;
export const CentralL = () => <Suspense fallback={carregando}><C /></Suspense>;
export const ToastsL = (p: ComponentProps<typeof ToastsT>) => <Suspense fallback={null}><T {...p} /></Suspense>;
export const SeloXPL = (p: ComponentProps<typeof SeloT>) => <Suspense fallback={null}><S {...p} /></Suspense>;

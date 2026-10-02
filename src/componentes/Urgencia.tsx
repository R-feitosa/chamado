import { URGENCIAS, type Urgencia } from '../lib/tipos';

/** Urgência sempre com cor + texto. */
export function PilulaUrgencia({ u }: { u: Urgencia }) {
  return <span className={`pill u${u}`} style={{ justifySelf: 'start' }}><i className="dot" />{URGENCIAS[u]}</span>;
}

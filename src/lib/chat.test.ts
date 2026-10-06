import { describe, expect, it } from 'vitest';
import { agruparPorDia, juntar, rotuloDia, type MensagemChat } from './chat';

const m = (id: number, iso: string, autor: MensagemChat['autor'] = 'time'): MensagemChat => ({ id, autor, texto: `m${id}`, criada_em: iso, apagada: false, nome: 'Kaio' });
const AGORA = new Date(2026, 9, 6, 15, 0).getTime();

describe('chat', () => {
  it('junta sem repetir e em ordem', () => {
    expect(juntar([m(1, '2026-10-06T10:00:00'), m(3, '2026-10-06T10:02:00')], [m(3, '2026-10-06T10:02:00'), m(2, '2026-10-06T10:01:00')]).map((x) => x.id)).toEqual([1, 2, 3]);
  });
  it('rótulos de dia', () => {
    expect(rotuloDia(new Date(2026, 9, 6, 9).toISOString(), AGORA)).toBe('Hoje');
    expect(rotuloDia(new Date(2026, 9, 5, 23).toISOString(), AGORA)).toBe('Ontem');
    expect(rotuloDia(new Date(2026, 9, 3, 12).toISOString(), AGORA)).toBe('03/10');
  });
  it('agrupa por dia mantendo a ordem', () => {
    const g = agruparPorDia([m(1, new Date(2026, 9, 5, 10).toISOString()), m(2, new Date(2026, 9, 6, 9).toISOString()), m(3, new Date(2026, 9, 6, 10).toISOString())], AGORA);
    expect(g.map((x) => [x.dia, x.mensagens.length])).toEqual([['Ontem', 1], ['Hoje', 2]]);
  });
});

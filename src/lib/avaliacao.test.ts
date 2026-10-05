import { describe, expect, it } from 'vitest';
import { avaliacaoDaUrl, linkAvaliacao, urlSemAvaliacao } from './avaliacao';

const COD = 'a1b2c3d4e5f60718293a4b5c';

describe('link de avaliação', () => {
  it('monta e lê de volta', () => {
    const l = linkAvaliacao('https://chamado.exemplo/', 'TI-0425', COD);
    expect(l).toBe(`https://chamado.exemplo/?avaliar=TI-0425.${COD}`);
    expect(avaliacaoDaUrl(new URL(l).search)).toEqual({ protocolo: 'TI-0425', codigo: COD });
  });
  it('rejeita formatos inválidos', () => {
    expect(avaliacaoDaUrl('?avaliar=TI-0425.123')).toBeNull();
    expect(avaliacaoDaUrl('?t=abc')).toBeNull();
  });
  it('tira o parâmetro da barra de endereço', () => {
    expect(urlSemAvaliacao(`https://x.br/?avaliar=TI-0425.${COD}#acompanhar`)).toBe('/#acompanhar');
    expect(urlSemAvaliacao(`https://x.br/?a=1&avaliar=TI-0425.${COD}`)).toBe('/?a=1');
  });
});

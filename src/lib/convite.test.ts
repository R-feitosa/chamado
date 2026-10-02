import { describe, expect, it } from 'vitest';
import { tokenDaUrl, urlSemToken } from './convite';

const T = 'a'.repeat(32) + '0123456789abcdef'.repeat(2);

describe('tokenDaUrl', () => {
  it('aceita 64 hex', () => expect(tokenDaUrl(`?t=${T}`)).toBe(T));
  it('normaliza maiúsculas e espaços', () => expect(tokenDaUrl(`?t=${T.toUpperCase()}%20`)).toBe(T));
  it('recusa formato inválido', () => {
    expect(tokenDaUrl('?t=abc')).toBeNull();
    expect(tokenDaUrl(`?t=${T}zz`)).toBeNull();
    expect(tokenDaUrl('')).toBeNull();
  });
});

describe('urlSemToken', () => {
  it('remove só o t', () => expect(urlSemToken(`https://x.app/?t=${T}&a=1#acompanhar`)).toBe('/?a=1#acompanhar'));
  it('sem outros parâmetros', () => expect(urlSemToken(`https://x.app/?t=${T}`)).toBe('/'));
});

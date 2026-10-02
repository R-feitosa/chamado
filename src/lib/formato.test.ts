import { describe, expect, it } from 'vitest';
import { faltando, filtrarPrints, iniciais, mensagemErro, quando, titulo } from './formato';

describe('iniciais', () => {
  it('usa primeira letra de nome e sobrenome', () => expect(iniciais('Brenno Magalhães')).toBe('BM'));
  it('nome único usa duas primeiras letras', () => expect(iniciais('Kaio')).toBe('KA'));
  it('vazio vira traço', () => expect(iniciais('  ')).toBe('—'));
});

describe('quando', () => {
  const agora = new Date('2026-10-02T12:00:00Z').getTime();
  it('agora', () => expect(quando('2026-10-02T11:59:40Z', agora)).toBe('agora'));
  it('minutos', () => expect(quando('2026-10-02T11:45:00Z', agora)).toBe('há 15 min'));
  it('horas', () => expect(quando('2026-10-02T09:00:00Z', agora)).toBe('há 3 h'));
  it('dias', () => expect(quando('2026-09-29T12:00:00Z', agora)).toBe('há 3 d'));
});

describe('titulo', () => {
  it('corta em 90 caracteres', () => expect(titulo('a'.repeat(120))).toHaveLength(90));
});

describe('faltando', () => {
  it('lista o que falta', () =>
    expect(faltando({ sistema: null, descricao: ' ', urgencia: null })).toEqual(['o sistema', 'a descrição', 'a urgência']));
  it('vazio quando completo', () => expect(faltando({ sistema: 1, descricao: 'x', urgencia: 0 })).toEqual([]));
});

describe('filtrarPrints', () => {
  const png = { type: 'image/png', size: 1000 };
  it('aceita até 3', () => expect(filtrarPrints(1, [png, png, png]).aceitos).toEqual([0, 1]));
  it('recusa não-imagem', () => expect(filtrarPrints(0, [{ type: 'application/pdf', size: 10 }]).msg).toMatch(/Só imagens/));
  it('recusa acima de 5 MB', () => expect(filtrarPrints(0, [{ type: 'image/png', size: 6 * 1024 * 1024 }]).msg).toMatch(/5 MB/));
});

describe('mensagemErro', () => {
  it('traduz login inválido', () => expect(mensagemErro({ message: 'Invalid login credentials' })).toBe('E-mail ou senha incorretos.'));
  it('repassa o limite contra abuso', () =>
    expect(mensagemErro({ message: 'Muitos chamados em pouco tempo. Aguarde alguns minutos e tente de novo.' })).toMatch(/^Muitos chamados/));
  it('repassa mensagens das RPCs', () =>
    expect(mensagemErro({ message: 'Este chamado já foi assumido ou resolvido.' })).toBe('Este chamado já foi assumido ou resolvido.'));
  it('usa padrão para o resto', () => expect(mensagemErro({ message: 'xyz' }, 'P')).toBe('P'));
});

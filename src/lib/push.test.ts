import { describe, expect, it } from 'vitest';
import { erroDoNavegador } from './push';

const dom = (name: string, message: string) => Object.assign(new Error(message), { name });

describe('erroDoNavegador', () => {
  it('permissão bloqueada', () => {
    expect(erroDoNavegador(dom('NotAllowedError', 'Registration failed - permission denied')).message).toMatch(/^O navegador bloqueou/);
  });
  it('serviço de push indisponível mostra o detalhe técnico', () => {
    const m = erroDoNavegador(dom('AbortError', 'Registration failed - push service error')).message;
    expect(m).toMatch(/^O navegador não conseguiu falar com o serviço de push/);
    expect(m).toContain('AbortError: Registration failed - push service error');
  });
  it('erro desconhecido vira mensagem com detalhe', () => {
    expect(erroDoNavegador(dom('InvalidStateError', 'x')).message).toBe('Não foi possível ativar neste navegador (InvalidStateError: x).');
  });
  it('mensagem já traduzida passa direto', () => {
    const e = new Error('O serviço de notificações do site não iniciou. Recarregue a página com Ctrl+Shift+R e tente de novo.');
    expect(erroDoNavegador(e)).toBe(e);
  });
});

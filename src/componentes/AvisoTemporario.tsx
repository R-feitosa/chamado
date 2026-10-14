/** Aviso temporário (Abrir chamado e Acompanhar). Some sozinho depois de `ate`, horário de Brasília. */
const AVISO = {
  de: new Date('2026-10-13T00:00:00-03:00').getTime(),
  ate: new Date('2026-10-17T23:59:59-03:00').getTime(),
  texto: 'De 13 a 17/10, os chamados podem demorar um pouco mais para ser atendidos por conta do Connect Valley. Obrigado pela compreensão!',
};

export function AvisoTemporario() {
  const agora = Date.now();
  if (agora < AVISO.de || agora > AVISO.ate) return null;
  return <p className="banner aviso-temp" role="status">{AVISO.texto}</p>;
}

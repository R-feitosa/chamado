import { useEffect, useRef } from 'react';

export function Ampliar({ src, onFechar }: { src: string; onFechar: () => void }) {
  const botao = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    botao.current?.focus();
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') onFechar(); };
    document.addEventListener('keydown', tecla);
    return () => document.removeEventListener('keydown', tecla);
  }, [onFechar]);
  return (
    <div className="lb" role="dialog" aria-label="Print do chamado" onClick={(e) => { if (e.target === e.currentTarget) onFechar(); }}>
      <img src={src} alt="Print anexado ao chamado" />
      <button type="button" ref={botao} onClick={onFechar}>Fechar</button>
    </div>
  );
}

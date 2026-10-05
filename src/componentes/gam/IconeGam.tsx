/** Ícones da gamificação (traço, herdam a cor). Nomes vêm de chamados.gam_conquistas.icone. */
const PATHS: Record<string, JSX.Element> = {
  passo: <><path d="M7 17c-1.5 0-3-1-3-3.5S5.5 8 7.5 8 10 10 10 12s-1.5 5-3 5z" /><path d="M16 12c-1.5 0-3-1-3-3.5S14.5 3 16.5 3 19 5 19 7s-1.5 5-3 5z" /><path d="M6 20h3M15 15h3" /></>,
  chama: <path d="M12 3c1 3 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5 0 2 1 3 2 3 0-3-1-5 1-8.5z" />,
  engrenagem: <><circle cx="12" cy="12" r="3" /><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" /></>,
  escudo: <><path d="M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6l8-3z" /><path d="M8.5 12l2.5 2.5 4.5-5" /></>,
  coroa: <><path d="M3 8l4 4 5-7 5 7 4-4-2 11H5L3 8z" /><path d="M5 19h14" /></>,
  raio: <path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z" />,
  alvo: <><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="5" /><circle cx="12" cy="12" r="1.5" /></>,
  diamante: <><path d="M6 3h12l4 6-10 12L2 9l4-6z" /><path d="M2 9h20M9 3l3 18 3-18" /></>,
  estrela: <path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 3z" />,
  sirene: <><path d="M6 18v-6a6 6 0 0 1 12 0v6" /><path d="M4 18h16v3H4zM12 2v2M3 6l1.5 1.5M21 6l-1.5 1.5" /></>,
  sol: <><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" /></>,
  pessoas: <><circle cx="9" cy="8" r="3.5" /><path d="M2 20c0-3.9 3.1-7 7-7s7 3.1 7 7" /><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 13.5c2.4.9 4 3.2 4 6" /></>,
  foguete: <><path d="M12 15l-3-3c1-5 4-8.5 10-9-.5 6-4 9-9 10z" /><path d="M9 12l-4 1-2 4 4-1M12 15l-1 4-4 2 1-4" /><circle cx="15" cy="9" r="1.5" /></>,
  medalha: <><circle cx="12" cy="15" r="6" /><path d="M8.5 9.5L6 2h4l2 5 2-5h4l-2.5 7.5" /><path d="M12 12.5l.9 1.8 2 .3-1.4 1.4.3 2-1.8-.9-1.8.9.3-2-1.4-1.4 2-.3.9-1.8z" /></>,
  trofeu: <><path d="M8 4h8v5a4 4 0 0 1-8 0V4z" /><path d="M8 6H4v1a4 4 0 0 0 4 4M16 6h4v1a4 4 0 0 1-4 4M12 13v4M8 21h8M9 17h6v4H9z" /></>,
  cadeado: <><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></>,
  nivel: <path d="M4 20l4-8 4 4 4-10 4 14" />,
  missao: <><path d="M9 11l3 3 8-8" /><path d="M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" /></>,
  revisao: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
};

export function IconeGam({ nome, tamanho = 20, titulo }: { nome: string; tamanho?: number; titulo?: string }) {
  return (
    <svg width={tamanho} height={tamanho} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
      strokeLinecap="round" strokeLinejoin="round" role={titulo ? 'img' : undefined} aria-label={titulo} aria-hidden={titulo ? undefined : true}>
      {PATHS[nome] ?? PATHS.medalha}
    </svg>
  );
}

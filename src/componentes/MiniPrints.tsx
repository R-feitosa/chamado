import { useEffect, useState } from 'react';
import { linksDosPrints } from '../lib/api';

/** Miniaturas dos prints de um chamado; clique amplia. */
export function MiniPrints({ caminhos, onAmpliar }: { caminhos: string[]; onAmpliar: (src: string) => void }) {
  const [links, setLinks] = useState<Record<string, string>>({});
  const chave = caminhos.join('|');
  useEffect(() => {
    let vivo = true;
    if (caminhos.length) linksDosPrints(caminhos).then((l) => { if (vivo) setLinks(l); }).catch(() => undefined);
    return () => { vivo = false; };
  }, [chave]);
  if (!caminhos.length) return null;
  return (
    <div className="pt">
      {caminhos.map((c, i) => (
        <button key={c} type="button" aria-label={`Ver print ${i + 1}`} disabled={!links[c]} onClick={() => links[c] && onAmpliar(links[c])}>
          {links[c] && <img src={links[c]} alt="" />}
        </button>
      ))}
    </div>
  );
}

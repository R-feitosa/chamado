import { useEffect, useState } from 'react';
import { filtrarPrints, MAX_PRINTS } from '../lib/formato';
import { Imagem } from './Icones';

export interface PrintLocal { file: File; url: string }

/** Prints da tela: clicar, arrastar ou colar com Ctrl+V (colar só vale enquanto `colarAtivo`). */
export function AnexarPrints({ prints, onMudar, colarAtivo }: {
  prints: PrintLocal[]; onMudar: (p: PrintLocal[]) => void; colarAtivo: boolean;
}) {
  const [msg, setMsg] = useState('');
  const [sobre, setSobre] = useState(false);

  function adicionar(lista: File[]) {
    const { aceitos, msg } = filtrarPrints(prints.length, lista);
    setMsg(msg);
    if (aceitos.length) onMudar([...prints, ...aceitos.map((i) => ({ file: lista[i], url: URL.createObjectURL(lista[i]) }))]);
  }

  useEffect(() => {
    if (!colarAtivo) return;
    const colar = (e: ClipboardEvent) => {
      const fs = Array.from(e.clipboardData?.items ?? [])
        .filter((it) => it.kind === 'file' && it.type.startsWith('image/'))
        .map((it) => it.getAsFile()).filter((f): f is File => !!f);
      if (fs.length) { e.preventDefault(); adicionar(fs); }
    };
    document.addEventListener('paste', colar);
    return () => document.removeEventListener('paste', colar);
  });

  function remover(i: number) {
    URL.revokeObjectURL(prints[i].url);
    onMudar(prints.filter((_, j) => j !== i));
  }

  return (
    <div className="grp">
      <span className="lbl">Prints da tela <span className="muted" style={{ fontWeight: 400 }}>· opcional, até {MAX_PRINTS}</span></span>
      {prints.length < MAX_PRINTS && (
        <label
          className={`drop${sobre ? ' on' : ''}`} htmlFor="arq"
          onDragEnter={(e) => { e.preventDefault(); setSobre(true); }}
          onDragOver={(e) => { e.preventDefault(); setSobre(true); }}
          onDragLeave={(e) => { e.preventDefault(); setSobre(false); }}
          onDrop={(e) => { e.preventDefault(); setSobre(false); adicionar(Array.from(e.dataTransfer.files)); }}
        >
          <span className="ic"><Imagem /></span>
          <span><b>Clique para escolher</b>, arraste a imagem aqui ou cole com Ctrl+V</span>
        </label>
      )}
      <input
        type="file" id="arq" className="sr" multiple accept="image/png,image/jpeg,image/webp,image/gif"
        onChange={(e) => { adicionar(Array.from(e.target.files ?? [])); e.target.value = ''; }}
      />
      <div className="thumbs">
        {prints.map((p, i) => (
          <div className="th" key={p.url}>
            <img src={p.url} alt={`Print ${i + 1}`} />
            <button type="button" aria-label={`Remover print ${i + 1}`} onClick={() => remover(i)}>×</button>
          </div>
        ))}
      </div>
      <span className="muted" style={{ fontSize: 13 }}>{msg}</span>
    </div>
  );
}

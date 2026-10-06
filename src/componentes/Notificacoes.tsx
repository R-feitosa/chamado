import { useEffect, useRef, useState } from 'react';
import { frequenciaPorExtenso, REGRAS_PADRAO } from '../lib/alertas';
import { precisaInstalarNoIOS } from '../lib/push';
import { COR_URGENCIA, URGENCIAS, type Urgencia } from '../lib/tipos';
import type { useAlertas } from '../hooks/useAlertas';

type Alertas = ReturnType<typeof useAlertas>;

const Sino = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" /><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
  </svg>
);

/** Sino no topo: estado das notificações neste aparelho + painel (ativar, som, testar, regras). */
export function Notificacoes({ a }: { a: Alertas }) {
  const [aberto, setAberto] = useState(false);
  const caixa = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!aberto) return;
    const fora = (e: MouseEvent) => { if (!caixa.current?.contains(e.target as Node)) setAberto(false); };
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setAberto(false); };
    document.addEventListener('mousedown', fora); document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('mousedown', fora); document.removeEventListener('keydown', esc); };
  }, [aberto]);
  const ios = precisaInstalarNoIOS();
  const regras = a.config?.regras ?? REGRAS_PADRAO;
  const estado = a.pushAtivo ? 'Ativas neste aparelho' : 'Desativadas neste aparelho';

  return (
    <div className="notif" ref={caixa}>
      <button type="button" className={`sino${a.pushAtivo ? ' on' : ''}`} aria-expanded={aberto} aria-haspopup="dialog"
        title={`Notificações: ${estado.toLowerCase()}`} aria-label={`Notificações: ${estado.toLowerCase()}`} onClick={() => setAberto((v) => !v)}>
        <Sino />{!a.pushAtivo && <span className="sino-dot" aria-hidden="true" />}
      </button>
      {aberto && (
        <div className="notif-pop card" role="dialog" aria-label="Notificações">
          <div className="notif-h">
            <b>Notificações</b>
            <span className={`pill ${a.pushAtivo ? 'u0' : 'aguardando'}`}><i className="dot" />{estado}</span>
          </div>
          {!a.suporta ? (
            <p className="muted notif-p">Este navegador não aceita notificações. Use Chrome, Edge, Firefox ou Safari atualizados.</p>
          ) : ios ? (
            <p className="banner notif-p" style={{ margin: 0 }}>No iPhone, as notificações só chegam com a Central instalada: no Safari, toque em <b>Compartilhar</b> → <b>Adicionar à Tela de Início</b> e abra por lá.</p>
          ) : (
            <p className="muted notif-p">Avisa chamado novo na hora e repete enquanto ninguém assume, mesmo com a Central fechada.</p>
          )}
          <div className="notif-acoes">
            {a.pushAtivo
              ? <button type="button" className="mini" disabled={a.ocupado} onClick={() => void a.desativar()}>Desativar</button>
              : <button type="button" className="btn pri notif-btn" disabled={a.ocupado || !a.suporta || ios} onClick={() => void a.ativar()}>{a.ocupado ? 'Ativando…' : 'Ativar neste aparelho'}</button>}
            {a.pushAtivo && <button type="button" className="mini go" disabled={a.ocupado} onClick={() => void a.testar()}>Enviar teste</button>}
          </div>
          {a.aviso && <p className="notif-aviso" role="status">{a.aviso}</p>}
          <label className="notif-som">
            <input type="checkbox" className="chave" checked={a.som} onChange={(e) => a.setSom(e.target.checked)} />
            <span><b>Som com a Central aberta</b><small>Fora dela, toca o som padrão do aparelho.</small></span>
          </label>
          <div className="notif-regras">
            <span className="lbl">Enquanto ninguém assume</span>
            {regras.map((r) => (
              <div key={r.nivel} className="notif-regra">
                <span className={`pill u${r.nivel}`}><i className="dot" />{URGENCIAS[r.nivel]}</span>
                <span>{frequenciaPorExtenso(r)}</span>
                <button type="button" className="ouvir" title={`Ouvir o som de ${URGENCIAS[r.nivel]}`} aria-label={`Ouvir o som de ${URGENCIAS[r.nivel]}`}
                  onClick={() => a.ouvir(r.nivel as Urgencia)}>▶</button>
              </div>
            ))}
            <small className="muted">Prazo de assumir vencido avisa também o gestor. Quem assumiu recebe aviso com o prazo de resolver perto e vencido.</small>
          </div>
        </div>
      )}
    </div>
  );
}

/** Cartões de aviso no canto da tela (chamado novo / sem responsável). */
export function AvisosNaTela({ a, onVer }: { a: Alertas; onVer?: () => void }) {
  if (!a.alertas.length) return null;
  return (
    <div className="avisos" aria-live="assertive">
      {a.alertas.map((x) => (
        <div key={x.id} className={`toast aviso aviso-u${x.urgencia}`} role="alert" style={{ ['--uc' as string]: `var(--${COR_URGENCIA[x.urgencia]})` }}>
          <div className="tcorpo">
            <b>{x.titulo}</b>
            <span>{x.corpo}</span>
            {onVer && <button type="button" className="mini go" style={{ alignSelf: 'flex-start', marginTop: 6 }} onClick={() => { a.fechar(x.id); onVer(); }}>Ver no painel</button>}
          </div>
          <button type="button" className="tfechar" aria-label="Fechar aviso" onClick={() => a.fechar(x.id)}>×</button>
        </div>
      ))}
    </div>
  );
}

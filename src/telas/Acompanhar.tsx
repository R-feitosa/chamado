import { useEffect, useState, type FormEvent } from 'react';
import { consultarChamado, type Consulta } from '../lib/api';
import { mensagemErro } from '../lib/formato';
import { situacaoPrazo, textoPrazo } from '../lib/sla';
import { duracao } from '../lib/analytics';
import type { Chamado } from '../lib/tipos';
import { PilulaUrgencia } from '../componentes/Urgencia';

const fmt = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

/** Adapta a consulta pública ao formato usado pelas regras de prazo. */
function comoChamado(c: Consulta): Chamado {
  return {
    id: c.protocolo, protocolo: c.protocolo, descricao: '', solicitante_id: '', sistema_id: 0, urgencia: c.urgencia, status: c.status,
    responsavel_id: c.responsavel ? 'x' : null, assumido_em: c.assumido_em, prazo_assumir_em: c.prazo_assumir_em, prazo_em: c.prazo_em,
    prints: [], criado_em: c.criado_em, atualizado_em: c.criado_em, resolvido_em: c.resolvido_em,
  };
}

/** Acompanhamento sem login: pelo protocolo, só situação e prazos (nunca a descrição). */
export function Acompanhar({ inicial = '' }: { inicial?: string }) {
  const [protocolo, setProtocolo] = useState(inicial);
  const [resultado, setResultado] = useState<Consulta | null | undefined>(undefined);
  const [erro, setErro] = useState('');
  const [buscando, setBuscando] = useState(false);

  async function buscar(p: string) {
    const alvo = p.trim().toUpperCase();
    if (!alvo) return;
    setBuscando(true); setErro('');
    try { setResultado(await consultarChamado(/^\d+$/.test(alvo) ? `TI-${alvo.padStart(4, '0')}` : alvo)); }
    catch (e) { setErro(mensagemErro(e)); }
    finally { setBuscando(false); }
  }
  useEffect(() => { if (inicial) void buscar(inicial); }, [inicial]);

  function enviar(e: FormEvent) { e.preventDefault(); void buscar(protocolo); }

  const agora = Date.now();
  const c = resultado ? comoChamado(resultado) : null;
  const situacao = !resultado ? null
    : resultado.status === 'resolvido' ? { texto: 'Resolvido', classe: 'u0' }
    : resultado.responsavel ? { texto: `Em andamento com ${resultado.responsavel}`, classe: 'andamento' }
    : { texto: 'Aguardando o time', classe: 'aguardando' };

  return (
    <section>
      <div className="hero">
        <h1>Acompanhar chamado</h1>
        <p>Digite o protocolo que apareceu quando você abriu o chamado.</p>
      </div>
      <div className="card done" style={{ maxWidth: 620 }}>
        <form onSubmit={enviar} style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          <label className="sr" htmlFor="protocolo">Protocolo</label>
          <input className="field mono" id="protocolo" placeholder="TI-0422" value={protocolo} autoComplete="off"
            onChange={(e) => setProtocolo(e.target.value)} style={{ flex: '1 1 200px', textTransform: 'uppercase' }} />
          <button className="btn pri" type="submit" disabled={buscando || !protocolo.trim()}>{buscando ? 'Buscando…' : 'Consultar'}</button>
        </form>
        {erro && <p className="erro" role="alert">{erro}</p>}
        {resultado === null && <p className="muted" style={{ margin: 0 }} role="status">Nenhum chamado com esse protocolo. Confira e tente de novo.</p>}
        {resultado && c && situacao && (
          <>
            <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
              <span className="mono" style={{ fontSize: 20, fontWeight: 600 }}>{resultado.protocolo}</span>
              <span className={`pill ${situacao.classe}`}><i className="dot" />{situacao.texto}</span>
            </div>
            <dl>
              <dt>Onde</dt><dd>{resultado.sistema}</dd>
              <dt>Urgência</dt><dd><PilulaUrgencia u={resultado.urgencia} /></dd>
              <dt>Aberto em</dt><dd>{fmt(resultado.criado_em)} · há {duracao(agora - new Date(resultado.criado_em).getTime())}</dd>
              <dt>Prazo</dt><dd><span className={`prazo ${situacaoPrazo(c, agora).situacao}`}>{textoPrazo(c, agora)}</span></dd>
              <dt>Assumir até</dt><dd>{fmt(resultado.prazo_assumir_em)}{resultado.assumido_em && ` · assumido em ${fmt(resultado.assumido_em)}`}</dd>
              <dt>Resolver até</dt><dd>{fmt(resultado.prazo_em)}{resultado.resolvido_em && ` · resolvido em ${fmt(resultado.resolvido_em)}`}</dd>
            </dl>
          </>
        )}
      </div>
    </section>
  );
}

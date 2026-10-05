import { useEffect, useState, type FormEvent } from 'react';
import { avaliarChamado, consultarChamado, type Consulta } from '../lib/api';
import { codigoDe } from '../lib/avaliacao';
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
export function Acompanhar({ inicial = '', codigoInicial }: { inicial?: string; codigoInicial?: string }) {
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
            <Avaliacao consulta={resultado} codigo={codigoInicial ?? codigoDe(resultado.protocolo)} onAvaliado={() => void buscar(resultado.protocolo)} />
          </>
        )}
      </div>
    </section>
  );
}

const NOTAS = ['Muito ruim', 'Ruim', 'Regular', 'Bom', 'Excelente'];

/** Avaliação do atendimento: só com o código de quem abriu, 1 vez, até 14 dias depois de resolvido. */
function Avaliacao({ consulta, codigo, onAvaliado }: { consulta: Consulta; codigo: string | null; onAvaliado: () => void }) {
  const [nota, setNota] = useState(0);
  const [elogio, setElogio] = useState(false);
  const [comentario, setComentario] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState('');
  if (consulta.avaliado) return <p className="banner" style={{ margin: 0 }} role="status">Avaliação registrada. Obrigado por contar como foi o atendimento.</p>;
  if (!consulta.avaliavel || !codigo) return null;
  async function enviar(e: FormEvent) {
    e.preventDefault();
    if (!nota || enviando || !codigo) return;
    setEnviando(true); setErro('');
    try { await avaliarChamado(consulta.protocolo, codigo, nota, elogio, comentario); onAvaliado(); }
    catch (err) { setErro(mensagemErro(err)); } finally { setEnviando(false); }
  }
  return (
    <form className="aval" onSubmit={enviar}>
      <b>Como foi o atendimento?</b>
      <div className="estrelas" role="group" aria-label="Nota de 1 a 5">
        {NOTAS.map((nome, i) => (
          <button key={nome} type="button" aria-pressed={nota === i + 1} aria-label={`${i + 1} de 5: ${nome}`} title={nome} onClick={() => setNota(i + 1)}>
            <svg viewBox="0 0 24 24" fill={nota > i ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 3z" /></svg>
            {i + 1}
          </button>
        ))}
      </div>
      {nota > 0 && <span className="muted" style={{ fontSize: 13 }}>{NOTAS[nota - 1]}</span>}
      <label style={{ display: 'flex', gap: 8, alignItems: 'center', fontSize: 14 }}>
        <input type="checkbox" checked={elogio} onChange={(e) => setElogio(e.target.checked)} /> Quero elogiar quem me atendeu
      </label>
      <textarea className="field" rows={2} maxLength={500} placeholder="Comentário (opcional)" value={comentario} onChange={(e) => setComentario(e.target.value)} aria-label="Comentário" />
      {erro && <p className="erro" role="alert">{erro}</p>}
      <button className="btn pri" type="submit" disabled={!nota || enviando} style={{ alignSelf: 'flex-start' }}>{enviando ? 'Enviando…' : 'Enviar avaliação'}</button>
    </form>
  );
}

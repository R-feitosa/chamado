import { useState, type FormEvent } from 'react';
import { abrirChamado } from '../lib/api';
import { faltando, mensagemErro } from '../lib/formato';
import { COR_URGENCIA, NOME_GRUPO, URGENCIAS, URGENCIA_PADRAO, type Catalogo, type Chamado, type Pessoa, type Sistema, type Urgencia } from '../lib/tipos';
import { minutosPorExtenso } from '../lib/sla';
import { AnexarPrints, type PrintLocal } from '../componentes/AnexarPrints';
import { Check, Seta } from '../componentes/Icones';

interface Props {
  eu: Pessoa;
  userId: string;
  catalogo: Catalogo;
  ativa: boolean;
  onVerPainel?: () => void;
  rotuloVer?: string;
}

export function AbrirChamado({ eu, userId, catalogo, ativa, onVerPainel, rotuloVer = 'Ver no painel do time' }: Props) {
  const [sistema, setSistema] = useState<number | null>(null);
  const [descricao, setDescricao] = useState('');
  const [urgencia, setUrgencia] = useState<Urgencia | null>(URGENCIA_PADRAO);
  const [prints, setPrints] = useState<PrintLocal[]>([]);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState('');
  const [enviado, setEnviado] = useState<Chamado | null>(null);

  const setor = catalogo.setores.find((s) => s.id === eu.setor_id)?.nome;
  const grupos: [string, Sistema[]][] = [
    ['Sistemas (desenvolvimento)', catalogo.sistemas.filter((s) => s.ativo && s.grupo !== 'suporte')],
    ['Suporte técnico (computador, impressora, e-mail, acessos)', catalogo.sistemas.filter((s) => s.ativo && s.grupo === 'suporte')],
  ];
  const nivel = catalogo.urgencias.find((u) => u.nivel === urgencia);
  const grupo = catalogo.sistemas.find((s) => s.id === sistema)?.grupo ?? null;
  const prazoDe = (n: number | null) => (grupo === null || n === null ? undefined : catalogo.prazos.find((p) => p.grupo === grupo && p.nivel === n));
  const prazoAtual = prazoDe(urgencia);
  const nomeSistema = (id: number | null) => catalogo.sistemas.find((s) => s.id === id)?.nome ?? '';
  const falta = faltando({ sistema, descricao, urgencia });

  const itens: [string, string][] = [
    ['Nome', eu.nome],
    ['Sistema', nomeSistema(sistema)],
    ['Descrição', descricao.trim() ? 'Preenchida' : ''],
    ['Urgência', urgencia === null ? '' : URGENCIAS[urgencia]],
  ];
  const feitos = itens.filter((i) => i[1]).length;

  async function enviar(e: FormEvent) {
    e.preventDefault();
    if (falta.length || enviando || sistema === null || urgencia === null) return;
    setEnviando(true); setErro('');
    try {
      const c = await abrirChamado(userId, { sistemaId: sistema, descricao, urgencia, arquivos: prints.map((p) => p.file) });
      setEnviado(c);
    } catch (err) {
      setErro(mensagemErro(err, 'Não foi possível enviar. Tente de novo.'));
    } finally {
      setEnviando(false);
    }
  }

  function outro() {
    prints.forEach((p) => URL.revokeObjectURL(p.url));
    setSistema(null); setDescricao(''); setUrgencia(URGENCIA_PADRAO); setPrints([]); setErro(''); setEnviado(null);
  }

  return (
    <section>
      <div className="hero">
        <span className="pill" style={{ alignSelf: 'flex-start', background: 'var(--accent-soft)', color: 'var(--accent-ink)' }}>Leva menos de 1 minuto</span>
        <h1>Algum sistema ou equipamento deu problema?</h1>
        <p>Conte o que aconteceu e o chamado chega na hora para o time de desenvolvimento e suporte.</p>
      </div>

      {enviado ? (
        <div className="card done">
          <span className="pill u0" style={{ alignSelf: 'flex-start', fontSize: 13 }}>Chamado enviado</span>
          <h2 style={{ fontSize: 26, fontWeight: 600 }}>Recebemos seu chamado</h2>
          <p className="muted" style={{ margin: 0 }}>O time foi avisado e já vê o chamado no painel.</p>
          <dl>
            <dt>Protocolo</dt><dd className="mono">{enviado.protocolo}</dd>
            <dt>Aberto por</dt><dd>{eu.nome}</dd>
            <dt>Sistema</dt><dd>{nomeSistema(enviado.sistema_id)}</dd>
            <dt>Urgência</dt><dd>{URGENCIAS[enviado.urgencia]}</dd>
            <dt>Prints</dt><dd>{enviado.prints.length ? `${enviado.prints.length} anexado${enviado.prints.length > 1 ? 's' : ''}` : 'Nenhum'}</dd>
          </dl>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
            <button className="btn sec" type="button" onClick={outro}>Abrir outro chamado</button>
            {onVerPainel && <button className="btn pri" type="button" onClick={onVerPainel}>{rotuloVer}</button>}
          </div>
        </div>
      ) : (
        <form className="wrap" noValidate onSubmit={enviar}>
          <div className="card form">
            <div className="grp">
              <span className="lbl">Seu nome</span>
              <div className="field" style={{ display: 'flex', alignItems: 'center', background: 'var(--soft)' }}>
                {eu.nome}{setor && <span className="muted">&nbsp;· {setor}</span>}
              </div>
            </div>
            <div className="grp">
              <span className="lbl">Onde está o problema?</span>
              {grupos.filter(([, lista]) => lista.length).map(([nomeGrupo, lista]) => (
                <div key={nomeGrupo} className="grp" style={{ gap: 8 }}>
                  <span className="sub" id={`g-${nomeGrupo}`}>{nomeGrupo}</span>
                  <div className="sis" role="group" aria-labelledby={`g-${nomeGrupo}`}>
                    {lista.map((s) => (
                      <button key={s.id} type="button" className="tile" aria-pressed={sistema === s.id} onClick={() => setSistema(s.id)}>
                        <span>{s.nome}</span><span className="chk"><Check /></span>
                      </button>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            <div className="grp">
              <label className="lbl" htmlFor="desc">O que aconteceu?</label>
              <textarea className="field" id="desc" rows={4} maxLength={5000} value={descricao} onChange={(e) => setDescricao(e.target.value)}
                placeholder="Ex.: abri o ATLAS JURIS e a tela de intimações está vazia desde hoje cedo. / Meu notebook não liga desde a manhã." />
            </div>
            <AnexarPrints prints={prints} onMudar={setPrints} colarAtivo={ativa && !enviado} />
            <div className="grp">
              <span className="lbl" id="lblUrg">Qual a urgência?</span>
              <div className="seg urg" role="group" aria-labelledby="lblUrg">
                {URGENCIAS.map((u, i) => {
                  const pz = prazoDe(i);
                  return (
                    <button key={u} type="button" aria-pressed={urgencia === i} onClick={() => setUrgencia(i as Urgencia)}>
                      <span><span className="dot" style={{ background: `var(--${COR_URGENCIA[i]})`, display: 'inline-block', marginRight: 6 }} />{u}</span>
                      {pz && <small>resolver em até {minutosPorExtenso(pz.resolver_min)}</small>}
                    </button>
                  );
                })}
              </div>
              {nivel && (
                <p className={`explica u${nivel.nivel}`} role="status">
                  <b>{nivel.nome}:</b> {nivel.descricao}{' '}
                  {prazoAtual && grupo
                    ? <>Para {NOME_GRUPO[grupo].toLowerCase()}, o time assume em até <b>{minutosPorExtenso(prazoAtual.assumir_min)}</b> e resolve em até <b>{minutosPorExtenso(prazoAtual.resolver_min)}</b>.</>
                    : <>Escolha onde está o problema para ver os prazos.</>}
                </p>
              )}
            </div>
            <div className="foot">
              <button className="btn pri" type="submit" disabled={falta.length > 0 || enviando}>Enviar chamado <Seta /></button>
              <span className="muted" style={{ fontSize: 14, color: erro ? 'var(--bad)' : undefined }} role={erro ? 'alert' : undefined}>
                {erro || (enviando ? (prints.length ? 'Enviando prints…' : 'Enviando…') : falta.length ? `Falta ${falta.join(', ')}.` : 'Tudo pronto.')}
              </span>
            </div>
          </div>
          <aside className="card side" aria-label="Resumo">
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <b style={{ fontSize: 14 }}>Seu chamado</b><span className="mono muted" style={{ fontSize: 13 }}>{feitos}/4</span>
            </div>
            <div className="bar"><i style={{ width: `${feitos * 25}%` }} /></div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              {itens.map(([rotulo, valor]) => (
                <div key={rotulo} className={`step${valor ? ' ok' : ''}`}>
                  <span className="chk"><Check /></span>
                  <div><small>{rotulo}</small><span>{valor || 'Pendente'}</span></div>
                </div>
              ))}
            </div>
          </aside>
        </form>
      )}
    </section>
  );
}

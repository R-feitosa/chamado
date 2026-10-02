import { useState, type FormEvent } from 'react';
import { abrirChamado, type ChamadoAberto, type Convite } from '../lib/api';
import { faltando, mensagemErro } from '../lib/formato';
import { COR_URGENCIA, NOME_GRUPO, URGENCIAS, URGENCIA_PADRAO, type Catalogo, type Pessoa, type Sistema, type Urgencia } from '../lib/tipos';
import { minutosPorExtenso } from '../lib/sla';
import { AnexarPrints, type PrintLocal } from '../componentes/AnexarPrints';
import { Check, Seta } from '../componentes/Icones';

/**
 * Com login (time): o nome vem da conta. Sem login: a pessoa escolhe setor e nome na lista,
 * ou chega pelo botão de um sistema do hub (convite) com nome e, em geral, setor já definidos.
 */
export type Quem =
  | { tipo: 'dev'; eu: Pessoa; userId: string }
  | { tipo: 'publico' }
  | { tipo: 'convite'; token: string; convite: Convite };

interface Props {
  quem: Quem;
  catalogo: Catalogo;
  ativa: boolean;
  onVerPainel?: () => void;
  onAcompanhar?: (protocolo: string) => void;
  /** Convite já usado: o próximo chamado volta ao formulário comum. */
  onConviteUsado?: () => void;
}

const CHAVE_NOME = 'rfg-chamados-solicitante';
const CHAVE_SETOR = 'rfg-chamados-setor';
function lembrado(chave: string): string {
  try { return localStorage.getItem(chave) ?? ''; } catch { return ''; }
}
const fmt = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

export function AbrirChamado({ quem, catalogo, ativa, onVerPainel, onAcompanhar, onConviteUsado }: Props) {
  const publico = quem.tipo === 'publico';
  const convite = quem.tipo === 'convite' ? quem.convite : null;
  const escolheSetor = publico || !!convite?.precisa_setor;
  // Sem login, setor e nome são obrigatórios e precisam combinar (o banco confere de novo).
  const [setorId, setSetorId] = useState(() => {
    const id = publico ? lembrado(CHAVE_SETOR) : '';
    return catalogo.setores.some((s) => String(s.id) === id) ? id : '';
  });
  const [solicitanteId, setSolicitanteId] = useState(() => {
    const id = publico ? lembrado(CHAVE_NOME) : '';
    return catalogo.pessoas.some((p) => p.id === id && String(p.setor_id) === setorId) ? id : '';
  });
  const pessoasDoSetor = catalogo.pessoas.filter((p) => String(p.setor_id) === setorId);
  function trocarSetor(id: string) {
    setSetorId(id);
    if (!catalogo.pessoas.some((p) => p.id === solicitanteId && String(p.setor_id) === id)) setSolicitanteId('');
  }
  const [sistema, setSistema] = useState<number | null>(convite?.sistema_id ?? null);
  const [descricao, setDescricao] = useState('');
  const [urgencia, setUrgencia] = useState<Urgencia | null>(URGENCIA_PADRAO);
  const [prints, setPrints] = useState<PrintLocal[]>([]);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState('');
  const [enviado, setEnviado] = useState<ChamadoAberto | null>(null);

  const eu: Pick<Pessoa, 'nome'> & { id?: string } | undefined = quem.tipo === 'dev' ? quem.eu
    : convite ? { nome: convite.nome }
    : pessoasDoSetor.find((p) => p.id === solicitanteId);
  const setor = quem.tipo === 'dev'
    ? catalogo.setores.find((s) => s.id === quem.eu.setor_id)?.nome
    : convite && !convite.precisa_setor ? convite.setor ?? undefined
    : catalogo.setores.find((s) => String(s.id) === setorId)?.nome;
  const setoresComPessoas = catalogo.setores.filter((s) => catalogo.pessoas.some((p) => p.setor_id === s.id));
  const grupos: [string, Sistema[]][] = [
    ['Sistemas (desenvolvimento)', catalogo.sistemas.filter((s) => s.ativo && s.grupo !== 'suporte')],
    ['Suporte técnico (computador, impressora, e-mail, acessos)', catalogo.sistemas.filter((s) => s.ativo && s.grupo === 'suporte')],
  ];
  const nivel = catalogo.urgencias.find((u) => u.nivel === urgencia);
  const grupo = catalogo.sistemas.find((s) => s.id === sistema)?.grupo ?? null;
  const prazoDe = (n: number | null) => (grupo === null || n === null ? undefined : catalogo.prazos.find((p) => p.grupo === grupo && p.nivel === n));
  const prazoAtual = prazoDe(urgencia);
  const nomeSistema = (id: number | null) => catalogo.sistemas.find((s) => s.id === id)?.nome ?? '';
  const falta = [...(escolheSetor && !setorId ? ['seu setor'] : []), ...(eu ? [] : ['seu nome']), ...faltando({ sistema, descricao, urgencia })];

  const itens: [string, string][] = [
    ...(quem.tipo !== 'dev' ? [['Setor', setor ?? ''] as [string, string]] : []),
    ['Nome', eu?.nome ?? ''],
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
      if (!eu) return;
      const c = await abrirChamado(
        quem.tipo === 'dev' ? { userId: quem.userId }
          : quem.tipo === 'convite' ? { token: quem.token, setorId: quem.convite.precisa_setor ? Number(setorId) : null }
          : { setorId: Number(setorId), solicitanteId: eu.id! },
        { sistemaId: sistema, descricao, urgencia, arquivos: prints.map((p) => p.file) });
      if (publico) { try { localStorage.setItem(CHAVE_SETOR, setorId); localStorage.setItem(CHAVE_NOME, eu.id!); } catch { /* sem armazenamento: só não lembra */ } }
      setEnviado(c);
    } catch (err) {
      setErro(mensagemErro(err, 'Não foi possível enviar. Tente de novo.'));
    } finally {
      setEnviando(false);
    }
  }

  function outro() {
    prints.forEach((p) => URL.revokeObjectURL(p.url));
    if (convite && onConviteUsado) { onConviteUsado(); return; } // token é de uso único
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
          <p className="muted" style={{ margin: 0 }}>
            O time foi avisado e já vê o chamado no painel.{publico && <> <b style={{ color: 'var(--ink)' }}>Guarde o protocolo</b> para acompanhar.</>}
          </p>
          <dl>
            <dt>Protocolo</dt><dd className="mono" style={{ fontSize: 18 }}>{enviado.protocolo}</dd>
            <dt>Aberto por</dt><dd>{eu?.nome}{setor && <span className="muted"> · {setor}</span>}</dd>
            <dt>Onde</dt><dd>{nomeSistema(enviado.sistema_id)}</dd>
            <dt>Urgência</dt><dd>{URGENCIAS[enviado.urgencia]}</dd>
            <dt>Assumir até</dt><dd>{fmt(enviado.prazo_assumir_em)}</dd>
            <dt>Resolver até</dt><dd>{fmt(enviado.prazo_em)}</dd>
            <dt>Prints</dt><dd>{enviado.prints ? `${enviado.prints} anexado${enviado.prints > 1 ? 's' : ''}` : 'Nenhum'}</dd>
          </dl>
          <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
            <button className="btn sec" type="button" onClick={outro}>Abrir outro chamado</button>
            {onVerPainel && <button className="btn pri" type="button" onClick={onVerPainel}>Ver no painel do time</button>}
            {onAcompanhar && <button className="btn pri" type="button" onClick={() => onAcompanhar(enviado.protocolo)}>Acompanhar este chamado</button>}
          </div>
        </div>
      ) : (
        <form className="wrap" noValidate onSubmit={enviar}>
          <div className="card form">
            {publico ? (
              <div className="dupla">
                <div className="grp">
                  <label className="lbl" htmlFor="setor">Seu setor <span className="obrig" aria-hidden="true">*</span></label>
                  <select className="field" id="setor" required value={setorId} onChange={(e) => trocarSetor(e.target.value)}>
                    <option value="">Selecione o setor</option>
                    {setoresComPessoas.map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}
                  </select>
                </div>
                <div className="grp">
                  <label className="lbl" htmlFor="nome">Seu nome <span className="obrig" aria-hidden="true">*</span></label>
                  <select className="field" id="nome" required disabled={!setorId} value={solicitanteId} onChange={(e) => setSolicitanteId(e.target.value)}>
                    <option value="">{setorId ? 'Selecione seu nome' : 'Escolha o setor primeiro'}</option>
                    {pessoasDoSetor.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
                  </select>
                </div>
              </div>
            ) : convite ? (
              <div className="grp">
                <p className="banner" style={{ margin: 0 }} role="status">
                  <span>
                    Você veio {convite.sistema_origem ? <>do <b>{convite.sistema_origem}</b></> : 'de um sistema do hub'}.{' '}
                    {convite.precisa_setor ? 'Seu nome vem do seu login; falta só informar o setor.' : 'Nome e setor vêm do seu login.'}
                  </span>
                </p>
                <div className={convite.precisa_setor ? 'dupla' : undefined}>
                  <div className="grp">
                    <span className="lbl">Seu nome</span>
                    <div className="field" style={{ background: 'var(--soft)', lineHeight: '22px' }}>
                      {convite.nome}{!convite.precisa_setor && setor && <span className="muted">&nbsp;· {setor}</span>}
                      {convite.cargo && <span className="muted">&nbsp;· {convite.cargo}</span>}
                    </div>
                  </div>
                  {convite.precisa_setor && (
                    <div className="grp">
                      <label className="lbl" htmlFor="setor">Seu setor <span className="obrig" aria-hidden="true">*</span></label>
                      <select className="field" id="setor" required value={setorId} onChange={(e) => setSetorId(e.target.value)}>
                        <option value="">Selecione o setor</option>
                        {catalogo.setores.map((s) => <option key={s.id} value={s.id}>{s.nome}</option>)}
                      </select>
                    </div>
                  )}
                </div>
              </div>
            ) : (
              <div className="grp">
                <span className="lbl">Seu nome</span>
                <div className="field" style={{ display: 'flex', alignItems: 'center', background: 'var(--soft)' }}>
                  {eu?.nome}{setor && <span className="muted">&nbsp;· {setor}</span>}
                </div>
              </div>
            )}
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
              <b style={{ fontSize: 14 }}>Seu chamado</b><span className="mono muted" style={{ fontSize: 13 }}>{feitos}/{itens.length}</span>
            </div>
            <div className="bar"><i style={{ width: `${(feitos / itens.length) * 100}%` }} /></div>
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

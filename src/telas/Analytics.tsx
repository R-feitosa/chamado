import { useMemo, useState } from 'react';
import {
  PERIODOS, duracao, inicioDoPeriodo, matriz, porTecnico, resolvidosNoPeriodo, temposMedios, type ChavePeriodo,
} from '../lib/analytics';
import type { Catalogo, Chamado } from '../lib/tipos';

interface Props { catalogo: Catalogo; chamados: Chamado[] }

/** Mapa de calor técnico × área: uma cor (sequencial), número sempre visível, dica no hover. */
function Mapa({ titulo, tecnicos, colunas, m, nome }: {
  titulo: string; tecnicos: { id: string; nome: string }[]; colunas: { chave: string; nome: string }[];
  m: Map<string, Map<string, number>>; nome: Map<string, string>;
}) {
  const max = Math.max(1, ...[...m.values()].flatMap((l) => [...l.values()]));
  const usadas = colunas.filter((col) => tecnicos.some((t) => m.get(t.id)?.get(col.chave)));
  if (!usadas.length) return (
    <div className="secao"><h2>{titulo}</h2><div className="card empty">Nenhum chamado resolvido no período.</div></div>
  );
  const totCol = (k: string) => tecnicos.reduce((s, t) => s + (m.get(t.id)?.get(k) ?? 0), 0);
  return (
    <div className="secao">
      <h2>{titulo}</h2>
      <div className="card mapa" style={{ padding: 12 }}>
        <table>
          <thead>
            <tr><th scope="col">Técnico</th>{usadas.map((c) => <th key={c.chave} scope="col">{c.nome}</th>)}<th scope="col" className="tot">Total</th></tr>
          </thead>
          <tbody>
            {tecnicos.map((t) => {
              const linha = m.get(t.id);
              const total = usadas.reduce((s, c) => s + (linha?.get(c.chave) ?? 0), 0);
              return (
                <tr key={t.id}>
                  <th scope="row">{t.nome}</th>
                  {usadas.map((c) => {
                    const n = linha?.get(c.chave) ?? 0;
                    const pct = Math.round(12 + (n / max) * 48);
                    return (
                      <td key={c.chave} className={n ? '' : 'zero'} title={`${t.nome} · ${nome.get(c.chave) ?? c.nome}: ${n} resolvido${n === 1 ? '' : 's'}`}
                        style={n ? { background: `color-mix(in srgb, var(--accent) ${pct}%, var(--surface))`, color: 'var(--ink)', fontWeight: 600 } : undefined}>
                        {n}
                      </td>
                    );
                  })}
                  <td className="tot">{total}</td>
                </tr>
              );
            })}
            <tr><th scope="row" className="tot">Total</th>{usadas.map((c) => <td key={c.chave} className="tot">{totCol(c.chave)}</td>)}
              <td className="tot">{usadas.reduce((s, c) => s + totCol(c.chave), 0)}</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function Analytics({ catalogo, chamados }: Props) {
  const [periodo, setPeriodo] = useState<ChavePeriodo>('30');
  const agora = Date.now();
  const desde = inicioDoPeriodo(periodo, agora);

  const devs = useMemo(() => catalogo.pessoas.filter((p) => p.papel === 'dev' && p.ativo), [catalogo]);
  const pessoa = useMemo(() => new Map(catalogo.pessoas.map((p) => [p.id, p])), [catalogo]);
  const nomeSistema = useMemo(() => new Map(catalogo.sistemas.map((s) => [String(s.id), s.nome])), [catalogo]);
  const nomeSetor = useMemo(() => new Map(catalogo.setores.map((s) => [String(s.id), s.nome])), [catalogo]);

  const resolvidos = resolvidosNoPeriodo(chamados, desde);
  const linhas = porTecnico(chamados, devs.map((d) => d.id), desde);
  const tempos = temposMedios(chamados, desde);
  const maxRes = Math.max(1, ...linhas.map((l) => l.resolvidos));
  const tecnicos = linhas.map((l) => ({ id: l.id, nome: pessoa.get(l.id)?.nome ?? '—' }));
  const porSistema = matriz(resolvidos, (c) => c.sistema_id);
  const porSetor = matriz(resolvidos, (c) => pessoa.get(c.solicitante_id)?.setor_id ?? 'dev');
  const colSetores = [...catalogo.setores.map((s) => ({ chave: String(s.id), nome: s.nome })), { chave: 'dev', nome: 'Dev/Suporte' }];

  const kpis: [string, string][] = [
    ['Resolvidos', String(resolvidos.length)],
    ['Em aberto agora', String(chamados.filter((c) => c.status !== 'resolvido').length)],
    ['Tempo médio até assumir', duracao(tempos.mediaAssumir)],
    ['Tempo médio até resolver', duracao(tempos.mediaResolver)],
  ];

  return (
    <section>
      <div className="ph">
        <div><div className="sub">Produtividade do time</div><h1>Analytics</h1></div>
        <div className="tabs" role="group" aria-label="Período">
          {PERIODOS.map((p) => (
            <button key={p.chave} type="button" className="tab" aria-pressed={periodo === p.chave} aria-selected={periodo === p.chave} onClick={() => setPeriodo(p.chave)}>{p.nome}</button>
          ))}
        </div>
      </div>

      <div className="kpis">
        {kpis.map(([nome, v]) => <div key={nome} className="card kpi"><span>{nome}</span><b style={{ fontSize: 26 }}>{v}</b></div>)}
      </div>

      <div className="secao">
        <h2>Resolvidos por técnico</h2>
        <div className="card fila">
          <div className="tec head"><span>Técnico</span><span className="bar-col">Resolvidos</span><span className="num">Qtd.</span><span className="num opt">Em andamento</span><span className="num opt">Tempo médio</span></div>
          {linhas.map((l) => {
            const nome = pessoa.get(l.id)?.nome ?? '—';
            return (
              <div className="tec" key={l.id} title={`${nome}: ${l.resolvidos} resolvido(s), ${l.emAndamento} em andamento, tempo médio ${duracao(l.mediaResolver)}`}>
                <span style={{ fontWeight: 500 }}>{nome}</span>
                <span className="bar-col"><span className="trilho" style={{ display: 'block' }}>
                  <i style={{ width: l.resolvidos ? `${(l.resolvidos / maxRes) * 100}%` : 0 }} />
                </span></span>
                <span className="num" style={{ fontWeight: 600 }}>{l.resolvidos}</span>
                <span className="num opt">{l.emAndamento}</span>
                <span className="num opt muted">{duracao(l.mediaResolver)}</span>
              </div>
            );
          })}
        </div>
      </div>

      <Mapa titulo="Por sistema" tecnicos={tecnicos} m={porSistema} nome={nomeSistema}
        colunas={catalogo.sistemas.map((s) => ({ chave: String(s.id), nome: s.nome }))} />
      <Mapa titulo="Por setor de quem abriu" tecnicos={tecnicos} m={porSetor} nome={nomeSetor} colunas={colSetores} />
      <p className="muted" style={{ fontSize: 13, marginTop: 16 }}>
        Considera chamados resolvidos no período, atribuídos ao responsável no momento da resolução. Tempo médio: da abertura à resolução.
      </p>
    </section>
  );
}

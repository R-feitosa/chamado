import { useCallback, useEffect, useRef, useState, type KeyboardEvent } from 'react';
import {
  agruparPorDia, enviarComoSolicitante, enviarComoTime, juntar, lerConversa, marcarConversaLida, marcarVisto, mensagensDoChamado,
  ultimoVisto, type EstadoChat, type MensagemChat,
} from '../lib/chat';
import { mensagemErro } from '../lib/formato';
import { prepararAudio, somLigado, tocarSom } from '../lib/som';
import { supabase } from '../lib/supabase';

const hora = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

/** Caixa de conversa (mesma para os dois lados). `lado` = quem está vendo. */
function Conversa({ lado, mensagens, estado, apagaEm, podeEscrever, aviso, onEnviar, outroNome }: {
  lado: 'solicitante' | 'time'; mensagens: MensagemChat[]; estado: EstadoChat; apagaEm?: string | null; podeEscrever: boolean;
  aviso?: string; onEnviar: (texto: string) => Promise<void>; outroNome?: string;
}) {
  const [texto, setTexto] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState('');
  const lista = useRef<HTMLDivElement>(null);
  useEffect(() => { lista.current?.scrollTo({ top: lista.current.scrollHeight }); }, [mensagens.length]);

  async function enviar() {
    const t = texto.trim();
    if (!t || enviando) return;
    setEnviando(true); setErro('');
    try { await onEnviar(t); setTexto(''); } catch (e) { setErro(mensagemErro(e)); } finally { setEnviando(false); }
  }
  function tecla(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void enviar(); }
  }
  const quem = (m: MensagemChat) => m.autor === lado ? 'Você'
    : m.autor === 'time' ? `${m.nome ?? 'Time'} · time` : (outroNome ?? 'Quem abriu');

  return (
    <div className="chat">
      <div className="chat-lista" ref={lista} aria-live="polite">
        {!mensagens.length && <p className="chat-vazio">{estado === 'aberto' ? 'Nenhuma mensagem ainda.' : 'Sem mensagens.'}</p>}
        {agruparPorDia(mensagens).map((g) => (
          <div key={g.dia}>
            <div className="chat-dia"><span>{g.dia}</span></div>
            {g.mensagens.map((m) => (
              <div key={m.id} className={`msg ${m.autor === lado ? 'minha' : 'outra'}${m.apagada ? ' apagada' : ''}`}>
                <span className="msg-quem">{quem(m)} · {hora(m.criada_em)}</span>
                <div className="msg-balao">{m.apagada ? 'Mensagem apagada (a conversa expira 24 h após resolver).' : m.texto}</div>
              </div>
            ))}
          </div>
        ))}
      </div>
      {estado === 'aberto' ? (podeEscrever ? (
        <div className="chat-envio">
          <textarea className="field" rows={2} maxLength={1000} placeholder="Escreva uma mensagem… (Enter envia, Shift+Enter quebra a linha)"
            value={texto} onChange={(e) => setTexto(e.target.value)} onKeyDown={tecla} aria-label="Mensagem" />
          <div className="chat-envio-pe">
            <small className="muted">Não envie senhas nem dados pessoais. {texto.length > 800 && `${texto.length}/1000`}</small>
            <button type="button" className="btn pri" disabled={enviando || !texto.trim()} onClick={() => void enviar()}>{enviando ? 'Enviando…' : 'Enviar'}</button>
          </div>
          {erro && <p className="erro" role="alert">{erro}</p>}
        </div>
      ) : <p className="chat-aviso">{aviso ?? 'Só o responsável e quem ajuda escrevem nesta conversa.'}</p>)
        : <p className="chat-aviso">{estado === 'fechado'
          ? `Chamado resolvido: a conversa ficou só para leitura e será apagada${apagaEm ? ` em ${new Date(apagaEm).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}` : ' em 24 h'}.`
          : 'A conversa expirou e foi apagada (24 h depois de resolvido).'}</p>}
    </div>
  );
}

/** Quem abriu (sem login): protocolo + código secreto. Atualiza a cada 5 s (30 s com a aba em segundo plano). */
export function ChatSolicitante({ protocolo, codigo }: { protocolo: string; codigo: string }) {
  const [msgs, setMsgs] = useState<MensagemChat[]>([]);
  const [estado, setEstado] = useState<EstadoChat>('aberto');
  const [apagaEm, setApagaEm] = useState<string | null>(null);
  const [falhou, setFalhou] = useState('');
  const ultimo = useRef(0);

  const atualizar = useCallback(async () => {
    try {
      const c = await lerConversa(protocolo, codigo, ultimo.current);
      setEstado(c.estado); setApagaEm(c.apaga_em); setFalhou('');
      if (c.mensagens.length) {
        const visto = ultimoVisto(protocolo);
        const novasDoTime = c.mensagens.filter((m) => m.autor === 'time' && m.id > visto);
        if (ultimo.current > 0 && novasDoTime.length && somLigado()) tocarSom(1);
        ultimo.current = c.mensagens[c.mensagens.length - 1].id;
        marcarVisto(protocolo, ultimo.current);
        setMsgs((a) => juntar(a, c.mensagens));
      }
      if (c.estado === 'apagado') setMsgs((a) => a.map((m) => ({ ...m, texto: null, apagada: true })));
    } catch (e) { setFalhou(mensagemErro(e, 'Não foi possível carregar a conversa.')); }
  }, [protocolo, codigo]);

  useEffect(() => {
    ultimo.current = 0; setMsgs([]); void atualizar();
    let t = 0;
    const agendar = () => { t = window.setTimeout(async () => { await atualizar(); agendar(); }, document.hidden ? 30_000 : 5_000); };
    agendar();
    const liberar = () => prepararAudio();
    window.addEventListener('pointerdown', liberar);
    return () => { window.clearTimeout(t); window.removeEventListener('pointerdown', liberar); };
  }, [atualizar]);

  if (falhou) return <p className="erro" role="alert">{falhou}</p>;
  return (
    <div className="chat-bloco">
      <b>Conversa com o time</b>
      <Conversa lado="solicitante" mensagens={msgs} estado={estado} apagaEm={apagaEm} podeEscrever
        onEnviar={async (t) => { await enviarComoSolicitante(protocolo, codigo, t); await atualizar(); }} />
    </div>
  );
}

/** Time: conversa do chamado em tempo real (RLS + realtime). */
export function ChatTime({ chamadoId, protocolo, resolvido, resolvidoEm, podeEscrever, outroNome, onLido }: {
  chamadoId: string; protocolo: string; resolvido: boolean; resolvidoEm: string | null; podeEscrever: boolean; outroNome?: string; onLido?: () => void;
}) {
  const [msgs, setMsgs] = useState<MensagemChat[]>([]);
  const [erro, setErro] = useState('');
  const carregar = useCallback(async () => {
    try { setMsgs(await mensagensDoChamado(chamadoId)); await marcarConversaLida(chamadoId); onLido?.(); }
    catch (e) { setErro(mensagemErro(e)); }
  }, [chamadoId, onLido]);
  useEffect(() => {
    void carregar();
    const canal = supabase.channel(`chat-${chamadoId}`)
      .on('postgres_changes', { event: '*', schema: 'chamados', table: 'chat_mensagens', filter: `chamado_id=eq.${chamadoId}` }, (p) => {
        if (p.eventType === 'INSERT' && (p.new as { autor?: string }).autor === 'solicitante' && somLigado()) tocarSom(1);
        void carregar();
      })
      .subscribe();
    return () => { void supabase.removeChannel(canal); };
  }, [chamadoId, carregar]);

  const apagaEm = resolvidoEm ? new Date(new Date(resolvidoEm).getTime() + 86_400_000).toISOString() : null;
  const estado: EstadoChat = !resolvido ? 'aberto' : apagaEm && new Date(apagaEm).getTime() < Date.now() ? 'apagado' : 'fechado';
  return (
    <div className="chat-bloco">
      <b>Conversa · <span className="mono">{protocolo}</span></b>
      {erro && <p className="erro" role="alert">{erro}</p>}
      <Conversa lado="time" mensagens={msgs} estado={estado} apagaEm={apagaEm} podeEscrever={podeEscrever} outroNome={outroNome}
        onEnviar={async (t) => { await enviarComoTime(chamadoId, t); await carregar(); }} />
    </div>
  );
}

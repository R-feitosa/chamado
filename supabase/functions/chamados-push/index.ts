// Edge Function chamados-push — entrega os avisos da Central de Chamados via Web Push.
//
// Quem decide QUANDO avisar é o banco (gatilho na abertura + chamados.push_agendar no pg_cron, 1x/min);
// esta função só entrega o que estiver pendente em chamados.push_envios. É chamada pelo pg_net com o
// segredo de despacho do Vault no cabeçalho `x-chamados-push-secret` — por isso verify_jwt=false: a
// autenticação é esse segredo, conferido pelos próprios RPCs (que além disso só aceitam service_role).
// Mesmo desenho da send-punch-reminder (Atlas Ponto). Chamar duas vezes não duplica (FOR UPDATE SKIP LOCKED).
import { generateVapidKeys, isAllowedPushEndpoint, sendWebPush, type VapidKeys } from './webpush.ts'

interface Inscricao { id: string; endpoint: string; p256dh: string; auth: string }
interface Envio { id: number; tipo: string; payload: Record<string, unknown>; expira_em: string; inscricoes: Inscricao[] }
interface Lote { vapid: (VapidKeys & { subject: string }) | null; envios: Envio[] }

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

class RpcError extends Error {
  constructor(public status: number, message: string) { super(message) }
}

// Os RPCs ficam no schema chamados (Content-Profile), como todo o resto da Central.
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
      'Content-Profile': 'chamados',
      'Accept-Profile': 'chamados',
    },
    body: JSON.stringify(args),
  })
  const text = await res.text()
  if (!res.ok) throw new RpcError(res.status, `${fn}: ${res.status} ${text.slice(0, 300)}`)
  return (text ? JSON.parse(text) : null) as T
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
  const segredo = req.headers.get('x-chamados-push-secret')
  if (!segredo) return json({ error: 'unauthorized' }, 401)

  let lote: Lote
  try {
    lote = await rpc<Lote>('push_lote', { p_segredo: segredo })
  } catch (err) {
    if (err instanceof RpcError && (err.status === 401 || err.status === 403)) return json({ error: 'unauthorized' }, 401)
    console.error(String(err))
    return json({ error: 'lote_indisponivel' }, 500)
  }

  // Primeira execução: gera o par VAPID aqui e grava no Vault. A chave privada nunca sai do servidor.
  let vapid = lote.vapid
  if (!vapid) {
    const gerado = await generateVapidKeys()
    vapid = await rpc<VapidKeys & { subject: string }>('push_salvar_vapid', {
      p_segredo: segredo, p_publica: gerado.publicKey, p_privada: gerado.privateKey,
    })
  }

  const resultados: { envio_id: number; concluido: boolean; detalhe: Record<string, unknown> }[] = []
  const ok: string[] = [], expiradas: string[] = [], falhas: string[] = []

  for (const envio of lote.envios) {
    const ttl = Math.max(60, Math.floor((new Date(envio.expira_em).getTime() - Date.now()) / 1000))
    const tentativas = await Promise.all(envio.inscricoes.map(async (insc) => {
      if (!isAllowedPushEndpoint(insc.endpoint)) return { insc, status: 0, erro: 'endpoint_recusado' }
      try {
        const res = await sendWebPush(insc, envio.payload, vapid!, vapid!.subject, {
          ttl,
          // Sempre 'high': com 'normal' o FCM pode segurar e entregar em lote (visto: atraso no Chrome do Windows).
          urgency: 'high',
          topic: typeof envio.payload.tag === 'string' ? envio.payload.tag : undefined,
        })
        const erro = res.ok ? undefined : (await res.text()).slice(0, 200)
        return { insc, status: res.status, erro }
      } catch (err) {
        return { insc, status: 0, erro: String(err).slice(0, 200) }
      }
    }))

    let entregues = 0, reenviar = false
    for (const t of tentativas) {
      if (t.status >= 200 && t.status < 300) { entregues++; ok.push(t.insc.id) }
      else if (t.status === 404 || t.status === 410) expiradas.push(t.insc.id)
      else {
        falhas.push(t.insc.id)
        // 429/5xx/rede: vale tentar de novo (até 3x, enquanto o aviso não expirar).
        if (t.status === 0 || t.status === 429 || t.status >= 500) reenviar = true
      }
    }
    resultados.push({
      envio_id: envio.id,
      concluido: entregues > 0 || !reenviar,
      detalhe: {
        entregues, aparelhos: tentativas.length, status: tentativas.map((t) => t.status),
        erros: tentativas.filter((t) => t.erro).map((t) => `${t.status}: ${t.erro}`),
      },
    })
  }

  if (resultados.length > 0 || expiradas.length > 0) {
    await rpc('push_confirmar', {
      p_segredo: segredo, p_resultados: resultados, p_ok: ok, p_expiradas: expiradas, p_falhas: falhas,
    })
  }
  return json({ envios: resultados.length, entregues: ok.length, expiradas: expiradas.length, falhas: falhas.length, vapid_inicializado: !lote.vapid })
})

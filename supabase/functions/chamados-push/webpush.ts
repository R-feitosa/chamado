// Web Push sem dependências: VAPID (RFC 8292) + criptografia de payload aes128gcm (RFC 8291 /
// RFC 8188), escrito só com WebCrypto. Cópia do módulo da Edge Function send-punch-reminder
// (Atlas Ponto, mesmo projeto Supabase), já validado contra o vetor oficial do RFC 8291.
// Roda igual no Deno (Edge Function) e no Node 22 — nada aqui usa API do Deno.

const encoder = new TextEncoder()

export function b64urlEncode(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function b64urlDecode(value: string): Uint8Array {
  const b64 = value.replace(/-/g, '+').replace(/_/g, '/')
  const bin = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4))
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0))
  let offset = 0
  for (const p of parts) {
    out.set(p, offset)
    offset += p.length
  }
  return out
}

/** JWK de uma chave P-256 a partir do ponto público não comprimido (65 bytes) e, opcionalmente, do escalar privado d. */
function p256Jwk(publicRaw: Uint8Array, d?: string): JsonWebKey {
  if (publicRaw.length !== 65 || publicRaw[0] !== 0x04) throw new Error('Chave pública P-256 inválida')
  const jwk: JsonWebKey = {
    kty: 'EC',
    crv: 'P-256',
    x: b64urlEncode(publicRaw.slice(1, 33)),
    y: b64urlEncode(publicRaw.slice(33, 65)),
    ext: true,
  }
  if (d) jwk.d = d
  return jwk
}

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, bytes: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', ikm as BufferSource, 'HKDF', false, ['deriveBits'])
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: salt as BufferSource, info: info as BufferSource },
    key,
    bytes * 8
  )
  return new Uint8Array(bits)
}

export interface VapidKeys {
  /** Ponto público não comprimido (65 bytes), base64url — o `applicationServerKey` do navegador. */
  publicKey: string
  /** Escalar privado d (32 bytes), base64url. Nunca sai do servidor (fica no Supabase Vault). */
  privateKey: string
}

export async function generateVapidKeys(): Promise<VapidKeys> {
  const pair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
    'sign',
    'verify',
  ])) as CryptoKeyPair
  const publicRaw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))
  const jwk = await crypto.subtle.exportKey('jwk', pair.privateKey)
  return { publicKey: b64urlEncode(publicRaw), privateKey: jwk.d as string }
}

/** Cabeçalho Authorization do VAPID (RFC 8292): JWT ES256 com `aud` = origem do push service. */
export async function vapidAuthorization(
  endpoint: string,
  keys: VapidKeys,
  subject: string,
  nowSeconds = Math.floor(Date.now() / 1000)
): Promise<string> {
  const header = b64urlEncode(encoder.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })))
  const claims = b64urlEncode(
    encoder.encode(JSON.stringify({ aud: new URL(endpoint).origin, exp: nowSeconds + 12 * 3600, sub: subject }))
  )
  const signingInput = `${header}.${claims}`
  const privateKey = await crypto.subtle.importKey(
    'jwk',
    p256Jwk(b64urlDecode(keys.publicKey), keys.privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )
  // WebCrypto devolve a assinatura ECDSA no formato r||s (IEEE P1363) que o JWS exige.
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, privateKey, encoder.encode(signingInput))
  )
  return `vapid t=${signingInput}.${b64urlEncode(signature)}, k=${keys.publicKey}`
}

export interface EncryptOptions {
  /** Só para teste com o vetor do RFC 8291 — em produção, sal e par efêmero são sempre aleatórios. */
  salt?: Uint8Array
  senderKeys?: { publicKey: string; privateKey: string }
}

/** Criptografa o payload para a inscrição (RFC 8291, content-coding aes128gcm, registro único). */
export async function encryptPayload(
  plaintext: Uint8Array,
  p256dh: string,
  authSecret: string,
  options: EncryptOptions = {}
): Promise<Uint8Array> {
  const uaPublic = b64urlDecode(p256dh)
  const auth = b64urlDecode(authSecret)
  if (auth.length !== 16) throw new Error('auth secret da inscrição deve ter 16 bytes')

  let senderPrivate: CryptoKey
  let senderPublicRaw: Uint8Array
  if (options.senderKeys) {
    senderPublicRaw = b64urlDecode(options.senderKeys.publicKey)
    senderPrivate = await crypto.subtle.importKey(
      'jwk',
      p256Jwk(senderPublicRaw, options.senderKeys.privateKey),
      { name: 'ECDH', namedCurve: 'P-256' },
      false,
      ['deriveBits']
    )
  } else {
    const pair = (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, [
      'deriveBits',
    ])) as CryptoKeyPair
    senderPrivate = pair.privateKey
    senderPublicRaw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey))
  }

  const uaKey = await crypto.subtle.importKey('raw', uaPublic as BufferSource, { name: 'ECDH', namedCurve: 'P-256' }, false, [])
  const ecdhSecret = new Uint8Array(
    await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey } as EcdhKeyDeriveParams, senderPrivate, 256)
  )

  const keyInfo = concat(encoder.encode('WebPush: info\0'), uaPublic, senderPublicRaw)
  const ikm = await hkdf(auth, ecdhSecret, keyInfo, 32)

  const salt = options.salt ?? crypto.getRandomValues(new Uint8Array(16))
  const cek = await hkdf(salt, ikm, encoder.encode('Content-Encoding: aes128gcm\0'), 16)
  const nonce = await hkdf(salt, ikm, encoder.encode('Content-Encoding: nonce\0'), 12)

  // 0x02 = delimitador do último (e único) registro, sem padding.
  const record = concat(plaintext, new Uint8Array([0x02]))
  const aesKey = await crypto.subtle.importKey('raw', cek as BufferSource, 'AES-GCM', false, ['encrypt'])
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce as BufferSource }, aesKey, record as BufferSource)
  )

  const recordSize = new Uint8Array(4)
  new DataView(recordSize.buffer).setUint32(0, 4096)
  return concat(salt, recordSize, new Uint8Array([senderPublicRaw.length]), senderPublicRaw, ciphertext)
}

export interface PushSubscriptionKeys {
  endpoint: string
  p256dh: string
  auth: string
}

export interface SendOptions {
  /** Segundos que o push service guarda a mensagem se o aparelho estiver offline. */
  ttl: number
  /** `high` faz o Android acordar do Doze e o APNs entregar com a tela apagada. */
  urgency?: 'very-low' | 'low' | 'normal' | 'high'
  /** Mensagens com o mesmo Topic se substituem na fila do push service (máx. 32 chars base64url). */
  topic?: string
}

// Só os push services reais dos navegadores (anti-SSRF). A mesma regra é CHECK em chamados.push_inscricoes.
const ALLOWED_PUSH_HOSTS = [
  /^fcm\.googleapis\.com$/,
  /^(.+\.)?push\.apple\.com$/,
  /^(.+\.)?push\.services\.mozilla\.com$/,
  /^(.+\.)?notify\.windows\.com$/,
]

export function isAllowedPushEndpoint(endpoint: string): boolean {
  try {
    const url = new URL(endpoint)
    return url.protocol === 'https:' && ALLOWED_PUSH_HOSTS.some((re) => re.test(url.hostname))
  } catch {
    return false
  }
}

export async function sendWebPush(
  subscription: PushSubscriptionKeys,
  payload: unknown,
  keys: VapidKeys,
  subject: string,
  options: SendOptions
): Promise<Response> {
  if (!isAllowedPushEndpoint(subscription.endpoint)) throw new Error('Endpoint de push fora da lista permitida')
  const body = await encryptPayload(
    encoder.encode(JSON.stringify(payload)),
    subscription.p256dh,
    subscription.auth
  )
  const headers: Record<string, string> = {
    Authorization: await vapidAuthorization(subscription.endpoint, keys, subject),
    'Content-Encoding': 'aes128gcm',
    'Content-Type': 'application/octet-stream',
    TTL: String(Math.max(0, Math.floor(options.ttl))),
    Urgency: options.urgency ?? 'high',
  }
  if (options.topic) headers.Topic = options.topic.replace(/[^A-Za-z0-9_-]/g, '').slice(0, 32)
  return fetch(subscription.endpoint, { method: 'POST', headers, body: body as BodyInit })
}

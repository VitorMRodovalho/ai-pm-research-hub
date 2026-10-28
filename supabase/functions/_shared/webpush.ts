// #2806: Web Push sem dependencia externa. Cifra a mensagem (RFC 8291, content coding aes128gcm) e identifica o
// servidor por VAPID (RFC 8292) usando so WebCrypto, que existe igual no Deno da Edge Function e no Node dos testes.
//
// Por que nao `npm:web-push`: ele usa `crypto.createECDH` e outras APIs do Node que a camada de compatibilidade de
// runtimes de borda nao implementa por inteiro (relatos de busca em 28/10/2026, nao medido aqui). WebCrypto e nativo.
// A conferencia byte a byte contra o vetor do apendice A da RFC 8291 esta em tests/edge-functions/webpush.test.mjs.

const enc = new TextEncoder()

export function b64urlEncode(bytes: Uint8Array): string {
  let s = ''
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function b64urlDecode(s: string): Uint8Array {
  const clean = s.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/')
  const bin = atob(clean + '='.repeat((4 - (clean.length % 4)) % 4))
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0))
  let o = 0
  for (const p of parts) {
    out.set(p, o)
    o += p.length
  }
  return out
}

// WebCrypto e fetch pedem BufferSource; uma copia em ArrayBuffer novo nao depende do tipo do buffer de origem.
export function toArrayBuffer(u: Uint8Array): ArrayBuffer {
  const out = new ArrayBuffer(u.byteLength)
  new Uint8Array(out).set(u)
  return out
}
const ab = toArrayBuffer

async function hmac(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey('raw', ab(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, ab(data)))
}

// Chave publica P-256 na forma nao comprimida (65 octetos, 0x04 || x || y) para JWK.
export function rawPublicToJwk(raw: Uint8Array): JsonWebKey {
  if (raw.length !== 65 || raw[0] !== 0x04) throw new Error('chave publica P-256 invalida')
  return { kty: 'EC', crv: 'P-256', x: b64urlEncode(raw.slice(1, 33)), y: b64urlEncode(raw.slice(33, 65)), ext: true }
}

// RFC 8291 secao 3.3 e 3.4, com o HKDF de um bloco escrito como HMAC para que cada valor intermediario possa ser
// comparado com o apendice A: PRK_key, IKM, PRK, CEK e NONCE.
export async function deriveContentKeys(
  ecdhSecret: Uint8Array,
  authSecret: Uint8Array,
  uaPublic: Uint8Array,
  asPublic: Uint8Array,
  salt: Uint8Array,
): Promise<{ prkKey: Uint8Array; ikm: Uint8Array; prk: Uint8Array; cek: Uint8Array; nonce: Uint8Array }> {
  const one = new Uint8Array([1])
  const prkKey = await hmac(authSecret, ecdhSecret)
  const keyInfo = concat(enc.encode('WebPush: info\x00'), uaPublic, asPublic)
  const ikm = await hmac(prkKey, concat(keyInfo, one))
  const prk = await hmac(salt, ikm)
  const cek = (await hmac(prk, concat(enc.encode('Content-Encoding: aes128gcm\x00'), one))).slice(0, 16)
  const nonce = (await hmac(prk, concat(enc.encode('Content-Encoding: nonce\x00'), one))).slice(0, 12)
  return { prkKey, ikm, prk, cek, nonce }
}

// 4096 octetos de cabecalho+corpo e o minimo que o servico de push precisa aceitar; menos 86 de cabecalho, 16 da
// etiqueta do AES-GCM e 1 do delimitador, sobram 3993 de texto (RFC 8291 secao 4).
export const MAX_PLAINTEXT = 3993
const RECORD_SIZE = 4096

export async function encryptPayload(
  plaintext: Uint8Array,
  uaPublic: Uint8Array,
  authSecret: Uint8Array,
  opts: { salt?: Uint8Array; asKeyPair?: CryptoKeyPair } = {},
): Promise<Uint8Array> {
  if (plaintext.length > MAX_PLAINTEXT) throw new Error('mensagem de push acima de 3993 octetos')
  if (authSecret.length !== 16) throw new Error('auth secret da inscricao deve ter 16 octetos')
  const salt = opts.salt ?? crypto.getRandomValues(new Uint8Array(16))
  const asPair = opts.asKeyPair ??
    (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']) as CryptoKeyPair)
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', asPair.publicKey))
  const uaKey = await crypto.subtle.importKey('jwk', rawPublicToJwk(uaPublic), { name: 'ECDH', namedCurve: 'P-256' }, false, [])
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, asPair.privateKey, 256))
  const { cek, nonce } = await deriveContentKeys(ecdh, authSecret, uaPublic, asPublic, salt)
  const key = await crypto.subtle.importKey('raw', ab(cek), { name: 'AES-GCM' }, false, ['encrypt'])
  // um registro so, com o delimitador 0x02 de ultimo registro e sem preenchimento
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: ab(nonce), tagLength: 128 }, key, ab(concat(plaintext, new Uint8Array([2])))),
  )
  const rs = new Uint8Array([(RECORD_SIZE >>> 24) & 255, (RECORD_SIZE >>> 16) & 255, (RECORD_SIZE >>> 8) & 255, RECORD_SIZE & 255])
  return concat(salt, rs, new Uint8Array([asPublic.length]), asPublic, ciphertext)
}

export type VapidKeys = { publicKey: Uint8Array; publicKeyB64: string; privateKey: CryptoKey }

// Chave publica em base64url da forma nao comprimida (o mesmo valor que o navegador recebe em
// applicationServerKey) e chave privada em base64url do escalar d de 32 octetos.
export async function importVapidKeys(publicB64: string, privateB64: string): Promise<VapidKeys> {
  const publicKey = b64urlDecode(publicB64)
  if (b64urlDecode(privateB64).length !== 32) throw new Error('chave privada VAPID deve ter 32 octetos')
  const jwk = { ...rawPublicToJwk(publicKey), d: privateB64.trim() }
  const privateKey = await crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'])
  return { publicKey, publicKeyB64: b64urlEncode(publicKey), privateKey }
}

// A RFC 8292 limita o exp a 24 h; 12 h deixa folga para relogio adiantado do servico de push.
export const VAPID_TOKEN_SECONDS = 12 * 3600

export async function vapidAuthorization(audience: string, subject: string, keys: VapidKeys, nowSec: number): Promise<string> {
  if (!/^(mailto:|https:\/\/)/.test(subject)) throw new Error('VAPID subject deve ser mailto: ou https://')
  const header = b64urlEncode(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })))
  const claims = b64urlEncode(enc.encode(JSON.stringify({ aud: audience, exp: nowSec + VAPID_TOKEN_SECONDS, sub: subject })))
  const input = `${header}.${claims}`
  // ECDSA do WebCrypto devolve r || s em 64 octetos, que e exatamente a assinatura ES256 do JWS
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, keys.privateKey, ab(enc.encode(input))))
  return `vapid t=${input}.${b64urlEncode(sig)}, k=${keys.publicKeyB64}`
}

// A Apple pede para nao renovar o JWT mais de uma vez por hora (documentacao de web push, lida em 28/10/2026).
// O cabecalho fica guardado por origem do servico de push e so e refeito quando falta menos de 1 h para vencer.
export class VapidSigner {
  private cache = new Map<string, { value: string; expSec: number }>()
  private keys: VapidKeys
  private subject: string
  constructor(keys: VapidKeys, subject: string) {
    this.keys = keys
    this.subject = subject
  }

  async authorizationFor(endpoint: string, nowSec: number): Promise<string> {
    const audience = new URL(endpoint).origin
    const hit = this.cache.get(audience)
    if (hit && hit.expSec - nowSec > 3600) return hit.value
    const value = await vapidAuthorization(audience, this.subject, this.keys, nowSec)
    this.cache.set(audience, { value, expSec: nowSec + VAPID_TOKEN_SECONDS })
    return value
  }
}

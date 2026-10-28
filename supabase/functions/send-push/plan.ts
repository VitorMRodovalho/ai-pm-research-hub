// #2806: decisao de QUEM recebe push, separada do I/O para ser testada sem banco nem rede
// (tests/edge-functions/send-push-plan.test.mjs). O index.ts so le, reivindica, chama planSends e envia.

export type PendingNotification = {
  id: string
  recipient_id: string
  type: string
  title: string
  link: string | null
  created_at: string
  is_read: boolean | null
  read_at: string | null
}
export type MemberRow = { id: string; is_active: boolean | null; notify_delivery_mode_pref: string | null }
export type PrefRow = { member_id: string; muted_types: string[] | null }
export type SubscriptionRow = {
  id: string
  member_id: string
  endpoint: string
  p256dh: string
  auth_secret: string
  created_at: string
  disabled_at: string | null
  failure_count: number
}
export type Send = { notification: PendingNotification; subscription: SubscriptionRow }

// Aviso com mais de 1 h nao vai por push: depois de uma parada (segredo ausente, EF fora do ar), a fila acumulada
// sairia de uma vez no celular das pessoas. O e-mail e o sino continuam cobrindo o aviso.
export const STALE_AFTER_MS = 60 * 60 * 1000

// Depois de 5 falhas seguidas que nao sao 404/410, a inscricao para de receber ate o aparelho se inscrever de novo
// (register_push_subscription zera failure_count e disabled_at).
export const MAX_FAILURES = 5

// So envia para servico de push conhecido. O endpoint vem do navegador do membro, e sem esta lista a EF faria POST
// para qualquer URL https que alguem gravasse. A lista mora em platform_settings.push_service_hosts.
export function isAllowedPushHost(endpoint: string, hosts: readonly string[]): boolean {
  let u: URL
  try {
    u = new URL(endpoint)
  } catch {
    return false
  }
  if (u.protocol !== 'https:' || u.port !== '' || u.username !== '' || u.password !== '') return false
  const h = u.hostname.toLowerCase()
  return hosts.some((entry) => {
    const e = entry.trim().toLowerCase().replace(/^\*?\./, '')
    return e !== '' && (h === e || h.endsWith('.' + e))
  })
}

export type Skips = {
  stale: number
  inactive: number
  suppressed: number
  muted: number
  read: number
  noSubscription: number
  hostNotAllowed: number
  subscriptionNewer: number
}

export function planSends(input: {
  notifications: PendingNotification[]
  members: MemberRow[]
  prefs: PrefRow[]
  subscriptions: SubscriptionRow[]
  hosts: readonly string[]
  nowMs: number
}): { sends: Send[]; skips: Skips } {
  const skips: Skips = { stale: 0, inactive: 0, suppressed: 0, muted: 0, read: 0, noSubscription: 0, hostNotAllowed: 0, subscriptionNewer: 0 }
  const memberById = new Map(input.members.map((m) => [m.id, m]))
  const mutedByMember = new Map(input.prefs.map((p) => [p.member_id, p.muted_types ?? []]))
  const subsByMember = new Map<string, SubscriptionRow[]>()
  for (const s of input.subscriptions) {
    if (s.disabled_at !== null) continue
    if (!subsByMember.has(s.member_id)) subsByMember.set(s.member_id, [])
    subsByMember.get(s.member_id)!.push(s)
  }

  const sends: Send[] = []
  for (const n of input.notifications) {
    const createdMs = Date.parse(n.created_at)
    if (!(input.nowMs - createdMs <= STALE_AFTER_MS)) { skips.stale++; continue }
    const member = memberById.get(n.recipient_id)
    if (member?.is_active !== true) { skips.inactive++; continue }
    if (member.notify_delivery_mode_pref === 'suppress_all') { skips.suppressed++; continue }
    if ((mutedByMember.get(n.recipient_id) ?? []).includes(n.type)) { skips.muted++; continue }
    if (n.is_read === true || n.read_at !== null) { skips.read++; continue }
    const subs = subsByMember.get(n.recipient_id) ?? []
    if (subs.length === 0) { skips.noSubscription++; continue }
    for (const s of subs) {
      // aviso anterior a inscricao nunca vai para ela
      if (Date.parse(s.created_at) > createdMs) { skips.subscriptionNewer++; continue }
      if (!isAllowedPushHost(s.endpoint, input.hosts)) { skips.hostNotAllowed++; continue }
      sends.push({ notification: n, subscription: s })
    }
  }
  return { sends, skips }
}

// RFC 8030: 404 e 410 dizem que a inscricao acabou. O resto (400, 403, 413, 429, 5xx, rede) conta como falha.
export function classifyStatus(status: number): 'ok' | 'gone' | 'fail' {
  if (status >= 200 && status < 300) return 'ok'
  if (status === 404 || status === 410) return 'gone'
  return 'fail'
}

// Link so como caminho do proprio site: o service worker abre na origem dele, e um link absoluto para outro
// endereco da plataforma levaria a pessoa a uma sessao diferente (o login e por endereco).
export function safePushPath(link: string | null): string {
  const fallback = '/notifications'
  if (!link) return fallback
  const s = link.trim()
  if (!s.startsWith('/') || s.startsWith('//') || s.includes('\\')) return fallback
  for (const ch of s) {
    const c = ch.charCodeAt(0)
    if (c <= 0x20 || c === 0x7f) return fallback
  }
  return s
}

// Conteudo que aparece na tela bloqueada: so o titulo do aviso e o caminho, nunca o corpo.
export function buildPayload(n: PendingNotification): string {
  const title = Array.from(n.title ?? '').slice(0, 120).join('')
  return JSON.stringify({ title, url: safePushPath(n.link), tag: n.id })
}

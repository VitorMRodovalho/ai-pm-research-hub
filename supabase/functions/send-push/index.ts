/// <reference types="https://esm.sh/@supabase/functions-js@2.116.0/src/edge-runtime.d.ts" />
// #2806: envia por push web os avisos imediatos (notifications.delivery_mode = 'transactional_immediate', ADR-0022)
// para as inscricoes ativas do destinatario. O e-mail e o sino continuam iguais; o push e um canal a mais.
//
// Chamada so pelo pg_cron, com a service_role_key do vault, e so quando ha aviso imediato pendente. Precisa dos
// segredos VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY e VAPID_SUBJECT e da lista platform_settings.push_service_hosts.
// A resposta traz so contagens: nenhum endpoint, id de membro ou titulo sai daqui.
import { createClient } from 'jsr:@supabase/supabase-js@2'
import { bearerFrom, isServiceRoleToken } from '../_shared/service-auth.ts'
import { b64urlDecode, encryptPayload, importVapidKeys, toArrayBuffer, VapidSigner } from '../_shared/webpush.ts'
import { buildPayload, classifyStatus, MAX_FAILURES, type PendingNotification, planSends, type Send, type SubscriptionRow } from './plan.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const IMMEDIATE = 'transactional_immediate'
const PUSH_TTL_SECONDS = 24 * 3600
const CONCURRENCY = 8
const SEND_TIMEOUT_MS = 10_000

// Escopo de modulo: o mesmo isolate reaproveita o cabecalho VAPID entre execucoes (a Apple pede no maximo uma
// renovacao por hora).
let signer: VapidSigner | null = null

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

async function sendOne(s: Send, vapid: VapidSigner): Promise<'ok' | 'gone' | 'fail'> {
  try {
    const body = await encryptPayload(
      new TextEncoder().encode(buildPayload(s.notification)),
      b64urlDecode(s.subscription.p256dh),
      b64urlDecode(s.subscription.auth_secret),
    )
    const res = await fetch(s.subscription.endpoint, {
      method: 'POST',
      headers: {
        Authorization: await vapid.authorizationFor(s.subscription.endpoint, Math.floor(Date.now() / 1000)),
        'Content-Encoding': 'aes128gcm',
        'Content-Type': 'application/octet-stream',
        TTL: String(PUSH_TTL_SECONDS),
        Urgency: 'high',
      },
      body: toArrayBuffer(body),
      // servico de push nao redireciona; seguir um redirecionamento levaria o POST para fora da lista de hosts
      redirect: 'manual',
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    })
    await res.body?.cancel()
    return classifyStatus(res.status)
  } catch {
    return 'fail'
  }
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length)
  let next = 0
  const worker = async () => {
    while (next < items.length) {
      const i = next++
      out[i] = await fn(items[i])
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))
  return out
}

Deno.serve(async (req) => {
  // Primeira instrucao: sem service_role, nada e lido nem reivindicado.
  if (!(await isServiceRoleToken(SUPABASE_URL, bearerFrom(req)))) {
    return json({ error: 'unauthorized', detail: 'service-role only' }, 401)
  }

  const vapidPublic = Deno.env.get('VAPID_PUBLIC_KEY') ?? ''
  const vapidPrivate = Deno.env.get('VAPID_PRIVATE_KEY') ?? ''
  const vapidSubject = Deno.env.get('VAPID_SUBJECT') ?? ''
  // Sem as chaves, a fila fica intacta; quando o segredo existir, o corte de 1 h impede que ela saia acumulada.
  if (!vapidPublic || !vapidPrivate || !vapidSubject) return json({ error: 'vapid_not_configured' }, 500)

  try {
    if (!signer) signer = new VapidSigner(await importVapidKeys(vapidPublic, vapidPrivate), vapidSubject)
    const vapid = signer
    const sb = createClient<any, 'public', any>(SUPABASE_URL, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const { data: hostRow, error: hostErr } = await sb.from('platform_settings').select('value').eq('key', 'push_service_hosts').maybeSingle()
    if (hostErr) throw hostErr
    const hosts: string[] = Array.isArray(hostRow?.value) ? hostRow.value.filter((h: unknown) => typeof h === 'string') : []
    // Sem a lista, nada e reivindicado: enviar sem ela seria fazer POST para qualquer endpoint gravado.
    if (hosts.length === 0) return json({ error: 'push_service_hosts_missing' }, 500)

    // Reivindica antes de enviar. O UPDATE so pega a linha que ainda esta sem marca, entao duas execucoes simultaneas
    // nunca enviam o mesmo aviso. O preco e que um envio que falhe depois daqui nao volta para a fila; o e-mail e o
    // sino continuam cobrindo o aviso.
    const { data: claimed, error: claimErr } = await sb
      .from('notifications')
      .update({ push_dispatched_at: new Date().toISOString() })
      .eq('delivery_mode', IMMEDIATE)
      .is('push_dispatched_at', null)
      .select('id, recipient_id, type, title, link, created_at, is_read, read_at')
    if (claimErr) throw claimErr
    const notifications = (claimed ?? []) as PendingNotification[]
    if (notifications.length === 0) return json({ claimed: 0, sent: 0 })

    const recipients = [...new Set(notifications.map((n) => n.recipient_id))]
    const { data: members, error: memErr } = await sb.from('members').select('id, is_active, notify_delivery_mode_pref').in('id', recipients)
    if (memErr) throw memErr
    const { data: prefs, error: prefErr } = await sb.from('notification_preferences').select('member_id, muted_types').in('member_id', recipients)
    if (prefErr) throw prefErr
    const { data: subs, error: subErr } = await sb
      .from('push_subscriptions')
      .select('id, member_id, endpoint, p256dh, auth_secret, created_at, disabled_at, failure_count')
      .in('member_id', recipients)
      .is('disabled_at', null)
    if (subErr) throw subErr

    const { sends, skips } = planSends({
      notifications,
      members: members ?? [],
      prefs: prefs ?? [],
      subscriptions: (subs ?? []) as SubscriptionRow[],
      hosts,
      nowMs: Date.now(),
    })
    const results = await mapLimit(sends, CONCURRENCY, (s) => sendOne(s, vapid))

    // Por inscricao: 404/410 em qualquer envio apaga; senao, um sucesso zera as falhas; senao, conta mais uma falha.
    const outcome = new Map<string, { sub: SubscriptionRow; r: 'ok' | 'gone' | 'fail' }>()
    results.forEach((r, i) => {
      const sub = sends[i].subscription
      const cur = outcome.get(sub.id)
      if (!cur || r === 'gone' || (r === 'ok' && cur.r === 'fail')) outcome.set(sub.id, { sub, r })
    })
    const nowIso = new Date().toISOString()
    const goneIds = [...outcome.values()].filter((o) => o.r === 'gone').map((o) => o.sub.id)
    const okIds = [...outcome.values()].filter((o) => o.r === 'ok').map((o) => o.sub.id)
    const failed = [...outcome.values()].filter((o) => o.r === 'fail').map((o) => o.sub)
    let bookkeepingErrors = 0

    if (goneIds.length) {
      const { error } = await sb.from('push_subscriptions').delete().in('id', goneIds)
      if (error) bookkeepingErrors++
    }
    if (okIds.length) {
      const { error } = await sb.from('push_subscriptions').update({ last_success_at: nowIso, failure_count: 0 }).in('id', okIds)
      if (error) bookkeepingErrors++
    }
    for (const sub of failed) {
      const count = (sub.failure_count ?? 0) + 1
      const { error } = await sb
        .from('push_subscriptions')
        .update({ failure_count: count, disabled_at: count >= MAX_FAILURES ? nowIso : null })
        .eq('id', sub.id)
      if (error) bookkeepingErrors++
    }

    return json({
      claimed: notifications.length,
      sent: results.filter((r) => r === 'ok').length,
      gone: goneIds.length,
      failed: failed.length,
      bookkeeping_errors: bookkeepingErrors,
      skips,
    })
  } catch (e) {
    // O detalhe fica no log da EF; a resposta leva so o codigo (CodeQL js/stack-trace-exposure).
    const m = e instanceof Error ? e.message : String(e)
    console.error('[send-push] FATAL:', m)
    return json({ error: 'send_push_failed' }, 500)
  }
})

// sync-attendance-points
//
// #2292 — esta EF DEIXOU de implementar a regra do credito de presenca. Ela autentica,
// resolve o escopo, e delega para `public._sync_attendance_points_worker(p_member_id)`,
// que e a regra.
//
// POR QUE. Ate 2026-09-15 existiam DUAS implementacoes: esta EF (que o cron chama, e
// portanto a que de fato roda) e a RPC `sync_attendance_points()` (que declarava a
// regra e nao era chamada por superficie nenhuma). Divergiam em cinco pontos — filtro
// de cancelado, filtro de e.type, criterio de de-duplicacao, origem dos pontos, e
// formato gravado de ref_id — e a assimetria do criterio de de-duplicacao produzia
// credito em dobro POR CONSTRUCAO: a RPC checa os dois formatos e grava o antigo, esta
// EF so conhecia o novo. Medido: 224 pares duplicados, e 100% deles eram exatamente um
// par uma-linha-da-RPC + uma-linha-desta-EF. Nao havia um par de outra forma.
//
// A constante POINTS_PER_ATTENDANCE saiu junto: o valor vem de `gamification_rules`,
// que e o catalogo. Uma constante no codigo e uma segunda fonte, e uma segunda fonte so
// parece inofensiva enquanto os dois numeros coincidem.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { isServiceRoleToken } from '../_shared/service-auth.ts'

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function extractError(err: unknown): string {
  if (err && typeof err === 'object') {
    const e = err as Record<string, unknown>
    if (typeof e.message === 'string' && e.message) return e.message
    if (typeof e.msg === 'string' && e.msg) return e.msg
    if (typeof e.error_description === 'string') return e.error_description
    try { return JSON.stringify(err) } catch { /* fallthrough */ }
  }
  return String(err || 'Unknown error')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace(/^Bearer\s+/i, '')
  if (!token) return jsonResponse({ success: false, error: 'Unauthorized' }, 401)

  // #1223: robust service-role check (PostgREST-verified) — a literal compare
  // against the injected env key rejects the vault-stored key every pg_net cron
  // sends, which diverged after the sb_secret_* key rotation. See _shared/service-auth.ts.
  const isServiceRole = await isServiceRoleToken(supabaseUrl, token)

  const sb = createClient<any, "public", any>(supabaseUrl, serviceRoleKey)

  // null = varrer todo mundo. Um membro nao-admin so sincroniza a si mesmo, e e esse
  // escopo que a EF precisa resolver antes de delegar: o worker nao tem sessao.
  let callerMemberId: string | null = null

  if (!isServiceRole) {
    const { data: { user }, error: userError } = await sb.auth.getUser(token)
    if (userError || !user) return jsonResponse({ success: false, error: `Auth failed: ${userError?.message || 'no user'}` }, 401)

    const { data: member, error: memberError } = await sb
      .from('members')
      .select('id, is_superadmin, operational_role')
      .eq('auth_id', user.id)
      .single()

    if (!member) return jsonResponse({ success: false, error: `Member not found: ${memberError?.message || user.id}` }, 401)

    const isAdmin = member.is_superadmin === true
      || member.operational_role === 'manager'
      || member.operational_role === 'deputy_manager'

    if (!isAdmin) {
      callerMemberId = member.id
    }
  }

  try {
    const { data, error } = await sb.rpc('_sync_attendance_points_worker', { p_member_id: callerMemberId })
    if (error) throw error

    // O worker devolve jsonb; points_created e a chave que gamification.astro le.
    return jsonResponse({
      success: true,
      points_created: data?.points_created ?? 0,
      points_per_attendance: data?.points_per_attendance ?? null,
    })
  } catch (error) {
    return jsonResponse({ success: false, error: extractError(error) }, 500)
  }
})

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const PROJECT_KEYWORDS = [
  'nucleo', 'núcleo', 'ia & gp', 'ia&gp', 'pmi', 'tribo', 'tribe',
  'pesquisa', 'research', 'sprint', 'standup', 'reunião geral',
  'general meeting', 'webinar', 'onboarding', 'kick-off', 'kickoff',
  'artigo', 'article', 'mentoria', 'mentoring',
]

type CalendarEvent = {
  id: string
  summary: string
  description?: string
  start: { dateTime?: string; date?: string }
  end?: { dateTime?: string; date?: string }
  location?: string
  htmlLink?: string
  recurringEventId?: string
  attendees?: { email: string }[]
}

type ImportPayload = {
  events: CalendarEvent[]
  dry_run?: boolean
  default_tribe_id?: number
}

function matchesProject(summary: string, desc?: string): boolean {
  const text = ((summary || '') + ' ' + (desc || '')).toLowerCase()
  return PROJECT_KEYWORDS.some(kw => text.includes(kw))
}

function inferEventType(summary: string): string {
  const s = summary.toLowerCase()
  if (s.includes('webinar')) return 'webinar'
  if (s.includes('geral') || s.includes('general')) return 'general_meeting'
  return 'tribe_meeting'
}

function durationMinutes(start: string, end?: string): number {
  if (!end) return 60
  const ms = new Date(end).getTime() - new Date(start).getTime()
  return Math.max(15, Math.round(ms / 60000))
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const jsonHeaders = { ...corsHeaders, 'Content-Type': 'application/json' }

  try {
    const rawBody = await req.text()

    const authHeader = req.headers.get('Authorization') ?? ''
    if (!authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing Authorization' }),
        { headers: jsonHeaders, status: 401 }
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const token = authHeader.replace(/^Bearer\s+/i, '')

    const uc = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: 'Bearer ' + token } },
    })
    const { data: { user }, error: userErr } = await uc.auth.getUser()
    if (userErr || !user) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid token' }),
        { headers: jsonHeaders, status: 401 }
      )
    }

    const sb = createClient(supabaseUrl, serviceRoleKey)

    const { data: caller } = await sb
      .from('members')
      .select('id, is_superadmin, operational_role')
      .eq('auth_id', user.id)
      .single()

    if (!caller?.is_superadmin) {
      return new Response(
        JSON.stringify({ success: false, error: 'Superadmin access required' }),
        { headers: jsonHeaders, status: 403 }
      )
    }

    let payload: ImportPayload
    try {
      payload = JSON.parse(rawBody)
    } catch {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid JSON body' }),
        { headers: jsonHeaders, status: 400 }
      )
    }

    const { events, dry_run, default_tribe_id } = payload
    if (!events?.length) {
      return new Response(
        JSON.stringify({ success: true, dry_run: true, total: 0, imported: 0, skipped: 0, details: [] }),
        { headers: jsonHeaders }
      )
    }

    let defaultInitiativeId: string | null = null
    if (default_tribe_id) {
      const { data: initRow } = await sb
        .from('initiatives')
        .select('id')
        .eq('legacy_tribe_id', default_tribe_id)
        .limit(1)
        .maybeSingle()
      defaultInitiativeId = (initRow as any)?.id ?? null
    }

    let imported = 0
    let skipped = 0
    const details: any[] = []

    for (const ev of events) {
      if (!matchesProject(ev.summary, ev.description)) {
        skipped++
        continue
      }

      const startDt = ev.start?.dateTime || ev.start?.date
      if (!startDt) { skipped++; continue }

      const endDt = ev.end?.dateTime || ev.end?.date
      const row: any = {
        title: ev.summary,
        date: startDt.split('T')[0],
        type: inferEventType(ev.summary),
        duration_minutes: durationMinutes(startDt, endDt || undefined),
        meeting_link: ev.location || ev.htmlLink || null,
        initiative_id: defaultInitiativeId,
        recurrence_group: ev.recurringEventId || null,
        source: 'google_calendar',
        calendar_event_id: ev.id,
      }

      if (!dry_run) {
        const { error } = await sb.from('events').upsert(
          [row],
          { onConflict: 'calendar_event_id', ignoreDuplicates: true }
        )
        if (error) {
          details.push({ id: ev.id, title: ev.summary, error: error.message })
          skipped++
          continue
        }
      }

      imported++
      details.push({ id: ev.id, title: ev.summary, date: row.date, type: row.type })
    }

    return new Response(
      JSON.stringify({
        success: true,
        dry_run: dry_run ?? false,
        total: events.length,
        imported,
        skipped,
        details: details.slice(0, 50),
      }),
      { headers: jsonHeaders }
    )

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err)
    return new Response(
      JSON.stringify({ success: false, error: 'Internal error', detail: msg }),
      { headers: jsonHeaders, status: 500 }
    )
  }
})

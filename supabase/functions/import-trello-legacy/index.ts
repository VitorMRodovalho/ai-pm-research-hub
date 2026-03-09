import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const STATUS_MAP: Record<string, string> = {
  'to do': 'draft',
  'doing': 'draft',
  'em andamento': 'draft',
  'done': 'published',
  'concluído': 'published',
  'publicado': 'published',
  'review': 'review',
  'revisão': 'review',
}

const CYCLE_MAP: Record<string, number> = {
  'articles_c1': 1,
  'articles_c2': 2,
  'comms_c3': 3,
  'social_media': 3,
}

const TAG_DEFAULTS: Record<string, string[]> = {
  'articles_c1': ['research'],
  'articles_c2': ['research'],
  'comms_c3': ['community', 'comms'],
  'social_media': ['comms'],
}

type TrelloCard = {
  id: string
  name: string
  desc?: string
  url?: string
  closed: boolean
  idList: string
  labels?: { name: string }[]
  idMembers?: string[]
  due?: string | null
  dateLastActivity?: string
}

type TrelloList = {
  id: string
  name: string
}

type TrelloBoard = {
  name: string
  lists: TrelloList[]
  cards: TrelloCard[]
}

type ImportPayload = {
  board: TrelloBoard
  board_source: string
  target_table: 'artifacts' | 'hub_resources'
  dry_run?: boolean
  member_map?: Record<string, string>
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

    const isAdmin = caller?.is_superadmin === true
      || caller?.operational_role === 'manager'
      || caller?.operational_role === 'deputy_manager'

    if (!isAdmin) {
      return new Response(
        JSON.stringify({ success: false, error: 'Admin access required' }),
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

    const { board, board_source, target_table, dry_run, member_map } = payload
    if (!board?.cards || !board_source || !target_table) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing board, board_source, or target_table' }),
        { headers: jsonHeaders, status: 400 }
      )
    }

    const listMap = Object.fromEntries((board.lists || []).map(l => [l.id, l.name.toLowerCase().trim()]))
    const cycle = CYCLE_MAP[board_source] ?? 3
    const defaultTags = TAG_DEFAULTS[board_source] ?? []

    let mapped = 0
    let skipped = 0
    const details: any[] = []

    for (const card of board.cards) {
      if (card.closed) { skipped++; continue }

      const listName = listMap[card.idList] || ''
      const status = STATUS_MAP[listName] || 'draft'
      const tags = [
        ...defaultTags,
        ...(card.labels || []).map(l => l.name.toLowerCase().replace(/\s+/g, '_')).filter(Boolean),
      ]

      let memberId: string | null = null
      if (member_map && card.idMembers?.length) {
        memberId = member_map[card.idMembers[0]] || null
      }

      if (target_table === 'artifacts') {
        const row = {
          title: card.name,
          description: card.desc || null,
          url: card.url || null,
          type: 'article',
          status: status,
          cycle: cycle,
          member_id: memberId,
          trello_card_id: card.id,
          tags: tags,
          source: 'trello_' + board_source,
          submitted_at: card.dateLastActivity || null,
        }

        if (!dry_run) {
          const { error } = await sb.from('artifacts').upsert(
            [row],
            { onConflict: 'trello_card_id', ignoreDuplicates: true }
          )
          if (error) {
            details.push({ card_id: card.id, title: card.name, error: error.message })
            skipped++
            continue
          }
        }
      } else {
        const row = {
          title: card.name,
          description: card.desc || null,
          url: card.url || null,
          asset_type: 'reference' as const,
          is_active: true,
          trello_card_id: card.id,
          tags: tags,
          source: 'trello_' + board_source,
          cycle_code: 'cycle_' + cycle,
        }

        if (!dry_run) {
          const { error } = await sb.from('hub_resources').upsert(
            [row],
            { onConflict: 'trello_card_id', ignoreDuplicates: true }
          )
          if (error) {
            details.push({ card_id: card.id, title: card.name, error: error.message })
            skipped++
            continue
          }
        }
      }

      mapped++
      details.push({ card_id: card.id, title: card.name, status, tags })
    }

    if (!dry_run) {
      const { error: logErr } = await sb.from('trello_import_log').insert([{
        board_name: board.name || board_source,
        board_source: board_source,
        cards_total: board.cards.length,
        cards_mapped: mapped,
        cards_skipped: skipped,
        target_table: target_table,
        notes: 'Import via Edge Function',
      }])
      if (logErr) {
        console.error('Failed to log import:', logErr.message)
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        dry_run: dry_run ?? false,
        total: board.cards.length,
        mapped,
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

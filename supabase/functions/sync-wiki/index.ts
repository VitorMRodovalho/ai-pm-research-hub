// supabase/functions/sync-wiki/index.ts
// Receives GitHub push webhooks from nucleo-ia-gp/wiki repo and syncs
// changed markdown files to the wiki_pages Supabase table (FTS index).
// Deploy: supabase functions deploy sync-wiki --no-verify-jwt

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-hub-signature-256',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (d: Record<string, unknown>, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

// ─── GitHub webhook signature verification ───

async function verifyGitHubSignature(payload: string, signature: string | null, secret: string): Promise<boolean> {
  if (!signature) return false
  const encoder = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  )
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(payload))
  const hex = 'sha256=' + Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('')
  return hex === signature
}

// ─── Markdown frontmatter parser ───

interface WikiMeta {
  title: string
  domain: string
  summary?: string
  tags: string[]
  authors: string[]
  license?: string
  ip_track?: string
}

function parseFrontmatter(content: string): { meta: Partial<WikiMeta>; body: string } {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/)
  if (!match) return { meta: {}, body: content }

  const raw = match[1]
  const body = match[2].trim()
  const meta: Record<string, unknown> = {}

  for (const line of raw.split('\n')) {
    const m = line.match(/^(\w+):\s*(.+)$/)
    if (m) {
      const val = m[2].trim()
      // Handle YAML arrays like [a, b, c]
      if (val.startsWith('[') && val.endsWith(']')) {
        meta[m[1]] = val.slice(1, -1).split(',').map(s => s.trim().replace(/^["']|["']$/g, ''))
      } else if (val === 'null' || val === '~') {
        // YAML null values — skip (don't store the string "null")
      } else {
        meta[m[1]] = val.replace(/^["']|["']$/g, '')
      }
    }
  }

  return { meta: meta as Partial<WikiMeta>, body }
}

// ─── Infer domain from file path ───

function inferDomain(path: string): string {
  const first = path.split('/')[0]
  const domainMap: Record<string, string> = {
    governance: 'governance',
    research: 'research',
    tribes: 'tribes',
    partnerships: 'partnerships',
    platform: 'platform',
    onboarding: 'onboarding',
  }
  return domainMap[first] || 'governance'
}

// ─── Infer title from filename ───

function inferTitle(path: string): string {
  const filename = path.split('/').pop() || path
  return filename
    .replace(/\.md$/, '')
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase())
}

// ─── Main handler ───

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const rawBody = await req.text()
  const secret = Deno.env.get('GITHUB_WEBHOOK_SECRET')

  // Verify signature if secret is configured
  if (secret) {
    const signature = req.headers.get('x-hub-signature-256')
    const valid = await verifyGitHubSignature(rawBody, signature, secret)
    if (!valid) {
      console.error('[sync-wiki] Invalid GitHub webhook signature')
      return json({ error: 'Invalid signature' }, 401)
    }
  }

  const event = req.headers.get('x-github-event')
  if (event === 'ping') return json({ ok: true, message: 'pong' })
  if (event !== 'push') return json({ error: `Unsupported event: ${event}` }, 400)

  let payload: Record<string, unknown>
  try {
    payload = JSON.parse(rawBody)
  } catch {
    return json({ error: 'Invalid JSON' }, 400)
  }

  const ref = payload.ref as string
  if (ref !== 'refs/heads/main') {
    return json({ ok: true, message: 'Ignored non-main branch push' })
  }

  const commits = (payload.commits || []) as Array<{
    added: string[]; modified: string[]; removed: string[]
  }>

  // Collect unique changed .md files
  const toUpsert = new Set<string>()
  const toDelete = new Set<string>()

  for (const commit of commits) {
    for (const f of [...(commit.added || []), ...(commit.modified || [])]) {
      if (f.endsWith('.md')) { toUpsert.add(f); toDelete.delete(f) }
    }
    for (const f of (commit.removed || [])) {
      if (f.endsWith('.md')) { toDelete.add(f); toUpsert.delete(f) }
    }
  }

  if (toUpsert.size === 0 && toDelete.size === 0) {
    return json({ ok: true, message: 'No markdown changes', upserted: 0, deleted: 0 })
  }

  const headSha = (payload.after || payload.head_commit?.id || '') as string
  const repoFullName = ((payload.repository as Record<string, unknown>)?.full_name || 'nucleo-ia-gp/wiki') as string

  // GitHub API token for fetching file contents
  const ghToken = Deno.env.get('GITHUB_TOKEN')
  if (!ghToken) return json({ error: 'GITHUB_TOKEN not configured' }, 500)

  const sb = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )

  let upserted = 0
  let deleted = 0
  const errors: string[] = []

  // ─── Upsert changed files ───
  for (const path of toUpsert) {
    try {
      const res = await fetch(
        `https://api.github.com/repos/${repoFullName}/contents/${encodeURIComponent(path)}?ref=${headSha}`,
        { headers: { Authorization: `Bearer ${ghToken}`, Accept: 'application/vnd.github.raw+json' } }
      )
      if (!res.ok) {
        errors.push(`fetch ${path}: HTTP ${res.status}`)
        continue
      }

      const rawContent = await res.text()
      const { meta, body } = parseFrontmatter(rawContent)

      const row = {
        path,
        title: meta.title || inferTitle(path),
        domain: meta.domain || inferDomain(path),
        content: body,
        summary: meta.summary || null,
        tags: meta.tags || [],
        authors: meta.authors || [],
        license: meta.license || null,
        ip_track: meta.ip_track ? String(meta.ip_track).toUpperCase() : null,
        source_repo: repoFullName,
        source_sha: headSha,
        synced_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }

      const { error } = await sb
        .from('wiki_pages')
        .upsert(row, { onConflict: 'path' })

      if (error) {
        errors.push(`upsert ${path}: ${error.message}`)
      } else {
        upserted++
      }
    } catch (e) {
      errors.push(`upsert ${path}: ${(e as Error).message}`)
    }
  }

  // ─── Delete removed files ───
  for (const path of toDelete) {
    try {
      const { error } = await sb
        .from('wiki_pages')
        .delete()
        .eq('path', path)

      if (error) {
        errors.push(`delete ${path}: ${error.message}`)
      } else {
        deleted++
      }
    } catch (e) {
      errors.push(`delete ${path}: ${(e as Error).message}`)
    }
  }

  console.log(`[sync-wiki] upserted=${upserted} deleted=${deleted} errors=${errors.length}`)
  if (errors.length > 0) console.error(`[sync-wiki] errors:`, errors)

  return json({
    ok: errors.length === 0,
    upserted,
    deleted,
    errors: errors.length > 0 ? errors : undefined,
  })
})

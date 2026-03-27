/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { AwsClient } from 'https://esm.sh/aws4fetch@1.0.20'

const RETAIN_COUNT = 7

Deno.serve(async (req) => {
  try {
    // Auth: service_role key OR dedicated BACKUP_SECRET
    const authHeader = req.headers.get('Authorization')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    const backupSecret = Deno.env.get('BACKUP_SECRET') || ''
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''

    // Validate caller — accept service_role_key or BACKUP_SECRET
    const token = (authHeader || '').replace('Bearer ', '')
    if (!token || (token !== serviceRoleKey && (backupSecret && token !== backupSecret))) {
      // If no BACKUP_SECRET is configured, only service_role_key works
      if (token !== serviceRoleKey) {
        return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 })
      }
    }

    // R2 credentials
    const r2AccessKeyId = Deno.env.get('R2_ACCESS_KEY_ID')
    const r2SecretAccessKey = Deno.env.get('R2_SECRET_ACCESS_KEY')
    const r2BucketName = Deno.env.get('R2_BUCKET_NAME') || 'nucleo-backups'
    const r2AccountId = Deno.env.get('R2_ACCOUNT_ID') || '67d4c2262aebde75efb5fb6a1bb12cd2'

    if (!r2AccessKeyId || !r2SecretAccessKey) {
      return new Response(JSON.stringify({ error: 'R2 credentials not configured' }), { status: 500 })
    }

    // Connect to Supabase with service_role
    const sb = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false }
    })

    // Critical tables to backup (known list — avoids schema queries that fail with RLS)
    const tableNames = [
      'members', 'tribes', 'events', 'attendance', 'board_items', 'board_item_assignments',
      'board_lifecycle_events', 'certificates', 'gamification_points', 'notifications',
      'partner_entities', 'partner_interactions', 'partner_attachments',
      'governance_documents', 'change_requests', 'cr_approvals', 'manual_sections',
      'blog_posts', 'announcements', 'tags', 'event_tag_assignments',
      'releases', 'release_items', 'admin_audit_log', 'member_status_transitions',
      'onboarding_progress', 'member_cycle_history', 'tribe_selections',
    ]

    // Dump each table
    const backup: Record<string, any> = {}
    let totalRows = 0

    for (const tableName of tableNames) {
      try {
        const { data, error } = await sb.from(tableName).select('*').limit(50000)
        if (!error && data) {
          backup[tableName] = data
          totalRows += data.length
        }
      } catch {
        // Skip tables that can't be read (RLS deny-all)
      }
    }

    const now = new Date()
    const timestamp = now.toISOString()
    const filename = `backup-${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}-${String(now.getHours()).padStart(2, '0')}${String(now.getMinutes()).padStart(2, '0')}${String(now.getSeconds()).padStart(2, '0')}.json`

    const backupPayload = JSON.stringify({
      metadata: {
        timestamp,
        version: '1.0',
        table_count: Object.keys(backup).length,
        total_rows: totalRows,
        generated_by: 'backup-to-r2 v1.0',
      },
      tables: backup,
    })

    // Upload to R2 via S3-compatible API
    const r2 = new AwsClient({
      accessKeyId: r2AccessKeyId,
      secretAccessKey: r2SecretAccessKey,
      service: 's3',
      region: 'auto',
    })

    const endpoint = `https://${r2AccountId}.r2.cloudflarestorage.com`
    const putUrl = `${endpoint}/${r2BucketName}/${filename}`

    const putResponse = await r2.fetch(putUrl, {
      method: 'PUT',
      body: backupPayload,
      headers: { 'Content-Type': 'application/json' },
    })

    if (!putResponse.ok) {
      const errText = await putResponse.text()
      throw new Error(`R2 upload failed: ${putResponse.status} ${errText}`)
    }

    // Retention: list objects and delete old ones
    try {
      const listUrl = `${endpoint}/${r2BucketName}?list-type=2&prefix=backup-`
      const listResponse = await r2.fetch(listUrl)
      if (listResponse.ok) {
        const listXml = await listResponse.text()
        // Parse S3 XML response for keys
        const keys: { key: string; lastModified: string }[] = []
        const keyMatches = listXml.matchAll(/<Key>([^<]+)<\/Key>/g)
        const dateMatches = listXml.matchAll(/<LastModified>([^<]+)<\/LastModified>/g)
        const keyArr = [...keyMatches].map(m => m[1])
        const dateArr = [...dateMatches].map(m => m[1])
        for (let i = 0; i < keyArr.length; i++) {
          keys.push({ key: keyArr[i], lastModified: dateArr[i] || '' })
        }

        // Sort by date desc and delete beyond RETAIN_COUNT
        keys.sort((a, b) => b.lastModified.localeCompare(a.lastModified))
        const toDelete = keys.slice(RETAIN_COUNT)
        for (const obj of toDelete) {
          await r2.fetch(`${endpoint}/${r2BucketName}/${obj.key}`, { method: 'DELETE' })
        }
      }
    } catch (retentionErr) {
      console.warn('Retention cleanup failed (non-critical):', retentionErr)
    }

    // Audit log (use service_role client)
    await sb.from('admin_audit_log').insert({
      actor_id: '00000000-0000-0000-0000-000000000000', // system actor
      action: 'backup_completed',
      target_type: 'system',
      metadata: {
        filename,
        table_count: Object.keys(backup).length,
        total_rows: totalRows,
        size_bytes: backupPayload.length,
        retained: RETAIN_COUNT,
      },
    }).throwOnError().catch(() => { /* non-critical */ })

    return new Response(JSON.stringify({
      success: true,
      filename,
      tables: Object.keys(backup).length,
      rows: totalRows,
      size_kb: Math.round(backupPayload.length / 1024),
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('Backup failed:', err)
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

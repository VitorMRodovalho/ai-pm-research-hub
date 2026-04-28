/**
 * Drive Phase 4 — auto-discovery atas via cron.
 *
 * Iterates initiative_drive_links with link_purpose='minutes' (active only),
 * calls drive-list-folder-files EF for each, invokes record_drive_discovery RPC
 * per file. RPC handles idempotency (UNIQUE drive_file_id) + auto-match
 * (filename date heuristic) + auto-promote (event.minutes_url IS NULL → fill).
 *
 * Called daily by pg_cron at 03:00 UTC. Returns summary for cron logs +
 * health observability via get_drive_discovery_health RPC.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface DriveFile {
  drive_file_id: string;
  filename: string;
  mime_type?: string;
  size_bytes?: number | null;
  drive_file_url?: string;
  modified_at?: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405 });
  }
  const startedAt = Date.now();
  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Pull active minutes folders
  const { data: links, error: linksErr } = await sb
    .from("initiative_drive_links")
    .select("id, initiative_id, drive_folder_id, drive_folder_name")
    .eq("link_purpose", "minutes")
    .is("unlinked_at", null);

  if (linksErr) {
    return new Response(JSON.stringify({ error: "links_query_error", detail: linksErr.message }), { status: 500 });
  }

  const summary = {
    folders_scanned: 0,
    files_seen: 0,
    new_discoveries: 0,
    auto_matched: 0,
    auto_promoted: 0,
    errors: [] as Array<{ link_id?: string; folder_id?: string; error: string }>,
    duration_ms: 0,
  };

  for (const link of links ?? []) {
    summary.folders_scanned++;

    let listJson: any;
    try {
      const listRes = await fetch(`${SUPABASE_URL}/functions/v1/drive-list-folder-files`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
        body: JSON.stringify({ folder_id: link.drive_folder_id }),
      });
      listJson = await listRes.json();
      if (!listRes.ok || !listJson.success) {
        summary.errors.push({
          link_id: link.id,
          folder_id: link.drive_folder_id,
          error: listJson.error || `list status ${listRes.status}`,
        });
        continue;
      }
    } catch (e) {
      summary.errors.push({
        link_id: link.id,
        folder_id: link.drive_folder_id,
        error: `list_fetch_error: ${String(e)}`,
      });
      continue;
    }

    const files: DriveFile[] = listJson.files ?? [];
    for (const f of files) {
      summary.files_seen++;
      const { data: rec, error: recErr } = await sb.rpc("record_drive_discovery", {
        p_initiative_drive_link_id: link.id,
        p_drive_file_id: f.drive_file_id,
        p_drive_file_url: f.drive_file_url ?? "",
        p_filename: f.filename,
        p_mime_type: f.mime_type ?? null,
        p_size_bytes: f.size_bytes ?? null,
        p_drive_modified_at: f.modified_at ?? null,
      });
      if (recErr) {
        summary.errors.push({ link_id: link.id, error: `record_rpc: ${recErr.message}` });
        continue;
      }
      if (rec?.is_new) {
        summary.new_discoveries++;
        if (rec.matched_event_id) summary.auto_matched++;
        if (rec.auto_promoted) summary.auto_promoted++;
      }
    }
  }

  summary.duration_ms = Date.now() - startedAt;

  // Health observability via cron.job_run_details + counters in
  // get_drive_discovery_health RPC. No EF-side snapshot needed.

  return new Response(JSON.stringify({ success: true, ...summary }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

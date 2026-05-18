/**
 * pmi-vep-sync — resume binary mirror to Supabase Storage (p195 Opção B+).
 *
 * BACKGROUND:
 *   PMI VEP exposes resume PDFs via Azure SAS-signed URLs that expire ~24h.
 *   Prior to p195, the UI linked directly to those Azure URLs → CV access
 *   broke daily during evaluation cycles. PM had to re-import the JSON every
 *   morning to refresh SAS tokens.
 *
 * STRATEGY (PM-approved):
 *   Worker downloads the PDF binary using the SAS link that was generated
 *   for the human recruiter (NO automation beyond the manual JSON import the
 *   PM already does). PDF is uploaded to private Supabase Storage bucket
 *   `selection-resumes`. Frontend creates 7-day signed URLs from that bucket
 *   instead of pointing at Azure directly.
 *
 *   Re-imports re-trigger the download → keeps storage mirror fresh whenever
 *   the candidate's CV changes in VEP.
 *
 * AUTH / TOS POSTURE:
 *   - The SAS URL was issued by PMI Azure for the PM's authenticated session.
 *     Worker downloads with that exact URL → semantically identical to a
 *     human click. No script bypasses PMI authentication or scrapes the UI.
 *   - If PMI later flags binary mirroring as out-of-scope, we revert to
 *     fallback (resumeUrl Azure link in UI) with zero schema change.
 *
 * LGPD POSTURE:
 *   - Bucket is private + RLS-gated on view_pii capability (chair + assigned
 *     evaluators) — see migration 20260705000000 policy.
 *   - Art. 18 erasure path extended in same migration so binary deletion
 *     happens alongside member anonymization.
 *   - 5y anonymize cron also cleans terminal application binaries.
 */

const BUCKET = 'selection-resumes';

export interface ResumeSyncResult {
  storage_path: string | null;
  synced_at: string | null;
  error?: string;
}

/**
 * Fetch PDF from VEP Azure SAS URL + upload to Supabase Storage.
 * Returns { storage_path, synced_at } on success; { storage_path: null, error } on failure.
 *
 * Idempotent: re-imports overwrite the existing object (upsert=true) so a candidate
 * who updates their CV in VEP gets the new binary mirrored on next PM re-import.
 *
 * Path convention: `cycle-{cycle_code}/{applicant_id}.pdf`
 *   - Organizes by evaluation cycle (matches PM mental model + facilitates cleanup
 *     when a cycle is fully concluded + 5y anonymize)
 *   - applicant_id from PMI is stable across cycles → same person's CV in different
 *     cycles lives at different paths (one per cycle they applied to)
 */
export async function syncResumeToStorage(
  supabaseUrl: string,
  serviceRoleKey: string,
  args: {
    resumeUrl: string | null | undefined;
    applicantId: string | number | null | undefined;
    cycleCode: string;
  }
): Promise<ResumeSyncResult> {
  const { resumeUrl, applicantId, cycleCode } = args;
  if (!resumeUrl || !applicantId) {
    return { storage_path: null, synced_at: null, error: 'no_resume_url_or_applicant_id' };
  }

  let pdfBuffer: ArrayBuffer;
  try {
    const azureResp = await fetch(resumeUrl);
    if (!azureResp.ok) {
      return {
        storage_path: null,
        synced_at: null,
        error: `azure_fetch_${azureResp.status}`,
      };
    }
    pdfBuffer = await azureResp.arrayBuffer();
  } catch (e: any) {
    return {
      storage_path: null,
      synced_at: null,
      error: `azure_fetch_exception:${e?.message ?? 'unknown'}`,
    };
  }

  // Empty/invalid file guard
  if (pdfBuffer.byteLength === 0) {
    return { storage_path: null, synced_at: null, error: 'azure_empty_pdf' };
  }

  const path = `cycle-${cycleCode}/${applicantId}.pdf`;

  try {
    // Supabase Storage REST API (service-role bypasses RLS)
    // POST /storage/v1/object/{bucket}/{path}?x-upsert=true
    const uploadResp = await fetch(
      `${supabaseUrl}/storage/v1/object/${BUCKET}/${encodeURIComponent(path)}`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          'Content-Type': 'application/pdf',
          'x-upsert': 'true',
          'Cache-Control': 'private, max-age=0',
        },
        body: pdfBuffer,
      }
    );
    if (!uploadResp.ok) {
      const text = await uploadResp.text();
      return {
        storage_path: null,
        synced_at: null,
        error: `storage_upload_${uploadResp.status}:${text.slice(0, 100)}`,
      };
    }
    return { storage_path: path, synced_at: new Date().toISOString() };
  } catch (e: any) {
    return {
      storage_path: null,
      synced_at: null,
      error: `storage_upload_exception:${e?.message ?? 'unknown'}`,
    };
  }
}

/**
 * Parallelism wrapper — process N apps in concurrent batches.
 * Default chunkSize=5 keeps Worker CPU pressure low and respects polite-throughput
 * vs PMI Azure (no published rate limit but conservative default).
 */
export async function syncResumesParallel<T extends { resumeUrl?: string | null; applicantId?: string | number | null }>(
  supabaseUrl: string,
  serviceRoleKey: string,
  apps: T[],
  cycleCode: string,
  chunkSize: number = 5
): Promise<Map<T, ResumeSyncResult>> {
  const results = new Map<T, ResumeSyncResult>();
  for (let i = 0; i < apps.length; i += chunkSize) {
    const chunk = apps.slice(i, i + chunkSize);
    const settled = await Promise.all(
      chunk.map(async (app) => {
        const res = await syncResumeToStorage(supabaseUrl, serviceRoleKey, {
          resumeUrl: app.resumeUrl,
          applicantId: app.applicantId,
          cycleCode,
        });
        return [app, res] as [T, ResumeSyncResult];
      })
    );
    for (const [app, res] of settled) results.set(app, res);
  }
  return results;
}

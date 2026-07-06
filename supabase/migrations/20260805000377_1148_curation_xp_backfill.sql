-- #1148 (Fio 2 da umbrella #1150) — backfill histórico de XP de curadoria
--
-- WHAT: The four curation XP triggers (curation_doc_locked / _doc_published / _comment_resolved /
--   _ratification) fire correctly GOING FORWARD, but were attached AFTER the source data already
--   existed and no retroactive backfill ever ran. Audit (2026-07-06, execute_sql read-only):
--     rule                       events  recipient-NULL  XP-now  pre-trigger gap
--     curation_doc_locked          41          1            1        38
--     curation_doc_published       21          1            1        19
--     curation_comment_resolved    29          0           12        17
--     curation_ratification        78          0           32        39  (curator 30 + leader_awareness 9)
--   → 113 unpaid eligible events across 5 members / 2010 XP. See handoff
--   handoff_2026_07_06_gamif_attribution_audit + #1150 umbrella + #1087 (SSOT/atribuição/extrato).
--
--   This is a BACKFILL-ONLY migration: no new trigger, no trigger retired — forward is already correct
--   (post-trigger probe = 0 organic misses). It is one idempotent pass that replays each source row
--   through the SAME XP core the trigger uses (_grant_auto_xp), so the historical backlog earns exactly
--   what the live trigger would have granted.
--
--   SCOPE = events whose timestamp predates the rule's effective_from (read from gamification_rules,
--   no hardcoded date). Rationale:
--     • _grant_auto_xp itself refuses to pay when effective_from > now(); a pre-effective event was
--       UN-payable at the time = the definition of backfillable backlog.
--     • This naturally EXCLUDES the 2026-05-25 02:11:33.748952 batch seed (1 doc-lock + 7
--       member_ratification signoffs, single signer, single instant = session_replication_role=replica
--       bulk insert, NOT organic UI acts). Vitor's decision (2026-07-06): exclude the seed — paying
--       175 XP to one member for a technical batch would be an unearned windfall. Those 8 rows are
--       allowlisted in the contract test so they never read as "new backlog".
--     • Any gap AFTER effective_from is, by construction, not backfill — it is a forward regression or a
--       seed, and the contract test flags it for investigation instead of this pass absorbing it silently.
--
--   On-time: N/A. None of the curation triggers pass p_on_time → curation is always base-only
--   (gamification_rules.on_time_bonus_points is NULL for all four). No deadline reconstruction (unlike
--   Fio 1 #1147). recipient = the trigger's recipient column; ref_id = the source table's PK; granted_by
--   resolves to NULL (system) inside a DO-block, matching a backfill.
--
-- WHY: extrato/leaderboard understate whoever produced curation (locked/published docs, resolved
--   comments, ratifications) before each trigger went live. Early-cycle curators are the most penalized.
--
-- ROLLBACK: the backfilled gamification_points rows can be removed by (category, ref_id) with reason
--   LIKE '%(backfill #1148)%'. The idempotency guard in _grant_auto_xp ((ref_id, category, member_id))
--   makes a re-apply a no-op.
--
-- NOTE: reuses _grant_auto_xp unchanged. No change to the XP core; points stay config in
--   gamification_rules (SSOT). Idempotent → safe to re-run.

DO $backfill$
DECLARE
  r record;
BEGIN
  -- ── 1. curation_doc_locked ── recipient=locked_by, ref=document_versions.id ──
  FOR r IN
    SELECT dv.id AS ref_id, dv.locked_by AS member_id,
           coalesce(dv.version_label, dv.version_number::text, '?') AS lbl
    FROM public.document_versions dv
    JOIN public.gamification_rules gr
      ON gr.slug = 'curation_doc_locked'
    WHERE dv.locked_at IS NOT NULL
      AND dv.locked_by IS NOT NULL
      AND dv.locked_at < gr.effective_from   -- pre-rule = backfillable; excludes 2026-05-25 seed
  LOOP
    PERFORM public._grant_auto_xp(
      'curation_doc_locked', r.member_id, r.ref_id,
      'Versão de doc travada (backfill #1148) — v' || r.lbl,
      NULL   -- on-time N/A for curation
    );
  END LOOP;

  -- ── 2. curation_doc_published ── recipient=published_by, ref=document_versions.id ──
  FOR r IN
    SELECT dv.id AS ref_id, dv.published_by AS member_id,
           coalesce(dv.version_label, dv.version_number::text, '?') AS lbl
    FROM public.document_versions dv
    JOIN public.gamification_rules gr
      ON gr.slug = 'curation_doc_published'
    WHERE dv.published_at IS NOT NULL
      AND dv.published_by IS NOT NULL
      AND dv.published_at < gr.effective_from
  LOOP
    PERFORM public._grant_auto_xp(
      'curation_doc_published', r.member_id, r.ref_id,
      'Versão canônica publicada (backfill #1148) — v' || r.lbl,
      NULL
    );
  END LOOP;

  -- ── 3. curation_comment_resolved ── recipient=resolved_by, ref=document_comments.id ──
  FOR r IN
    SELECT dc.id AS ref_id, dc.resolved_by AS member_id
    FROM public.document_comments dc
    JOIN public.gamification_rules gr
      ON gr.slug = 'curation_comment_resolved'
    WHERE dc.resolved_at IS NOT NULL
      AND dc.resolved_by IS NOT NULL
      AND dc.resolved_at < gr.effective_from
  LOOP
    PERFORM public._grant_auto_xp(
      'curation_comment_resolved', r.member_id, r.ref_id,
      'Comentário resolvido em doc (backfill #1148)',
      NULL
    );
  END LOOP;

  -- ── 4. curation_ratification ── recipient=signer_id, ref=approval_signoffs.id, any gate_kind ──
  FOR r IN
    SELECT s.id AS ref_id, s.signer_id AS member_id, coalesce(s.gate_kind, '?') AS gate
    FROM public.approval_signoffs s
    JOIN public.gamification_rules gr
      ON gr.slug = 'curation_ratification'
    WHERE s.signer_id IS NOT NULL
      AND s.created_at < gr.effective_from   -- excludes the 2026-05-25 member_ratification batch seed
  LOOP
    PERFORM public._grant_auto_xp(
      'curation_ratification', r.member_id, r.ref_id,
      'Ratificação assinada (backfill #1148) — gate ' || r.gate,
      NULL
    );
  END LOOP;
END
$backfill$;

-- ── 5. Pin the backfilled rows inside the C3 window ──
-- _grant_auto_xp inserts with created_at = now(). This migration ships after the C3→C4 boundary
-- (cycles: C3 ended 2026-07-08, C4 is_current since 2026-07-09), and cycle leaderboards bucket
-- gamification_points by created_at — so without this pin the historical backlog would leak into
-- the freshly-zeroed C4 leaderboard. Same instant as the #1147 backfill (verified live to land in
-- C3, 0 rows in C4). Idempotent: no-op once pinned.
UPDATE public.gamification_points
SET created_at = TIMESTAMPTZ '2026-07-08 12:00:00+00'
WHERE reason LIKE '%(backfill #1148)%'
  AND created_at IS DISTINCT FROM TIMESTAMPTZ '2026-07-08 12:00:00+00';

NOTIFY pgrst, 'reload schema';

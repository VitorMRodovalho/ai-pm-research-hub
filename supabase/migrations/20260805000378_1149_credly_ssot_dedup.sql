-- #1149 (Fio 3 da umbrella #1150) — Credly governed by the SSOT: CPMAI family dedup + stale
-- display-cache reconciliation.
--
-- GROUNDING (2026-07-08, execute_sql read-only — re-grounded from the 2026-07-06 audit):
--   • gamification_points (the REAL XP surface) matches gamification_rules 100% on points for all
--     10 Credly categories. The one XP defect is P1: the CPMAI credential family (v7 / +E / PLUS /
--     PMI-CPMAI) pays one row PER BADGE NAME — Henrique Diniz holds 4 family badges = 4 × 45 XP for
--     ONE certification (Marcos/Pedro hold 1 each, correct).
--   • members.credly_badges (display-only jsonb cache, rewritten on each sync) is stale for members
--     not re-synced since the classifier last changed: 2 × legacy category 'master_cert'@50 (not a
--     rule slug) + 9 × knowledge_ai_pm@15 (rule says 20). Display only — nothing sums these points;
--     no XP impact.
--
-- POLICY (Vitor, 2026-07-06, verified against pmi.org: v7≡PMI-CPMAI rebrand 2025-09-30, +E =
-- optional add-on exam, PLUS co-issued with v7): ONE cert_cpmai XP credit per member. Canonical =
-- the PMI-CPMAI-branded badge (current official credential), else the most recently issued.
-- Effect: Henrique 4→1 rows (keeps "PMI Certified Professional in Managing AI (PMI-CPMAI)™", −135 XP).
--
-- Forward fix ships in the same PR: _shared/classify-badge.ts (CATEGORY_POINTS single pricing table
-- + selectCanonicalCpmai) and the collapse in sync-credly-all + verify-credly, so a future re-sync
-- cannot re-duplicate. Contract test: tests/contracts/1149-credly-ssot.test.mjs.
--
-- ROLLBACK: deleted rows are reconstructible from members.credly_badges (family badge names are all
-- listed there; re-inserting `Credly: <name>` rows at 45 pts restores the old state). The jsonb
-- rewrite only touches 'category'/'points' of elements whose (normalized) category is an active
-- rule slug; original values are recoverable from a re-sync against Credly.
--
-- Idempotent: pass 1 leaves 1 row per member (rn>1 empty on re-run); pass 2 only fires when the
-- rewritten jsonb differs.

-- ── 1. P1 backfill: collapse the CPMAI family in gamification_points ──
-- Keep, per member, the single Credly-sourced cert_cpmai row: PMI-CPMAI brand first, else most
-- recent created_at (Credly rows carry issued_at as created_at), id as deterministic tiebreak.
WITH fam AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY member_id
           ORDER BY (reason ILIKE '%pmi-cpmai%'
                     OR reason ILIKE '%pmi certified professional in managing ai%') DESC,
                    created_at DESC,
                    id
         ) AS rn
  FROM public.gamification_points
  WHERE category = 'cert_cpmai'
    AND reason LIKE 'Credly: %'
)
DELETE FROM public.gamification_points gp
USING fam
WHERE gp.id = fam.id
  AND fam.rn > 1;

-- ── 2. P2 backfill: reconcile the stale display cache against the SSOT ──
-- Remap the legacy 'master_cert' category to its rule slug (cert_cpmai) and re-price every element
-- whose category is an active rule slug from gamification_rules.base_points. Elements with no
-- matching rule are left untouched (nothing to price them against). Order preserved via ordinality.
UPDATE public.members m
SET credly_badges = sub.new_badges
FROM (
  SELECT m2.id,
         jsonb_agg(
           CASE WHEN pr.base_points IS NOT NULL
                THEN b.el || jsonb_build_object('category', norm.cat, 'points', pr.base_points)
                ELSE b.el
           END
           ORDER BY b.ord
         ) AS new_badges
  FROM public.members m2
  CROSS JOIN LATERAL jsonb_array_elements(m2.credly_badges) WITH ORDINALITY AS b(el, ord)
  CROSS JOIN LATERAL (
    SELECT CASE WHEN b.el->>'category' = 'master_cert' THEN 'cert_cpmai'
                ELSE b.el->>'category' END AS cat
  ) norm
  LEFT JOIN LATERAL (
    SELECT gr.base_points
    FROM public.gamification_rules gr
    WHERE gr.slug = norm.cat
      AND gr.active = true
      AND gr.effective_from <= now()
    ORDER BY gr.effective_from DESC
    LIMIT 1
  ) pr ON true
  WHERE m2.credly_badges IS NOT NULL
    AND jsonb_typeof(m2.credly_badges) = 'array'
  GROUP BY m2.id
) sub
WHERE m.id = sub.id
  AND m.credly_badges IS DISTINCT FROM sub.new_badges;

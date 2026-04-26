-- DROP confirmed-dead analytics chain (p59 cleanup)
-- 8 fns total — all triple-verified zero callers (frontend + EF + SECDEF + cron)
--
-- Origin: 3 fns flagged "0 callers, preserved pending PM review" in
-- Q-D batch 3b (2026-04-26 p59). Triple-check post-cleanup confirmed:
-- - 0 .rpc() calls in src/ + supabase/functions/
-- - 0 SECDEF DB callers
-- - 0 pg_cron jobs
--
-- Dropping the 3 + their orphaned helper chain (5 helpers):
--   exec_analytics_v2_quality (orchestrator) calls
--     → exec_chapter_roi, exec_funnel_summary, exec_impact_hours_v2
--     → analytics_member_scope (called by all 4)
--   broadcast_count_today_v4 calls
--     → broadcast_count_today (V3 legacy)
--
-- After DROP: schema invariants hold; no app references break;
-- migration coverage test is happy (orphans removed).

DROP FUNCTION IF EXISTS public.broadcast_count_today_v4(uuid);
DROP FUNCTION IF EXISTS public.broadcast_count_today(integer);

DROP FUNCTION IF EXISTS public.exec_analytics_v2_quality(text, integer, text);
DROP FUNCTION IF EXISTS public.exec_certification_delta(text, integer, text);
DROP FUNCTION IF EXISTS public.exec_chapter_roi(text, integer, text);
DROP FUNCTION IF EXISTS public.exec_funnel_summary(text, integer, text);
DROP FUNCTION IF EXISTS public.exec_impact_hours_v2(text, integer, text);
DROP FUNCTION IF EXISTS public.analytics_member_scope(text, integer, text);

NOTIFY pgrst, 'reload schema';

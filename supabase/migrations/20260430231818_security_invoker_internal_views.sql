-- Security advisor auto-remediation captured locally (applied via dashboard).
-- Forces invoker semantics on internal observability views so RLS evaluates
-- against the calling user, not the (super) view owner.
ALTER VIEW public.v_ai_human_concordance SET (security_invoker = on);
ALTER VIEW public.v_cron_last_success SET (security_invoker = on);

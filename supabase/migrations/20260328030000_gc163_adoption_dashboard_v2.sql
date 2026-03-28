-- GC-163: Enhanced adoption dashboard — auth providers, MCP usage, designation counts
-- Applied via Supabase MCP on 2026-03-28. See SPEC_SPRINT2_ADOPTION_GC163.md

BEGIN;

CREATE OR REPLACE FUNCTION get_auth_provider_stats()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  SELECT jsonb_build_object(
    'providers', (SELECT COALESCE(jsonb_agg(jsonb_build_object('provider', COALESCE(au.raw_app_meta_data->>'provider','unknown'), 'total', count(*), 'last_used', max(au.last_sign_in_at)::date) ORDER BY count(*) DESC), '[]'::jsonb) FROM auth.users au GROUP BY COALESCE(au.raw_app_meta_data->>'provider','unknown')),
    'total_auth_users', (SELECT count(*) FROM auth.users),
    'ghost_count', (SELECT count(*) FROM auth.users au WHERE au.id NOT IN (SELECT auth_id FROM members WHERE auth_id IS NOT NULL UNION ALL SELECT unnest(secondary_auth_ids) FROM members WHERE secondary_auth_ids != '{}')),
    'ghost_visitors', (SELECT COALESCE(jsonb_agg(jsonb_build_object('email', au.email, 'provider', COALESCE(au.raw_app_meta_data->>'provider','unknown'), 'name', au.raw_user_meta_data->>'full_name') ORDER BY au.created_at DESC), '[]'::jsonb) FROM auth.users au WHERE au.id NOT IN (SELECT auth_id FROM members WHERE auth_id IS NOT NULL UNION ALL SELECT unnest(secondary_auth_ids) FROM members WHERE secondary_auth_ids != '{}')),
    'members_with_secondary_auth', (SELECT count(*) FROM members WHERE array_length(secondary_auth_ids, 1) > 0)
  );
$$;
GRANT EXECUTE ON FUNCTION get_auth_provider_stats() TO authenticated;

-- get_adoption_dashboard v2: adds mcp_usage, auth_providers, designation_counts + designations in member listing
-- Full function replacement applied via MCP (DROP + CREATE pattern)

NOTIFY pgrst, 'reload schema';
COMMIT;

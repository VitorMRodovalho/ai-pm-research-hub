-- Fix: auth provider stats now counts actual login sessions per provider route
-- Before: counted raw_app_meta_data->>'provider' (primary only), missing secondary providers
-- After: correlates auth.sessions with auth.identities.updated_at to determine
--        which provider was actually used for each login session
-- Percentages based on total login sessions (sum = 100%)

CREATE OR REPLACE FUNCTION get_auth_provider_stats()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = 'public', 'pg_temp' AS $$
  WITH session_provider AS (
    SELECT
      s.id as session_id,
      s.user_id,
      (
        SELECT i.provider
        FROM auth.identities i
        WHERE i.user_id = s.user_id
        ORDER BY ABS(EXTRACT(EPOCH FROM (i.updated_at - s.created_at)))
        LIMIT 1
      ) as login_provider
    FROM auth.sessions s
  ),
  provider_counts AS (
    SELECT login_provider as provider, count(*)::integer as total
    FROM session_provider
    GROUP BY login_provider
  ),
  total_logins AS (
    SELECT sum(total)::integer as total FROM provider_counts
  )
  SELECT jsonb_build_object(
    'providers', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'provider', pc.provider,
          'total', pc.total,
          'pct', ROUND(pc.total::numeric / NULLIF(tl.total, 0) * 100, 1)
        ) ORDER BY pc.total DESC
      ), '[]'::jsonb)
      FROM provider_counts pc, total_logins tl
    ),
    'total_logins', (SELECT total FROM total_logins),
    'total_auth_users', (SELECT count(*) FROM auth.users),
    'ghost_count', (SELECT count(*) FROM auth.users au WHERE au.id NOT IN (SELECT auth_id FROM members WHERE auth_id IS NOT NULL UNION ALL SELECT unnest(secondary_auth_ids) FROM members WHERE secondary_auth_ids != '{}')),
    'ghost_visitors', (SELECT COALESCE(jsonb_agg(jsonb_build_object('email', au.email, 'provider', COALESCE(au.raw_app_meta_data->>'provider','unknown'), 'name', au.raw_user_meta_data->>'full_name') ORDER BY au.created_at DESC), '[]'::jsonb) FROM auth.users au WHERE au.id NOT IN (SELECT auth_id FROM members WHERE auth_id IS NOT NULL UNION ALL SELECT unnest(secondary_auth_ids) FROM members WHERE secondary_auth_ids != '{}')),
    'members_with_secondary_auth', (SELECT count(*) FROM members WHERE array_length(secondary_auth_ids, 1) > 0)
  );
$$;

NOTIFY pgrst, 'reload schema';

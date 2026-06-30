-- #572 Block A — institutional data portability (LGPD doc4 §6.4 / Parecer 01/2026 rec g).
-- Full-DB institutional export for platform MIGRATION/SHUTDOWN — distinct from the per-titular
-- Art.18 export (export_my_data / #568). The bulk dump itself is pg_dump over the DIRECT Postgres
-- connection (see docs/operations/INSTITUTIONAL_EXPORT_RUNBOOK.md); the four RPCs below provide the
-- integrity manifest, the machine-readable data dictionary, the secret-redacted settings export, and
-- the two-phase Art.37 audit trail. ADR-0112.
--
-- Gate (all four, identical): can_by_member(caller,'manage_platform') AND caller_chapter_scope() IS NULL
--   = GP/sede only. NOT view_pii (held by chapter partners → would be a cross-chapter leak; FU-2 closed it).
-- Grants (all four): REVOKE PUBLIC/anon; GRANT authenticated + service_role (internal gate enforces GP;
--   anti-open-relay per #963/#570).

-- ---------------------------------------------------------------------------------------------------
-- RPC 1: pre-dump manifest — integrity hashes + rate-limit + mandatory justification + phase-1 audit.
-- ---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_institutional_export_manifest(
  p_justification text,
  p_export_id uuid DEFAULT gen_random_uuid(),
  p_trigger_event text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_recent integer;
  v_rec record;
  v_est bigint;
  v_count bigint;
  v_hash text;
  v_method text;
  v_tables jsonb := '[]'::jsonb;
  v_agg_hash text;
  v_redacted jsonb;
  -- Regular tables (relkind='r') whose DATA is excluded from the dump (DDL kept): reconstructable
  -- cache/derived/external-sync + the two settings tables (rows exported via export_redacted_settings).
  -- NOTE: matviews (relkind='m', e.g. cycle_tribe_dim) are ALREADY excluded by the relkind='r' loop
  -- filter below and are reported separately as excluded_matviews — list ONLY regular tables here.
  v_excluded_data text[] := ARRAY[
    'preview_gate_eligibles_cache','wiki_pages','artia_status_reports','cron_run_log',
    'site_config','platform_settings'
  ];
  v_threshold bigint := 20000;  -- tables above this use a count-only hash to stay under the statement timeout
BEGIN
  -- gate
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT (public.can_by_member(v_caller, 'manage_platform') AND public.caller_chapter_scope() IS NULL) THEN
    RAISE EXCEPTION 'unauthorized: institutional export requires manage_platform (GP/sede)';
  END IF;

  -- mandatory justification (RoPA Art.37 — no silent/undocumented export)
  IF p_justification IS NULL OR length(trim(p_justification)) < 10 THEN
    RAISE EXCEPTION 'justification_required: provide >= 10 chars describing the migration/shutdown trigger';
  END IF;

  -- rate-limit: max 5 manifests per rolling 30 days (forces an adversary into multiple detectable events)
  SELECT count(*) INTO v_recent
  FROM public.admin_audit_log
  WHERE action = 'institutional_export.manifest_generated' AND created_at > now() - interval '30 days';
  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'rate_limited: max 5 institutional export manifests per 30 days';
  END IF;

  -- per-table integrity: content hash for normal tables, count-only hash for the large audit tables.
  FOR v_rec IN
    SELECT n.nspname AS sch, c.relname AS tbl
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public','z_archive')
      AND c.relkind = 'r'
      AND NOT (n.nspname = 'public' AND c.relname = ANY(v_excluded_data))
    ORDER BY n.nspname, c.relname
  LOOP
    SELECT c.reltuples::bigint INTO v_est
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = v_rec.sch AND c.relname = v_rec.tbl;

    -- v_est < 0 = pg_class.reltuples for a never-analyzed table; treat conservatively (count-only).
    IF v_est < 0 OR v_est > v_threshold THEN
      EXECUTE format($q$SELECT count(*) FROM %I.%I$q$, v_rec.sch, v_rec.tbl) INTO v_count;
      v_hash := encode(extensions.digest('rowcount:' || v_count::text, 'sha256'), 'hex');
      v_method := 'count_only';
    ELSE
      EXECUTE format(
        $q$SELECT count(*), encode(extensions.digest(coalesce(string_agg(r::text, '' ORDER BY r::text), ''), 'sha256'), 'hex') FROM %I.%I r$q$,
        v_rec.sch, v_rec.tbl
      ) INTO v_count, v_hash;
      v_method := 'content_sha256';
    END IF;

    v_tables := v_tables || jsonb_build_object(
      'schema', v_rec.sch,
      'table', v_rec.tbl,
      'row_count', v_count,
      'content_hash', v_hash,
      'hash_method', v_method,
      'table_bytes', pg_table_size(format('%I.%I', v_rec.sch, v_rec.tbl)::regclass)
    );
  END LOOP;

  SELECT encode(extensions.digest(
      string_agg((t->>'schema') || '.' || (t->>'table') || ':' || (t->>'content_hash'),
                 ',' ORDER BY (t->>'schema') || '.' || (t->>'table')),
      'sha256'), 'hex')
  INTO v_agg_hash
  FROM jsonb_array_elements(v_tables) t;

  SELECT coalesce(jsonb_agg(key ORDER BY key), '[]'::jsonb) INTO v_redacted FROM (
    SELECT key FROM public.site_config       WHERE key ~ '(_secret|_token|_key|_password|_passphrase|_credential)$'
    UNION
    SELECT key FROM public.platform_settings WHERE key ~ '(_secret|_token|_key|_password|_passphrase|_credential)$'
  ) s;

  -- phase-1 audit (Art.37): committed with the function txn before the manifest is returned.
  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller, 'institutional_export.manifest_generated', 'platform', NULL,
    jsonb_build_object(
      'table_count', jsonb_array_length(v_tables),
      'redacted_keys', v_redacted,
      'manifest_aggregate_hash', v_agg_hash
    ),
    jsonb_build_object(
      'export_id', p_export_id::text,
      'migration_head', (SELECT max(version) FROM supabase_migrations.schema_migrations),
      'justification', p_justification,
      'trigger_event', p_trigger_event,
      'format', 'pg_dump+plain'
    )
  );

  RETURN jsonb_build_object(
    'export_id', p_export_id,
    'generated_at', now(),
    'generated_by', jsonb_build_object('member_id', v_caller, 'name', (SELECT name FROM public.members WHERE id = v_caller)),
    'migration_head', (SELECT max(version) FROM supabase_migrations.schema_migrations),
    'format', 'pg_dump --schema=public --schema=z_archive --no-owner --no-acl --format=plain',
    'table_count', jsonb_array_length(v_tables),
    'table_manifests', v_tables,
    'manifest_aggregate_hash', v_agg_hash,
    'redacted_keys', v_redacted,
    'excluded_table_data', to_jsonb(v_excluded_data),
    'excluded_matviews', (
      SELECT coalesce(jsonb_agg(n.nspname || '.' || c.relname ORDER BY n.nspname, c.relname), '[]'::jsonb)
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname IN ('public','z_archive') AND c.relkind = 'm'
    ),
    'excluded_schemas', jsonb_build_array('auth','vault','storage','realtime','supabase_migrations','extensions','cron'),
    'hash_fallback_threshold', v_threshold,
    'justification', p_justification,
    'trigger_event', p_trigger_event
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.generate_institutional_export_manifest(text, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_institutional_export_manifest(text, uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.generate_institutional_export_manifest(text, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_institutional_export_manifest(text, uuid, text) TO service_role;
COMMENT ON FUNCTION public.generate_institutional_export_manifest(text, uuid, text) IS
  '#572 Block A / ADR-0112: pre-dump integrity manifest (per-table SHA-256 + aggregate hash) with mandatory justification, 5/30d rate-limit, and phase-1 Art.37 audit. GP/sede only. Pairs with register_institutional_export_completion.';

-- ---------------------------------------------------------------------------------------------------
-- RPC 2: machine-readable data dictionary (read/validate/reimport) for public + z_archive.
-- ---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.export_institutional_data_dictionary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'z_archive', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT (public.can_by_member(v_caller, 'manage_platform') AND public.caller_chapter_scope() IS NULL) THEN
    RAISE EXCEPTION 'unauthorized: institutional export requires manage_platform (GP/sede)';
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'schemas_included', jsonb_build_array('public','z_archive'),
    'excluded_schemas', jsonb_build_array('auth','vault','storage','realtime','supabase_migrations','extensions','cron'),
    'rls_note', 'pg_dump --no-acl does NOT strip RLS — the restored DDL re-creates row-security. After restore, '
                || 'create roles anon/authenticated/service_role to match the source and verify policies are intact '
                || 'BEFORE exposing data to any role other than the table owner/superuser.',
    'tables', (
      SELECT coalesce(jsonb_agg(tbl ORDER BY tbl->>'schema', tbl->>'table'), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
          'schema', n.nspname,
          'table', c.relname,
          'kind', CASE c.relkind WHEN 'r' THEN 'table' WHEN 'm' THEN 'materialized_view' ELSE c.relkind::text END,
          'table_comment', obj_description(c.oid),
          'has_rls', c.relrowsecurity,
          'est_row_count', c.reltuples::bigint,
          'columns', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
              'ordinal_position', a.attnum,
              'column_name', a.attname,
              'data_type', format_type(a.atttypid, a.atttypmod),
              'is_nullable', NOT a.attnotnull,
              'column_default', pg_get_expr(ad.adbin, ad.adrelid),
              'column_comment', col_description(c.oid, a.attnum)
            ) ORDER BY a.attnum), '[]'::jsonb)
            FROM pg_attribute a
            LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
            WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
          ),
          'constraints', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
              'constraint_name', con.conname,
              'constraint_type', CASE con.contype
                WHEN 'p' THEN 'PRIMARY KEY' WHEN 'f' THEN 'FOREIGN KEY'
                WHEN 'u' THEN 'UNIQUE' WHEN 'c' THEN 'CHECK' ELSE con.contype::text END,
              'definition', pg_get_constraintdef(con.oid),
              'referenced_table', CASE WHEN con.contype = 'f' THEN con.confrelid::regclass::text ELSE NULL END
            ) ORDER BY con.conname), '[]'::jsonb)
            FROM pg_constraint con WHERE con.conrelid = c.oid
          )
        ) AS tbl
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('public','z_archive') AND c.relkind IN ('r','m')
      ) s
    )
  ) INTO v_result;

  RETURN v_result;
END;
$fn$;

REVOKE ALL ON FUNCTION public.export_institutional_data_dictionary() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.export_institutional_data_dictionary() FROM anon;
GRANT EXECUTE ON FUNCTION public.export_institutional_data_dictionary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.export_institutional_data_dictionary() TO service_role;
COMMENT ON FUNCTION public.export_institutional_data_dictionary() IS
  '#572 Block A / ADR-0112: machine-readable schema dictionary (tables/columns/types/PK-FK/RLS) for public + z_archive, for reading/validating/reimporting the institutional dump. GP/sede only.';

-- ---------------------------------------------------------------------------------------------------
-- RPC 3: secret-redacted settings export (the ONLY export path for site_config / platform_settings,
--         whose row data is --exclude-table-data in pg_dump). Keys ending _secret/_token/_key masked.
-- ---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.export_redacted_settings()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT (public.can_by_member(v_caller, 'manage_platform') AND public.caller_chapter_scope() IS NULL) THEN
    RAISE EXCEPTION 'unauthorized: institutional export requires manage_platform (GP/sede)';
  END IF;

  SELECT jsonb_build_object(
    'generated_at', now(),
    'redaction_pattern', '(_secret|_token|_key|_password|_passphrase|_credential)$',
    'redacted_keys', (
      SELECT coalesce(jsonb_agg(key ORDER BY key), '[]'::jsonb) FROM (
        SELECT key FROM public.site_config       WHERE key ~ '(_secret|_token|_key|_password|_passphrase|_credential)$'
        UNION
        SELECT key FROM public.platform_settings WHERE key ~ '(_secret|_token|_key|_password|_passphrase|_credential)$'
      ) s
    ),
    'site_config', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'key', key,
        'value', CASE WHEN key ~ '(_secret|_token|_key|_password|_passphrase|_credential)$' THEN '"[REDACTED]"'::jsonb ELSE value END,
        'updated_at', updated_at,
        'updated_by', updated_by
      ) ORDER BY key), '[]'::jsonb)
      FROM public.site_config
    ),
    'platform_settings', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'key', key,
        'value', CASE WHEN key ~ '(_secret|_token|_key|_password|_passphrase|_credential)$' THEN '"[REDACTED]"'::jsonb ELSE value END,
        'description', description,
        'changed_by', changed_by,
        'changed_at', changed_at,
        'change_reason', change_reason
      ) ORDER BY key), '[]'::jsonb)
      FROM public.platform_settings
    )
  ) INTO v_result;

  RETURN v_result;
END;
$fn$;

REVOKE ALL ON FUNCTION public.export_redacted_settings() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.export_redacted_settings() FROM anon;
GRANT EXECUTE ON FUNCTION public.export_redacted_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.export_redacted_settings() TO service_role;
COMMENT ON FUNCTION public.export_redacted_settings() IS
  '#572 Block A / ADR-0112: settings export with credential-pattern keys (_secret/_token/_key/_password/_passphrase/_credential) masked to [REDACTED]. The only export path for site_config/platform_settings WITHIN the institutional export bundle (their row data is --exclude-table-data in pg_dump). Does not govern unrelated admin surfaces (e.g. get_site_config). GP/sede only.';

-- ---------------------------------------------------------------------------------------------------
-- RPC 4: phase-2 audit — register the completed dump (file sha256 + bytes), keyed to the manifest.
-- ---------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_institutional_export_completion(
  p_export_id uuid,
  p_dump_sha256 text,
  p_dump_bytes bigint,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller uuid;
  v_audit_id uuid;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthorized'; END IF;
  IF NOT (public.can_by_member(v_caller, 'manage_platform') AND public.caller_chapter_scope() IS NULL) THEN
    RAISE EXCEPTION 'unauthorized: institutional export requires manage_platform (GP/sede)';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.admin_audit_log
    WHERE action = 'institutional_export.manifest_generated'
      AND metadata->>'export_id' = p_export_id::text
  ) THEN
    RAISE EXCEPTION 'no_manifest_for_export_id: % — call generate_institutional_export_manifest first', p_export_id;
  END IF;

  -- idempotency guard: one completion per export_id (no contradictory dual receipts in the Art.37 trail)
  IF EXISTS (
    SELECT 1 FROM public.admin_audit_log
    WHERE action = 'institutional_export.completed'
      AND metadata->>'export_id' = p_export_id::text
  ) THEN
    RAISE EXCEPTION 'already_registered: export_id % already has a completion record', p_export_id;
  END IF;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_caller, 'institutional_export.completed', 'platform', NULL,
    jsonb_build_object('export_id', p_export_id::text, 'dump_bytes', p_dump_bytes),
    jsonb_build_object(
      'export_id', p_export_id::text,
      'dump_sha256', p_dump_sha256,
      'dump_bytes', p_dump_bytes,
      'notes', p_notes,
      'registered_at', now()
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object(
    'audit_entry_id', v_audit_id,
    'export_id', p_export_id,
    'registered_at', now()
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.register_institutional_export_completion(uuid, text, bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.register_institutional_export_completion(uuid, text, bigint, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.register_institutional_export_completion(uuid, text, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_institutional_export_completion(uuid, text, bigint, text) TO service_role;
COMMENT ON FUNCTION public.register_institutional_export_completion(uuid, text, bigint, text) IS
  '#572 Block A / ADR-0112: phase-2 Art.37 audit — registers the completed dump file (sha256 + bytes) against a prior manifest export_id. GP/sede only.';

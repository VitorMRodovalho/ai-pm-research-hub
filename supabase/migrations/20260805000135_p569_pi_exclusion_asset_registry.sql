-- Migration: 20260805000135_p569_pi_exclusion_asset_registry
-- Issue: #569 — OpenTimestamps / carimbo de tempo para a Declaração de Exclusão de PI (Parecer 01/2026 rec k)
-- ADR: ADR-0101 (digest-only PI-exclusion asset registry + OpenTimestamps proofs)
-- Refs: doc7 Cláusula Quarta 4.1 + Anexo I; doc9 §B; ADR-0004 (organization_id), ADR-0007 (can()), GC-162 (RLS/LGPD).
-- Council: wf_e64398e5-c2c (data-architect + security-engineer + legal-counsel + senior-eng, all GO_W_FIXES);
--          all must-fix items folded (org FK, STABLE→VOLATILE on logging RPCs, pii_access_log on export_anexo_i
--          admin path, org-from-declaration in register, status guard, _ots_mark_error confirmed guard,
--          error/waiting split + asset id + digest_only_notice in export, LATERAL counts, CHECK invariants,
--          UNIQUE(declaration_id,seq), org index, least-privilege GRANT, updated_at trigger).
--
-- SLICE 1 of #569 (DB foundation). Slices 2-4 (EF stamp/verify via npm:opentimestamps, pg_cron upgrade pass,
-- MCP tools) follow. DIGEST-ONLY (PM decision 2026-06-09): the work never leaves the Núcleo — only the SHA-256
-- digest + the `.ots` proof (a few hundred bytes, bytea) are stored.
--
-- Access posture (GC-162 / LGPD): both tables RLS-enabled, DIRECT access denied (rpc_only). All reads/writes go
-- through SECURITY DEFINER RPCs — declarant self-service + a view_pii-gated, org-fenced admin read for
-- fiscalization (logged to pii_access_log, accessor_id = members.id). service_role (EF/cron) reaches the tables
-- only via the dedicated internal `_ots_*` RPCs.
--
-- State invariants enforced STRUCTURALLY via CHECK (stronger than a check_schema_invariants() drift probe — the
-- bad state cannot be written): confirmed ⇒ bitcoin_block + attested_at NOT NULL; pending ⇒ ots_proof NOT NULL.
-- Eficácia probatória plena (doc7 Cl.4.1) = ALL assets 'confirmed' (export_anexo_i.all_confirmed), with
-- error/waiting surfaced separately so a broken pipeline is never read as "merely awaiting Bitcoin".
--
-- DEFERRED (tracked, zero live data today — folded into the #569 wire-up slice, NOT this foundation):
--   * export_my_data() integration (LGPD Art. 18 II portability of a declarant's own PI registry) — Slice 4.
--   * admin_audit_log entry on declaration create/revoke (lifecycle audit) — Slice 4.
--   * retention/elimination of error/revoked rows + .ots bytea (doc1 2.5.6) — Slice 3 (with the cron).
--   * _ots_claim_unstamped_assets row-locking (FOR UPDATE SKIP LOCKED) — Slice 2/3. Until then the stamp/upgrade
--     pipeline MUST be single-consumer (one pg_cron job, no overlap) or it will submit duplicate OTS requests.
--
-- After apply: NOTIFY pgrst, 'reload schema'.
-- Rollback (Slice-1 only; DROP TABLE ... CASCADE also removes the indexes/policies/triggers/constraints. From
-- Slice 2+ a reverse-migration is required):
--   DROP FUNCTION public.create_exclusion_declaration(text);
--   DROP FUNCTION public.register_exclusion_asset(uuid,text,text,text,text,date,text,text);
--   DROP FUNCTION public.get_exclusion_declaration(uuid);
--   DROP FUNCTION public.list_my_exclusion_declarations();
--   DROP FUNCTION public.export_anexo_i(uuid);
--   DROP FUNCTION public._ots_claim_unstamped_assets(integer);
--   DROP FUNCTION public._ots_mark_stamped(uuid,bytea);
--   DROP FUNCTION public._ots_list_pending(integer);
--   DROP FUNCTION public._ots_mark_confirmed(uuid,bytea,bigint,timestamptz);
--   DROP FUNCTION public._ots_mark_error(uuid,text);
--   DROP TABLE public.pi_exclusion_assets CASCADE;
--   DROP TABLE public.pi_exclusion_declarations CASCADE;
--   DROP FUNCTION public.pi_exclusion_touch_updated_at();

-- ============================================================================
-- updated_at trigger fn (moddatetime extension is NOT installed — self-contained fn)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.pi_exclusion_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

-- ============================================================================
-- Tables
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.pi_exclusion_declarations (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id        uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  declarant_member_id    uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  governance_document_id uuid REFERENCES public.governance_documents(id) ON DELETE SET NULL, -- seam to doc7 instance (nullable until doc7 uploaded)
  title                  text,
  status                 text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','revoked')),
  created_by             uuid REFERENCES auth.users(id),
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.pi_exclusion_declarations IS
  'One row per declarant instance of the Declaração de Exclusão de PI (doc7). #569 / ADR-0101. RLS deny-all; access via SECURITY DEFINER RPCs only.';

CREATE TABLE IF NOT EXISTS public.pi_exclusion_assets (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  declaration_id  uuid NOT NULL REFERENCES public.pi_exclusion_declarations(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  seq             integer,                       -- order within Anexo I
  title           text NOT NULL,
  nature          text,                          -- tese / artigo / livro / metodologia / algoritmo
  author_label    text,                          -- autor(es) / capítulo
  work_created_on date,
  source_ref      text,                          -- caminho/URL/identificador (NOT the file — digest-only)
  sha256          text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  ots_proof       bytea,                         -- the .ots proof; null until stamped
  ots_status      text NOT NULL DEFAULT 'unstamped' CHECK (ots_status IN ('unstamped','pending','confirmed','error')),
  bitcoin_block   bigint,                        -- block height once confirmed
  attested_at     timestamptz,                   -- UTC of the Bitcoin attestation
  reinforcement   text,                          -- optional manual reinforcement note (ata notarial / ICP-Brasil / INPI)
  stamp_error     text,
  stamp_attempts  integer NOT NULL DEFAULT 0,
  created_by      uuid REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pi_excl_asset_uniq_digest   UNIQUE (declaration_id, sha256),
  CONSTRAINT pi_excl_asset_uniq_seq      UNIQUE (declaration_id, seq),
  -- structural state invariants (PI1/PI2) — the bad state cannot be persisted:
  CONSTRAINT pi_excl_asset_confirmed_anchored CHECK (ots_status <> 'confirmed' OR (bitcoin_block IS NOT NULL AND attested_at IS NOT NULL)),
  CONSTRAINT pi_excl_asset_pending_has_proof  CHECK (ots_status <> 'pending'   OR ots_proof IS NOT NULL)
);
COMMENT ON TABLE public.pi_exclusion_assets IS
  'Anexo I rows of a Declaração de Exclusão de PI: SHA-256 digest + OpenTimestamps proof (digest-only, work never stored). #569 / ADR-0101.';

CREATE INDEX IF NOT EXISTS idx_pi_excl_assets_declaration ON public.pi_exclusion_assets (declaration_id);
CREATE INDEX IF NOT EXISTS idx_pi_excl_assets_ots_status   ON public.pi_exclusion_assets (ots_status) WHERE ots_status IN ('unstamped','pending');
CREATE INDEX IF NOT EXISTS idx_pi_excl_decl_declarant      ON public.pi_exclusion_declarations (declarant_member_id);
CREATE INDEX IF NOT EXISTS idx_pi_excl_decl_org            ON public.pi_exclusion_declarations (organization_id);

CREATE TRIGGER trg_pi_excl_decl_updated_at  BEFORE UPDATE ON public.pi_exclusion_declarations FOR EACH ROW EXECUTE FUNCTION public.pi_exclusion_touch_updated_at();
CREATE TRIGGER trg_pi_excl_asset_updated_at BEFORE UPDATE ON public.pi_exclusion_assets        FOR EACH ROW EXECUTE FUNCTION public.pi_exclusion_touch_updated_at();

-- ============================================================================
-- RLS — deny-all (rpc_only); SECURITY DEFINER RPCs are the only access path. service_role bypasses RLS.
-- ============================================================================
ALTER TABLE public.pi_exclusion_declarations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pi_exclusion_assets        ENABLE ROW LEVEL SECURITY;

CREATE POLICY pi_excl_decl_rpc_only  ON public.pi_exclusion_declarations FOR ALL USING (false) WITH CHECK (false);
CREATE POLICY pi_excl_asset_rpc_only ON public.pi_exclusion_assets        FOR ALL USING (false) WITH CHECK (false);

REVOKE ALL ON public.pi_exclusion_declarations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.pi_exclusion_assets        FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pi_exclusion_declarations TO service_role; -- least-privilege (no TRUNCATE/REFERENCES)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pi_exclusion_assets        TO service_role;

-- ============================================================================
-- Member-facing RPCs (SECURITY DEFINER; auth.uid() → members.id ownership)
-- ============================================================================

-- create_exclusion_declaration — a declarant opens their own Declaração instance.
CREATE OR REPLACE FUNCTION public.create_exclusion_declaration(p_title text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_org_id    uuid;
  v_id        uuid;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_org_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  INSERT INTO public.pi_exclusion_declarations (organization_id, declarant_member_id, title, created_by)
  VALUES (v_org_id, v_member_id, p_title, auth.uid())
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.create_exclusion_declaration(text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.create_exclusion_declaration(text) TO authenticated, service_role;

-- register_exclusion_asset — add an Anexo I row (digest + metadata). Stamping happens later (ots_status='unstamped').
-- org + status come from the DECLARATION (not the caller's members row) → no parent/child org drift; revoked is immutable.
CREATE OR REPLACE FUNCTION public.register_exclusion_asset(
  p_declaration_id uuid,
  p_title          text,
  p_sha256         text,
  p_nature         text DEFAULT NULL,
  p_author_label   text DEFAULT NULL,
  p_work_created_on date DEFAULT NULL,
  p_source_ref     text DEFAULT NULL,
  p_reinforcement  text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_owner     uuid;
  v_decl_org  uuid;
  v_status    text;
  v_next_seq  integer;
  v_id        uuid;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT declarant_member_id, organization_id, status INTO v_owner, v_decl_org, v_status
  FROM public.pi_exclusion_declarations WHERE id = p_declaration_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Declaration not found'; END IF;
  IF v_owner <> v_member_id THEN RAISE EXCEPTION 'Access denied: not the declarant of this declaration'; END IF;
  IF v_status NOT IN ('draft','active') THEN RAISE EXCEPTION 'Cannot add assets to a % declaration', v_status; END IF;

  IF lower(p_sha256) !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Invalid SHA-256 digest (expected 64 lowercase hex chars)';
  END IF;

  SELECT COALESCE(max(seq), 0) + 1 INTO v_next_seq FROM public.pi_exclusion_assets WHERE declaration_id = p_declaration_id;

  INSERT INTO public.pi_exclusion_assets (
    declaration_id, organization_id, seq, title, nature, author_label,
    work_created_on, source_ref, sha256, reinforcement, created_by
  ) VALUES (
    p_declaration_id, v_decl_org, v_next_seq, p_title, p_nature, p_author_label,
    p_work_created_on, p_source_ref, lower(p_sha256), p_reinforcement, auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.register_exclusion_asset(uuid,text,text,text,text,date,text,text) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.register_exclusion_asset(uuid,text,text,text,text,date,text,text) TO authenticated, service_role;

-- get_exclusion_declaration — declaration + its assets. Owner OR view_pii admin (org-fenced + logged).
-- VOLATILE (NOT STABLE): the admin path INSERTs into pii_access_log; STABLE would let the planner drop the write.
CREATE OR REPLACE FUNCTION public.get_exclusion_declaration(p_declaration_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id  uuid;
  v_caller_org uuid;
  v_owner      uuid;
  v_decl_org   uuid;
  v_is_admin   boolean := false;
  v_result     jsonb;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_caller_org FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT declarant_member_id, organization_id INTO v_owner, v_decl_org
  FROM public.pi_exclusion_declarations WHERE id = p_declaration_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Declaration not found'; END IF;

  IF v_owner <> v_member_id THEN
    -- fiscalization path: view_pii + org fence (SECDEF bypasses RLS; view_pii doesn't bound the target).
    IF NOT public.can_by_member(v_member_id, 'view_pii') THEN
      RAISE EXCEPTION 'Access denied: not the declarant and missing view_pii';
    END IF;
    IF v_decl_org IS NULL OR v_caller_org IS NULL OR v_decl_org <> v_caller_org THEN
      RAISE EXCEPTION 'Access denied: declaration not in caller organization';
    END IF;
    v_is_admin := true;
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, accessed_at)
    VALUES (v_member_id, v_owner, ARRAY['pi_exclusion_declaration']::text[], 'get_exclusion_declaration', 'PI exclusion fiscalization', now());
  END IF;

  SELECT jsonb_build_object(
    'id', d.id,
    'title', d.title,
    'status', d.status,
    'declarant_member_id', d.declarant_member_id,
    'governance_document_id', d.governance_document_id,
    'created_at', d.created_at,
    'viewed_as', CASE WHEN v_is_admin THEN 'fiscalization' ELSE 'declarant' END,
    'assets', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', a.id, 'seq', a.seq, 'title', a.title, 'nature', a.nature,
        'author_label', a.author_label, 'work_created_on', a.work_created_on, 'source_ref', a.source_ref,
        'sha256', a.sha256, 'ots_status', a.ots_status, 'has_proof', (a.ots_proof IS NOT NULL),
        'bitcoin_block', a.bitcoin_block, 'attested_at', a.attested_at, 'reinforcement', a.reinforcement
      ) ORDER BY a.seq)
      FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id AND a.organization_id = d.organization_id
    ), '[]'::jsonb)
  ) INTO v_result
  FROM public.pi_exclusion_declarations d WHERE d.id = p_declaration_id;

  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.get_exclusion_declaration(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_exclusion_declaration(uuid) TO authenticated, service_role;

-- list_my_exclusion_declarations — the caller's own declarations (summary). LATERAL counts (no N+1).
CREATE OR REPLACE FUNCTION public.list_my_exclusion_declarations()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id uuid;
  v_result    jsonb;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', d.id, 'title', d.title, 'status', d.status, 'created_at', d.created_at,
    'asset_count', c.asset_count, 'confirmed_count', c.confirmed_count
  ) ORDER BY d.created_at DESC), '[]'::jsonb)
  INTO v_result
  FROM public.pi_exclusion_declarations d
  LEFT JOIN LATERAL (
    SELECT count(*) AS asset_count,
           count(*) FILTER (WHERE a.ots_status = 'confirmed') AS confirmed_count
    FROM public.pi_exclusion_assets a WHERE a.declaration_id = d.id
  ) c ON true
  WHERE d.declarant_member_id = v_member_id;

  RETURN v_result;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.list_my_exclusion_declarations() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.list_my_exclusion_declarations() TO authenticated, service_role;

-- export_anexo_i — render the Anexo I rows for doc7 + an honest efficacy envelope.
-- VOLATILE (NOT STABLE): admin path INSERTs into pii_access_log.
CREATE OR REPLACE FUNCTION public.export_anexo_i(p_declaration_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member_id  uuid;
  v_caller_org uuid;
  v_owner      uuid;
  v_decl_org   uuid;
  v_total      integer;
  v_confirmed  integer;
  v_pending    integer;
  v_unstamped  integer;
  v_error      integer;
  v_rows       jsonb;
BEGIN
  SELECT id, organization_id INTO v_member_id, v_caller_org FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT declarant_member_id, organization_id INTO v_owner, v_decl_org
  FROM public.pi_exclusion_declarations WHERE id = p_declaration_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Declaration not found'; END IF;

  IF v_owner <> v_member_id THEN
    IF NOT public.can_by_member(v_member_id, 'view_pii') THEN
      RAISE EXCEPTION 'Access denied: not the declarant and missing view_pii';
    END IF;
    IF v_decl_org IS NULL OR v_caller_org IS NULL OR v_decl_org <> v_caller_org THEN
      RAISE EXCEPTION 'Access denied: declaration not in caller organization';
    END IF;
    INSERT INTO public.pii_access_log (accessor_id, target_member_id, fields_accessed, context, reason, accessed_at)
    VALUES (v_member_id, v_owner, ARRAY['pi_exclusion_anexo_i']::text[], 'export_anexo_i', 'PI exclusion fiscalization export', now());
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE ots_status = 'confirmed'),
         count(*) FILTER (WHERE ots_status = 'pending'),
         count(*) FILTER (WHERE ots_status = 'unstamped'),
         count(*) FILTER (WHERE ots_status = 'error')
  INTO v_total, v_confirmed, v_pending, v_unstamped, v_error
  FROM public.pi_exclusion_assets WHERE declaration_id = p_declaration_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'seq', a.seq,
    'titulo', a.title,
    'natureza', a.nature,
    'autor_capitulo', a.author_label,
    'data_criacao', a.work_created_on,
    'caminho_url', a.source_ref,
    'sha256', a.sha256,
    'prova_ots', (a.ots_proof IS NOT NULL),
    'status', a.ots_status,
    'ancoragem', CASE WHEN a.ots_status = 'confirmed'
      THEN jsonb_build_object('bloco', a.bitcoin_block, 'utc', a.attested_at) ELSE NULL END,
    'reforco', a.reinforcement
  ) ORDER BY a.seq), '[]'::jsonb)
  INTO v_rows
  FROM public.pi_exclusion_assets a WHERE a.declaration_id = p_declaration_id;

  RETURN jsonb_build_object(
    'declaration_id', p_declaration_id,
    'total_assets', v_total,
    'confirmed_assets', v_confirmed,
    'pending_assets', v_pending,        -- aguardando ancoragem Bitcoin (carimbo já submetido)
    'unstamped_assets', v_unstamped,    -- ainda não carimbados
    'error_assets', v_error,            -- falha permanente do pipeline (≥5 tentativas) — NÃO é "aguardando"
    'all_confirmed', (v_total > 0 AND v_confirmed = v_total),  -- eficácia probatória plena exige TODOS confirmed
    'anexo_i', v_rows,
    'digest_only_notice', 'Carimbo de tempo digest-only: a plataforma atesta que o hash SHA-256 existia na data ancorada na blockchain; NÃO armazena a obra nem verifica que o digest corresponde ao arquivo final (responsabilidade do declarante — doc9 §B vi).',
    'exported_at', now()
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.export_anexo_i(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.export_anexo_i(uuid) TO authenticated, service_role;

-- ============================================================================
-- Internal OTS-pipeline RPCs (service_role only — called by the stamp/upgrade Edge Function / cron).
-- NOTE: no row-locking yet (FOR UPDATE SKIP LOCKED is Slice 2/3) → the pipeline MUST be single-consumer.
-- ============================================================================

-- claim a batch of assets needing the initial stamp.
CREATE OR REPLACE FUNCTION public._ots_claim_unstamped_assets(p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'sha256', sha256)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT id, sha256 FROM public.pi_exclusion_assets
    WHERE ots_status = 'unstamped' AND stamp_attempts < 5
    ORDER BY created_at LIMIT p_limit
  ) s;
  RETURN v_result;
END;
$function$;

-- mark an asset stamped (pending) with the calendar-commitment .ots proof.
CREATE OR REPLACE FUNCTION public._ots_mark_stamped(p_asset_id uuid, p_ots_proof bytea)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF p_ots_proof IS NULL THEN RAISE EXCEPTION '_ots_mark_stamped requires a non-null proof'; END IF;
  UPDATE public.pi_exclusion_assets
  SET ots_proof = p_ots_proof, ots_status = 'pending',
      stamp_attempts = stamp_attempts + 1, stamp_error = NULL
  WHERE id = p_asset_id AND ots_status IN ('unstamped','error');
END;
$function$;

-- list pending proofs (base64) for the upgrade pass.
CREATE OR REPLACE FUNCTION public._ots_list_pending(p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'sha256', sha256, 'ots_proof_b64', encode(ots_proof, 'base64')
  )), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT id, sha256, ots_proof FROM public.pi_exclusion_assets
    WHERE ots_status = 'pending' AND ots_proof IS NOT NULL
    ORDER BY updated_at LIMIT p_limit
  ) s;
  RETURN v_result;
END;
$function$;

-- promote a pending asset to confirmed with the upgraded (Bitcoin-anchored) proof + attestation.
CREATE OR REPLACE FUNCTION public._ots_mark_confirmed(
  p_asset_id uuid, p_ots_proof bytea, p_bitcoin_block bigint, p_attested_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF p_bitcoin_block IS NULL OR p_attested_at IS NULL THEN
    RAISE EXCEPTION '_ots_mark_confirmed requires bitcoin_block + attested_at (confirmed ⇒ anchored)';
  END IF;
  UPDATE public.pi_exclusion_assets
  SET ots_proof = COALESCE(p_ots_proof, ots_proof), ots_status = 'confirmed',
      bitcoin_block = p_bitcoin_block, attested_at = p_attested_at, stamp_error = NULL
  WHERE id = p_asset_id AND ots_status = 'pending';
END;
$function$;

-- record a stamp/upgrade error (status flips to 'error' on the 5th failure). Never degrades a confirmed asset.
CREATE OR REPLACE FUNCTION public._ots_mark_error(p_asset_id uuid, p_error text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  UPDATE public.pi_exclusion_assets
  SET stamp_error = p_error, stamp_attempts = stamp_attempts + 1,
      ots_status = CASE WHEN stamp_attempts + 1 >= 5 THEN 'error' ELSE ots_status END
  WHERE id = p_asset_id AND ots_status NOT IN ('confirmed');
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._ots_claim_unstamped_assets(integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._ots_mark_stamped(uuid,bytea)        FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._ots_list_pending(integer)           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._ots_mark_confirmed(uuid,bytea,bigint,timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._ots_mark_error(uuid,text)           FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._ots_claim_unstamped_assets(integer) TO service_role;
GRANT  EXECUTE ON FUNCTION public._ots_mark_stamped(uuid,bytea)        TO service_role;
GRANT  EXECUTE ON FUNCTION public._ots_list_pending(integer)           TO service_role;
GRANT  EXECUTE ON FUNCTION public._ots_mark_confirmed(uuid,bytea,bigint,timestamptz) TO service_role;
GRANT  EXECUTE ON FUNCTION public._ots_mark_error(uuid,text)           TO service_role;

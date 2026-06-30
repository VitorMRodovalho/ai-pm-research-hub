-- =====================================================================
-- #973 (PR-1 of #571) — Camada 5 Material-change backbone: FUNDAÇÕES
-- Two cross-cutting primitives shared by WA1/WA2/WA3: change_class
-- (Material/Editorial) + a Brazilian business-day calendar.
-- BEHAVIOR-NEUTRAL: no outward dispatch, no re-acceptance lifecycle, no
-- gate changes. SPEC docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-1 + §9.
-- ADR-0113.
--
-- INTERIM / FORWARD-COMPAT CONTRACT (read before PR-2..5):
--   * change_class is nullable. The 41 versions already locked, plus any
--     version locked through a caller that does not pass p_change_class
--     (the live frontend / MCP tool until they ship the selector, and
--     recirculate_governance_doc), carry change_class = NULL. The extended
--     immutability trigger then FREEZES that NULL once locked.
--   * Downstream material-change logic (PR-3 cadeia, PR-4 re-aceite) MUST
--     treat change_class IS NULL as "unclassified ⇒ NON-material" (fail-safe:
--     no re-acceptance obligation). The whole machinery is dormant until the
--     Termo/Política v2.7 ratify and the dispatch is un-gated (#334), so a
--     NULL during the interim opens nothing.
--   * lock_document_version stays BACKWARD-COMPATIBLE (old 2-arg calls resolve
--     via DEFAULT NULL, no RAISE) precisely so applying this migration to the
--     shared prod DB does not break the currently-deployed lock button before
--     the new frontend/MCP deploy. Classification is required in the UI lock
--     modal (shipped in this PR's frontend change).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. document_versions: change_class + aviso-30d summary columns
-- ---------------------------------------------------------------------
ALTER TABLE public.document_versions
  ADD COLUMN IF NOT EXISTS change_class text
    CHECK (change_class IN ('editorial','material')),
  ADD COLUMN IF NOT EXISTS summary_pt text,
  ADD COLUMN IF NOT EXISTS summary_en text,
  ADD COLUMN IF NOT EXISTS summary_es text;

COMMENT ON COLUMN public.document_versions.change_class IS
  '#571 Camada 5 PR-1: Material vs Editorial (Política 12.2 5-prong / Termo 15.4.4). '
  'Nullable; resolved deliberately at lock (lock_document_version p_change_class), never silently defaulted. '
  'Immutable once locked_at IS NOT NULL (trg_document_version_immutable). '
  'NULL = unclassified ⇒ downstream MUST treat as non-material (fail-safe).';
COMMENT ON COLUMN public.document_versions.summary_pt IS
  '#571 Camada 5 PR-1: plain-language change summary (PT) for the 30-day re-acceptance notice (Termo 15.3(a)). Mirrors privacy_policy_versions.summary_pt.';
COMMENT ON COLUMN public.document_versions.summary_en IS '#571 Camada 5 PR-1: change summary (EN) for the 30-day re-acceptance notice.';
COMMENT ON COLUMN public.document_versions.summary_es IS '#571 Camada 5 PR-1: change summary (ES) for the 30-day re-acceptance notice.';

-- ---------------------------------------------------------------------
-- 2. trg_document_version_immutable — extend to freeze change_class once
--    locked (§9.2: prevent silent material->editorial reclassification
--    post-lock, which would void re-acceptance obligations). All other
--    behavior verbatim. change_class is still WRITABLE during the locking
--    UPDATE itself (OLD.locked_at IS NULL at that instant).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_document_version_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.locked_at IS NOT NULL THEN
    IF NEW.content_html IS DISTINCT FROM OLD.content_html
       OR NEW.content_markdown IS DISTINCT FROM OLD.content_markdown
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.version_label IS DISTINCT FROM OLD.version_label
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.locked_at IS DISTINCT FROM OLD.locked_at
       OR NEW.change_class IS DISTINCT FROM OLD.change_class   -- #571 PR-1 §9.2
    THEN
      RAISE EXCEPTION 'document_versions row locked at % is immutable (id=%, document=%)', OLD.locked_at, OLD.id, OLD.document_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- 3. br_holidays — BR business-day calendar (national + GO/sede)
--    RLS enabled (GC-162). Non-PII public reference data → read-all SELECT;
--    no INSERT/UPDATE/DELETE policy ⇒ RLS default-deny for anon+authenticated
--    (only service_role / migrations, which bypass RLS, can write).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.br_holidays (
  holiday_date date PRIMARY KEY,
  label text NOT NULL,
  scope text NOT NULL CHECK (scope IN ('national','GO')),
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.br_holidays IS
  '#571 Camada 5 PR-1: Brazilian holiday calendar for business-day deadline math (add_business_days). '
  'scope=national (statutory) | GO (Goiás/Goiânia sede). add_business_days/business_days_between exclude ALL '
  'rows regardless of scope — the sede (GO) calendar is the canonical approximation. Partner-state holidays '
  '(CE/DF/MG/RS) are a known limitation deferred to PR-3/PR-4 (SPEC §9.5). Seed covers 2025–2030; extend before '
  '2030 (the functions RAISE WARNING past coverage).';

ALTER TABLE public.br_holidays ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS br_holidays_read_all ON public.br_holidays;
CREATE POLICY br_holidays_read_all ON public.br_holidays FOR SELECT USING (true);
GRANT SELECT ON public.br_holidays TO anon, authenticated;

-- Seed 2025–2030. National fixed (statutory) + Good Friday (movable, statutory,
-- Easter-2). GO scope: Carnaval Mon+Tue (Easter-48/-47), Corpus Christi (Easter+60),
-- Aniversário de Goiânia (Oct 24). Movable dates verified via Gregorian Computus.
-- Including widely-observed non-working days is pró-voluntário (extends windows, 15.4.6).
INSERT INTO public.br_holidays (holiday_date, label, scope) VALUES
  -- National fixed
  ('2025-01-01','Confraternização Universal','national'),
  ('2025-04-21','Tiradentes','national'),
  ('2025-05-01','Dia do Trabalho','national'),
  ('2025-09-07','Independência do Brasil','national'),
  ('2025-10-12','Nossa Senhora Aparecida','national'),
  ('2025-11-02','Finados','national'),
  ('2025-11-15','Proclamação da República','national'),
  ('2025-11-20','Dia da Consciência Negra','national'),
  ('2025-12-25','Natal','national'),
  ('2026-01-01','Confraternização Universal','national'),
  ('2026-04-21','Tiradentes','national'),
  ('2026-05-01','Dia do Trabalho','national'),
  ('2026-09-07','Independência do Brasil','national'),
  ('2026-10-12','Nossa Senhora Aparecida','national'),
  ('2026-11-02','Finados','national'),
  ('2026-11-15','Proclamação da República','national'),
  ('2026-11-20','Dia da Consciência Negra','national'),
  ('2026-12-25','Natal','national'),
  ('2027-01-01','Confraternização Universal','national'),
  ('2027-04-21','Tiradentes','national'),
  ('2027-05-01','Dia do Trabalho','national'),
  ('2027-09-07','Independência do Brasil','national'),
  ('2027-10-12','Nossa Senhora Aparecida','national'),
  ('2027-11-02','Finados','national'),
  ('2027-11-15','Proclamação da República','national'),
  ('2027-11-20','Dia da Consciência Negra','national'),
  ('2027-12-25','Natal','national'),
  ('2028-01-01','Confraternização Universal','national'),
  ('2028-04-21','Tiradentes','national'),
  ('2028-05-01','Dia do Trabalho','national'),
  ('2028-09-07','Independência do Brasil','national'),
  ('2028-10-12','Nossa Senhora Aparecida','national'),
  ('2028-11-02','Finados','national'),
  ('2028-11-15','Proclamação da República','national'),
  ('2028-11-20','Dia da Consciência Negra','national'),
  ('2028-12-25','Natal','national'),
  ('2029-01-01','Confraternização Universal','national'),
  ('2029-04-21','Tiradentes','national'),
  ('2029-05-01','Dia do Trabalho','national'),
  ('2029-09-07','Independência do Brasil','national'),
  ('2029-10-12','Nossa Senhora Aparecida','national'),
  ('2029-11-02','Finados','national'),
  ('2029-11-15','Proclamação da República','national'),
  ('2029-11-20','Dia da Consciência Negra','national'),
  ('2029-12-25','Natal','national'),
  ('2030-01-01','Confraternização Universal','national'),
  ('2030-04-21','Tiradentes','national'),
  ('2030-05-01','Dia do Trabalho','national'),
  ('2030-09-07','Independência do Brasil','national'),
  ('2030-10-12','Nossa Senhora Aparecida','national'),
  ('2030-11-02','Finados','national'),
  ('2030-11-15','Proclamação da República','national'),
  ('2030-11-20','Dia da Consciência Negra','national'),
  ('2030-12-25','Natal','national'),
  -- Sexta-feira Santa (Good Friday) — statutory national, Easter-2
  ('2025-04-18','Sexta-feira Santa','national'),
  ('2026-04-03','Sexta-feira Santa','national'),
  ('2027-03-26','Sexta-feira Santa','national'),
  ('2028-04-14','Sexta-feira Santa','national'),
  ('2029-03-30','Sexta-feira Santa','national'),
  ('2030-04-19','Sexta-feira Santa','national'),
  -- GO/Goiânia: Carnaval (segunda) — Easter-48
  ('2025-03-03','Carnaval (segunda)','GO'),
  ('2026-02-16','Carnaval (segunda)','GO'),
  ('2027-02-08','Carnaval (segunda)','GO'),
  ('2028-02-28','Carnaval (segunda)','GO'),
  ('2029-02-12','Carnaval (segunda)','GO'),
  ('2030-03-04','Carnaval (segunda)','GO'),
  -- GO/Goiânia: Carnaval (terça) — Easter-47
  ('2025-03-04','Carnaval (terça)','GO'),
  ('2026-02-17','Carnaval (terça)','GO'),
  ('2027-02-09','Carnaval (terça)','GO'),
  ('2028-02-29','Carnaval (terça)','GO'),
  ('2029-02-13','Carnaval (terça)','GO'),
  ('2030-03-05','Carnaval (terça)','GO'),
  -- GO/Goiânia: Corpus Christi — Easter+60
  ('2025-06-19','Corpus Christi','GO'),
  ('2026-06-04','Corpus Christi','GO'),
  ('2027-05-27','Corpus Christi','GO'),
  ('2028-06-15','Corpus Christi','GO'),
  ('2029-05-31','Corpus Christi','GO'),
  ('2030-06-20','Corpus Christi','GO'),
  -- GO/Goiânia: Aniversário de Goiânia
  ('2025-10-24','Aniversário de Goiânia','GO'),
  ('2026-10-24','Aniversário de Goiânia','GO'),
  ('2027-10-24','Aniversário de Goiânia','GO'),
  ('2028-10-24','Aniversário de Goiânia','GO'),
  ('2029-10-24','Aniversário de Goiânia','GO'),
  ('2030-10-24','Aniversário de Goiânia','GO')
ON CONFLICT (holiday_date) DO NOTHING;

-- ---------------------------------------------------------------------
-- 4. add_business_days / business_days_between — STABLE (read br_holidays),
--    NOT IMMUTABLE (§9.2) → never usable in GENERATED/DEFAULT; downstream PRs
--    compute deadlines in RPC at INSERT time. TZ-aware (America/Sao_Paulo, no
--    DST since 2019). Excludes weekends + ALL br_holidays (sede=GO calendar).
--    RAISE WARNING past 2025–2030 coverage so post-2030 gaps are loud, not silent.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_business_days(p_start timestamptz, p_days int)
 RETURNS timestamptz
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tz   constant text := 'America/Sao_Paulo';
  v_local timestamp := p_start AT TIME ZONE v_tz;   -- wall-clock at sede
  v_date date := v_local::date;
  v_time time := v_local::time;
  v_remaining int := abs(p_days);
  v_step int := sign(p_days)::int;
BEGIN
  WHILE v_remaining > 0 LOOP
    v_date := v_date + v_step;
    IF EXTRACT(ISODOW FROM v_date) < 6
       AND NOT EXISTS (SELECT 1 FROM public.br_holidays h WHERE h.holiday_date = v_date) THEN
      v_remaining := v_remaining - 1;
    END IF;
  END LOOP;
  IF v_date > DATE '2030-12-31' OR v_date < DATE '2025-01-01' THEN
    RAISE WARNING 'add_business_days: result % is outside br_holidays coverage (2025-2030); holidays past coverage were NOT observed — extend br_holidays', v_date;
  END IF;
  RETURN (v_date + v_time) AT TIME ZONE v_tz;
END;
$function$;
COMMENT ON FUNCTION public.add_business_days(timestamptz,int) IS
  '#571 Camada 5 PR-1: advance p_start by N Brazilian business days (skips weekends + ALL br_holidays, sede=GO calendar). '
  'STABLE — never use in GENERATED/DEFAULT; compute in RPC at write time (§9.2). p_days may be negative. '
  'WARNs past 2025–2030 coverage.';

CREATE OR REPLACE FUNCTION public.business_days_between(p_from timestamptz, p_to timestamptz)
 RETURNS int
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tz constant text := 'America/Sao_Paulo';
  v_from date := (p_from AT TIME ZONE v_tz)::date;
  v_to   date := (p_to   AT TIME ZONE v_tz)::date;
  v_lo date := least(v_from, v_to);
  v_hi date := greatest(v_from, v_to);
  v_cur date := v_lo;
  v_count int := 0;
BEGIN
  WHILE v_cur < v_hi LOOP
    v_cur := v_cur + 1;
    IF EXTRACT(ISODOW FROM v_cur) < 6
       AND NOT EXISTS (SELECT 1 FROM public.br_holidays h WHERE h.holiday_date = v_cur) THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;
  IF v_hi > DATE '2030-12-31' OR v_lo < DATE '2025-01-01' THEN
    RAISE WARNING 'business_days_between: range [%, %] is outside br_holidays coverage (2025-2030); holidays past coverage were NOT observed — extend br_holidays', v_lo, v_hi;
  END IF;
  RETURN CASE WHEN v_to < v_from THEN -v_count ELSE v_count END;
END;
$function$;
COMMENT ON FUNCTION public.business_days_between(timestamptz,timestamptz) IS
  '#571 Camada 5 PR-1: signed count of Brazilian business days in (from, to] (sede=GO calendar). STABLE. WARNs past 2025–2030 coverage.';

GRANT EXECUTE ON FUNCTION public.add_business_days(timestamptz,int) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.business_days_between(timestamptz,timestamptz) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 5. map_cr_type_to_change_class — explicit, documented mapping helper.
--    NULL/unknown → NULL (unresolved; caller MUST classify, never default).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.map_cr_type_to_change_class(p_cr_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_cr_type
    WHEN 'editorial'   THEN 'editorial'
    WHEN 'operational' THEN 'material'
    WHEN 'structural'  THEN 'material'
    WHEN 'emergency'   THEN 'material'
    ELSE NULL  -- NULL or unknown cr_type → unresolved; human resolves (never defaulted)
  END;
$function$;
COMMENT ON FUNCTION public.map_cr_type_to_change_class(text) IS
  '#571 Camada 5 PR-1: change_requests.cr_type → document_versions.change_class. '
  'editorial→editorial; operational/structural/emergency→material; NULL/unknown→NULL (unresolved, never defaulted).';
GRANT EXECUTE ON FUNCTION public.map_cr_type_to_change_class(text) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 6. lock_document_version — add p_change_class (BACKWARD-COMPATIBLE).
--    DROP+CREATE (arg-count change, GC-097). Old 2-arg calls resolve via the
--    DEFAULT NULL (no RAISE on NULL ⇒ behavior-neutral for the live frontend/MCP).
--    change_class persisted at lock; precedence: explicit param > pre-set draft
--    value. Validated when present. Body otherwise verbatim from the live p269
--    function (20260805000048). ACL replicated to match the current live grants.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.lock_document_version(uuid, jsonb);

CREATE OR REPLACE FUNCTION public.lock_document_version(p_version_id uuid, p_gates jsonb, p_change_class text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_version record;
  v_chain_id uuid;
  v_existing_chain uuid;
  v_notif_count int;
  v_class text;
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_member') THEN
    RAISE EXCEPTION 'Access denied: manage_member required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- include dv.change_class so COALESCE below sees a pre-set draft classification
  SELECT dv.id, dv.document_id, dv.organization_id, dv.version_number, dv.version_label, dv.locked_at, dv.change_class
  INTO v_version
  FROM public.document_versions dv WHERE dv.id = p_version_id;

  IF v_version.id IS NULL THEN
    RAISE EXCEPTION 'document_version not found (id=%)', p_version_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_version.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'document_version already locked at % — create a new version instead', v_version.locked_at
      USING ERRCODE = 'check_violation';
  END IF;

  -- #571 Camada 5 PR-1: resolve change_class (Material/Editorial). Precedence:
  -- explicit param > value pre-set on the draft. Validate when present; never default.
  -- NULL allowed (backward-compat); UI lock modal requires a deliberate choice.
  v_class := COALESCE(p_change_class, v_version.change_class);
  IF v_class IS NOT NULL AND v_class NOT IN ('editorial','material') THEN
    RAISE EXCEPTION 'change_class must be editorial or material (got %)', v_class
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_gates IS NULL OR jsonb_typeof(p_gates) <> 'array' OR jsonb_array_length(p_gates) = 0 THEN
    RAISE EXCEPTION 'gates must be a non-empty jsonb array' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_gates) g
    WHERE NOT (g ? 'kind' AND g ? 'order' AND g ? 'threshold')
  ) THEN
    RAISE EXCEPTION 'each gate must have kind, order, threshold keys' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT ac.id INTO v_existing_chain
  FROM public.approval_chains ac
  WHERE ac.version_id = p_version_id LIMIT 1;
  IF v_existing_chain IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'chain_already_exists',
      'chain_id', v_existing_chain,
      'version_id', p_version_id
    );
  END IF;

  UPDATE public.document_versions
    SET locked_at = now(),
        locked_by = v_member.id,
        published_at = now(),
        published_by = v_member.id,
        change_class = v_class,
        updated_at = now()
    WHERE id = p_version_id;

  INSERT INTO public.approval_chains (
    document_id, version_id, organization_id, status, gates, opened_at, opened_by
  ) VALUES (
    v_version.document_id, p_version_id, v_version.organization_id, 'review', p_gates, now(), v_member.id
  ) RETURNING id INTO v_chain_id;

  UPDATE public.governance_documents
    SET current_version_id = p_version_id,
        updated_at = now()
    WHERE id = v_version.document_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (
    v_member.id, 'document_version.locked', 'document_version', p_version_id,
    jsonb_build_object(
      'document_id', v_version.document_id,
      'version_number', v_version.version_number,
      'version_label', v_version.version_label,
      'chain_id', v_chain_id,
      'change_class', v_class,
      'gates', p_gates
    )
  );

  v_notif_count := public._enqueue_gate_notifications(v_chain_id, 'chain_opened', NULL);

  RETURN jsonb_build_object(
    'success', true,
    'version_id', p_version_id,
    'chain_id', v_chain_id,
    'change_class', v_class,
    'notifications_enqueued', v_notif_count,
    'locked_at', now()
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.lock_document_version(uuid, jsonb, text) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 7. Data hygiene: reconcile governance_documents.version ← current version
--    label, ONLY for stale draft-markers (NULL or '%draft%'). Targets the 6
--    lying rows (Política/Termo/addenda/Anexo read 'v2.3-adr0068-draft'/NULL)
--    while leaving clean labels (R2, v1.0, R3-C3, v2.2, R00) untouched — those
--    have cert-PDF literal deps (src/lib/certificates/pdf.ts). Frontend reads
--    document_versions.version_label, NOT gd.version, so this is safe.
--    NOTE: the predicate matches 7 governance_documents, but the INNER JOIN on
--    current_version_id + IS DISTINCT guard narrows the UPDATE to 6; the manual
--    row 'R3-DRAFT' (current_version_id IS NULL) stays a residual stale marker
--    (no published version to promote to). pdf.ts's gd.version fallback footer
--    for the 6 reconciled docs now shows the accurate current label (stale→correct).
-- ---------------------------------------------------------------------
UPDATE public.governance_documents gd
SET version = dv.version_label,
    updated_at = now()
FROM public.document_versions dv
WHERE dv.id = gd.current_version_id
  AND (gd.version IS NULL OR gd.version ILIKE '%draft%')
  AND gd.version IS DISTINCT FROM dv.version_label;

-- reload PostgREST schema cache (new columns + lock_document_version signature)
NOTIFY pgrst, 'reload schema';

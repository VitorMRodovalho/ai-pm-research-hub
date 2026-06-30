-- =====================================================================
-- #974 (PR-2 of #571) — Camada 5 Material-change backbone: VERSION PIN
-- (WA3 — Termo 15.4.1 / vedação de remissão dinâmica).
--
-- SSOT do pin instrumento->versão. Veda remissão dinâmica ("Política
-- vigente" = estado vivo) por construção (pinned_version_id NOT NULL,
-- referência dura a document_versions.id). Editorial auto-aplica
-- (append-only); Material exige re-âncora expressa.
--
-- BEHAVIOR-NEUTRAL / dormant: a tabela + RPCs + trigger ficam prontos;
-- o único efeito observável é o backfill dos 4 acordos bilaterais (4 pins
-- ANTECIPATÓRIOS que fixam o head vigente da Política, pré-ratificação do
-- Adendo) + 1 invariante novo (AN, gated em Adendo ratificado => dormente hoje).
-- SPEC docs/specs/SPEC_571_CAMADA5_MATERIAL_CHANGE.md §5 PR-2 + §9.3. ADR-0114.
--
-- GROUNDING (este turno, ao vivo) — corrige a premissa de backfill da SPEC §9.3:
--   * Os 4 acordos bilaterais ATIVOS (PMI-GO<->CE/DF/MG/RS) foram assinados em
--     DEZ/2025 e ratificados por chain sintética p257 (member_ratification /
--     acknowledge, referenced_policy_version_id = NULL). NÃO há president_go,
--     então a query canônica de §9.3 (president_go -> referenced_policy_version_id)
--     retorna NULL para os 4 — é inimplementável.
--   * Os corpos dos 4 acordos NÃO citam a Política nem "vigente". O instrumento
--     que carrega a remissão dinâmica ("a Política de Governança de PI vigente")
--     é o Adendo de PI aos Acordos de Cooperação (doc_type=cooperation_addendum,
--     "Aplica-se aos 4 acordos bilaterais"), hoje under_review (NÃO ratificado).
--   * A 1ª versão LACRADA da Política é de abr/2026 (v2.1); os acordos são de
--     dez/2025 => "versão na data de assinatura" NÃO EXISTE.
--   * DECISÃO PM (AskUserQuestion, 2026-06-30): backfill = 4 bindings (cada
--     acordo->Política), pin = HEAD vigente da Política (v2.7-p128, 8f4337e6) —
--     o valor que a remissão dinâmica do Adendo RESOLVERÁ após a ratificação. O
--     pin é ANTECIPATÓRIO (nenhuma obrigação contratual aos acordantes até a
--     ratificação do Adendo); quando a Política ratificar (possível versão
--     posterior), o trigger material marca re_anchor_required e o GP re-ancora
--     expressamente via reanchor_instrument_binding citando o ato de ratificação.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. instrument_version_bindings — SSOT do pin instrumento->versão.
--    pinned_version_id NOT NULL = vedação de remissão dinâmica por construção.
--    NÃO ligada a initiatives => invariante AJ (#785) não se aplica; sem
--    necessidade de policy RESTRICTIVE rls_can_see_initiative.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.instrument_version_bindings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  bound_document_id uuid NOT NULL REFERENCES public.governance_documents(id) ON DELETE RESTRICT,
  referenced_document_id uuid NOT NULL REFERENCES public.governance_documents(id) ON DELETE RESTRICT,
  pinned_version_id uuid NOT NULL REFERENCES public.document_versions(id) ON DELETE RESTRICT,
  pin_clause_ref text,
  re_anchor_required boolean NOT NULL DEFAULT false,
  last_material_version_id uuid REFERENCES public.document_versions(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','superseded')),
  bound_at timestamptz NOT NULL DEFAULT now(),
  bound_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  superseded_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ivb_referenced_not_bound CHECK (referenced_document_id <> bound_document_id)
);

COMMENT ON TABLE public.instrument_version_bindings IS
  '#974 Camada 5 PR-2 (WA3): SSOT do pin instrumento->versão. pinned_version_id NOT NULL '
  'veda remissão dinâmica ("Política vigente") por construção. Append-only: editorial auto-advance '
  '(trg_propagate_version_change_class) e re-âncora (reanchor_instrument_binding) inserem nova row '
  '+ supersede a antiga (status=superseded), nunca UPDATE in-place do pin. ADR-0114 / amenda ADR-0016.';
COMMENT ON COLUMN public.instrument_version_bindings.pinned_version_id IS
  'Referência DURA a document_versions.id (nunca label/texto). NOT NULL = sem remissão dinâmica.';
COMMENT ON COLUMN public.instrument_version_bindings.re_anchor_required IS
  'Setado para TRUE pelo trigger quando o instrumento referenciado sofre Material change; '
  'limpo SÓ por reanchor_instrument_binding (re-âncora expressa, Termo 15.4.1).';
COMMENT ON COLUMN public.instrument_version_bindings.last_material_version_id IS
  'A versão material que disparou re_anchor_required (alvo sugerido da re-âncora).';

-- UNIQUE parcial via statement separado (PG não aceita UNIQUE(...) WHERE inline — §9.3).
CREATE UNIQUE INDEX IF NOT EXISTS ivb_active_unique
  ON public.instrument_version_bindings(bound_document_id, referenced_document_id)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS ivb_referenced_active
  ON public.instrument_version_bindings(referenced_document_id)
  WHERE status = 'active';

-- RLS (GC-162): non-PII governance config. Read = manage_platform (GP-level);
-- nenhuma policy de escrita => writes só via SECURITY DEFINER RPCs / service_role / migration.
ALTER TABLE public.instrument_version_bindings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ivb_select_admin ON public.instrument_version_bindings;
CREATE POLICY ivb_select_admin ON public.instrument_version_bindings
  FOR SELECT TO authenticated
  USING (public.rls_can('manage_platform'));

-- ---------------------------------------------------------------------
-- 2. RPCs (todos SECURITY DEFINER, REVOKE de PUBLIC/anon/authenticated — §9.1).
--    Gate uniforme manage_platform (read e write) — alinhado à RLS SELECT,
--    sem assimetria de privilégio através da fronteira SECDEF.
-- ---------------------------------------------------------------------

-- 2a. pin_instrument_version: cria/atualiza o pin ativo de um par
--     (bound, referenced). Valida que a versão pertence ao referenced e
--     está LACRADA (pin duro não aponta para rascunho). Append-only: supersede
--     o ativo anterior do par, insere o novo ativo.
CREATE OR REPLACE FUNCTION public.pin_instrument_version(
  p_bound_document_id uuid,
  p_referenced_document_id uuid,
  p_pinned_version_id uuid,
  p_pin_clause_ref text DEFAULT NULL
) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_bound record;
  v_ref record;
  v_ver record;
  v_existing uuid;
  v_new_id uuid;
BEGIN
  SELECT m.id, m.name INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_bound_document_id = p_referenced_document_id THEN
    RAISE EXCEPTION 'bound and referenced documents must differ' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT gd.id, gd.organization_id INTO v_bound FROM public.governance_documents gd WHERE gd.id = p_bound_document_id;
  IF v_bound.id IS NULL THEN RAISE EXCEPTION 'bound document not found (id=%)', p_bound_document_id USING ERRCODE = 'no_data_found'; END IF;

  SELECT gd.id, gd.organization_id INTO v_ref FROM public.governance_documents gd WHERE gd.id = p_referenced_document_id;
  IF v_ref.id IS NULL THEN RAISE EXCEPTION 'referenced document not found (id=%)', p_referenced_document_id USING ERRCODE = 'no_data_found'; END IF;

  IF v_bound.organization_id IS DISTINCT FROM v_ref.organization_id THEN
    RAISE EXCEPTION 'bound and referenced documents belong to different organizations' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- pinned version must belong to the referenced document AND be locked (hard pin, never a draft)
  SELECT dv.id, dv.document_id, dv.locked_at INTO v_ver FROM public.document_versions dv WHERE dv.id = p_pinned_version_id;
  IF v_ver.id IS NULL THEN RAISE EXCEPTION 'pinned version not found (id=%)', p_pinned_version_id USING ERRCODE = 'no_data_found'; END IF;
  IF v_ver.document_id IS DISTINCT FROM p_referenced_document_id THEN
    RAISE EXCEPTION 'pinned version % does not belong to referenced document %', p_pinned_version_id, p_referenced_document_id
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_ver.locked_at IS NULL THEN
    RAISE EXCEPTION 'pinned version must be locked (a hard pin cannot reference an unlocked draft)' USING ERRCODE = 'check_violation';
  END IF;

  -- append-only: supersede the existing active binding for this (bound, referenced) pair
  SELECT id INTO v_existing FROM public.instrument_version_bindings
    WHERE bound_document_id = p_bound_document_id AND referenced_document_id = p_referenced_document_id AND status = 'active'
    FOR UPDATE;
  IF v_existing IS NOT NULL THEN
    UPDATE public.instrument_version_bindings
      SET status = 'superseded', superseded_at = now(), updated_at = now()
      WHERE id = v_existing;
  END IF;

  INSERT INTO public.instrument_version_bindings
    (organization_id, bound_document_id, referenced_document_id, pinned_version_id, pin_clause_ref, status, re_anchor_required, bound_at, bound_by)
  VALUES (v_bound.organization_id, p_bound_document_id, p_referenced_document_id, p_pinned_version_id, p_pin_clause_ref, 'active', false, now(), v_member.id)
  RETURNING id INTO v_new_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'instrument_binding.pinned', 'instrument_version_bindings', v_new_id,
    jsonb_build_object('bound_document_id', p_bound_document_id, 'referenced_document_id', p_referenced_document_id,
                       'pinned_version_id', p_pinned_version_id, 'superseded_binding', v_existing));

  RETURN jsonb_build_object('success', true, 'binding_id', v_new_id, 'superseded_binding', v_existing);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.pin_instrument_version(uuid,uuid,uuid,text) FROM PUBLIC, anon, authenticated;

-- 2b. reanchor_instrument_binding: ÚNICO caminho que limpa re_anchor_required.
--     SELECT ... FOR UPDATE na binding antiga (evita 2 ativas — §9.3). Append-only.
--     Exige avanço do pin (não confirma a versão atual — Termo 15.4.1 re-âncora expressa).
CREATE OR REPLACE FUNCTION public.reanchor_instrument_binding(
  p_binding_id uuid,
  p_new_version_id uuid,
  p_justification text
) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_old record;
  v_ver record;
  v_new_id uuid;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_justification IS NULL OR length(btrim(p_justification)) < 10 THEN
    RAISE EXCEPTION 're-anchor justification (>=10 chars) required' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- lock the old binding row to serialize concurrent re-anchors (no two active rows for a pair)
  SELECT * INTO v_old FROM public.instrument_version_bindings WHERE id = p_binding_id FOR UPDATE;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'binding not found (id=%)', p_binding_id USING ERRCODE = 'no_data_found'; END IF;
  IF v_old.status <> 'active' THEN
    RAISE EXCEPTION 'binding is not active (status=%) — re-anchor the current active binding', v_old.status USING ERRCODE = 'check_violation';
  END IF;
  IF p_new_version_id = v_old.pinned_version_id THEN
    RAISE EXCEPTION 're-anchor must advance the pin; new_version_id equals the current pinned_version_id (Termo 15.4.1 — re-âncora expressa à nova versão material)'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT dv.id, dv.document_id, dv.locked_at INTO v_ver FROM public.document_versions dv WHERE dv.id = p_new_version_id;
  IF v_ver.id IS NULL THEN RAISE EXCEPTION 'new version not found (id=%)', p_new_version_id USING ERRCODE = 'no_data_found'; END IF;
  IF v_ver.document_id IS DISTINCT FROM v_old.referenced_document_id THEN
    RAISE EXCEPTION 'new version % does not belong to referenced document %', p_new_version_id, v_old.referenced_document_id
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_ver.locked_at IS NULL THEN
    RAISE EXCEPTION 'new version must be locked' USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.instrument_version_bindings
    SET status = 'superseded', superseded_at = now(), updated_at = now()
    WHERE id = v_old.id;

  INSERT INTO public.instrument_version_bindings
    (organization_id, bound_document_id, referenced_document_id, pinned_version_id, pin_clause_ref,
     status, re_anchor_required, last_material_version_id, bound_at, bound_by, notes)
  VALUES (v_old.organization_id, v_old.bound_document_id, v_old.referenced_document_id, p_new_version_id, v_old.pin_clause_ref,
     'active', false, NULL, now(), v_member.id, p_justification)
  RETURNING id INTO v_new_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_member.id, 'instrument_binding.reanchored', 'instrument_version_bindings', v_new_id,
    jsonb_build_object('superseded_binding', v_old.id, 'old_pin', v_old.pinned_version_id, 'new_pin', p_new_version_id, 'justification', p_justification));

  RETURN jsonb_build_object('success', true, 'binding_id', v_new_id, 'superseded_binding', v_old.id,
                            'old_pin', v_old.pinned_version_id, 'new_pin', p_new_version_id);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.reanchor_instrument_binding(uuid,uuid,text) FROM PUBLIC, anon, authenticated;

-- 2c. list_stale_instrument_bindings: read p/ dashboard (par com get_version_diff(pinned, current)).
--     Gate manage_platform (alinhado à RLS + writes). Lista bindings ativos que
--     precisam de atenção: re_anchor_required OU pin atrás da versão corrente.
--     is_behind NULL-safe quando o referenced não tem current_version_id lacrado.
CREATE OR REPLACE FUNCTION public.list_stale_instrument_bindings()
RETURNS TABLE(
  binding_id uuid,
  bound_document_id uuid,
  bound_title text,
  referenced_document_id uuid,
  referenced_title text,
  pinned_version_id uuid,
  pinned_version_label text,
  current_version_id uuid,
  current_version_label text,
  re_anchor_required boolean,
  last_material_version_id uuid,
  is_behind boolean,
  pin_clause_ref text,
  bound_at timestamptz
)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
BEGIN
  SELECT m.id INTO v_member FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_member.id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NOT public.can_by_member(v_member.id, 'manage_platform') THEN
    RAISE EXCEPTION 'Access denied: manage_platform required' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  SELECT ivb.id,
         ivb.bound_document_id, bd.title,
         ivb.referenced_document_id, rd.title,
         ivb.pinned_version_id, pv.version_label,
         rd.current_version_id, cv.version_label,
         ivb.re_anchor_required,
         ivb.last_material_version_id,
         CASE WHEN rd.current_version_id IS NULL THEN NULL
              ELSE (ivb.pinned_version_id IS DISTINCT FROM rd.current_version_id) END AS is_behind,
         ivb.pin_clause_ref,
         ivb.bound_at
  FROM public.instrument_version_bindings ivb
  JOIN public.governance_documents bd ON bd.id = ivb.bound_document_id
  JOIN public.governance_documents rd ON rd.id = ivb.referenced_document_id
  LEFT JOIN public.document_versions pv ON pv.id = ivb.pinned_version_id
  LEFT JOIN public.document_versions cv ON cv.id = rd.current_version_id
  WHERE ivb.status = 'active'
    AND (ivb.re_anchor_required = true OR ivb.pinned_version_id IS DISTINCT FROM rd.current_version_id)
  ORDER BY ivb.re_anchor_required DESC, bd.title;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.list_stale_instrument_bindings() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. trg_propagate_version_change_class — propaga a classificação de uma
--    NOVA versão lacrada do instrumento REFERENCIADO para seus bindings ativos.
--    editorial => append-only auto-advance do pin (§4.1) + audit; material => seta
--    re_anchor_required (NÃO move o pin — re-âncora é ato humano expresso) + audit.
--    Trigger com WHEN (transição de lock + change_class resolvido) — evita a frame
--    PL/pgSQL em toda UPDATE de rascunho. Editorial loop usa FOR UPDATE (serializa
--    locks editoriais concorrentes p/ o mesmo referenced — evita violação do índice
--    parcial único). SECURITY DEFINER: escreve em instrument_version_bindings
--    (RLS sem policy de escrita) e em admin_audit_log (ciência 12.3, actor_id NULL=sistema).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_propagate_version_change_class()
 RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  r record;
  v_new_id uuid;
  v_flagged uuid[];
BEGIN
  -- defense-in-depth (the trigger WHEN already gates this); NULL class = non-material fail-safe (ADR-0113)
  IF NOT (OLD.locked_at IS NULL AND NEW.locked_at IS NOT NULL) THEN
    RETURN NEW;
  END IF;
  IF NEW.change_class IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.change_class = 'editorial' THEN
    -- editorial: append-only auto-advance of every active binding referencing this document.
    -- FOR UPDATE serializes concurrent editorial-advance triggers for the same referenced doc.
    FOR r IN
      SELECT * FROM public.instrument_version_bindings
       WHERE referenced_document_id = NEW.document_id AND status = 'active'
       FOR UPDATE
    LOOP
      -- supersede first (keeps the partial unique index at <=1 active per pair), then insert advanced row
      UPDATE public.instrument_version_bindings
         SET status = 'superseded', superseded_at = now(), updated_at = now()
       WHERE id = r.id;
      INSERT INTO public.instrument_version_bindings
        (organization_id, bound_document_id, referenced_document_id, pinned_version_id, pin_clause_ref,
         status, re_anchor_required, last_material_version_id, bound_at, bound_by, notes)
      VALUES (r.organization_id, r.bound_document_id, r.referenced_document_id, NEW.id, r.pin_clause_ref,
         'active', false, r.last_material_version_id, now(), NULL,
         'auto-advanced: editorial change of referenced instrument (§4.1 append-only; #974 PR-2)')
      RETURNING id INTO v_new_id;
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (NULL, 'instrument_binding.auto_advanced', 'instrument_version_bindings', v_new_id,
        jsonb_build_object('superseded_binding', r.id, 'old_pin', r.pinned_version_id, 'new_pin', NEW.id,
                           'referenced_document_id', NEW.document_id, 'change_class', 'editorial'));
    END LOOP;
  ELSIF NEW.change_class = 'material' THEN
    -- material: flag re-anchor on every active binding; do NOT move the pin (express re-anchor only).
    WITH upd AS (
      UPDATE public.instrument_version_bindings
         SET re_anchor_required = true, last_material_version_id = NEW.id, updated_at = now()
       WHERE referenced_document_id = NEW.document_id AND status = 'active'
      RETURNING id
    )
    SELECT array_agg(id) INTO v_flagged FROM upd;
    IF v_flagged IS NOT NULL AND array_length(v_flagged, 1) > 0 THEN
      INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
      VALUES (NULL, 'instrument_binding.material_reanchor_flagged', 'document_version', NEW.id,
        jsonb_build_object('referenced_document_id', NEW.document_id, 'material_version_id', NEW.id,
                           'flagged_bindings', to_jsonb(v_flagged)));
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_propagate_version_change_class ON public.document_versions;
CREATE TRIGGER trg_propagate_version_change_class
  AFTER UPDATE OF locked_at, change_class ON public.document_versions
  FOR EACH ROW
  WHEN (OLD.locked_at IS NULL AND NEW.locked_at IS NOT NULL AND NEW.change_class IS NOT NULL)
  EXECUTE FUNCTION public.trg_propagate_version_change_class();

-- ---------------------------------------------------------------------
-- 4. Backfill (MESMA migration — §9.3): os 4 acordos bilaterais ATIVOS pinam
--    a Política (head vigente). ANTECIPATÓRIO / pré-ratificação do Adendo.
--    Idempotente (NOT EXISTS) + self-verifying (guard escopado ao domínio coop->policy).
--    Pin = pol.current_version_id (= v2.7-p128 8f4337e6 hoje). Derivado por
--    doc_type/status (sem hardcode de UUID gerado).
-- ---------------------------------------------------------------------
INSERT INTO public.instrument_version_bindings
  (organization_id, bound_document_id, referenced_document_id, pinned_version_id, pin_clause_ref, status, re_anchor_required, bound_at, bound_by)
SELECT agr.organization_id, agr.id, pol.id, pol.current_version_id,
  'Registro preventivo (pré-ratificação do Adendo). O Adendo de PI aos Acordos de Cooperação (cooperation_addendum, under_review em 2026-06-30) PROPÕE vincular os 4 acordos bilaterais (PMI-GO<->CE/DF/MG/RS) à Política de Governança de PI; os acordos (assinados dez/2025) precedem a 1ª versão lacrada da Política (abr/2026) e NÃO a citam em seus corpos — o vínculo depende da ratificação formal do Adendo. Pin ANTECIPATÓRIO: fixa o head vigente da Política (v2.7-p128) para re-âncora expressa via reanchor_instrument_binding ao ratificar. Nenhuma obrigação contratual aos acordantes até a ratificação. #974 PR-2 / decisão PM 2026-06-30.',
  'active', false, now(), NULL
FROM public.governance_documents agr
CROSS JOIN public.governance_documents pol
JOIN public.document_versions pv ON pv.id = pol.current_version_id AND pv.locked_at IS NOT NULL
WHERE agr.doc_type = 'cooperation_agreement' AND agr.status = 'active'
  AND pol.doc_type = 'policy'
  AND agr.organization_id = pol.organization_id
  AND NOT EXISTS (
    SELECT 1 FROM public.instrument_version_bindings ivb
    WHERE ivb.bound_document_id = agr.id AND ivb.referenced_document_id = pol.id AND ivb.status = 'active'
  );

DO $do$
DECLARE
  v_policy_locked int;
  v_active int;
BEGIN
  SELECT count(*) INTO v_policy_locked
    FROM public.governance_documents pol
    JOIN public.document_versions pv ON pv.id = pol.current_version_id AND pv.locked_at IS NOT NULL
    WHERE pol.doc_type = 'policy';
  IF v_policy_locked <> 1 THEN
    RAISE EXCEPTION '#974 PR-2 backfill: expected exactly 1 policy doc with a locked current version, found %', v_policy_locked;
  END IF;

  -- scope the guard to the backfill's own domain (cooperation_agreement->policy active pairs)
  SELECT count(*) INTO v_active
    FROM public.instrument_version_bindings ivb
    JOIN public.governance_documents agr ON agr.id = ivb.bound_document_id
    JOIN public.governance_documents pol ON pol.id = ivb.referenced_document_id
    WHERE ivb.status = 'active'
      AND agr.doc_type = 'cooperation_agreement' AND agr.status = 'active'
      AND pol.doc_type = 'policy';
  IF v_active <> 4 THEN
    RAISE EXCEPTION '#974 PR-2 backfill: expected 4 active cooperation_agreement->policy bindings, found %', v_active;
  END IF;
END;
$do$;

-- ---------------------------------------------------------------------
-- 5. check_schema_invariants() + AN_no_dynamic_remission_cooperation (§9.3:
--    invariante adicionado na MESMA migration). Função reproduzida da captura
--    live (mig 20260805000292, sem drift) com o branch AN anexado antes do END.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_schema_invariants()
 RETURNS TABLE(invariant_name text, description text, severity text, violation_count integer, sample_ids uuid[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NULL
     AND current_setting('role', true) NOT IN ('service_role', 'postgres')
     AND current_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Unauthorized: check_schema_invariants requires authentication';
  END IF;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'alumni' AND operational_role IS DISTINCT FROM 'alumni'
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A1_alumni_role_consistency'::text,
         'member_status=alumni must coerce operational_role=alumni (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status = 'observer' AND operational_role NOT IN ('observer','guest','none')
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'A2_observer_role_consistency'::text,
         'member_status=observer must coerce operational_role IN (observer,guest,none) (B7 trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH computed AS (
    SELECT m.id AS member_id,
      CASE
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'manager')        THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'co_gp')          THEN 'manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role = 'deputy_manager') THEN 'deputy_manager'
        WHEN bool_or(ae.kind = 'volunteer' AND ae.role IN ('leader','comms_leader')) THEN 'tribe_leader'
        -- Wave 1 fix: sponsor outranks researcher (committee/workgroup) so a sponsor who also sits on a
        -- committee (e.g. the governance committee) shows as a sponsor, not a researcher.
        WHEN bool_or(ae.kind = 'sponsor') THEN 'sponsor'
        -- Wave 2 WS-1 (PM 2026-06-28 'governança vence'): chapter_board (chapter director) outranks
        -- researcher/observer so a chapter director who also sits on a committee or observes a
        -- tribe still shows as 'Ponto Focal do Capítulo' (chapter_liaison). Stays BELOW sponsor
        -- and operational leaders (manager/deputy/tribe_leader) — those who lead operationally keep that role.
        WHEN bool_or(ae.kind = 'chapter_board') THEN 'chapter_liaison'
        WHEN bool_or(
          (ae.kind = 'volunteer' AND ae.role IN ('researcher','facilitator','communicator','curator'))
          OR (ae.kind IN ('committee_member','workgroup_member','study_group_owner')
              AND ae.role IN ('leader','co_leader','owner','coordinator','researcher','contributor','member','participant'))
          OR (ae.kind IN ('committee_coordinator','workgroup_coordinator')
              AND ae.role IN ('leader','co_leader','owner','coordinator'))
        ) THEN 'researcher'
        WHEN bool_or(ae.kind = 'external_signer') THEN 'external_signer'
        WHEN bool_or(ae.kind = 'institutional_auditor') THEN 'institutional_auditor'
        WHEN bool_or(ae.kind = 'observer') THEN 'observer'
        WHEN bool_or(ae.kind = 'alumni') THEN 'alumni'
        WHEN bool_or(ae.kind = 'candidate') THEN 'candidate'
        ELSE 'guest'
      END AS expected_role
    FROM public.members m
    LEFT JOIN public.auth_engagements ae ON ae.person_id = m.person_id AND ae.is_authoritative = true
    WHERE m.member_status='active' AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT c.member_id FROM computed c
    JOIN public.members m ON m.id = c.member_id
    WHERE m.operational_role IS DISTINCT FROM c.expected_role
  )
  SELECT 'A3_active_role_engagement_derivation'::text,
         'active member operational_role must equal priority-ladder derivation from active engagements (cache trigger)'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE ((member_status='active' AND is_active=false) OR (member_status IN ('observer','alumni','inactive') AND is_active=true))
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B_is_active_status_mismatch'::text,
         'members.is_active must match member_status mapping (active=true, terminal=false)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND designations IS NOT NULL AND array_length(designations,1)>0
  )
  SELECT 'C_designations_in_terminal_status'::text,
         'members.designations must be empty when member_status is observer/alumni/inactive'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    JOIN public.persons p ON p.id = m.person_id
    WHERE m.auth_id IS NOT NULL AND p.auth_id IS NOT NULL AND m.auth_id IS DISTINCT FROM p.auth_id
  )
  SELECT 'D_auth_id_mismatch_person_member'::text,
         'persons.auth_id and members.auth_id must agree when both are set (ghost resolution sync)'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ae.engagement_id AS e_id FROM public.auth_engagements ae
    JOIN public.members m ON m.person_id = ae.person_id
    WHERE ae.status='active' AND m.member_status IN ('observer','alumni','inactive')
      AND ae.kind NOT IN ('observer','alumni','external_signer','sponsor','chapter_board','partner_contact')
  )
  SELECT 'E_engagement_active_with_terminal_member'::text,
         'engagement.status=active is inconsistent with member.member_status in (observer/alumni/inactive) unless kind matches'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(e_id ORDER BY e_id) FROM (SELECT e_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT i.id AS initiative_id FROM public.initiatives i
    WHERE i.legacy_tribe_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.tribes t WHERE t.id = i.legacy_tribe_id)
  )
  SELECT 'F_initiative_legacy_tribe_orphan'::text,
         'initiatives.legacy_tribe_id must point to an existing tribe (bridge integrity)'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(initiative_id ORDER BY initiative_id) FROM (SELECT initiative_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    LEFT JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.current_version_id IS NOT NULL
      AND (dv.id IS NULL OR dv.locked_at IS NULL)
      AND NOT EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status IN ('review','approved','activated')
          AND ac.closed_at IS NULL
      )
  )
  SELECT 'J_current_version_published'::text,
         'governance_documents.current_version_id must point to a document_versions row with locked_at IS NOT NULL — unless an open approval_chain (review/approved/activated, closed_at NULL) is in flight that will lock the version on close (Phase IP-1, chain-aware).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.operational_role='external_signer'
      AND NOT EXISTS (
        SELECT 1 FROM public.auth_engagements ae
        WHERE ae.person_id=m.person_id AND ae.kind='external_signer' AND ae.status='active' AND ae.is_authoritative=true
      )
  )
  SELECT 'K_external_signer_integrity'::text,
         'members.operational_role=external_signer must have an active auth_engagements row with kind=external_signer (Phase IP-1).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id FROM public.members m
    WHERE m.member_status IN ('alumni','observer','inactive') AND m.anonymized_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.member_offboarding_records r WHERE r.member_id=m.id)
  )
  SELECT 'L_offboarding_record_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have a member_offboarding_records row (#91 G3 trigger).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected AS (
    SELECT a.id AS application_id, a.research_score AS cached,
      CASE
        WHEN e.obj_avg IS NOT NULL AND e.int_avg IS NOT NULL THEN round(e.obj_avg + e.int_avg, 2)
        WHEN e.obj_avg IS NOT NULL THEN round(e.obj_avg, 2)
        ELSE NULL
      END AS expected
    FROM public.selection_applications a
    CROSS JOIN LATERAL (
      SELECT AVG(weighted_subtotal) FILTER (WHERE evaluation_type='objective' AND submitted_at IS NOT NULL) AS obj_avg,
        AVG(weighted_subtotal) FILTER (WHERE evaluation_type='interview' AND submitted_at IS NOT NULL) AS int_avg
      FROM public.selection_evaluations WHERE application_id=a.id
    ) e
  ),
  drift AS (
    SELECT application_id FROM expected
    WHERE (cached IS NULL) IS DISTINCT FROM (expected IS NULL)
       OR (cached IS NOT NULL AND expected IS NOT NULL AND ABS(cached - expected) > 0.01)
  )
  SELECT 'M_application_score_consistency'::text,
         'selection_applications.research_score must equal compute_application_scores(application_id) derivation (sync trigger trg_recompute_application_scores).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive')
      AND offboarded_at IS NULL AND anonymized_at IS NULL
      AND name <> 'VP Desenvolvimento Profissional (PMI-GO)'
  )
  SELECT 'N_terminal_status_offboarded_at_present'::text,
         'members in alumni/observer/inactive (not anonymized) must have offboarded_at NOT NULL (ARM-9 G6 defense-in-depth complement to L).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT ma.id AS artifact_id FROM public.meeting_artifacts ma
    WHERE ma.event_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.events e WHERE e.id = ma.event_id)
  )
  SELECT 'O_meeting_artifact_event_orphan'::text,
         'meeting_artifacts.event_id must point to an existing event when not NULL (FK defense).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(artifact_id ORDER BY artifact_id) FROM (SELECT artifact_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  SELECT 'P_tribe_initiative_bridge_complete'::text,
         'tribes.is_active=true must have at least one initiative.legacy_tribe_id pointing to it (V3-V4 bridge; cron leader digest depends).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM public.tribes t
          WHERE t.is_active = true
            AND NOT EXISTS (SELECT 1 FROM public.initiatives i WHERE i.legacy_tribe_id = t.id)),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS engagement_id FROM public.engagements
    WHERE status = 'expired' AND end_date > CURRENT_DATE
  )
  SELECT 'Q_expired_engagement_end_date'::text,
         'engagements.status=expired requires end_date <= CURRENT_DATE (impossible to be expired in the future; VEP service_latest_end_date is source of truth).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT a.id AS application_id
    FROM public.selection_applications a
    WHERE a.status = 'approved'
      AND a.email IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.members m WHERE lower(m.email) = lower(a.email)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.member_emails me WHERE lower(me.email) = lower(a.email)
      )
  )
  SELECT 'R_approved_application_has_member'::text,
         'selection_applications.status=approved must have a matching members row by lower(email). Bypass of approve_selection_application() canonical RPC creates this drift (Issue #180).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(application_id ORDER BY application_id) FROM (SELECT application_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT DISTINCT m.id AS member_id
    FROM public.selection_applications a
    JOIN public.members m ON lower(m.email) = lower(a.email)
    WHERE a.status = 'approved' AND m.person_id IS NULL
  )
  SELECT 'S_approved_member_has_person_id'::text,
         'members tied to an approved selection_applications row must have person_id NOT NULL (V4 graph anchor for engagements). Issue #180.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH primary_email_counts AS (
    SELECT m.id AS member_id,
           COUNT(me.id) FILTER (WHERE me.is_primary = true) AS primary_count
    FROM public.members m
    LEFT JOIN public.member_emails me ON me.member_id = m.id
    WHERE m.name NOT LIKE '%_synthetic%'
    GROUP BY m.id
  ),
  drift AS (
    SELECT member_id FROM primary_email_counts
    WHERE primary_count <> 1
  )
  SELECT 'T_member_has_exactly_one_primary_email'::text,
         'Every member must have exactly one primary email in member_emails (Issue #205).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status = 'pending_proposer_consent'
      AND EXISTS (
        SELECT 1 FROM public.approval_chains ac
        WHERE ac.document_id = gd.id
          AND ac.status NOT IN ('withdrawn','superseded')
      )
  )
  SELECT 'V_prime_pending_proposer_consent_no_open_chain'::text,
         'status=pending_proposer_consent must not have non-cancelled approval_chains rows (#315 P0-Q7 + Amendment A2 — pending_proposer_consent precedes any chain).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id FROM public.governance_documents gd
    WHERE gd.status IN ('approved','active')
      AND gd.current_ratified_chain_id IS NULL
  )
  SELECT 'V_status_chain_coherence'::text,
         'governance_documents with status approved/active must have current_ratified_chain_id NOT NULL (#315 P0-Q6 + #367 Wave 1b first leaf). NO carve-out: 7 legacy pre-chain docs backfilled with PM-designated synthetic chains via migration 20260805000038 (acknowledge signoffs, metadata.legacy_migration=true, role=migration_attestation).'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT cp.id AS product_id
    FROM public.content_products cp
    WHERE
      CASE cp.source_kind
        WHEN 'governance_document_version' THEN
          NOT (cp.source_document_version_id IS NOT NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'board_item' THEN
          NOT (cp.source_board_item_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'publication_idea' THEN
          NOT (cp.source_publication_idea_id IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_external_uri IS NULL)
        WHEN 'external' THEN
          NOT (cp.source_external_uri IS NOT NULL
               AND cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL)
        WHEN 'none' THEN
          NOT (cp.source_document_version_id IS NULL
               AND cp.source_board_item_id IS NULL
               AND cp.source_publication_idea_id IS NULL
               AND cp.source_external_uri IS NULL)
        ELSE TRUE
      END
  )
  SELECT 'W_content_product_source_integrity'::text,
         'content_products row must satisfy chk_content_products_source_integrity CHECK semantics (exactly one source FK populated per source_kind; ADR-0099 §2.2 + §6 step 9). Defense-in-depth complement to the CHECK constraint; mirrors V/V''/T pattern.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(product_id ORDER BY product_id) FROM (SELECT product_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT p.id AS parecer_id
    FROM public.blind_review_pareceres p
    WHERE NOT EXISTS (
      SELECT 1 FROM public.blind_review_assignments a
      WHERE a.session_id = p.session_id
        AND a.reviewer_member_id = p.reviewer_member_id
        AND a.status = 'active'
    )
  )
  SELECT 'X_blind_review_pareceres_session_product_match'::text,
         'blind_review_pareceres.reviewer_member_id must have an active blind_review_assignments row in the same session (assignment-parecer integrity; ADR-0099 §2.7 + §7 step 11). Defense-in-depth complement to FK constraints; catches drift if assignment is withdrawn while parecer remains. #382 PR-B.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(parecer_id ORDER BY parecer_id) FROM (SELECT parecer_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH pe AS (
    SELECT name AS k FROM public.partner_entities
    WHERE entity_type = 'pmi_chapter' AND status = 'active' AND NOT COALESCE(is_international, false)
  ),
  ch AS (
    SELECT 'PMI-' || code AS k FROM public.chapters WHERE status = 'active'
  ),
  drift AS (
    SELECT k FROM pe WHERE k NOT IN (SELECT k FROM ch)
    UNION ALL
    SELECT k FROM ch WHERE k NOT IN (SELECT k FROM pe)
  )
  SELECT 'Y_chapter_pipeline_parity'::text,
         'every active domestic pmi_chapter in partner_entities must have a matching active chapters row (by name = ''PMI-'' || chapters.code) and vice-versa — MEMBERSHIP parity (not just count), so it catches single-table inserts/archives even when row counts coincide. Drift = get_chapter_metrics()->>signed forks from the V4 chapters table (#481).'::text,
         'medium'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];

  RETURN QUERY
  WITH drift AS (
    SELECT id AS webinar_id FROM public.webinars
    WHERE status IS NULL OR status NOT IN ('planned','confirmed','completed','cancelled')
  )
  SELECT 'Z_webinar_status_domain'::text,
         'webinars.status must be within planned|confirmed|completed|cancelled (the realized=completed canonical definition depends on it; defense-in-depth complement to webinars_status_check — #479/#481).'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(webinar_id ORDER BY webinar_id) FROM (SELECT webinar_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id AS member_id FROM public.members
    WHERE member_status IN ('observer','alumni','inactive') AND current_cycle_active = true
      AND name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND name NOT LIKE '%_synthetic%'
  )
  SELECT 'B2_current_cycle_active_terminal_status'::text,
         'members in observer/alumni/inactive must have current_cycle_active=false (#483 sync_member_status_consistency B-trigger; CCA gates the get_gamification_leaderboard/get_public_leaderboard cohort).'::text,
         'low'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT m.id AS member_id
    FROM public.members m
    WHERE m.member_status = 'active'
      AND m.person_id IS NOT NULL
      AND m.name != 'VP Desenvolvimento Profissional (PMI-GO)'
      AND m.name NOT LIKE '%_synthetic%'
      AND replace(m.chapter, 'PMI-', '') IN (SELECT chapter_code FROM public.chapter_registry)
      AND NOT (m.operational_role = 'guest' AND m.entry_chapter_code IS NULL)
      AND (SELECT COUNT(*) FROM public.member_chapter_affiliations a
            WHERE a.person_id = m.person_id AND a.is_primary) <> 1
  )
  SELECT 'U_active_person_has_primary_chapter_affiliation'::text,
         'every active registry-chaptered member''s person_id must have exactly one is_primary=true member_chapter_affiliations row, else the members.chapter COALESCE(entry, primary, legacy) derivation breaks silently (ADR-0104 Wave 3b-ii). Excluded: operational_role=''guest'' AND entry_chapter_code IS NULL (pre-onboarding, entry-chapter choice not yet made — affiliation is seeded by set_my_entry_chapter, Wave 3b-i; until then the COALESCE falls through to the legacy default). Non-registry chapters (Outro/Externo) excluded — legitimately unaffiliated.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT op.member_id
    FROM public.onboarding_progress op
    WHERE op.step_key = 'volunteer_term'
      AND op.status <> 'completed'
      AND op.member_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = op.member_id
          AND c.type = 'volunteer_agreement'
          AND c.status = 'issued'
      )
  )
  SELECT 'AA_volunteer_term_complete_when_cert_issued'::text,
         'a member holding an issued volunteer_agreement certificate must have their volunteer_term onboarding_progress step at status=completed. Guaranteed by the cert-side AFTER trigger (_trg_complete_volunteer_term_on_cert on certificates) plus the seed-side BEFORE guard (_trg_complete_volunteer_term_on_seed on onboarding_progress), p233 / issue #766. A non-completed step alongside an issued cert means a trigger was bypassed (service_role direct INSERT, or a cert backfill that did not fire the AFTER trigger). Directional: a member with no volunteer_term row, or a completed step without an issued cert (all certs rejected or superseded), is NOT a violation.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;
  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'term_signed'
      AND NOT EXISTS (
        SELECT 1 FROM public.certificates c
        WHERE c.member_id = mm.member_id
          AND c.type = 'volunteer_agreement'
      )
  )
  SELECT 'AB_term_signed_milestone_has_cert_ancestry'::text,
         'a term_signed member_milestone must have at least one volunteer_agreement certificate of any status (issued/rejected/superseded) for the same member. Wave 3c reject/reissue is valid ancestry — the milestone persists after a cert is rejected or superseded because the member did sign once. A milestone with NO cert in any state indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK). #766 PR2, mig 20260805000202. Directional complement to AA.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_attendance'
      AND NOT EXISTS (
        SELECT 1 FROM public.attendance a
        WHERE a.member_id = mm.member_id
          AND a.present = true
      )
  )
  SELECT 'AC_first_attendance_milestone_has_attendance'::text,
         'a first_attendance member_milestone must have at least one present=true attendance row for the same member. source_id is informational-only (no FK), so a milestone with no present attendance indicates fabrication or a bad backfill (service_role direct INSERT into member_milestones). #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'first_deliverable'
      AND NOT EXISTS (
        SELECT 1 FROM public.tribe_deliverables td
        WHERE td.assigned_member_id = mm.member_id
          AND td.status = 'completed'
      )
  )
  SELECT 'AD_first_deliverable_milestone_has_completed_deliverable'::text,
         'a first_deliverable member_milestone must have at least one tribe_deliverable with status=''completed'' assigned to the same member. Keyed on status=''completed'' (same signal as the trigger and the XP sibling trg_tribe_deliverable_completed_xp; NOT completed_at, a derived audit column). A milestone with no completed deliverable indicates fabrication, a bad backfill, or a status reverted via service_role after the milestone fired. #766 PR3, mig 20260805000203. Directional, mirrors AA/AB.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT mm.member_id
    FROM public.member_milestones mm
    WHERE mm.milestone_key = 'profile_complete'
      AND NOT EXISTS (
        SELECT 1 FROM public.members m
        WHERE m.id = mm.member_id
          AND m.profile_completed_at IS NOT NULL
      )
  )
  SELECT 'AE_profile_complete_milestone_has_profile_completed_at'::text,
         'a profile_complete member_milestone must have members.profile_completed_at set. The column is monotonic — only update_my_profile writes it (NULL -> now() once, never cleared) — so this directional check is false-positive-free, unlike promotion whose mutable operational_role cache demotes routinely (hence PR4 added no invariant). A milestone with a NULL profile_completed_at indicates fabrication, a bad backfill (service_role direct INSERT into member_milestones; source_id is informational-only without FK), or the column cleared via a manual UPDATE after the milestone fired. #766 PR5, mig 20260805000205. Directional, mirrors AA/AB/AC/AD.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(member_id ORDER BY member_id) FROM (SELECT member_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT si.id AS interview_id
    FROM public.selection_interviews si
    WHERE si.status IN ('scheduled','rescheduled')
      AND EXISTS (
        SELECT 1 FROM public.selection_interviews si2
        WHERE si2.application_id = si.application_id
          AND si2.created_at > si.created_at
      )
  )
  SELECT 'AF_open_interview_is_newest_row'::text,
         'a selection_interviews row in an open status (scheduled/rescheduled) must be the most-recently-created interview row for its application. An open row older than another interview row of the same application indicates a reschedule/re-booking that did not close the prior open row (bypass of the AFTER INSERT trigger trg_supersede_prior_open_interviews, or pre-fix legacy drift). Root cause: sync_calendar_booking_to_interview / schedule_interview INSERTing a new scheduled row without superseding the prior open one (D4/D5, mig 20260805000210). KNOWN directional gap (defense-in-depth): a TERMINAL row inserted newer than an open row (only import_historical_interviews) is not superseded by the trigger and would surface here; the live path reaches completed via UPDATE in-place, so it is covered.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(interview_id ORDER BY interview_id) FROM (SELECT interview_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT e.id AS engagement_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    JOIN public.members m ON m.person_id = e.person_id
    WHERE e.kind = 'volunteer' AND e.status = 'active'
      AND m.tribe_id IS DISTINCT FROM i.legacy_tribe_id
  )
  SELECT 'AG_tribe_engagement_has_tribe_id'::text,
         'every active volunteer engagement in a research_tribe initiative must have member.tribe_id = initiative.legacy_tribe_id (the correctness contract of the bridge trigger trg_sync_tribe_id_from_engagement; count_tribe_slots reads members.tribe_id, so a divergence corrupts the slot count). A violation means the bridge was bypassed (service_role direct INSERT into engagements) or a stale legacy tribe_id conflicts with the engagement. Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(engagement_id ORDER BY engagement_id) FROM (SELECT engagement_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT e.person_id
    FROM public.engagements e
    JOIN public.initiatives i ON i.id = e.initiative_id AND i.kind = 'research_tribe'
    WHERE e.kind = 'volunteer' AND e.status = 'active'
    GROUP BY e.person_id
    HAVING COUNT(*) > 1
  )
  SELECT 'AH_research_tribe_single_active_engagement'::text,
         'a person must have at most one active volunteer engagement across research_tribe initiatives. members.tribe_id is a single scalar and the bridge trigger trg_sync_tribe_id_from_engagement (admission + demotion branch) assumes a single active tribe engagement; two make tribe_id ambiguous and can leave a stale tribe_id after one is demoted. Supersedes the SPEC''s I_research_tribe_no_dual_pending (which false-positives on a legitimate tribe-move and whose committed-divergence sibling is already non-zero from frozen legacy tribe_selections staleness, below the bridge since AG=0). Tribe Selection Híbrida PR1, mig 20260805000216. Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(person_id ORDER BY person_id) FROM (SELECT person_id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH drift AS (
    SELECT id FROM public.selection_applications WHERE interview_auto_rescue_count > 1
  )
  SELECT 'AI_unbooked_rescue_cap_respected'::text,
         'selection_applications with interview_auto_rescue_count > 1 (above cap=1). _selection_unbooked_rescue_cron + selection_rescue_unbooked_invite enforce the cap via a RAISE guard at count>=1; a value >1 means a re-entry bug or a service_role direct UPDATE bypassed the guard. D3 auto-rescue, mig 20260805000219. Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM drift LIMIT 10) s)
  FROM drift;

  RETURN QUERY
  WITH expected(tbl) AS (
    VALUES ('initiatives'),('events'),('project_boards'),('board_items'),
           ('meeting_artifacts'),('tribe_deliverables'),('recurring_meeting_rules'),('governance_documents')
  ),
  drift AS (
    SELECT e.tbl FROM expected e
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = e.tbl
        AND p.permissive = 'RESTRICTIVE'
        AND p.cmd IN ('SELECT','ALL')
        AND p.qual ILIKE '%rls_can_see_%'
    )
  )
  SELECT 'AJ_confidential_visibility_gate_present'::text,
         'each of the 8 initiative-dependent tables (initiatives/events/project_boards/board_items/meeting_artifacts/tribe_deliverables/recurring_meeting_rules/governance_documents) must carry a RESTRICTIVE SELECT policy whose USING calls a rls_can_see_* helper — the confidential-initiative visibility gate (#785 PR-2, mig 20260805000232). A missing policy means the gate was dropped and a confidential initiative''s rows leak to non-engaged members. Structural catalog check (pg_policies); baseline 0.'::text,
         'high'::text,
         (SELECT COUNT(*)::integer FROM drift),
         NULL::uuid[];


  -- #333 (Wave 4, #221/#218): voice-biometric consent enforcement — periodic detector that
  -- complements the write-time trigger trg_pmi_video_screening_voice_consent.
  RETURN QUERY
  WITH ack AS (
    -- Applications with a documented LGPD Art.18 retroactive-notification retention basis
    -- (the #332 acknowledged pre-block row). The application id is parsed from the pii_access_log
    -- audit record so NO candidate identifier is hardcoded in this migration; the exclusion IS the
    -- documented retention, and it self-heals to nothing if the row is eventually deleted.
    SELECT (substring(pal.reason FROM 'application_id=([0-9a-fA-F-]+)'))::uuid AS application_id
    FROM public.pii_access_log pal
    WHERE pal.context = 'lgpd_art_18_retroactive_notification'
      AND pal.reason ~ 'application_id='
  ),
  drift AS (
    SELECT vs.id
    FROM public.pmi_video_screenings vs
    WHERE vs.transcription IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.selection_applications sa
        WHERE sa.id = vs.application_id
          AND sa.consent_voice_biometric_at IS NOT NULL
          AND sa.consent_voice_biometric_revoked_at IS NULL
      )
      AND NOT EXISTS (
        SELECT 1 FROM ack WHERE ack.application_id = vs.application_id
      )
  )
  SELECT 'AK_voice_biometric_consent_enforcement'::text,
         'every pmi_video_screenings row with transcription IS NOT NULL must have a matching selection_applications row where consent_voice_biometric_at IS NOT NULL AND consent_voice_biometric_revoked_at IS NULL (voice-biometric consent, LGPD Art.11), UNLESS its application has a documented Art.18 retroactive-notification retention basis logged in pii_access_log. The BEFORE INSERT/UPDATE trigger trg_pmi_video_screening_voice_consent is the write-time moat; this invariant is the periodic detector for any NEW drift (trigger disabled, consent revoked without deleting the row, raw SQL bypass). #333/#221/#218 Wave 4. The 1 acknowledged pre-block row (#332, tacit Art.18 retention; PM path (b) 2026-06-27) is EXCLUDED via its retention record, so baseline is 0; a new non-consented transcription with no retention basis is flagged. Named AK because the U_ code is already held by U_active_person_has_primary_chapter_affiliation.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(id ORDER BY id) FROM (SELECT id FROM drift LIMIT 10) s)
  FROM drift;

  -- #209 / ADR-0107: Drive offboarding revocation queue state-machine integrity.
  RETURN QUERY
  WITH drift AS (
    SELECT id AS audit_id FROM public.drive_offboarding_audit
    WHERE
      (status = 'revoked' AND (approved_by IS NULL OR revoked_at IS NULL))
      OR (status IN ('pending_revoke','approved') AND EXISTS (
            SELECT 1 FROM public.members m
            WHERE m.id = drive_offboarding_audit.member_id
              AND (m.member_status = 'active' OR m.offboarded_at IS NULL)))
  )
  SELECT 'AL_drive_revocation_terminal_consistency'::text,
         'drive_offboarding_audit (#209/ADR-0107): a revoked row must carry approved_by AND revoked_at (proof it went through the approve_drive_revocation + mark_drive_revocation_done RPC path), and no OPEN row (pending_revoke/approved) may reference a member who is active / not offboarded — a reversed offboarding must clear the revocation queue. A violation means a service_role direct write bypassed the RPC path, or an offboarding was reversed without clearing pending grants. Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(audit_id ORDER BY audit_id) FROM (SELECT audit_id FROM drift LIMIT 10) s)
  FROM drift;

  -- #301 / ADR-0108: curation temporary Drive grant state-machine integrity.
  RETURN QUERY
  WITH drift AS (
    SELECT id AS grant_id FROM public.drive_curation_grants
    WHERE (status = 'granted' AND (permission_id IS NULL OR granted_at IS NULL))
       OR (status = 'granted' AND revoked_at IS NOT NULL)
       OR (status = 'revoked' AND revoked_at IS NULL)
  )
  SELECT 'AM_drive_curation_grant_terminal_consistency'::text,
         'drive_curation_grants (#301/ADR-0108): a granted row must carry permission_id AND granted_at (proof the Drive POST succeeded) and must NOT carry revoked_at; a revoked row must carry revoked_at. The grant/revoke EF mark RPCs (mark_curation_grant_done/mark_curation_grant_revoked) are the only legitimate writers of these terminal states; a violation means a service_role direct write bypassed them. Named AM (AL is the #209 sibling). Baseline 0.'::text,
         'medium'::text, COUNT(*)::integer,
         (SELECT array_agg(grant_id ORDER BY grant_id) FROM (SELECT grant_id FROM drift LIMIT 10) s)
  FROM drift;

  -- #974 (PR-2 of #571) — no dynamic remission: every active cooperation_agreement
  -- must carry an active instrument_version_bindings pin to the IP policy (a hard
  -- document_versions.id), never a free-text "Política vigente" dynamic remission.
  -- GATED on a ratified (active) cooperation_addendum: dormant until the Adendo
  -- imports the policy into the agreements (pre-ratification no ratified instrument
  -- obliges the agreements to pin the policy — §9.7 / legal review 2026-06-30).
  RETURN QUERY
  WITH drift AS (
    SELECT gd.id AS doc_id
    FROM public.governance_documents gd
    WHERE gd.doc_type = 'cooperation_agreement'
      AND gd.status = 'active'
      AND EXISTS (
        SELECT 1 FROM public.governance_documents addn
        WHERE addn.doc_type = 'cooperation_addendum' AND addn.status = 'active'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.instrument_version_bindings ivb
        JOIN public.governance_documents ref ON ref.id = ivb.referenced_document_id
        WHERE ivb.bound_document_id = gd.id
          AND ref.doc_type = 'policy'
          AND ivb.status = 'active'
      )
  )
  SELECT 'AN_no_dynamic_remission_cooperation'::text,
         'every active cooperation_agreement must carry an active instrument_version_bindings row pinning the IP policy to a hard document_versions.id (referenced doc_type=policy, status=active) — never a free-text "Política vigente" dynamic remission. The Adendo de PI aos Acordos de Cooperação (cooperation_addendum, under_review at mig 20260805000302) PROPOSES to import the IP policy into all 4 bilateral agreements; this invariant is GATED on an active (ratified) cooperation_addendum and is dormant until then — pre-ratification no ratified instrument obliges the agreements to pin the policy (legal review 2026-06-30, SPEC §9.7). #974 PR-2 materializes 4 anticipatory pins now (pinned_version_id is NOT NULL by table constraint, so the pin can never be a dynamic reference). Once a cooperation_addendum ratifies, an active cooperation_agreement with no active policy pin = dynamic remission reintroduced (#974, mig 20260805000302). Baseline 0.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(doc_id ORDER BY doc_id) FROM (SELECT doc_id FROM drift LIMIT 10) s)
  FROM drift;

END;
$function$;

-- ---------------------------------------------------------------------
-- 6. PostgREST schema reload (new RPCs + table exposed on the API surface).
-- ---------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

-- =====================================================================================
-- #625 F1b — Acesso à verificação de filiação: attestation de confidencialidade (§6.2.3)
-- SPEC: docs/specs/SPEC_625_AFFILIATION_VERIFICATION_LOOP.md · LIA: docs/legal/RoPA_625_AFFILIATION_VERIFICATION_LIA.md
--
-- Operacionaliza a "disciplina interna de acesso" do §6.2.3 (registro nominal + finalidade
-- restrita + vedação de uso próprio + log) como um ATESTE digital just-in-time, logado e com
-- re-aceite anual. ENFORCE via trigger BEFORE INSERT em member_affiliation_verifications —
-- gateia TODOS os caminhos de escrita (verify_member_affiliation, _bulk, INSERT direto) sem
-- re-emitir as RPCs. `manage_member` (PM/superadmin) é ISENTO: não é o agente fiduciário do loop.
--
-- NÃO é a LIA (Art. 7º IX) — essa é registro da CONTROLADORA no RoPA (papel LGPD distinto, não
-- substituível por um clique do agente). Ver o doc da LIA acima.
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS trg_affiliation_attestation ON public.member_affiliation_verifications;
--   DROP FUNCTION IF EXISTS public._enforce_affiliation_attestation();
--   DROP FUNCTION IF EXISTS public.get_my_affiliation_attestation();
--   DROP FUNCTION IF EXISTS public.attest_affiliation_access(text,text);
--   DROP FUNCTION IF EXISTS public._has_valid_affiliation_attestation(uuid);
--   DROP FUNCTION IF EXISTS public._current_affiliation_terms_version();
--   DROP TABLE IF EXISTS public.affiliation_access_attestations;
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Tabela append-only de atestes
-- -------------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.affiliation_access_attestations (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                        REFERENCES public.organizations(id) ON DELETE RESTRICT,
  member_id           uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  terms_version       text NOT NULL,
  accepted_at         timestamptz NOT NULL DEFAULT now(),
  valid_until         timestamptz NOT NULL,
  signed_ip           inet,
  signed_user_agent   text,
  created_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.affiliation_access_attestations IS
  '#625 F1b. Atestes APPEND-ONLY de confidencialidade/finalidade da Diretoria de Filiação antes '
  'do acesso de escrita ao loop (§6.2.3 — disciplina interna de acesso do agente; NÃO é DPA nem LIA). '
  'Re-aceite anual (valid_until = accepted_at + 1 ano). RLS deny-all; só SECDEF RPCs. Evidência do '
  'ato: signed_ip/signed_user_agent (do próprio agente). Enforce real via trigger BEFORE INSERT em '
  'member_affiliation_verifications. Retenção: vinculada ao membro (anonimização junto). '
  'Titulares com manage_member são ISENTOS do gate (não são o agente fiduciário do loop) — '
  'inserções por PM são auditáveis via admin_audit_log (affiliation.verified). (legal-counsel MEDIUM)';

CREATE INDEX IF NOT EXISTS idx_aaa_member ON public.affiliation_access_attestations (member_id, accepted_at DESC);

ALTER TABLE public.affiliation_access_attestations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.affiliation_access_attestations FROM anon, authenticated;

-- -------------------------------------------------------------------------------------
-- 2. Versão corrente dos termos (bump => re-aceite obrigatório). Fonte única p/ attest + gate.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._current_affiliation_terms_version()
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $function$
  SELECT 'v1-2026-06-11'::text;
$function$;

-- -------------------------------------------------------------------------------------
-- 3. Há ateste vigente? (versão corrente + não expirado)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._has_valid_affiliation_attestation(p_member_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.affiliation_access_attestations a
    WHERE a.member_id = p_member_id
      AND a.terms_version = public._current_affiliation_terms_version()
      AND a.valid_until > now()
  );
$function$;

-- -------------------------------------------------------------------------------------
-- 4. Registrar ateste (gate por designation filiacao_director OU manage_member)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.attest_affiliation_access(
  p_signed_ip text DEFAULT NULL,
  p_signed_user_agent text DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_designations text[];
  v_ver text; v_ip inet := NULL; v_id uuid; v_until timestamptz;
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Forbidden: authentication required'; END IF;

  IF NOT ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])))
     AND NOT public.can_by_member(v_caller_id, 'manage_member') THEN
    RAISE EXCEPTION 'Forbidden: requires filiacao_director designation or platform manager authority';
  END IF;

  p_signed_user_agent := left(p_signed_user_agent, 500);
  BEGIN
    IF p_signed_ip IS NOT NULL AND length(trim(p_signed_ip)) > 0 THEN v_ip := p_signed_ip::inet; END IF;
  EXCEPTION WHEN OTHERS THEN v_ip := NULL;
  END;

  v_ver := public._current_affiliation_terms_version();
  v_until := now() + interval '1 year';

  INSERT INTO public.affiliation_access_attestations
    (member_id, terms_version, valid_until, signed_ip, signed_user_agent)
  VALUES (v_caller_id, v_ver, v_until, v_ip, p_signed_user_agent)
  RETURNING id INTO v_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, changes)
  VALUES (v_caller_id, 'affiliation.access_attested', 'member', v_caller_id,
    jsonb_build_object('attestation_id', v_id, 'terms_version', v_ver, 'valid_until', v_until,
      'signed_ip', v_ip::text, 'signed_user_agent', p_signed_user_agent));

  RETURN jsonb_build_object('ok', true, 'attestation_id', v_id,
    'terms_version', v_ver, 'valid_until', v_until);
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 5. Status do ateste do caller (p/ o frontend decidir mostrar o modal)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_affiliation_attestation()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid; v_caller_designations text[];
  v_ver text; v_is_agent boolean; v_is_mgr boolean;
  v_accepted_at timestamptz; v_valid_until timestamptz; v_latest_ver text; v_attested boolean;
BEGIN
  SELECT m.id, m.designations INTO v_caller_id, v_caller_designations
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Forbidden: authentication required'; END IF;

  v_ver := public._current_affiliation_terms_version();
  v_is_agent := ('filiacao_director' = ANY(COALESCE(v_caller_designations, '{}'::text[])));
  v_is_mgr := public.can_by_member(v_caller_id, 'manage_member');

  SELECT a.accepted_at, a.valid_until, a.terms_version
  INTO v_accepted_at, v_valid_until, v_latest_ver
  FROM public.affiliation_access_attestations a
  WHERE a.member_id = v_caller_id
  ORDER BY a.accepted_at DESC LIMIT 1;

  v_attested := (v_valid_until IS NOT NULL AND v_valid_until > now() AND v_latest_ver = v_ver);

  RETURN jsonb_build_object(
    'current_terms_version', v_ver,
    'is_affiliation_agent', v_is_agent,
    'is_manager', v_is_mgr,
    'attested', v_attested,
    'latest_accepted_at', v_accepted_at,
    'latest_valid_until', v_valid_until,
    -- só o agente (filiacao_director) PRECISA atestar; manager é isento do gate de escrita.
    'needs_attestation', (v_is_agent AND NOT v_attested));
END;
$function$;

-- -------------------------------------------------------------------------------------
-- 6. Enforce via trigger BEFORE INSERT (cobre verify RPCs, bulk e INSERT direto)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._enforce_affiliation_attestation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_has_designation boolean;
BEGIN
  -- manage_member (PM/superadmin) é ISENTO (autoridade superior; não é o agente fiduciário do loop).
  IF NEW.verified_by_member_id IS NULL
     OR public.can_by_member(NEW.verified_by_member_id, 'manage_member') THEN
    RETURN NEW;
  END IF;

  -- Agente fiduciário: precisa da designation CORRENTE `filiacao_director` (fecha o caso ex-cargo
  -- com ateste ainda dentro do prazo de 12m — legal-counsel BLOCKER) E de ateste vigente.
  SELECT ('filiacao_director' = ANY(COALESCE(m.designations, '{}'::text[])))
    INTO v_has_designation
  FROM public.members m WHERE m.id = NEW.verified_by_member_id;

  IF NOT COALESCE(v_has_designation, false) THEN
    RAISE EXCEPTION 'Forbidden: verifier % no longer holds the filiacao_director designation', NEW.verified_by_member_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT public._has_valid_affiliation_attestation(NEW.verified_by_member_id) THEN
    RAISE EXCEPTION 'Forbidden: affiliation access attestation required for verifier %', NEW.verified_by_member_id
      USING ERRCODE = 'insufficient_privilege',
            HINT = 'Aceite o termo de confidencialidade de acesso (attest_affiliation_access) antes de verificar.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_affiliation_attestation ON public.member_affiliation_verifications;
CREATE TRIGGER trg_affiliation_attestation
  BEFORE INSERT ON public.member_affiliation_verifications
  FOR EACH ROW EXECUTE FUNCTION public._enforce_affiliation_attestation();

-- -------------------------------------------------------------------------------------
-- Grants (defesa em profundidade)
-- -------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.attest_affiliation_access(text,text) FROM public, anon;
REVOKE ALL ON FUNCTION public.get_my_affiliation_attestation() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.attest_affiliation_access(text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_affiliation_attestation() TO authenticated, service_role;
-- helpers internos: sem grant a authenticated/anon (chamados por SECDEF/trigger).
REVOKE ALL ON FUNCTION public._current_affiliation_terms_version() FROM public, anon;
REVOKE ALL ON FUNCTION public._has_valid_affiliation_attestation(uuid) FROM public, anon;

NOTIFY pgrst, 'reload schema';

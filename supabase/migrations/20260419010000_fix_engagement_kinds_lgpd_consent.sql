-- ============================================================================
-- Fix LGPD consent-without-agreement inconsistency in engagement_kinds
-- Purpose: 5 engagement_kinds had legal_basis='consent' but requires_agreement=false,
--          meaning no mechanism existed to collect the required explicit consent.
-- Changes:
--   1. Fix _audit_engagement_kinds_changes trigger (details→changes+metadata, nullable actor_id)
--   2. guest/observer/speaker/candidate → legitimate_interest (transient, low-PII)
--   3. ambassador → keep consent + requires_agreement=true (formal external role)
-- Rollback: UPDATE engagement_kinds SET legal_basis='consent' WHERE slug IN ('guest','observer','speaker','candidate');
--           UPDATE engagement_kinds SET requires_agreement=false WHERE slug='ambassador';
--           ALTER TABLE admin_audit_log ALTER COLUMN actor_id SET NOT NULL;
-- ============================================================================

-- ═══ PART 1: Allow NULL actor_id for system/admin operations ═══

ALTER TABLE admin_audit_log ALTER COLUMN actor_id DROP NOT NULL;

-- ═══ PART 2: Fix audit trigger (column mismatch + contract in whitelist) ═══

CREATE OR REPLACE FUNCTION public._audit_engagement_kinds_changes()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_changes jsonb := '[]'::jsonb;
  v_actor_id uuid;
BEGIN
  IF OLD.legal_basis IS DISTINCT FROM NEW.legal_basis THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'legal_basis', 'old', OLD.legal_basis, 'new', NEW.legal_basis
    ));
  END IF;

  IF OLD.retention_days_after_end IS DISTINCT FROM NEW.retention_days_after_end THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'retention_days_after_end', 'old', OLD.retention_days_after_end, 'new', NEW.retention_days_after_end
    ));
  END IF;

  IF OLD.anonymization_policy IS DISTINCT FROM NEW.anonymization_policy THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'anonymization_policy', 'old', OLD.anonymization_policy, 'new', NEW.anonymization_policy
    ));
  END IF;

  IF OLD.requires_agreement IS DISTINCT FROM NEW.requires_agreement THEN
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'field', 'requires_agreement', 'old', OLD.requires_agreement, 'new', NEW.requires_agreement
    ));
  END IF;

  IF jsonb_array_length(v_changes) = 0 THEN
    RETURN NEW;
  END IF;

  v_actor_id := auth.uid();

  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, changes, metadata)
  VALUES (
    v_actor_id,
    'engagement_kind_lgpd_update',
    'engagement_kinds',
    NULL,
    v_changes,
    jsonb_build_object(
      'slug', NEW.slug,
      'display_name', NEW.display_name,
      'warning', 'LGPD-relevant fields changed. Verify alignment with published privacy policy.',
      'privacy_policy_fields_to_check', ARRAY[
        'privacy.s6ret (retention table)',
        'privacy.s4legal (legal basis section)'
      ]
    )
  );

  IF NEW.legal_basis NOT IN (
    'contract_volunteer', 'contract_course', 'consent',
    'legitimate_interest', 'chapter_delegation', 'contract'
  ) THEN
    RAISE WARNING 'engagement_kind % has unrecognized legal_basis: %. Verify LGPD Art. 7 compliance.',
      NEW.slug, NEW.legal_basis;
  END IF;

  RETURN NEW;
END;
$function$;

-- ═══ PART 3: Fix engagement_kinds legal basis ═══

-- Transient/low-PII roles: consent → legitimate_interest
UPDATE engagement_kinds
SET legal_basis = 'legitimate_interest', updated_at = now()
WHERE slug IN ('guest', 'observer', 'speaker', 'candidate')
  AND legal_basis = 'consent'
  AND requires_agreement = false;

-- Formal external role: keep consent, require agreement
UPDATE engagement_kinds
SET requires_agreement = true, updated_at = now()
WHERE slug = 'ambassador'
  AND legal_basis = 'consent'
  AND requires_agreement = false;

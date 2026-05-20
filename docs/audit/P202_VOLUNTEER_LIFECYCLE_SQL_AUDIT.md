# p202 Volunteer Lifecycle SQL Audit Pack

**Data:** 2026-05-19  
**Tipo:** SQL read-only para auditoria de lifecycle  
**Uso:** Rodar antes/depois de migrations relacionadas a #177, #179, #180, #181, #182 e #183.

> Não cole resultados com PII em issues públicas. As queries de detalhe usam hashes para identificação operacional sem expor email/nome.

---

## 1. Schema Probe

Confirma colunas e assinaturas esperadas antes da auditoria.

```sql
WITH cols AS (
  SELECT table_name, column_name, data_type
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name IN (
      'selection_applications',
      'members',
      'persons',
      'engagements',
      'certificates',
      'notifications',
      'auth_engagements',
      'engagement_kinds',
      'admin_audit_log'
    )
),
funcs AS (
  SELECT
    p.proname,
    pg_get_function_arguments(p.oid) AS args,
    pg_get_function_result(p.oid) AS result
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'admin_update_application',
      'finalize_decisions',
      'sign_volunteer_agreement',
      'counter_sign_certificate',
      'get_my_signatures'
    )
)
SELECT jsonb_build_object(
  'columns', (SELECT jsonb_agg(to_jsonb(cols) ORDER BY table_name, column_name) FROM cols),
  'functions', (SELECT jsonb_agg(to_jsonb(funcs) ORDER BY proname, args) FROM funcs)
) AS schema_probe;
```

---

## 2. Aggregate Evidence

Resumo sem PII para registrar em PRs/issues.

```sql
WITH
approved_apps AS (
  SELECT id, email, status, created_at, updated_at
  FROM public.selection_applications
  WHERE status IN ('approved', 'converted')
),
approved_without_member AS (
  SELECT aa.*
  FROM approved_apps aa
  WHERE NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE lower(m.email) = lower(aa.email)
  )
),
approved_member_matches AS (
  SELECT
    aa.id AS application_id,
    m.id AS member_id,
    m.person_id,
    m.is_active,
    m.operational_role
  FROM approved_apps aa
  JOIN public.members m ON lower(m.email) = lower(aa.email)
),
active_auth AS (
  SELECT ae.*
  FROM public.auth_engagements ae
  WHERE ae.status = 'active'
),
pending_agreement AS (
  SELECT ae.*
  FROM active_auth ae
  WHERE ae.requires_agreement IS TRUE
    AND ae.agreement_certificate_id IS NULL
),
pending_with_notification AS (
  SELECT
    pa.engagement_id,
    EXISTS (
      SELECT 1
      FROM public.members m
      JOIN public.notifications n ON n.recipient_id = m.id
      WHERE m.person_id = pa.person_id
        AND n.created_at >= COALESCE(pa.start_date::timestamptz, now() - interval '365 days')
        AND (
          lower(coalesce(n.title, '')) LIKE '%termo%'
          OR lower(coalesce(n.body, '')) LIKE '%termo%'
          OR lower(coalesce(n.type, '')) LIKE '%agreement%'
          OR lower(coalesce(n.type, '')) LIKE '%certificate%'
        )
    ) AS has_agreement_notification
  FROM pending_agreement pa
),
cert_base AS (
  SELECT * FROM public.certificates
),
cert_signed AS (
  SELECT *
  FROM cert_base
  WHERE status IN ('signed', 'issued', 'active', 'counter_signed')
     OR signature_hash IS NOT NULL
     OR counter_signed_at IS NOT NULL
)
SELECT jsonb_build_object(
  'approved_pipeline', jsonb_build_object(
    'approved_or_converted_total', (SELECT count(*) FROM approved_apps),
    'approved_without_member_count', (SELECT count(*) FROM approved_without_member),
    'approved_with_member_count', (SELECT count(*) FROM approved_member_matches),
    'approved_member_without_person_id_count', (
      SELECT count(*) FROM approved_member_matches WHERE person_id IS NULL
    ),
    'approved_inactive_member_count', (
      SELECT count(*) FROM approved_member_matches WHERE is_active IS FALSE
    ),
    'approved_by_status', (
      SELECT jsonb_object_agg(status, rows)
      FROM (SELECT status, count(*) rows FROM approved_apps GROUP BY status) s
    ),
    'matched_member_roles', (
      SELECT jsonb_object_agg(coalesce(operational_role, 'NULL'), rows)
      FROM (SELECT operational_role, count(*) rows FROM approved_member_matches GROUP BY operational_role) r
    )
  ),
  'engagement_authority', jsonb_build_object(
    'active_engagements_total', (SELECT count(*) FROM active_auth),
    'active_requires_agreement_total', (
      SELECT count(*) FROM active_auth WHERE requires_agreement IS TRUE
    ),
    'active_requires_agreement_missing_certificate', (
      SELECT count(*) FROM pending_agreement
    ),
    'active_requires_agreement_non_authoritative', (
      SELECT count(*) FROM active_auth
      WHERE requires_agreement IS TRUE AND is_authoritative IS FALSE
    ),
    'pending_agreement_by_kind_role', (
      SELECT jsonb_agg(to_jsonb(x) ORDER BY rows DESC, kind, role)
      FROM (
        SELECT kind, role, count(*) rows
        FROM pending_agreement
        GROUP BY kind, role
      ) x
    ),
    'pending_agreement_notification_coverage', (
      SELECT jsonb_build_object(
        'pending_total', count(*),
        'with_agreement_notification', count(*) FILTER (WHERE has_agreement_notification),
        'without_agreement_notification', count(*) FILTER (WHERE NOT has_agreement_notification)
      )
      FROM pending_with_notification
    )
  ),
  'certificates', jsonb_build_object(
    'total', (SELECT count(*) FROM cert_base),
    'by_type_status', (
      SELECT jsonb_agg(to_jsonb(x) ORDER BY rows DESC, type, status)
      FROM (SELECT type, status, count(*) rows FROM cert_base GROUP BY type, status) x
    ),
    'signed_or_counter_signed_total', (SELECT count(*) FROM cert_signed),
    'signature_hash_missing_on_signed', (
      SELECT count(*) FROM cert_signed WHERE signature_hash IS NULL
    ),
    'counter_signed_total', (
      SELECT count(*) FROM cert_base WHERE counter_signed_at IS NOT NULL
    ),
    'counter_signature_hash_column_exists', EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'certificates'
        AND column_name = 'counter_signature_hash'
    ),
    'signed_ip_missing_on_signed', (
      SELECT count(*) FROM cert_signed WHERE signed_ip IS NULL
    ),
    'signed_user_agent_missing_on_signed', (
      SELECT count(*) FROM cert_signed WHERE signed_user_agent IS NULL
    ),
    'period_end_distribution', (
      SELECT jsonb_agg(to_jsonb(x) ORDER BY rows DESC, period_end)
      FROM (SELECT period_end, count(*) rows FROM cert_base GROUP BY period_end) x
    ),
    'source_distribution', (
      SELECT jsonb_object_agg(coalesce(source, 'NULL'), rows)
      FROM (SELECT source, count(*) rows FROM cert_base GROUP BY source) s
    )
  )
) AS lifecycle_evidence;
```

---

## 3. Hashed Detail Evidence

Usar para triagem operacional sem publicar email/nome.

```sql
WITH
approved_apps AS (
  SELECT id, email, status, role_applied, created_at, updated_at
  FROM public.selection_applications
  WHERE status IN ('approved', 'converted')
),
approved_without_member AS (
  SELECT aa.*
  FROM approved_apps aa
  WHERE NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE lower(m.email) = lower(aa.email)
  )
),
pending_agreement AS (
  SELECT ae.*
  FROM public.auth_engagements ae
  WHERE ae.status = 'active'
    AND ae.requires_agreement IS TRUE
    AND ae.agreement_certificate_id IS NULL
),
pending_with_notification AS (
  SELECT
    pa.engagement_id,
    pa.person_id,
    pa.kind,
    pa.role,
    pa.start_date,
    EXISTS (
      SELECT 1
      FROM public.members m
      JOIN public.notifications n ON n.recipient_id = m.id
      WHERE m.person_id = pa.person_id
        AND n.created_at >= COALESCE(pa.start_date::timestamptz, now() - interval '365 days')
        AND (
          lower(coalesce(n.title, '')) LIKE '%termo%'
          OR lower(coalesce(n.body, '')) LIKE '%termo%'
          OR lower(coalesce(n.type, '')) LIKE '%agreement%'
          OR lower(coalesce(n.type, '')) LIKE '%certificate%'
        )
    ) AS has_agreement_notification
  FROM pending_agreement pa
),
pending_sample AS (
  SELECT *
  FROM pending_with_notification
  ORDER BY has_agreement_notification ASC, kind, role
  LIMIT 20
)
SELECT jsonb_build_object(
  'approved_without_member_samples', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'application_id', id,
      'email_hash', md5(lower(email)),
      'status', status,
      'role_applied', role_applied,
      'created_at', created_at,
      'updated_at', updated_at
    ) ORDER BY updated_at DESC), '[]'::jsonb)
    FROM approved_without_member
  ),
  'pending_agreement_without_notification_by_kind_role', (
    SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY rows DESC, kind, role), '[]'::jsonb)
    FROM (
      SELECT kind, role, count(*) rows
      FROM pending_with_notification
      WHERE NOT has_agreement_notification
      GROUP BY kind, role
    ) x
  ),
  'pending_agreement_samples_hashed', (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'engagement_id', engagement_id,
      'person_hash', md5(person_id::text),
      'kind', kind,
      'role', role,
      'start_date', start_date,
      'has_agreement_notification', has_agreement_notification
    ) ORDER BY has_agreement_notification ASC, kind, role), '[]'::jsonb)
    FROM pending_sample
  )
) AS lifecycle_evidence_detail;
```

---

## 4. Function Definition Checks

Usar para confirmar se os fixes de #181 entraram.

```sql
SELECT
  proname,
  pg_get_functiondef(p.oid) AS function_def
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'sign_volunteer_agreement',
    'counter_sign_certificate',
    'get_my_signatures'
  );
```

Checks esperados após #181:

- `certificates.counter_signature_hash` existe.
- `counter_sign_certificate()` faz `UPDATE certificates SET counter_signature_hash = ...`.
- decisão sobre `signed_ip`/`signed_user_agent` está refletida no código ou em comentário de schema.
- `get_my_signatures()` inclui certificados/termos quando essa for a decisão de produto/LGPD.


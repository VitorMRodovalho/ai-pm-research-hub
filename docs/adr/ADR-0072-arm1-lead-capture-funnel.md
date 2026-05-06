# ADR-0072: ARM-1 Lead Capture & Funnel (visitor_leads enrichment)

**Status**: Accepted
**Date**: 2026-05-06
**Decider**: PM Vitor Maia Rodovalho (GP Núcleo IA & GP)
**Trigger**: ARM-1 Captação deep dive (sessão p108 cont., plano ABCD bloco B)

---

## Context

ARM-1 Captação foi reportado em maturidade 1 no `ARM_PILLARS_AUDIT_P107.md`. Audit revelou substrato parcial:

- `visitor_leads` table existe com schema base (name, email, phone, chapter_interest, role_interest, message, lgpd_consent, source, status) + RLS com policy "Anyone can submit lead" (anon insert allowed) + admin read/update via `manage_member`
- Form em `/about` (ImpactPageIsland.tsx) já fazia `sb.from('visitor_leads').insert()` direct
- 0 leads em produção até este momento — table existia mas pipeline nunca foi exercitado

Gaps reais identificados:

1. **Sem UTM enrichment** — capture só populava `source='website'` hardcoded; URL query params (utm_*, ref) eram descartados
2. **Sem promote path** — leads não tinham caminho formal para virar `selection_applications` (re-typing manual em VEP era caminho real)
3. **Sem admin visibility** — sem RPC `list_visitor_leads`, sem dashboard
4. **Sem funnel stats** — impossível responder "leads → applications conversion rate"
5. **Status não enforced** — `status` era text livre sem CHECK

## Decision

### Schema enrichment (visitor_leads)

```sql
ALTER TABLE visitor_leads ADD COLUMN
  utm_data jsonb,
  referrer_member_id uuid REFERENCES members(id),
  promoted_to_application_id uuid REFERENCES selection_applications(id),
  promoted_at timestamptz, promoted_by uuid REFERENCES members(id),
  dismissed_at timestamptz, dismissed_by uuid REFERENCES members(id),
  dismissal_reason text,
  dedupe_email_normalized text GENERATED ALWAYS AS (LOWER(TRIM(email))) STORED;

ALTER TABLE visitor_leads ADD CONSTRAINT visitor_leads_status_check
  CHECK (status IS NULL OR status IN ('new','contacted','promoted','dismissed'));
```

Mirror das colunas de `selection_applications` (Onda 2.1) para preservar UTM/referrer semantics quando lead é promovido.

### State machine `visitor_leads.status`

```
new (default) → contacted → promoted (terminal good)
                          → dismissed (terminal bad)
              → promoted (skip contacted, direct via admin curation)
              → dismissed (skip contacted, direct admin discard)
```

`promoted` e `dismissed` são terminais; sem voltar para `new`.

### 5 RPCs

| RPC | Auth | Purpose |
|-----|------|---------|
| `capture_visitor_lead(p_payload jsonb)` | **anon-callable** | Public capture com LGPD consent + email format check + idempotência (same email + status=new → update last-wins) |
| `list_visitor_leads(p_status, p_chapter, p_limit)` | manage_member | Admin view com referrer/contacted_by/promoted_by/dismissed_by name JOINs |
| `promote_lead_to_application(p_lead_id, p_cycle_id, p_pmi_id)` | manage_member | INSERT em selection_applications + UPDATE lead status='promoted'; cycle.status='open' guard |
| `dismiss_visitor_lead(p_lead_id, p_reason)` | manage_member | UPDATE status='dismissed' + audit log |
| `get_volunteer_funnel_stats(p_cycle_id)` | manage_member | Funnel breakdown: lead status counts + app status counts + by_source (UTM) + by_chapter |

Todos com `SECURITY DEFINER`, `SET search_path`, audit log entries.

### LGPD safeguards no `capture_visitor_lead`

- `lgpd_consent` é mandatório (boolean true). RPC retorna `error` se false/missing
- Email format checked via regex `^[^@]+@[^@]+\.[^@]+$` (soft validation)
- Email normalized lowercase + trimmed (dedupe via stored generated column)
- Idempotente: same email + status=new → update last-wins (não cria duplicata)

### Frontend update (ImpactPageIsland.tsx)

Mudou de `sb.from('visitor_leads').insert(...)` para `sb.rpc('capture_visitor_lead', { p_payload })`. Captura adicional de URL query params:

- `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content` → `utm_data` jsonb
- `ref` ou `referrer` (UUID member) → `referrer_member_id`
- `source` derivado de `utm_source` quando presente (formato `utm:google`, `utm:linkedin`, etc.); fallback `website`

### `dedupe_email_normalized` GENERATED column

Permite UNIQUE em emails normalizados sem duplicar lógica. Index `idx_visitor_leads_email_norm` viabiliza dedup query rápida.

## Implementation

Migration: `20260516890000_arm1_lead_capture_funnel.sql`

Frontend: `src/components/islands/ImpactPageIsland.tsx` (handleSubmit refactor)

Endpoint público: `/about` (e seus equivalentes /en/about, /es/about) já são as landing pages que servem o form. Sem necessidade de criar nova rota `/volunteer` separada — o substrato já existia e é mais coerente surfacing existente.

## Consequences

### Positive

- Funnel completo visitor_leads → selection_applications
- UTM tracking real-time (preservado no promote → application)
- LGPD compliant: consent gate + audit log + idempotência preserva direito de retificação
- Admin visibility via RPC (futuro: `/admin/funnel` page surface this)
- Status state machine enforced via CHECK
- `referrer_member_id` permite member-driven recruitment tracking (`?ref=member_uuid` em link compartilhado)
- 0 breaking changes (form em /about continua funcional, agora via RPC)

### Negative

- Direct INSERT via RLS ainda permitido (compatibility) — `capture_visitor_lead` é o canonical path mas RLS policy "Anyone can submit lead" persiste. Future cleanup: migrar para RPC-only após verificar 100% do traffic via RPC.
- Frontend dashboard `/admin/funnel` não criado nesta sessão (RPC pronto, surface defer)

### LGPD note

- `visitor_leads` é PII (email, phone, name). RLS atual permite anon INSERT com consent gate. Read restrito a `manage_member` permission.
- Anonymization cron monthly (já existe `lgpd-anonymize-inactive-monthly`) cobre via members; visitor_leads pode precisar cron próprio se volume crescer. Defer até primeira coorte significativa.

## Follow-ups

1. **Frontend `/admin/funnel` dashboard** — surface `get_volunteer_funnel_stats` com chart por source + chapter. Onda 4 browser session.
2. **Auto-promote cron quando cycle abre** — opcional, baseado em opt-in do lead; manual é suficiente para volume atual.
3. **MCP exposure** dos 5 RPCs (admin domain) — defer próxima sessão MCP.
4. **Anonymization cron** específico de visitor_leads quando volume > 1000.
5. **Dedupe enforcement**: hoje idempotente em `capture_visitor_lead` mas `bulk insert via RLS direct` ainda pode duplicar. Migrar para RPC-only no futuro.

## References

- Migration: `supabase/migrations/20260516890000_arm1_lead_capture_funnel.sql`
- Frontend: `src/components/islands/ImpactPageIsland.tsx` (LeadCaptureForm)
- Mirror schema: `selection_applications` Onda 2.1 (`utm_data`, `referral_source`, `referrer_member_id`)
- ADR-0011: V4 authority (`can_by_member` para gates admin)
- Audit doc: `docs/strategy/ARM_PILLARS_AUDIT_P107.md`

-- ============================================================================
-- V4 Phase 3 — Migration 2/3: persons table + backfill from members
-- ADR: ADR-0006 (Person + Engagement Identity Model)
-- Depends on: 20260413300000_v4_phase3_engagement_kinds.sql
-- Rollback: ALTER TABLE public.members DROP COLUMN person_id;
--           DROP TABLE public.persons CASCADE;
-- ============================================================================

-- persons is the universal identity table. One row per human, regardless of
-- how many engagements they have across orgs/initiatives. PII lives here.
-- members.person_id is the bridge column during transition.

CREATE TABLE public.persons (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                    REFERENCES public.organizations(id) ON DELETE RESTRICT,
  auth_id           uuid UNIQUE,
  name              text NOT NULL,
  email             text NOT NULL,
  secondary_emails  text[] NOT NULL DEFAULT '{}'::text[],
  photo_url         text,
  linkedin_url      text,
  pmi_id            text,
  phone             text,
  address           text,
  city              text,
  state             text,
  country           text DEFAULT 'Brazil',
  birth_date        date,
  share_whatsapp    boolean NOT NULL DEFAULT false,
  share_address     boolean NOT NULL DEFAULT false,
  share_birth_date  boolean NOT NULL DEFAULT false,
  consent_status    text NOT NULL DEFAULT 'pending'
                    CHECK (consent_status IN ('pending', 'accepted', 'revoked')),
  consent_accepted_at timestamptz,
  consent_version   text,
  credly_url        text,
  credly_badges     jsonb DEFAULT '[]'::jsonb,
  credly_verified_at timestamptz,
  legacy_member_id  uuid UNIQUE,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.persons IS 'V4: Universal identity — one row per human. PII lives here. legacy_member_id bridges to members.id during transition (ADR-0006).';

CREATE INDEX idx_persons_org ON public.persons(organization_id);
CREATE INDEX idx_persons_auth ON public.persons(auth_id) WHERE auth_id IS NOT NULL;
CREATE INDEX idx_persons_email ON public.persons(email);
CREATE INDEX idx_persons_legacy_member ON public.persons(legacy_member_id) WHERE legacy_member_id IS NOT NULL;

ALTER TABLE public.persons ENABLE ROW LEVEL SECURITY;

-- Authenticated users can see persons in their org (non-PII fields via views)
CREATE POLICY "persons_select_authenticated"
  ON public.persons FOR SELECT TO authenticated
  USING (true);

-- Org-scoped RESTRICTIVE policy
CREATE POLICY "persons_org_scope"
  ON public.persons AS RESTRICTIVE FOR ALL TO authenticated
  USING (organization_id = public.auth_org() OR organization_id IS NULL)
  WITH CHECK (organization_id = public.auth_org());

-- ── Backfill: 71 members → 71 persons ─────────────────────────────────────
INSERT INTO public.persons (
  organization_id, auth_id, name, email, secondary_emails,
  photo_url, linkedin_url, pmi_id, phone,
  address, city, state, country, birth_date,
  share_whatsapp, share_address, share_birth_date,
  consent_status, consent_accepted_at, consent_version,
  credly_url, credly_badges, credly_verified_at,
  legacy_member_id, created_at
)
SELECT
  m.organization_id,
  m.auth_id,
  m.name,
  m.email,
  COALESCE(m.secondary_emails, '{}'::text[]),
  m.photo_url,
  m.linkedin_url,
  m.pmi_id,
  m.phone,
  m.address,
  m.city,
  m.state,
  m.country,
  m.birth_date,
  COALESCE(m.share_whatsapp, false),
  COALESCE(m.share_address, false),
  COALESCE(m.share_birth_date, false),
  CASE
    WHEN m.privacy_consent_accepted_at IS NOT NULL THEN 'accepted'
    ELSE 'pending'
  END,
  m.privacy_consent_accepted_at,
  m.privacy_consent_version,
  m.credly_url,
  COALESCE(m.credly_badges, '[]'::jsonb),
  m.credly_verified_at,
  m.id,
  m.created_at
FROM public.members m
ORDER BY m.created_at;

-- ── Bridge: add person_id to members ──────────────────────────────────────
ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS person_id uuid
    REFERENCES public.persons(id) ON DELETE SET NULL;

UPDATE public.members m
SET person_id = p.id
FROM public.persons p
WHERE p.legacy_member_id = m.id;

CREATE INDEX IF NOT EXISTS idx_members_person
  ON public.members(person_id) WHERE person_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';

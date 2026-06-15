-- =====================================================================================
-- #700 Agenda Viva [Foundation] — SLICE 1: schema + catalog + RLS + V4 action seed
--
-- Parent epic #698. The Reunião Geral (events.type='geral', 90 min) hosts volunteer-owned
-- "blocks" of 5/10/15/20/30 min. Today the agenda is coordinated over WhatsApp; this
-- structures it as a transparent reservable layer with protagonism XP (XP + RPCs land in
-- slices 2-3).
--
-- Scope of THIS slice (DB foundation only — NO RPCs yet):
--   1. `agenda_block_formats` config-driven catalog (ADR-0009/0081) + trilingual seed.
--   2. `event_agenda_blocks` canonical table (constraints, indexes) + audit table/trigger.
--   3. RLS: owner + manage_event read; anon denied at the table (public read arrives via a
--      SECURITY DEFINER RPC in slice 2). Writes happen exclusively through SECDEF RPCs
--      (slice 2) so the 90-min capacity invariant can be enforced under a row lock — direct
--      table writes are intentionally NOT granted (mirrors #676 recurring_meeting_rules).
--   4. New V4 org-scoped action `reserve_agenda_block` seeded in
--      engagement_kind_permissions for every active "doer" engagement combo (PM decision
--      2026-06-15: all active volunteers/doers, not just leadership — the rank-and-file
--      volunteer/researcher cohort is exactly who should reserve protagonism blocks).
--
-- Authority note (V4_AUTHORITY_MODEL 4-step): reserve_agenda_block is a NEW, non-destructive,
-- self-scoped capability (caller reserves only for themselves via auth.uid() in the RPC). It
-- is not a gap in an existing action, so Path 1 (engagement_kind_permissions) is the canonical
-- model. can() matches (kind, role) EXACTLY and requires is_authoritative (signed term), so the
-- full (kind, role) universe of doer engagements is enumerated below; org scope always grants.
--
-- NOT in scope here: reserve/update/cancel/confirm/reorder RPCs, get_geral_agenda_viva,
-- gamification pillar + XP crediting, frontend. Capacity ≤90 is RPC-enforced (slice 2).
--
-- Convention notes:
--   - duration_min CHECK (%5=0 AND >0); UNIQUE(event_id, owner_member_id) = 1 block/person/event.
--   - organization_id default = canonical org (matches #676).
--
-- ROLLBACK:
--   DROP TABLE IF EXISTS public.event_agenda_block_audit CASCADE;
--   DROP TABLE IF EXISTS public.event_agenda_blocks CASCADE;
--   DROP TABLE IF EXISTS public.agenda_block_formats CASCADE;
--   DROP FUNCTION IF EXISTS public.eab_audit_trigger();
--   DELETE FROM public.engagement_kind_permissions WHERE action = 'reserve_agenda_block';
-- =====================================================================================

-- ----------------------------------------------------------------------------
-- 1) Config-driven format catalog (coordination can tune without a migration).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.agenda_block_formats (
  slug                  text PRIMARY KEY,
  label_i18n            jsonb NOT NULL,        -- {pt-BR, en-US, es-LATAM}
  base_points           integer NOT NULL CHECK (base_points >= 0),
  default_duration_min  integer NOT NULL CHECK (default_duration_min > 0 AND default_duration_min % 5 = 0),
  active                boolean NOT NULL DEFAULT true,
  sort_order            integer NOT NULL DEFAULT 0,
  organization_id       uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                          REFERENCES public.organizations(id),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.agenda_block_formats IS
  '#700 config-driven catalog of Reunião Geral block formats (ADR-0009/0081). base_points × duration weight + bonuses = protagonism XP (credited on confirmation, slice 3).';

INSERT INTO public.agenda_block_formats (slug, label_i18n, base_points, default_duration_min, sort_order)
VALUES
  ('prompt_semana',     '{"pt-BR":"Prompt da Semana","en-US":"Prompt of the Week","es-LATAM":"Prompt de la Semana"}'::jsonb,      20, 15, 10),
  ('review_ferramenta', '{"pt-BR":"Review de Ferramenta","en-US":"Tool Review","es-LATAM":"Reseña de Herramienta"}'::jsonb,        20, 10, 20),
  ('insight_rapido',    '{"pt-BR":"Insight Rápido","en-US":"Quick Insight","es-LATAM":"Insight Rápido"}'::jsonb,                   15,  5, 30),
  ('pilula_quinzena',   '{"pt-BR":"Pílula da Quinzena","en-US":"Fortnight Pill","es-LATAM":"Píldora de la Quincena"}'::jsonb,      15,  5, 40),
  ('case_aplicado',     '{"pt-BR":"Case Aplicado","en-US":"Applied Case","es-LATAM":"Caso Aplicado"}'::jsonb,                      25, 20, 50),
  ('demo_pratica',      '{"pt-BR":"Demonstração Prática","en-US":"Practical Demo","es-LATAM":"Demostración Práctica"}'::jsonb,     25, 20, 60),
  ('convidado',         '{"pt-BR":"Convidado Relâmpago","en-US":"Lightning Guest","es-LATAM":"Invitado Relámpago"}'::jsonb,        20, 15, 70),
  ('espaco_aberto',     '{"pt-BR":"Espaço Aberto","en-US":"Open Space","es-LATAM":"Espacio Abierto"}'::jsonb,                      10, 10, 80)
ON CONFLICT (slug) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2) Canonical reservable-block table.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_agenda_blocks (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id          uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  owner_member_id   uuid NOT NULL REFERENCES public.members(id) ON DELETE CASCADE,
  format_slug       text NOT NULL REFERENCES public.agenda_block_formats(slug),
  title             text NOT NULL,
  duration_min      integer NOT NULL CHECK (duration_min > 0 AND duration_min % 5 = 0),
  guest_name        text,
  material_url      text,
  external_guest    boolean NOT NULL DEFAULT false,
  sort_order        integer NOT NULL DEFAULT 0,
  status            text NOT NULL DEFAULT 'reserved'
                       CHECK (status IN ('reserved','confirmed','cancelled','no_show')),
  reserved_at       timestamptz NOT NULL DEFAULT now(),
  confirmed_at      timestamptz,
  cancelled_by      uuid REFERENCES public.members(id) ON DELETE SET NULL,
  cancelled_reason  text,
  created_by        uuid REFERENCES public.members(id) ON DELETE SET NULL,
  organization_id   uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
                       REFERENCES public.organizations(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT eab_one_block_per_person_per_event UNIQUE (event_id, owner_member_id)
);

CREATE INDEX IF NOT EXISTS ix_eab_event_status   ON public.event_agenda_blocks(event_id, status);
CREATE INDEX IF NOT EXISTS ix_eab_owner          ON public.event_agenda_blocks(owner_member_id);

COMMENT ON TABLE public.event_agenda_blocks IS
  '#700 Agenda Viva: volunteer-reserved blocks on a Reunião Geral. Capacity SUM(duration_min) WHERE status IN (reserved,confirmed) ≤ 90 is enforced in the reserve RPC under a row lock (slice 2), not as a cross-row CHECK.';

-- ----------------------------------------------------------------------------
-- 3) Audit table + trigger (keeps updated_at fresh + change history).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.event_agenda_block_audit (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  block_id    uuid,
  action      text NOT NULL,                  -- insert | update | delete
  actor_id    uuid,
  old_row     jsonb,
  new_row     jsonb,
  changed_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_eab_audit_block ON public.event_agenda_block_audit(block_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.eab_audit_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.event_agenda_block_audit(block_id, action, actor_id, new_row)
    VALUES (NEW.id, 'insert', auth.uid(), to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_at := now();
    INSERT INTO public.event_agenda_block_audit(block_id, action, actor_id, old_row, new_row)
    VALUES (NEW.id, 'update', auth.uid(), to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSE
    INSERT INTO public.event_agenda_block_audit(block_id, action, actor_id, old_row)
    VALUES (OLD.id, 'delete', auth.uid(), to_jsonb(OLD));
    RETURN OLD;
  END IF;
END
$function$;

DROP TRIGGER IF EXISTS trg_eab_audit ON public.event_agenda_blocks;
CREATE TRIGGER trg_eab_audit
  BEFORE INSERT OR UPDATE OR DELETE ON public.event_agenda_blocks
  FOR EACH ROW EXECUTE FUNCTION public.eab_audit_trigger();

-- ----------------------------------------------------------------------------
-- 4) RLS — catalog is public-read (no PII); blocks are owner/manage_event read;
--    anon never reads the blocks table (public agenda arrives via SECDEF RPC, slice 2).
-- ----------------------------------------------------------------------------
ALTER TABLE public.agenda_block_formats     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_agenda_blocks      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_agenda_block_audit ENABLE ROW LEVEL SECURITY;

-- Catalog: anyone (incl. anon) may read active+inactive labels to render the agenda UI.
DROP POLICY IF EXISTS abf_select_all ON public.agenda_block_formats;
CREATE POLICY abf_select_all ON public.agenda_block_formats
  FOR SELECT TO anon, authenticated
  USING (true);

-- Blocks: a member sees their own; manage_event sees all. No anon table read.
DROP POLICY IF EXISTS eab_select_owner_or_admin ON public.event_agenda_blocks;
CREATE POLICY eab_select_owner_or_admin ON public.event_agenda_blocks
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.auth_id = auth.uid()
        AND (m.id = event_agenda_blocks.owner_member_id
             OR public.can_by_member(m.id, 'manage_event'))
    )
  );

-- Audit: manage_event read only.
DROP POLICY IF EXISTS eab_audit_select_admin ON public.event_agenda_block_audit;
CREATE POLICY eab_audit_select_admin ON public.event_agenda_block_audit
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.auth_id = auth.uid() AND public.can_by_member(m.id, 'manage_event')
  ));

-- Grants: catalog readable by anon+auth; blocks readable by auth only (RLS-scoped);
-- writes to blocks happen via SECDEF RPCs (slice 2), never directly.
REVOKE ALL ON public.agenda_block_formats     FROM anon, PUBLIC;
REVOKE ALL ON public.event_agenda_blocks      FROM anon, PUBLIC;
REVOKE ALL ON public.event_agenda_block_audit FROM anon, PUBLIC;
GRANT SELECT ON public.agenda_block_formats     TO anon, authenticated;
GRANT SELECT ON public.event_agenda_blocks      TO authenticated;
GRANT SELECT ON public.event_agenda_block_audit TO authenticated;

-- ----------------------------------------------------------------------------
-- 5) Seed the new V4 action reserve_agenda_block for all active "doer" combos.
--    can() matches (kind, role) exactly; org scope always grants. Idempotent via
--    NOT EXISTS (no unique constraint on engagement_kind_permissions).
-- ----------------------------------------------------------------------------
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description, organization_id)
SELECT v.kind, v.role, 'reserve_agenda_block', 'organization',
       '#700 reserve a protagonism block on the Reunião Geral (Agenda Viva)',
       '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
FROM (VALUES
  ('committee_coordinator','coordinator'),
  ('committee_coordinator','leader'),
  ('committee_member','coordinator'),
  ('committee_member','leader'),
  ('committee_member','participant'),
  ('study_group_owner','leader'),
  ('study_group_owner','owner'),
  ('study_group_participant','leader'),
  ('study_group_participant','participant'),
  ('volunteer','co_gp'),
  ('volunteer','comms_leader'),
  ('volunteer','communicator'),
  ('volunteer','coordinator'),
  ('volunteer','curator'),
  ('volunteer','deputy_manager'),
  ('volunteer','facilitator'),
  ('volunteer','leader'),
  ('volunteer','manager'),
  ('volunteer','observer'),
  ('volunteer','participant'),
  ('volunteer','researcher'),
  ('workgroup_coordinator','coordinator'),
  ('workgroup_coordinator','leader'),
  ('workgroup_member','coordinator'),
  ('workgroup_member','leader'),
  ('workgroup_member','participant'),
  ('workgroup_member','researcher')
) AS v(kind, role)
WHERE NOT EXISTS (
  SELECT 1 FROM public.engagement_kind_permissions ekp
  WHERE ekp.kind = v.kind AND ekp.role = v.role AND ekp.action = 'reserve_agenda_block'
);

NOTIFY pgrst, 'reload schema';

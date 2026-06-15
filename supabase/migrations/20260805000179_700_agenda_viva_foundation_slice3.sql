-- =====================================================================================
-- #700 Agenda Viva [Foundation] — SLICE 3: gamification pillar + confirm/XP + revoke
--
-- Builds on slice 1 (tables + V4 action) and slice 2 (reserve/read/update/cancel/reorder).
-- This slice closes the Foundation by crediting protagonismo XP at confirmation time.
--
-- Scope of THIS slice:
--   1. New gamification pillar `protagonismo` (extends the gamification_rules.pillar CHECK).
--   2. Config-driven gamification_rules seed: the credit anchor `agenda_block_protagonismo`
--      (ledger category; base comes from the FORMAT, not this row) + 3 bonus config rows
--      (`agenda_block_bonus_external_guest` +2 · `agenda_block_bonus_shared_material` +1 ·
--      `agenda_block_bonus_first_time` +1). Coordination tunes bonuses via /admin/gamification
--      without a migration (ADR-0009 config-not-code).
--   3. _grant_agenda_block_xp(block_id) — pure credit helper. Computes
--      pontos = round(format.base_points × duration_weight) + Σ active bonuses, writes ONE
--      gamification_points row (category = 'agenda_block_protagonismo', ref_id = block_id),
--      idempotent by (ref_id, category, member_id). Honors the rule's `active` kill-switch.
--      Duration weight bands: 5–10 ×1.0 · 15–20 ×1.15 · ≥25 ×1.3. first_time computed here
--      (anti-gaming: NOT persisted — counts the owner's OTHER confirmed blocks).
--   4. confirm_agenda_block(block_id) + confirm_event_blocks(event_id) — gate manage_event;
--      set status='confirmed'; credit XP ONLY when attendance.present = true for the owner.
--   5. revoke_agenda_block_xp(block_id, reason?) — gate manage_event; status → 'no_show',
--      delete the protagonismo ledger row(s), clear confirmed_at.
--
-- NOT in scope: dedicated protagonismo bucket in the leaderboard/tribe per-pillar displays
--   (p165/p167) and the admin/gamification pillar list — protagonismo points are already
--   carried correctly in every TOTAL (unfiltered SUM) and surface as their own pillar group
--   in get_member_xp_pillars_v2; the dedicated display bucket is frontend follow-up (#701).
--   Frontend reservation/confirm UI is #701.
--
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.confirm_agenda_block(uuid);
--   DROP FUNCTION IF EXISTS public.confirm_event_blocks(uuid);
--   DROP FUNCTION IF EXISTS public.revoke_agenda_block_xp(uuid, text);
--   DROP FUNCTION IF EXISTS public._grant_agenda_block_xp(uuid);
--   DELETE FROM public.gamification_points WHERE category = 'agenda_block_protagonismo';
--   DELETE FROM public.gamification_rules WHERE slug IN
--     ('agenda_block_protagonismo','agenda_block_bonus_external_guest',
--      'agenda_block_bonus_shared_material','agenda_block_bonus_first_time');
--   ALTER TABLE public.gamification_rules DROP CONSTRAINT gamification_rules_pillar_check;
--   ALTER TABLE public.gamification_rules ADD CONSTRAINT gamification_rules_pillar_check
--     CHECK (pillar = ANY (ARRAY['presenca','trilha','certificacoes','producao','curadoria','champions']));
-- =====================================================================================

-- ----------------------------------------------------------------------------
-- 1) Enable the `protagonismo` pillar.
-- ----------------------------------------------------------------------------
ALTER TABLE public.gamification_rules DROP CONSTRAINT gamification_rules_pillar_check;
ALTER TABLE public.gamification_rules ADD CONSTRAINT gamification_rules_pillar_check
  CHECK (pillar = ANY (ARRAY['presenca','trilha','certificacoes','producao','curadoria','champions','protagonismo']));

-- ----------------------------------------------------------------------------
-- 2) Seed protagonismo rules for every organization that already uses gamification.
--    The credit anchor carries base_points = 0 (the real base lives in the FORMAT row);
--    the three bonus rows hold the tunable bonus amounts as base_points.
-- ----------------------------------------------------------------------------
INSERT INTO public.gamification_rules
  (organization_id, slug, display_name_i18n, description_i18n, base_points, pillar, trigger_source, active)
SELECT o.organization_id, s.slug, s.display_name_i18n, s.description_i18n, s.base_points, 'protagonismo', 'rpc_callback', true
FROM (SELECT DISTINCT organization_id FROM public.gamification_rules) o
CROSS JOIN (VALUES
  ('agenda_block_protagonismo',
   '{"pt-BR":"Protagonismo: bloco na Reunião Geral","en-US":"Protagonism: General Meeting block","es-LATAM":"Protagonismo: bloque en la Reunión General"}'::jsonb,
   '{"pt-BR":"Pontos por apresentar um bloco confirmado na Reunião Geral (base do formato × peso da duração + bônus).","en-US":"Points for presenting a confirmed block at the General Meeting (format base × duration weight + bonuses).","es-LATAM":"Puntos por presentar un bloque confirmado en la Reunión General (base del formato × peso de la duración + bonos)."}'::jsonb,
   0),
  ('agenda_block_bonus_external_guest',
   '{"pt-BR":"Bônus: convidado externo","en-US":"Bonus: external guest","es-LATAM":"Bono: invitado externo"}'::jsonb,
   '{"pt-BR":"Bônus por trazer um convidado externo ao bloco.","en-US":"Bonus for bringing an external guest to the block.","es-LATAM":"Bono por traer un invitado externo al bloque."}'::jsonb,
   2),
  ('agenda_block_bonus_shared_material',
   '{"pt-BR":"Bônus: material compartilhado","en-US":"Bonus: shared material","es-LATAM":"Bono: material compartido"}'::jsonb,
   '{"pt-BR":"Bônus por compartilhar material de apoio do bloco.","en-US":"Bonus for sharing supporting material for the block.","es-LATAM":"Bono por compartir material de apoyo del bloque."}'::jsonb,
   1),
  ('agenda_block_bonus_first_time',
   '{"pt-BR":"Bônus: primeira vez","en-US":"Bonus: first time","es-LATAM":"Bono: primera vez"}'::jsonb,
   '{"pt-BR":"Bônus na primeira vez que o voluntário apresenta um bloco.","en-US":"Bonus on the volunteer''s first presented block.","es-LATAM":"Bono en la primera vez que el voluntario presenta un bloque."}'::jsonb,
   1)
) AS s(slug, display_name_i18n, description_i18n, base_points)
ON CONFLICT (organization_id, slug) DO UPDATE
  -- `active` is intentionally NOT in the SET clause: a re-run must preserve any
  -- operator kill-switch state set via /admin/gamification.
  SET display_name_i18n = EXCLUDED.display_name_i18n,
      description_i18n  = EXCLUDED.description_i18n,
      base_points      = EXCLUDED.base_points,
      pillar           = EXCLUDED.pillar,
      trigger_source   = EXCLUDED.trigger_source,
      updated_at       = now();

-- ----------------------------------------------------------------------------
-- 3) _grant_agenda_block_xp — pure credit helper (no auth/attendance gating here;
--    the caller decides whether to credit). Idempotent; honors the rule kill-switch.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._grant_agenda_block_xp(p_block_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_block    record;
  v_org      uuid;
  v_base     int;
  v_weight   numeric;
  v_bonus    int := 0;
  v_total    int;
  v_reason   text;
BEGIN
  SELECT b.id, b.event_id, b.owner_member_id, b.format_slug, b.duration_min,
         b.external_guest, b.material_url, b.title, b.organization_id
    INTO v_block
    FROM public.event_agenda_blocks b
    WHERE b.id = p_block_id;
  IF v_block.id IS NULL OR v_block.owner_member_id IS NULL THEN
    RETURN;
  END IF;
  v_org := v_block.organization_id;

  -- Kill-switch: skip if the protagonismo credit rule is disabled/missing for this org.
  IF NOT EXISTS (
    SELECT 1 FROM public.gamification_rules
    WHERE slug = 'agenda_block_protagonismo' AND organization_id = v_org
      AND active = true AND effective_from <= now()
  ) THEN
    RETURN;
  END IF;

  -- Idempotency: one protagonismo credit per (block, owner).
  IF EXISTS (
    SELECT 1 FROM public.gamification_points
    WHERE ref_id = p_block_id AND category = 'agenda_block_protagonismo'
      AND member_id = v_block.owner_member_id
  ) THEN
    RETURN;
  END IF;

  -- Base from the FORMAT catalog (config-driven). Missing format → no credit.
  SELECT base_points INTO v_base FROM public.agenda_block_formats WHERE slug = v_block.format_slug;
  IF v_base IS NULL THEN
    RETURN;
  END IF;

  -- Duration weight bands (multiples of 5): 5–10 ×1.0 · 15–20 ×1.15 · ≥25 ×1.3.
  v_weight := CASE
    WHEN v_block.duration_min <= 10 THEN 1.0
    WHEN v_block.duration_min <= 20 THEN 1.15
    ELSE 1.3
  END;

  -- Config bonuses (amount = the bonus rule's base_points; absent/inactive → 0).
  IF v_block.external_guest IS TRUE THEN
    v_bonus := v_bonus + COALESCE((SELECT base_points FROM public.gamification_rules
      WHERE slug = 'agenda_block_bonus_external_guest' AND organization_id = v_org AND active = true), 0);
  END IF;
  IF v_block.material_url IS NOT NULL AND btrim(v_block.material_url) <> '' THEN
    v_bonus := v_bonus + COALESCE((SELECT base_points FROM public.gamification_rules
      WHERE slug = 'agenda_block_bonus_shared_material' AND organization_id = v_org AND active = true), 0);
  END IF;
  -- first_time: owner has no OTHER confirmed block (computed at confirmation, never stored).
  IF NOT EXISTS (
    SELECT 1 FROM public.event_agenda_blocks
    WHERE owner_member_id = v_block.owner_member_id AND status = 'confirmed' AND id <> p_block_id
  ) THEN
    v_bonus := v_bonus + COALESCE((SELECT base_points FROM public.gamification_rules
      WHERE slug = 'agenda_block_bonus_first_time' AND organization_id = v_org AND active = true), 0);
  END IF;

  v_total := round(v_base * v_weight)::int + v_bonus;
  v_reason := 'Bloco na Reunião Geral: ' || v_block.title || ' (' || v_block.format_slug || ', ' || v_block.duration_min || 'min)';

  INSERT INTO public.gamification_points (member_id, points, reason, category, ref_id, organization_id)
  VALUES (v_block.owner_member_id, v_total, v_reason, 'agenda_block_protagonismo', p_block_id, v_org);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 4a) confirm_agenda_block — manage_event; status→confirmed; credit XP iff present.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_agenda_block(p_block_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_block   record;
  v_present boolean;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  SELECT * INTO v_block FROM public.event_agenda_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  IF v_block.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'cannot_confirm_cancelled', 'block_id', p_block_id);
  END IF;
  -- Re-confirming an already-confirmed block is intentionally a no-op on XP (the credit is
  -- idempotent by ref_id) but DOES re-attempt the credit — this is the heal path for
  -- "confirmed before attendance was marked, then corrected to present, then re-confirmed".

  v_present := EXISTS (
    SELECT 1 FROM public.attendance
    WHERE event_id = v_block.event_id AND member_id = v_block.owner_member_id AND present = true
  );

  UPDATE public.event_agenda_blocks
     SET status = 'confirmed', confirmed_at = now()
   WHERE id = p_block_id;

  IF v_present THEN
    PERFORM public._grant_agenda_block_xp(p_block_id);
  END IF;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'confirmed',
                            'xp_credited', v_present);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 4b) confirm_event_blocks — bulk-confirm all reserved blocks of an event.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.confirm_event_blocks(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller    uuid;
  v_block     record;
  v_present   boolean;
  v_confirmed int := 0;
  v_credited  int := 0;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  FOR v_block IN
    SELECT id, event_id, owner_member_id
      FROM public.event_agenda_blocks
      WHERE event_id = p_event_id AND status = 'reserved'
      ORDER BY sort_order, duration_min DESC
      FOR UPDATE
  LOOP
    v_present := EXISTS (
      SELECT 1 FROM public.attendance
      WHERE event_id = v_block.event_id AND member_id = v_block.owner_member_id AND present = true
    );
    UPDATE public.event_agenda_blocks SET status = 'confirmed', confirmed_at = now() WHERE id = v_block.id;
    v_confirmed := v_confirmed + 1;
    IF v_present THEN
      PERFORM public._grant_agenda_block_xp(v_block.id);
      v_credited := v_credited + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'event_id', p_event_id,
                            'confirmed', v_confirmed, 'credited', v_credited);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 4c) revoke_agenda_block_xp — manage_event; status→no_show; delete the ledger row.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revoke_agenda_block_xp(p_block_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','pg_temp'
AS $function$
DECLARE
  v_caller  uuid;
  v_block   record;
  v_deleted int := 0;
BEGIN
  SELECT id INTO v_caller FROM public.members WHERE auth_id = auth.uid();
  IF v_caller IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT public.can_by_member(v_caller, 'manage_event') THEN
    RETURN jsonb_build_object('error', 'access_denied', 'required', 'manage_event');
  END IF;

  SELECT * INTO v_block FROM public.event_agenda_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.id IS NULL THEN RETURN jsonb_build_object('error', 'block_not_found'); END IF;
  -- A cancelled block has its own terminal outcome; do not overwrite it with no_show.
  IF v_block.status = 'cancelled' THEN
    RETURN jsonb_build_object('error', 'cannot_revoke_cancelled', 'block_id', p_block_id);
  END IF;

  DELETE FROM public.gamification_points
   WHERE ref_id = p_block_id AND category = 'agenda_block_protagonismo'
     AND member_id = v_block.owner_member_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  UPDATE public.event_agenda_blocks
     SET status = 'no_show', confirmed_at = NULL,
         cancelled_by = v_caller, cancelled_reason = COALESCE(p_reason, cancelled_reason)
   WHERE id = p_block_id;

  RETURN jsonb_build_object('success', true, 'block_id', p_block_id, 'status', 'no_show',
                            'xp_revoked', v_deleted);
END;
$function$;

-- ----------------------------------------------------------------------------
-- 5) Grants: coordination-only RPCs are authenticated; anon is revoked.
--    _grant_agenda_block_xp is internal (called only from SECDEF confirm RPCs).
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public._grant_agenda_block_xp(uuid)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.confirm_agenda_block(uuid)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.confirm_event_blocks(uuid)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_agenda_block_xp(uuid, text)  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_agenda_block(uuid)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_event_blocks(uuid)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_agenda_block_xp(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

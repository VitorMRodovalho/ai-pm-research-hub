-- PR-1 (#785) — Iniciativas confidenciais: coluna de visibilidade + helper RLS.
-- Behavior-neutral: default 'standard' + helper devolve true p/ standard e p/ NULL,
-- preservando read-all da curadoria (decisão #5 CLAUDE.md). Só confidenciais exigem engagement.

ALTER TABLE public.initiatives
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'standard'
  CHECK (visibility IN ('standard','confidential'));

COMMENT ON COLUMN public.initiatives.visibility IS
  'Visibilidade da iniciativa (#785). standard = piso org-members-only atual; confidential = board/eventos/atas/docs visíveis só a engajados + GP/superadmin. Tribos herdam via bridge ADR-0005.';

-- Helper canônico de visibilidade (espelha rls_can_for_initiative).
-- Reusa o padrão V4: engajamento autoritativo via auth_engagements.initiative_id.
CREATE OR REPLACE FUNCTION public.rls_can_see_initiative(p_initiative_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path TO 'public','pg_temp' AS $$
  SELECT
    p_initiative_id IS NULL  -- boards/eventos org-level sem iniciativa: visíveis
    OR NOT EXISTS (SELECT 1 FROM public.initiatives i
                   WHERE i.id = p_initiative_id AND i.visibility = 'confidential')
    OR EXISTS (SELECT 1 FROM public.auth_engagements ae
               WHERE ae.auth_id = auth.uid() AND ae.initiative_id = p_initiative_id
                 AND ae.is_authoritative = true)
    OR public.rls_is_superadmin()
    OR public.rls_can('manage_platform');  -- decisão PM #1: GP vê sempre
$$;

COMMENT ON FUNCTION public.rls_can_see_initiative(uuid) IS
  'Gate de visibilidade de iniciativa (#785, PR-1). true p/ standard e p/ NULL; confidencial exige engajamento autoritativo ou GP/superadmin. Usado nas policies SELECT (PR-2) e nas RPCs SECURITY DEFINER de leitura (PR-3).';

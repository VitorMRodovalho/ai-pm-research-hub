-- ARM P1 (post Onda 2): localStorage onboarding state → server-side persistence
--
-- Estado pré: onboarding.astro:249 usa localStorage com STORAGE_KEY 'onboarding_progress'
-- → progresso resetado entre dispositivos (mobile→desktop), navegadores, sessões.
-- Member que troca de device perde o tracking de quais steps já completou.
--
-- Mudanças:
--   1) Nova tabela member_quick_start_progress (1 row por member, completed_steps int[])
--   2) RLS rpc-only pattern (mesmo de selection_*)
--   3) RPC upsert_my_quick_start_step(step_idx, done) — toggle individual com auth
--   4) RPC get_my_quick_start_progress() — retorna array + timestamp
--
-- Frontend (onboarding.astro) será atualizado em commit subsequente para chamar
-- RPCs em vez de localStorage. Backward compat: localStorage pode coexistir como
-- fallback offline.
--
-- Rollback: DROP TABLE public.member_quick_start_progress CASCADE;

CREATE TABLE IF NOT EXISTS public.member_quick_start_progress (
  member_id uuid PRIMARY KEY REFERENCES public.members(id) ON DELETE CASCADE,
  completed_steps integer[] NOT NULL DEFAULT ARRAY[]::integer[],
  total_steps integer NOT NULL DEFAULT 8,
  last_updated timestamptz NOT NULL DEFAULT now(),
  organization_id uuid NOT NULL DEFAULT '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.member_quick_start_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpc_only_deny_all ON public.member_quick_start_progress;
CREATE POLICY rpc_only_deny_all
  ON public.member_quick_start_progress
  AS PERMISSIVE FOR ALL TO public
  USING (false);

DROP POLICY IF EXISTS member_qsp_v4_org_scope ON public.member_quick_start_progress;
CREATE POLICY member_qsp_v4_org_scope
  ON public.member_quick_start_progress
  AS RESTRICTIVE FOR ALL TO public
  USING ((organization_id = auth_org()) OR (organization_id IS NULL))
  WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.member_quick_start_progress FROM anon;
REVOKE INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.member_quick_start_progress FROM authenticated;
REVOKE SELECT ON public.member_quick_start_progress FROM anon;

COMMENT ON TABLE public.member_quick_start_progress IS
  'Server-side persistence do onboarding quick-start guide (onboarding.astro). 1 row por member, completed_steps int[] com índices dos steps marcados como done. Resolve gap localStorage cross-device. ARM P1 post-Onda 2 (audit p107).';

-- RPC: get_my_quick_start_progress
CREATE OR REPLACE FUNCTION public.get_my_quick_start_progress()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_member_id uuid;
  v_row record;
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  SELECT completed_steps, total_steps, last_updated
  INTO v_row
  FROM public.member_quick_start_progress
  WHERE member_id = v_member_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'completed_steps', '[]'::jsonb,
      'total_steps', 8,
      'last_updated', NULL
    );
  END IF;

  RETURN jsonb_build_object(
    'completed_steps', to_jsonb(v_row.completed_steps),
    'total_steps', v_row.total_steps,
    'last_updated', v_row.last_updated
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.get_my_quick_start_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_quick_start_progress() TO authenticated;

-- RPC: upsert_my_quick_start_step
CREATE OR REPLACE FUNCTION public.upsert_my_quick_start_step(
  p_step_idx integer,
  p_done boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $func$
DECLARE
  v_member_id uuid;
  v_completed integer[];
BEGIN
  SELECT id INTO v_member_id FROM public.members WHERE auth_id = auth.uid();
  IF v_member_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  IF p_step_idx < 0 OR p_step_idx > 50 THEN
    RETURN jsonb_build_object('error', 'Invalid step_idx (must be 0-50)');
  END IF;

  -- Upsert
  INSERT INTO public.member_quick_start_progress (member_id, completed_steps, last_updated)
  VALUES (
    v_member_id,
    CASE WHEN p_done THEN ARRAY[p_step_idx] ELSE ARRAY[]::integer[] END,
    now()
  )
  ON CONFLICT (member_id) DO UPDATE SET
    completed_steps = CASE
      WHEN p_done AND NOT (excluded.completed_steps[1] = ANY(public.member_quick_start_progress.completed_steps))
        THEN array_append(public.member_quick_start_progress.completed_steps, p_step_idx)
      WHEN NOT p_done
        THEN array_remove(public.member_quick_start_progress.completed_steps, p_step_idx)
      ELSE public.member_quick_start_progress.completed_steps
    END,
    last_updated = now()
  RETURNING completed_steps INTO v_completed;

  RETURN jsonb_build_object(
    'success', true,
    'completed_steps', to_jsonb(v_completed),
    'last_updated', now()
  );
END;
$func$;

REVOKE ALL ON FUNCTION public.upsert_my_quick_start_step(integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_my_quick_start_step(integer, boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- #1660 (Onda 1, épica #1652) - a falta simples volta a ser gravável, e "tirar presença"
-- vira ato distinto em vez de ser o mesmo botão.
--
-- O p199-c (2026-05-19) fez `mark_member_present(p_present := false)` APAGAR a linha, em vez de
-- gravar `present=false`. Com isso a plataforma perdeu como dizer "faltou": medido em 09/08/2026,
-- 3 linhas de falta simples na base inteira (2.029 linhas de presença), todas anteriores àquela
-- data e todas com `excuse_reason` nulo e `updated_at > created_at`.
--
-- Não era ausência de capacidade, era CONTORNO: `mark_member_excused(p_excused := false)` faz
-- `UPDATE ... SET excused = false` sem tocar em `present`, então justificar e depois desjustificar
-- deixa `present=false, excused=false`. O ato direto apagava; o único caminho para a falta passava
-- por um estado que não era o que se queria afirmar.
--
-- O front já modela três estados e já pede o certo: `AttendanceGridTab.tsx` e
-- `TribeAttendanceTab.tsx` calculam `nextState: 'present' | 'absent'` e chamam
-- `mark_member_present(p_present: false)` para "ausente", com o toast dizendo "❌ Ausente".
-- Era o banco que não guardava. Por isso esta migration não pede mudança de front.
--
-- A intenção do p199-c era legítima e continua existindo: "tirar presença" (desfazer o registro)
-- é um ato REAL, só que distinto de "marcar falta". Ele passa a ter nome próprio:
-- `clear_member_attendance`.
--
-- Superfície contada antes de aplicar (09/08/2026): 95 funções em `public` mencionam `attendance`,
-- 33 inferem falta pela AUSÊNCIA de linha e 9 escrevem. A inferência é o #1657 e NÃO é tocada aqui:
-- depois desta migration as leitoras passam a ver faltas explícitas ALÉM das inferidas.

-- ── 1. mark_member_present: o ramo falso grava a falta em vez de apagar a linha ──────────────

CREATE OR REPLACE FUNCTION public.mark_member_present(p_event_id uuid, p_member_id uuid, p_present boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: can only mark own presence or requires manage_event permission';
  END IF;

  IF p_present THEN
    INSERT INTO public.attendance (event_id, member_id, present, excused)
    VALUES (p_event_id, p_member_id, true, false)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = true, excused = false, updated_at = now();
  ELSE
    -- #1660 (2026-08-09): p_present=false volta a GRAVAR a falta simples (era DELETE desde o
    -- p199-c). Desfazer o registro continua existindo, com nome proprio:
    -- clear_member_attendance(). A justificativa e limpada junto porque o front so chega aqui
    -- vindo de 'excused' depois de confirmar com o usuario que o motivo sera removido.
    INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason)
    VALUES (p_event_id, p_member_id, false, false, NULL)
    ON CONFLICT (event_id, member_id) DO UPDATE SET
      present = false, excused = false, excuse_reason = NULL, updated_at = now();
  END IF;

  RETURN json_build_object('success', true);
END;
$function$;

-- ── 2. clear_member_attendance: o ato do p199-c, agora separado ──────────────────────────────

CREATE OR REPLACE FUNCTION public.clear_member_attendance(p_event_id uuid, p_member_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_caller_id uuid;
  v_removed int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  IF v_caller_id = p_member_id THEN
    NULL;
  ELSIF NOT public.can_by_member(v_caller_id, 'manage_event') THEN
    RAISE EXCEPTION 'Unauthorized: can only clear own attendance or requires manage_event permission';
  END IF;

  DELETE FROM public.attendance WHERE event_id = p_event_id AND member_id = p_member_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  RETURN json_build_object('success', true, 'cleared', v_removed);
END;
$function$;

COMMENT ON FUNCTION public.clear_member_attendance(uuid, uuid) IS
  '#1660: desfaz o REGISTRO de presenca (apaga a linha). Ato distinto de mark_member_present(false), '
  'que grava falta simples. Mesma autoridade: o proprio membro ou manage_event.';

-- Mesma superfície de `mark_member_present`: nada de anon.
REVOKE ALL ON FUNCTION public.clear_member_attendance(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clear_member_attendance(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.clear_member_attendance(uuid, uuid) TO authenticated, service_role;

-- ── 3. admin_bulk_mark_attendance: mesma semântica em lote, e o ON CONFLICT que faltava ──────
--
-- Duas mudanças, e a segunda é consequência da primeira:
--
-- (a) o ramo falso gravava DELETE em lote; passa a gravar falta, para a porta não ficar PARCIAL
--     (um ato por membro significando uma coisa e o mesmo ato em lote significando outra).
--
-- (b) o ramo VERDADEIRO nunca gravou `present`: ele inseria só `checked_in_at`/`marked_by` e
--     dependia do DEFAULT `true` da coluna, e o `DO UPDATE` também não tocava `present`. Isso era
--     inofensivo enquanto falta não existia como linha. Com (a), o `ON CONFLICT` passa a encontrar
--     linhas `present=false`, e marcar o lote como presente NÃO as corrigiria: a pessoa ficaria
--     ausente depois de o líder marcá-la presente. O `DO UPDATE` passa a afirmar `present = true`.
--
-- Medido em 09/08/2026: o ramo falso não tem chamador vivo. `attendance.astro` chama sempre com
-- `p_present: true`, e o único caminho que passa a flag adiante (`useAttendance.ts::batchToggle`)
-- só é consumido por `AttendanceGrid.tsx`, que é exportado e nunca importado (a grade órfã do
-- #1655). O alinhamento é preventivo, e é barato agora.

CREATE OR REPLACE FUNCTION public.admin_bulk_mark_attendance(p_event_id uuid, p_member_ids uuid[], p_present boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_count int := 0;
  v_mid uuid;
BEGIN
  SELECT m.id INTO v_caller_id FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  -- V4: delegate to _can_manage_event (covers org admin + tribe-scoped leader)
  IF NOT public._can_manage_event(p_event_id) THEN
    RETURN json_build_object('success', false, 'error', 'permission_denied');
  END IF;

  IF p_present THEN
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      INSERT INTO public.attendance (event_id, member_id, present, excused, checked_in_at, marked_by)
      VALUES (p_event_id, v_mid, true, false, now(), v_caller_id)
      ON CONFLICT (event_id, member_id)
      DO UPDATE SET present = true, excused = false, checked_in_at = now(), marked_by = v_caller_id;
      v_count := v_count + 1;
    END LOOP;
  ELSE
    -- #1660: era DELETE em lote. Grava a falta, como o ato por membro.
    FOREACH v_mid IN ARRAY p_member_ids LOOP
      INSERT INTO public.attendance (event_id, member_id, present, excused, excuse_reason, marked_by)
      VALUES (p_event_id, v_mid, false, false, NULL, v_caller_id)
      ON CONFLICT (event_id, member_id)
      DO UPDATE SET present = false, excused = false, excuse_reason = NULL, marked_by = v_caller_id;
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN json_build_object('success', true, 'marked', v_count);
END;
$function$;

NOTIFY pgrst, 'reload schema';

-- #2897: o cache de preview_gate_eligibles acompanha a virada do dia, e o adapter so responde
-- pelo cache quando ele cobre todo membro ativo.
--
-- O QUE FALHAVA (medido em 01/11/2026):
--
--   * O cache so e recalculado em escrita (gatilhos em members e engagements). Quem decide os
--     gates, porem, depende de data: auth_engagements.is_authoritative le CURRENT_DATE contra
--     start_date e end_date, e _can_sign_gate le CURRENT_DATE (volunteers_in_role_active) e
--     now() (janela de 60 dias do chapter_witness). Um vinculo notify_only que passou do
--     end_date de 31/10 continuou com status 'active', o can() passou a negar, e o cache ficou
--     com a concessao antiga: 4 tuplas em desvio no _audit_preview_gate_eligibles_drift.
--   * v4_expire_engagements roda as 03:05 UTC e so faz UPDATE nos ramos suspend e offboard.
--     Mesmo chamando o refresh ali, sobrariam a janela de 00:00 a 03:05 e o start_date futuro.
--   * O adapter usava o cache se existisse UMA linha fresca (< 24 h) do doc_type, e contava so
--     as linhas frescas. Com 117 membros ativos e 1 linha fresca por doc_type, ele respondeu
--     source='cache' com curator 0 (eram 3) e leader_awareness 0 (eram 16) em
--     cooperation_agreement. O audit compara sem o corte de 24 h e nao via esse caso.
--
-- O QUE MUDA:
--
--   1. rebuild_preview_gate_eligibles_cache_cron(): recalcula o cache de todo membro ativo e
--      apaga as linhas de quem nao esta ativo. Roda numa transacao so, entao todas as linhas
--      saem com o mesmo last_refreshed. Sem portao de sessao: sob pg_cron nao ha JWT
--      (#1548), e a protecao e o ACL, fechado abaixo a service_role.
--   2. O job preview-gate-eligibles-rebuild-daily chama essa funcao as 00:01 UTC, logo depois
--      da virada que muda CURRENT_DATE. Minuto 1, e nao 0, por #1844. Nenhum job roda as
--      00:01 hoje; o mais proximo e operational-role-reconcile-daily, as 00:04.
--   3. preview_gate_eligibles so usa o cache quando TODO membro ativo tem linha fresca para o
--      doc_type. Na mistura, ou com linha faltando, cai para o calculo ao vivo
--      (source='live_fallback'), que e o que o adapter ja fazia com o cache inteiro velho.
--      O resto do corpo fica como na 20260514210000.
--
-- Custo: o audit, que roda _can_sign_gate para todo membro ativo e todo gate, levou ~2 s.
-- O rebuild faz o mesmo trabalho, uma vez por dia.
--
-- Cross-ref: #2897, #1548 (pg_cron nao tem sessao), #1844 (minuto deslocado), #2323 (forma do
-- agendamento), ADR-0016 Amendment 3 (o cache hibrido).

CREATE OR REPLACE FUNCTION public.rebuild_preview_gate_eligibles_cache_cron()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_member record;
  v_members int := 0;
  v_orphans int := 0;
BEGIN
  FOR v_member IN SELECT m.id FROM public.members m WHERE m.is_active = true
  LOOP
    PERFORM public._refresh_preview_gate_eligibles_for_member(v_member.id);
    v_members := v_members + 1;
  END LOOP;

  DELETE FROM public.preview_gate_eligibles_cache c
  WHERE NOT EXISTS (
    SELECT 1 FROM public.members m WHERE m.id = c.member_id AND m.is_active = true
  );
  GET DIAGNOSTICS v_orphans = ROW_COUNT;

  RETURN jsonb_build_object(
    'rebuilt_at', now(),
    'members_processed', v_members,
    'orphans_removed', v_orphans
  );
END;
$function$;

COMMENT ON FUNCTION public.rebuild_preview_gate_eligibles_cache_cron() IS
  'Full rebuild of preview_gate_eligibles_cache for pg_cron (#2897): every active member is recomputed in one transaction, so every row shares one last_refreshed, and rows of inactive members are removed. No session gate (no JWT under pg_cron); EXECUTE is service_role only.';

REVOKE ALL ON FUNCTION public.rebuild_preview_gate_eligibles_cache_cron() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rebuild_preview_gate_eligibles_cache_cron() TO service_role;

CREATE OR REPLACE FUNCTION public.preview_gate_eligibles(p_doc_type text, p_submitter_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_gates jsonb;
  v_result jsonb := '[]'::jsonb;
  v_gate jsonb;
  v_gate_kind text;
  v_count int;
  v_sample jsonb;
  v_use_cache boolean;
  v_stale_cutoff timestamptz := now() - interval '24 hours';
BEGIN
  v_gates := public.resolve_default_gates(p_doc_type);
  IF v_gates IS NULL THEN RETURN NULL; END IF;

  -- #2897: the cache answers only when EVERY active member has a fresh row for this doc_type.
  -- One fresh row used to be enough, and the counts below then covered only the fresh rows.
  v_use_cache := p_doc_type = ANY(public._cacheable_preview_doc_types())
    AND NOT EXISTS (
      SELECT 1 FROM public.members m
      WHERE m.is_active = true
        AND NOT EXISTS (
          SELECT 1 FROM public.preview_gate_eligibles_cache c
          WHERE c.member_id = m.id
            AND c.doc_type = p_doc_type
            AND c.last_refreshed >= v_stale_cutoff
        )
    );

  FOR v_gate IN SELECT * FROM jsonb_array_elements(v_gates)
  LOOP
    v_gate_kind := v_gate->>'kind';

    IF v_gate_kind = 'submitter_acceptance' THEN
      SELECT count(*) INTO v_count
      FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id);

      SELECT coalesce(jsonb_agg(name ORDER BY name), '[]'::jsonb) INTO v_sample
      FROM (
        SELECT m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id)
        ORDER BY m.name LIMIT 3
      ) m;

    ELSIF v_use_cache THEN
      SELECT count(*) INTO v_count
      FROM public.preview_gate_eligibles_cache c
      JOIN public.members m ON m.id = c.member_id
      WHERE c.doc_type = p_doc_type
        AND m.is_active = true
        AND c.last_refreshed >= v_stale_cutoff
        AND v_gate_kind = ANY(c.eligible_gates);

      SELECT coalesce(jsonb_agg(name ORDER BY name), '[]'::jsonb) INTO v_sample
      FROM (
        SELECT m.name
        FROM public.preview_gate_eligibles_cache c
        JOIN public.members m ON m.id = c.member_id
        WHERE c.doc_type = p_doc_type
          AND m.is_active = true
          AND c.last_refreshed >= v_stale_cutoff
          AND v_gate_kind = ANY(c.eligible_gates)
        ORDER BY m.name LIMIT 3
      ) m;

    ELSE
      SELECT count(*) INTO v_count
      FROM public.members m
      WHERE m.is_active = true
        AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id);

      SELECT coalesce(jsonb_agg(name ORDER BY name), '[]'::jsonb) INTO v_sample
      FROM (
        SELECT m.name FROM public.members m
        WHERE m.is_active = true
          AND public._can_sign_gate(m.id, NULL, v_gate_kind, p_doc_type, p_submitter_id)
        ORDER BY m.name LIMIT 3
      ) m;
    END IF;

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'gate_kind', v_gate_kind,
      'gate_order', (v_gate->>'order')::int,
      'threshold', v_gate->'threshold',
      'count', v_count,
      'sample', v_sample,
      'source', CASE
        WHEN v_gate_kind = 'submitter_acceptance' THEN 'live'
        WHEN v_use_cache THEN 'cache'
        ELSE 'live_fallback'
      END
    ));
  END LOOP;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.preview_gate_eligibles(text, uuid) IS
  'Hybrid cache + live fallback (ADR-0016 Amendment 3). Reads preview_gate_eligibles_cache only when every active member has a fresh row (<24h) for the doc_type (#2897); otherwise, including a mix of fresh and stale rows, falls back to live _can_sign_gate. Always evaluates submitter_acceptance live. Each gate response includes "source": cache|live|live_fallback for diagnostics.';

SELECT cron.unschedule('preview-gate-eligibles-rebuild-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'preview-gate-eligibles-rebuild-daily');

SELECT cron.schedule(
  'preview-gate-eligibles-rebuild-daily',
  '1 0 * * *',
  $cron$SELECT public.rebuild_preview_gate_eligibles_cache_cron();$cron$
);

NOTIFY pgrst, 'reload schema';

-- PR-B (certificates admin revamp): bulk counter-signature for the volunteer director.
--
-- The director had only per-row counter-sign (counter_sign_certificate, one cert per click +
-- confirm). With 35 terms awaiting the director (26 of them the v9 Onda-1 batch), that is 35
-- individual confirmations. This RPC counter-signs a selected batch in one call.
--
-- Authority is NOT lowered: it loops and delegates to counter_sign_certificate for each id, so
-- the exact same gate applies per cert (manage_member OR chapter_board of the contracting
-- chapter) and each cert gets its own hash, audit row, and (now suppressed, #1169) ready
-- notification. Any id the caller may not sign, or that is already counter-signed / not issued,
-- is reported in the per-id results and counted as failed — the batch does not abort.

CREATE OR REPLACE FUNCTION public.bulk_counter_sign_certificates(
  p_certificate_ids uuid[],
  p_signed_user_agent text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
  v_res jsonb;
  v_ok int := 0;
  v_failed int := 0;
  v_results jsonb := '[]'::jsonb;
BEGIN
  IF p_certificate_ids IS NULL OR array_length(p_certificate_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('error', 'no_ids');
  END IF;
  -- Keep the transaction bounded; the pending queue is far below this in practice.
  IF array_length(p_certificate_ids, 1) > 200 THEN
    RETURN jsonb_build_object('error', 'too_many', 'max', 200);
  END IF;

  FOREACH v_id IN ARRAY p_certificate_ids LOOP
    -- Delegate to the single-cert RPC so the authority gate + hashing + audit + notification
    -- stay in one place. p_signed_ip omitted (mirrors the frontend single-cert call).
    v_res := public.counter_sign_certificate(v_id, NULL, p_signed_user_agent);
    IF COALESCE((v_res->>'success')::boolean, false) THEN
      v_ok := v_ok + 1;
    ELSE
      v_failed := v_failed + 1;
    END IF;
    v_results := v_results || jsonb_build_object('id', v_id, 'result', v_res);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'ok', v_ok, 'failed', v_failed, 'results', v_results);
END;
$function$;

REVOKE ALL ON FUNCTION public.bulk_counter_sign_certificates(uuid[], text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bulk_counter_sign_certificates(uuid[], text) TO authenticated;

NOTIFY pgrst, 'reload schema';

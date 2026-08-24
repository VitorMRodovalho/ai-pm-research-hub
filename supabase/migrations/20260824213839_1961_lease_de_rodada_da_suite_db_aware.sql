-- #1961 — lease de rodada para serializar quem escreve no banco de producao durante a
-- suite DB-aware. Duas sessoes locais + a CI escrevendo ao mesmo tempo produzem timeout
-- que se le como defeito: medido em 24/08/2026, o mesmo teste foi de 234.009 ms (reprovando,
-- 57014 statement timeout) para 232,6 ms so por rodar isolado.
--
-- Por que tabela e nao pg_advisory_lock: lock de sessao do Postgres morre com a conexao, e
-- sobre PostgREST cada request pega uma conexao do pool. O lock seria solto na hora.

CREATE TABLE IF NOT EXISTS public.test_suite_leases (
  source      text PRIMARY KEY,
  holder      text        NOT NULL,
  acquired_at timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL
);

COMMENT ON TABLE public.test_suite_leases IS
  'Lease de exclusao mutua entre rodadas da suite DB-aware (#1961). Uma linha por fonte; '
  'expires_at e o TTL que impede que uma rodada morta trave todas as seguintes.';

ALTER TABLE public.test_suite_leases ENABLE ROW LEVEL SECURITY;
-- Sem policy de proposito: apenas service_role (que contorna RLS) escreve e le. anon e
-- authenticated nao tem nada aqui, e nao ha PII.

-- Aquisicao ATOMICA. O predicado do DO UPDATE decide num unico comando: sem ele, dois
-- processos poderiam ambos ler "expirado" e ambos inserir.
CREATE OR REPLACE FUNCTION public.acquire_test_suite_lease(
  p_source text,
  p_holder text,
  p_ttl_minutes integer DEFAULT 60
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_row public.test_suite_leases;
  v_cur public.test_suite_leases;
BEGIN
  IF coalesce(p_source,'') = '' OR coalesce(p_holder,'') = '' THEN
    RAISE EXCEPTION 'source e holder sao obrigatorios' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  INSERT INTO public.test_suite_leases (source, holder, acquired_at, expires_at)
  VALUES (p_source, p_holder, now(), now() + make_interval(mins => greatest(coalesce(p_ttl_minutes,60), 1)))
  ON CONFLICT (source) DO UPDATE
     SET holder = EXCLUDED.holder,
         acquired_at = EXCLUDED.acquired_at,
         expires_at = EXCLUDED.expires_at
   WHERE public.test_suite_leases.expires_at <= now()
      OR public.test_suite_leases.holder = EXCLUDED.holder
  RETURNING * INTO v_row;

  IF v_row.source IS NOT NULL THEN
    RETURN jsonb_build_object('acquired', true, 'source', v_row.source,
                              'holder', v_row.holder, 'expires_at', v_row.expires_at);
  END IF;

  SELECT * INTO v_cur FROM public.test_suite_leases WHERE source = p_source;
  RETURN jsonb_build_object('acquired', false, 'source', p_source,
                            'holder', v_cur.holder, 'expires_at', v_cur.expires_at);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.release_test_suite_lease(
  p_source text,
  p_holder text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_n integer;
BEGIN
  -- casa o holder: uma rodada nunca solta o lease de outra.
  DELETE FROM public.test_suite_leases WHERE source = p_source AND holder = p_holder;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('released', v_n > 0, 'source', p_source, 'holder', p_holder);
END;
$fn$;

-- CREATE FUNCTION nasce com EXECUTE para PUBLIC (logo, anon e authenticated). Revogar e
-- obrigatorio: estas duas escrevem, e nada fora do service_role tem o que fazer aqui.
REVOKE ALL ON FUNCTION public.acquire_test_suite_lease(text, text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_test_suite_lease(text, text)          FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acquire_test_suite_lease(text, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.release_test_suite_lease(text, text)          TO service_role;

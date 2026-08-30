-- #2104 (guard do acoplamento): a SEDE passa a ser resolvida ATRAVES de partner_chapters.
--
-- A juncao dos ramos president_go e cert_director_go usa partner_chapters como ponte entre a
-- forma de display (PMI-GO) e a canonica (GO). Decisao do PM: aceitar o acoplamento COM guard,
-- porque sem a linha do capitulo contratante os dois portoes negam em SILENCIO.
--
-- ROTA DELIBERADA: o corpo novo e montado a partir do proprio prosrc, server-side, em vez de
-- transcrito. check_schema_invariants tem 46 KB e e rede de seguranca; transcrever esse volume
-- por um canal de texto arrisca corrupcao, e o md5 so prova DEPOIS de ja estar em producao.
-- Montando a partir do que esta vivo, corrupcao e impossivel por construcao.
--
-- ⚠️ ARMADILHA que mordeu na primeira tentativa: a string de substituicao NAO pode usar prefixo
-- E na parte do backreference. Em `E'...\1'` o `\1` vira o BYTE 0x01, nao referencia de grupo,
-- e o CREATE saiu com um caractere de controle no lugar do END. A migration abortou inteira e
-- nada foi aplicado, que e a propriedade que justifica esta rota. Aqui o `'\1'` vai concatenado
-- como string SEM prefixo E.
--
-- ASSERCOES, todas dentro da transacao:
--   1. a funcao existe
--   2. o invariante ainda nao esta la (idempotencia)
--   3. o padrao do END final casou (senao a insercao seria no-op silencioso)
--   4. RETURN QUERY passa de 43 para 44
--   5. o corpo original e prefixo do novo (nada removido)

DO $mig$
DECLARE
  v_src text;
  v_new text;
  v_antes int;
  v_depois int;
  v_blk text := $blk$
  -- AQ (#2104): a SEDE e resolvida ATRAVES de partner_chapters nos ramos president_go e
  -- cert_director_go. Sem a linha do contratante, os dois portoes negam em SILENCIO, que e
  -- a classe de falha mais cara. Este invariante converte o silencio em ruido alto.
  RETURN QUERY
  WITH drift AS (
    SELECT cr.id AS chapter_id
    FROM public.chapter_registry cr
    WHERE cr.is_contracting_chapter
      AND NOT EXISTS (SELECT 1 FROM public.partner_chapters pc
                      WHERE pc.registry_chapter_code = cr.chapter_code)
  )
  SELECT 'AQ_contracting_chapter_has_participation'::text,
         'o capitulo contratante tem de ter linha em partner_chapters: _can_sign_gate resolve a SEDE atraves dessa tabela nos ramos president_go e cert_director_go (#2104). Sem a linha, os dois portoes negam em SILENCIO.'::text,
         'high'::text, COUNT(*)::integer,
         (SELECT array_agg(chapter_id ORDER BY chapter_id) FROM (SELECT chapter_id FROM drift LIMIT 10) s)
  FROM drift;
$blk$;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p
   WHERE p.proname = 'check_schema_invariants'
     AND p.pronamespace = 'public'::regnamespace;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'check_schema_invariants nao encontrada';
  END IF;

  IF position('AQ_contracting_chapter_has_participation' in v_src) > 0 THEN
    RAISE NOTICE 'invariante AQ ja presente; nada a fazer';
    RETURN;
  END IF;

  v_antes := (SELECT count(*) FROM regexp_matches(v_src, 'RETURN QUERY', 'g'));

  v_new := regexp_replace(v_src, '(\nEND;\s*)$', E'\n' || v_blk || E'\n' || '\1');

  IF v_new = v_src THEN
    RAISE EXCEPTION 'o padrao do END final nao casou: a insercao seria no-op silencioso';
  END IF;

  v_depois := (SELECT count(*) FROM regexp_matches(v_new, 'RETURN QUERY', 'g'));
  IF v_antes <> 43 OR v_depois <> 44 THEN
    RAISE EXCEPTION 'RETURN QUERY esperado 43 -> 44, veio % -> %', v_antes, v_depois;
  END IF;

  IF position(substr(v_src, 1, 2000) in v_new) <> 1 THEN
    RAISE EXCEPTION 'o corpo original nao e prefixo do novo: algo foi removido';
  END IF;

  IF position(chr(1) in v_new) > 0 THEN
    RAISE EXCEPTION 'caractere de controle no corpo novo: o backreference foi interpretado como escape';
  END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.check_schema_invariants() '
    'RETURNS TABLE(invariant_name text, description text, severity text, '
    'violation_count integer, sample_ids uuid[]) '
    'LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''public'', ''pg_temp'' AS %L',
    v_new);
END
$mig$;

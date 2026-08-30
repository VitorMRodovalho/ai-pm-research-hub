-- CONSERTO DE REGRESSAO que eu proprio introduzi horas antes, na migration do invariante AQ.
--
-- O QUE ACONTECEU: o `EXECUTE format('CREATE OR REPLACE FUNCTION ... LANGUAGE plpgsql
-- SECURITY DEFINER ...')` daquela migration OMITIU o atributo STABLE. A captura anterior
-- (20260822033913) declarava `STABLE SECURITY DEFINER`; o meu format nao, e a funcao caiu
-- para VOLATILE (provolatile 'v').
--
-- POR QUE NAO DISPAROU ALARME: `CREATE OR REPLACE FUNCTION` RECONSTROI a funcao a partir do
-- que voce declara. Atributo omitido NAO e preservado: ele volta ao default, em silencio.
-- Eu tinha 6 assercoes protegendo o CORPO e ZERO protegendo a ASSINATURA, entao o texto do
-- corpo estava blindado e a volatilidade passou por fora do escopo inteiro das assercoes.
--
-- Pego pela lane hub-latam ao montar a captura literal: escrever a captura com STABLE nao
-- casaria com o vivo, e escrever sem congelaria a regressao. Nenhuma das duas era aceitavel.
--
-- IMPACTO: baixo na pratica (a funcao e chamada explicitamente, nao usada em indice nem em
-- constraint), mas e divergencia do contrato declarado e contaminaria a captura.
--
-- ESTA MIGRATION preserva o corpo BYTE A BYTE (relido do proprio prosrc) e muda SO o atributo.

DO $mig$
DECLARE
  v_src text;
  v_vol_antes "char";
  v_md5_antes text;
BEGIN
  SELECT p.prosrc, p.provolatile, md5(p.prosrc)
    INTO v_src, v_vol_antes, v_md5_antes
    FROM pg_proc p
   WHERE p.proname = 'check_schema_invariants'
     AND p.pronamespace = 'public'::regnamespace;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'check_schema_invariants nao encontrada';
  END IF;

  IF v_vol_antes = 's' THEN
    RAISE NOTICE 'ja esta STABLE; nada a fazer';
    RETURN;
  END IF;

  -- o corpo tem de conter o invariante novo: se nao contiver, estou operando sobre a funcao
  -- errada ou sobre um estado que nao esperava
  IF position('AQ_contracting_chapter_has_participation' in v_src) = 0 THEN
    RAISE EXCEPTION 'o corpo vivo nao contem o invariante AQ: estado inesperado';
  END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.check_schema_invariants() '
    'RETURNS TABLE(invariant_name text, description text, severity text, '
    'violation_count integer, sample_ids uuid[]) '
    'LANGUAGE plpgsql STABLE SECURITY DEFINER '
    'SET search_path TO ''public'', ''pg_temp'' AS %L',
    v_src);

  -- ASSERCAO SOBRE A ASSINATURA, que e o que faltou da outra vez.
  -- Sem isto, um erro no format voltaria a passar em silencio.
  PERFORM 1 FROM pg_proc p
   WHERE p.proname = 'check_schema_invariants'
     AND p.pronamespace = 'public'::regnamespace
     AND p.provolatile = 's'
     AND p.prosecdef
     AND p.proconfig @> ARRAY['search_path=public, pg_temp']
     AND md5(p.prosrc) = v_md5_antes;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'pos-condicao falhou: esperava STABLE + SECURITY DEFINER + search_path intacto + corpo com md5 %', v_md5_antes;
  END IF;
END
$mig$;

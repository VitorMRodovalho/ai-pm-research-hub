-- #3189: o aviso de filiacao pendente (entry_chapter_action_needed) deixa de dizer que o capitulo de entrada falta a
-- quem ja tem members.entry_chapter_code. Para essas pessoas o que falta e a filiacao verificada (o portao de
-- affiliation_gate fechado), e e isso que o texto passa a pedir.
--
-- Nada de segunda regra:
--   - affiliation_nudge_variant fica como esta (md5 normalizado d22c0cb6). A variante continua sendo a situacao na
--     VEP, e o plano do cron, o source_type e o painel (que le a variante do source_type) nao mudam;
--   - affiliation_nudge_text(variante) continua o lugar dos textos, com a mesma assinatura. O title e o body do topo
--     ficam identicos aos de hoje (a pos-condicao prova), e o painel, que reconhece pelo title do topo os avisos antigos
--     sem source_type, nao muda. Cada variante ganha 'with_chapter', a forma para quem ja tem capitulo de entrada, que
--     pede a confirmacao da filiacao sem dizer que o capitulo falta;
--   - affiliation_nudge_deliver, o envio unico do cron e da aprovacao (#3168), le members.entry_chapter_code, o mesmo
--     campo que o card do perfil mostra, e escolhe a forma. O dedupe de 30 dias fica igual e antes de tudo.
--
-- O texto com capitulo e decisao do GP (pacote da #3189).
--
-- Rollback: recriar affiliation_nudge_deliver pela captura 20261124005114 e affiliation_nudge_text pela 20261120204018.

-- 0) o plano e os textos de antes, para a pos-condicao provar o que nao mudou
-- sem ON COMMIT DROP: se a migration nao rodar numa transacao, elas sumiriam antes da pos-condicao
CREATE TEMP TABLE _3189_plano_antes AS
  SELECT member_id, variant FROM public.affiliation_nudge_plan();
CREATE TEMP TABLE _3189_texto_antes AS
  SELECT v AS variant, public.affiliation_nudge_text(v) AS texto
  FROM unnest(ARRAY['ambiguous', 'profile_private', 'no_fetch', 'not_affiliated']) AS v;

-- 1) os textos, por variante; 'with_chapter' para quem ja tem capitulo de entrada
CREATE OR REPLACE FUNCTION public.affiliation_nudge_text(p_variant text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE p_variant
    WHEN 'ambiguous' THEN jsonb_build_object(
      'title', 'Escolha seu capítulo de entrada no Núcleo',
      'body',  'Encontramos mais de um capítulo PMI ativo na sua filiação. Escolha por qual capítulo você entra no Núcleo para ajustarmos a governança e os indicadores do seu capítulo. Leva um clique no seu perfil.',
      'with_chapter', jsonb_build_object(
        'title', 'Confirme seu capítulo de entrada no Núcleo',
        'body',  'O capítulo de entrada registrado no seu perfil não aparece entre os capítulos PMI ativos da sua filiação, e encontramos mais de um capítulo ativo. Escolha por qual deles você entra no Núcleo. Leva um clique no seu perfil.'))
    WHEN 'profile_private' THEN jsonb_build_object(
      'title', 'Deixe seu perfil PMI público para confirmarmos seu capítulo',
      'body',  'Seu perfil no community.pmi.org está com a visibilidade privada, então não conseguimos ler seus capítulos para definir seu capítulo de entrada no Núcleo. Acesse community.pmi.org, deixe seu perfil público (ao menos a seção de capítulos) e nós atualizamos automaticamente.',
      'with_chapter', jsonb_build_object(
        'title', 'Deixe seu perfil PMI público para confirmarmos sua filiação',
        'body',  'Seu capítulo de entrada no Núcleo já está registrado. Falta confirmar sua filiação PMI, e seu perfil no community.pmi.org está com a visibilidade privada. Acesse community.pmi.org, deixe seu perfil público (ao menos a seção de capítulos) e a confirmação é automática.'))
    WHEN 'no_fetch' THEN jsonb_build_object(
      'title', 'Vincule seu perfil PMI para definir seu capítulo de entrada',
      'body',  'Ainda não localizamos seu perfil no community.pmi.org. Se você tem filiação PMI, confira se o perfil está criado e público em community.pmi.org para confirmarmos seu capítulo de entrada no Núcleo automaticamente.',
      'with_chapter', jsonb_build_object(
        'title', 'Vincule seu perfil PMI para confirmarmos sua filiação',
        'body',  'Seu capítulo de entrada no Núcleo já está registrado. Falta confirmar sua filiação PMI, e ainda não localizamos seu perfil no community.pmi.org. Se você tem filiação PMI, confira se o perfil está criado e público em community.pmi.org, e a confirmação é automática.'))
    WHEN 'not_affiliated' THEN jsonb_build_object(
      'title', 'Confirme sua filiação PMI para definir seu capítulo de entrada',
      'body',  'Não conseguimos confirmar uma filiação PMI ativa no seu perfil do community.pmi.org. Para registrarmos seu capítulo de entrada no Núcleo, verifique se sua filiação PMI está ativa e se o capítulo aparece no seu perfil em community.pmi.org. Assim que estiver regular, atualizamos automaticamente.',
      'with_chapter', jsonb_build_object(
        'title', 'Confirme sua filiação PMI ativa',
        'body',  'Seu capítulo de entrada no Núcleo já está registrado. Falta confirmar sua filiação PMI: no seu perfil do community.pmi.org não encontramos uma filiação ativa. Verifique se sua filiação PMI está ativa e se o capítulo aparece no seu perfil em community.pmi.org. Assim que estiver regular, a confirmação é automática.'))
  END;
$function$;

-- 2) o envio unico le o capitulo de entrada e escolhe a forma; o dedupe fica igual e antes de tudo
CREATE OR REPLACE FUNCTION public.affiliation_nudge_deliver(p_member_id uuid, p_variant text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_text jsonb;
  v_has_entry_chapter boolean;
BEGIN
  -- Dedup: do not re-fire if this member already got the nudge in the last 30 days.
  IF EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.recipient_id = p_member_id
      AND n.type = 'entry_chapter_action_needed'
      AND n.created_at > now() - interval '30 days'
  ) THEN
    RETURN false;
  END IF;

  -- o mesmo campo que o card do perfil mostra como capitulo de entrada
  SELECT m.entry_chapter_code IS NOT NULL INTO v_has_entry_chapter
  FROM public.members m WHERE m.id = p_member_id;

  v_text := public.affiliation_nudge_text(p_variant);
  IF COALESCE(v_has_entry_chapter, false) THEN
    v_text := v_text -> 'with_chapter';
  END IF;
  PERFORM public.create_notification(
    p_member_id,
    'entry_chapter_action_needed',
    v_text ->> 'title',
    v_text ->> 'body',
    '/profile#entry-chapter-card',
    'affiliation_nudge.' || p_variant,
    NULL::uuid
  );
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.affiliation_nudge_text(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_text(text) TO service_role;
REVOKE ALL ON FUNCTION public.affiliation_nudge_deliver(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.affiliation_nudge_deliver(uuid, text) TO service_role;

-- 3) pos-condicao: nao envia nada
DO $postcondition$
DECLARE
  v_diff int;
  v_rec record;
BEGIN
  SELECT count(*) INTO v_diff FROM (
    (SELECT member_id, variant FROM _3189_plano_antes
     EXCEPT ALL SELECT member_id, variant FROM public.affiliation_nudge_plan())
    UNION ALL
    (SELECT member_id, variant FROM public.affiliation_nudge_plan()
     EXCEPT ALL SELECT member_id, variant FROM _3189_plano_antes)
  ) d;
  IF v_diff <> 0 THEN
    RAISE EXCEPTION '#3189: o plano mudou (% linhas diferentes)', v_diff;
  END IF;

  FOR v_rec IN SELECT variant, texto FROM _3189_texto_antes LOOP
    -- o topo, que o painel le e que vai a quem nao tem capitulo, fica identico
    IF v_rec.texto IS NULL
       OR (public.affiliation_nudge_text(v_rec.variant) - 'with_chapter') IS DISTINCT FROM v_rec.texto THEN
      RAISE EXCEPTION '#3189: o texto sem capitulo de % mudou', v_rec.variant;
    END IF;
    -- a forma com capitulo existe, e outra, e nao diz que o capitulo falta
    IF public.affiliation_nudge_text(v_rec.variant) #>> '{with_chapter,title}' IS NULL
       OR public.affiliation_nudge_text(v_rec.variant) #>> '{with_chapter,body}' IS NULL
       OR public.affiliation_nudge_text(v_rec.variant) #>> '{with_chapter,title}' = v_rec.texto ->> 'title'
       OR (public.affiliation_nudge_text(v_rec.variant) -> 'with_chapter')::text ILIKE '%definir seu capítulo%' THEN
      RAISE EXCEPTION '#3189: a forma com capitulo de % falta, repete o titulo antigo ou diz que o capitulo falta', v_rec.variant;
    END IF;
  END LOOP;

  IF has_function_privilege('authenticated', 'public.affiliation_nudge_text(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.affiliation_nudge_deliver(uuid, text)', 'EXECUTE') THEN
    RAISE EXCEPTION '#3189: uma funcao interna do aviso ficou exposta';
  END IF;
  RAISE NOTICE '#3189 ok: plano igual (% linhas), texto sem capitulo igual', (SELECT count(*) FROM _3189_plano_antes);
END
$postcondition$;

DROP TABLE _3189_plano_antes;
DROP TABLE _3189_texto_antes;

NOTIFY pgrst, 'reload schema';

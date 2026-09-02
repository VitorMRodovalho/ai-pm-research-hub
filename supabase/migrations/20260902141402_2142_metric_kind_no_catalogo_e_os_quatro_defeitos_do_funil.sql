-- WHAT: (1) `comms_channel_config.metric_kind` declara se a serie do canal e acumulada ou diaria;
--       (2) get_comms_to_adoption_funnel corrige os QUATRO defeitos da #2142;
--       (3) comms_executive_kpis corrige o mesmo defeito de reach que compartilha com o funil.
-- WHY:  os quatro defeitos vivem na MESMA funcao, e ela e reescrita por inteiro para consertar
--       qualquer um deles. Deixar de pe, tres linhas acima do conserto, um count() que conta a
--       coisa errada e uma taxa que divide populacoes diferentes faria a proxima pessoa supor que
--       o que ficou passou por revisao.
--
-- OS QUATRO, MEDIDOS EM 02/09/2026 ANTES DE APLICAR:
--
--   1. applications.total conta GRUPOS, nao candidaturas.
--      O count(*) externo contava linhas da subconsulta agrupada por (role_applied, referral_source).
--        candidaturas criadas em 30d ......... 5
--        grupos ............................... 1   <- o que a tela mostrava
--
--   2. approval_rate de 1880%, e o numero e aritmetica exata, nao estimativa.
--      Numerador: status IN (approved, converted) AND updated_at >= janela  -> 94
--      Denominador: created_at >= janela                                    ->  5
--      94/5 = 1880. Sao populacoes E colunas de data diferentes: candidatura antiga aprovada
--      hoje entra em cima e nao embaixo. A mesma coorte da 1 de 5, ou 20%.
--
--   3. audience invariante ao periodo. `DISTINCT ON (channel) ORDER BY metric_date DESC` devolve
--      sempre a linha mais recente, entao 7, 30 e 90 dias davam o MESMO numero. Correto como
--      "nivel atual", errado como "audiencia no periodo". O nome do campo ja dizia `_latest`;
--      o que faltava era o periodo ter a sua propria medida.
--
--   4. reach somado sobre serie ACUMULADA. Em 90 dias: soma 3.021.464 contra crescimento real de
--      42.267 no LinkedIn, fator de 71x.
--
-- POR QUE metric_kind E COLUNA, E POR QUE NO CATALOGO DE CANAL:
--       agregar certo exige saber se a serie e acumulada, e isso e propriedade do CANAL (da API de
--       origem), nao do dia. Detectar por monotonicidade em runtime seria adivinhar: medido em
--       02/09, youtube 96,4% e linkedin 94,0% nao-decrescentes contra instagram 45,7%. A separacao
--       e limpa, mas as 4 e 5 descidas pediriam explicacao antes de virar regra, e uma regra que
--       decide por 94% erra em silencio no dia em que o padrao mudar.
--       Coluna TIPADA com CHECK, e nao chave dentro de `config jsonb`, porque dominio declarado e
--       greppavel e restringivel (#1822).
--
-- CANAL SEM CONFIG NAO SOME EM SILENCIO. `newsletter` tem 1 linha em comms_metrics_daily, de
--       `manual_smoke`, e nenhuma linha de config. Um JOIN o descartaria sem dizer. A funcao passa
--       a expor `channels_unconfigured`, separando "nao classificado" de "zero" - a licao do
--       `instrumented`.
--
-- SCOPE LOCK: nenhuma politica de RLS e tocada. O portao de autoridade da RPC (view_internal_
--       analytics OR manage_platform OR view_aggregate_analytics OR can_view_comms_analytics)
--       e preservado byte a byte. Nenhuma coluna de dado e apagada.
-- ROLLBACK: restaurar os corpos anteriores das duas funcoes e
--       ALTER TABLE public.comms_channel_config DROP COLUMN metric_kind.
-- CROSS-REF: #2142 · #1822 (dominio declarado) · #2133 (a metrica de post que expos o funil)

-- 1. O catalogo passa a declarar a natureza da serie──────────────────────────────
ALTER TABLE public.comms_channel_config
  ADD COLUMN IF NOT EXISTS metric_kind text;

UPDATE public.comms_channel_config SET metric_kind = 'cumulative'
 WHERE channel IN ('linkedin','youtube') AND metric_kind IS NULL;
UPDATE public.comms_channel_config SET metric_kind = 'daily'
 WHERE channel = 'instagram' AND metric_kind IS NULL;

DO $mig$
DECLARE v_nulos int;
BEGIN
  SELECT count(*) INTO v_nulos FROM public.comms_channel_config WHERE metric_kind IS NULL;
  IF v_nulos <> 0 THEN
    RAISE EXCEPTION '% canal(is) configurado(s) sem metric_kind: classifique antes de travar a coluna', v_nulos;
  END IF;
END $mig$;

ALTER TABLE public.comms_channel_config
  ALTER COLUMN metric_kind SET NOT NULL;

ALTER TABLE public.comms_channel_config
  DROP CONSTRAINT IF EXISTS comms_channel_config_metric_kind_check;
ALTER TABLE public.comms_channel_config
  ADD CONSTRAINT comms_channel_config_metric_kind_check
  CHECK (metric_kind IN ('cumulative','daily'));

COMMENT ON COLUMN public.comms_channel_config.metric_kind IS
  'cumulative = a serie do canal e um contador acumulado (crescimento na janela = ultimo - primeiro); daily = a serie e um fluxo diario (crescimento = soma). Classificado por monotonicidade medida em 02/09/2026 (#2142). Somar uma serie acumulada inflou o reach do LinkedIn em 71x (ver #2142).';

-- 2. O funil: os quatro defeitos──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_comms_to_adoption_funnel(p_period_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_caller_id      uuid;
  v_period         interval := (greatest(p_period_days, 1) || ' days')::interval;
  v_since_ts       timestamptz := now() - v_period;
  v_since_date     date        := current_date - greatest(p_period_days, 1);
  v_social         jsonb;
  v_engagement     jsonb;
  v_apps           jsonb;
  v_approved       jsonb;
  v_top_content    jsonb;
  v_unconfigured   int;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;
  IF NOT (public.can_by_member(v_caller_id, 'view_internal_analytics')
       OR public.can_by_member(v_caller_id, 'manage_platform')
       OR public.can_by_member(v_caller_id, 'view_aggregate_analytics')
       OR public.can_view_comms_analytics()) THEN
    RETURN jsonb_build_object('error', 'Unauthorized');
  END IF;

  -- Canal com dado e SEM classificacao no catalogo nao entra na agregacao. Contar aqui separa
  -- "nao classificado" de "zero": sem esta linha, o canal sumiria sem deixar rastro.
  SELECT count(DISTINCT d.channel) INTO v_unconfigured
  FROM public.comms_metrics_daily d
  LEFT JOIN public.comms_channel_config c ON c.channel = d.channel
  WHERE d.metric_date >= v_since_date AND c.channel IS NULL;

  -- Stage 1: alcance social
  -- DEFEITO 4 (reach): somar serie ACUMULADA inflava 71x no LinkedIn. Agora a agregacao pergunta
  --   ao catalogo o que a serie e: acumulada -> ultimo menos primeiro; diaria -> soma.
  -- DEFEITO 3 (audience): `_latest` e o NIVEL ATUAL e por isso nao responde ao periodo, o que esta
  --   correto para o que ele mede. O que faltava era o periodo ter medida propria, entao entra
  --   `audience_growth_period` ao lado, sem tirar o nivel.
  WITH latest_per_channel AS (
    SELECT DISTINCT ON (channel)
      channel, audience, reach, engagement_rate, metric_date
    FROM public.comms_metrics_daily
    WHERE metric_date >= v_since_date
    ORDER BY channel, metric_date DESC
  ),
  period_agg AS (
    SELECT d.channel,
           c.metric_kind,
           CASE c.metric_kind
             WHEN 'cumulative' THEN greatest(
                 (array_agg(d.reach ORDER BY d.metric_date DESC) FILTER (WHERE d.reach IS NOT NULL))[1]
               - (array_agg(d.reach ORDER BY d.metric_date ASC)  FILTER (WHERE d.reach IS NOT NULL))[1], 0)
             ELSE coalesce(sum(d.reach), 0)
           END AS reach_period,
           greatest(
               (array_agg(d.audience ORDER BY d.metric_date DESC) FILTER (WHERE d.audience IS NOT NULL))[1]
             - (array_agg(d.audience ORDER BY d.metric_date ASC)  FILTER (WHERE d.audience IS NOT NULL))[1], 0)
             AS audience_growth
    FROM public.comms_metrics_daily d
    JOIN public.comms_channel_config c ON c.channel = d.channel
    WHERE d.metric_date >= v_since_date
    GROUP BY d.channel, c.metric_kind
  )
  SELECT jsonb_build_object(
    'total_audience_latest',   coalesce((SELECT sum(audience) FROM latest_per_channel), 0),
    'total_audience_growth',   coalesce((SELECT sum(audience_growth) FROM period_agg), 0),
    'total_reach_period',      coalesce((SELECT sum(reach_period) FROM period_agg), 0),
    'channels_unconfigured',   v_unconfigured,
    'by_channel', coalesce(jsonb_agg(jsonb_build_object(
      'channel',           l.channel,
      'audience_latest',   l.audience,
      'audience_growth',   coalesce(p.audience_growth, 0),
      'reach_period',      coalesce(p.reach_period, 0),
      'metric_kind',       p.metric_kind,
      'engagement_rate',   l.engagement_rate
    ) ORDER BY l.audience DESC NULLS LAST), '[]'::jsonb)
  ) INTO v_social
  FROM latest_per_channel l
  LEFT JOIN period_agg p ON p.channel = l.channel;

  -- Stage 2: engajamento no site (inalterado)
  WITH grouped AS (
    SELECT
      CASE
        WHEN first_page LIKE '/blog/%' THEN 'blog'
        WHEN first_page LIKE '/cpmai%' THEN 'cpmai'
        WHEN first_page LIKE '/trail%' THEN 'trail'
        WHEN first_page LIKE '/presentations%' THEN 'presentations'
        WHEN first_page LIKE '/gamification%' THEN 'gamification'
        WHEN first_page = '/' OR first_page LIKE '/en/%' OR first_page LIKE '/es/%' THEN 'home'
        ELSE 'other'
      END AS landing_group,
      member_id
    FROM public.member_activity_sessions
    WHERE session_date >= v_since_date
  ),
  agg AS (
    SELECT landing_group, count(*) AS sessions, count(DISTINCT member_id) AS members
    FROM grouped
    GROUP BY landing_group
  )
  SELECT jsonb_build_object(
    'content_sessions',      coalesce((SELECT sum(sessions) FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'content_unique_members', coalesce((SELECT sum(members)  FROM agg WHERE landing_group IN ('blog','cpmai','trail','presentations','gamification')), 0),
    'home_sessions',         coalesce((SELECT sessions FROM agg WHERE landing_group='home'), 0),
    'home_unique_members',   coalesce((SELECT members  FROM agg WHERE landing_group='home'), 0),
    'by_landing_group', coalesce(jsonb_agg(jsonb_build_object(
      'group',           a.landing_group,
      'sessions',        a.sessions,
      'unique_members',  a.members
    ) ORDER BY a.sessions DESC), '[]'::jsonb)
  ) INTO v_engagement
  FROM agg a;

  -- Stage 3: candidaturas
  -- DEFEITO 1: o count(*) externo contava LINHAS DA SUBCONSULTA agrupada, isto e, pares
  --   (role_applied, referral_source). Cinco candidaturas em um par unico apareciam como "1".
  --   De quebra, `by_role` usava jsonb_object_agg sobre a mesma subconsulta: dois referral_source
  --   para o mesmo papel produziam chave repetida e a ultima vencia em silencio.
  WITH apps AS (
    SELECT role_applied, referral_source
    FROM public.selection_applications
    WHERE created_at >= v_since_ts
  )
  SELECT jsonb_build_object(
    'total',   (SELECT count(*) FROM apps),
    'via_vep', (SELECT count(*) FROM apps WHERE referral_source = 'vep'),
    'other',   (SELECT count(*) FROM apps WHERE referral_source IS DISTINCT FROM 'vep'),
    'by_role', coalesce((SELECT jsonb_object_agg(role_applied, n)
                         FROM (SELECT role_applied, count(*) AS n FROM apps GROUP BY role_applied) r), '{}'::jsonb)
  ) INTO v_apps;

  -- Stage 4: aprovadas
  -- DEFEITO 2: numerador e denominador vinham de populacoes e de COLUNAS DE DATA diferentes.
  --   Numerador: updated_at na janela, qualquer created_at -> 94.  Denominador: created_at na
  --   janela -> 5.  94/5 = 1880%. A taxa agora e da MESMA coorte: das criadas na janela, quantas
  --   estao aprovadas ou convertidas hoje.
  --   O numero antigo nao era inutil, era mal rotulado: ele mede ATIVIDADE de decisao na janela.
  --   Fica, com nome proprio (`decided_in_period`) e fora do calculo da taxa.
  WITH coorte AS (
    SELECT status FROM public.selection_applications WHERE created_at >= v_since_ts
  )
  SELECT jsonb_build_object(
    'cohort_total',      (SELECT count(*) FROM coorte),
    'approved',          (SELECT count(*) FROM coorte WHERE status = 'approved'),
    'converted',         (SELECT count(*) FROM coorte WHERE status = 'converted'),
    'approval_rate',     CASE WHEN (SELECT count(*) FROM coorte) > 0
                              THEN round((SELECT count(*) FROM coorte WHERE status IN ('approved','converted'))::numeric
                                         * 100.0 / (SELECT count(*) FROM coorte), 1)
                              ELSE NULL END,
    'decided_in_period', (SELECT count(*) FROM public.selection_applications
                           WHERE status IN ('approved','converted') AND updated_at >= v_since_ts)
  ) INTO v_approved;

  -- Top content (inalterado)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'channel',      m.channel,
    'media_type',   m.media_type,
    'permalink',    m.permalink,
    'caption_excerpt', left(coalesce(m.caption, ''), 80),
    'views',        m.views,
    'likes',        m.likes,
    'comments',     m.comments,
    'published_at', m.published_at
  ) ORDER BY (coalesce(m.likes,0) + coalesce(m.comments,0) + coalesce(m.views,0)) DESC), '[]'::jsonb)
  INTO v_top_content
  FROM (
    SELECT *
    FROM public.comms_media_items
    WHERE published_at >= v_since_ts
    ORDER BY (coalesce(likes,0) + coalesce(comments,0) + coalesce(views,0)) DESC
    LIMIT 6
  ) m;

  RETURN jsonb_build_object(
    'period_days',  p_period_days,
    'period_since', v_since_ts,
    'generated_at', now(),
    'caveat',       'Correlation, not attribution. Pre-login pageviews + UTM tracking infrastructure pending (Phase B backlog). PMI VEP external form does not pass UTM. Funnel reflects what is measurable today: post-login engagement + total application counts in period.',
    'stages', jsonb_build_object(
      'social_reach',    v_social,
      'site_engagement', v_engagement,
      'applications',    v_apps,
      'approved',        v_approved
    ),
    'top_content', v_top_content
  );
END;
$fn$;

-- 3. A funcao executiva: o MESMO defeito de reach─────────────────────────────────
-- Ela ja tinha o padrao certo tres linhas abaixo do defeito: `audience_growth_pct` compara a foto
-- de hoje com a foto de sete dias atras, que e exatamente a forma correta para serie acumulada.
-- Esse trecho fica INTACTO de proposito: ele e o controle. O que muda e aplicar ao `reach` o
-- padrao que a propria funcao ja usava para `audience`.
CREATE OR REPLACE FUNCTION public.comms_executive_kpis()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_result jsonb; v_channels jsonb;
  v_total_audience bigint := 0; v_weekly_reach bigint := 0;
  v_avg_engagement numeric := 0; v_growth_pct numeric := 0;
  v_this_week_audience bigint := 0; v_last_week_audience bigint := 0;
BEGIN
  WITH latest_per_channel AS (
    SELECT DISTINCT ON (channel) channel, audience, reach, engagement_rate, metric_date, payload
    FROM public.comms_metrics_daily ORDER BY channel, metric_date DESC
  )
  SELECT COALESCE(SUM(audience), 0),
    COALESCE(jsonb_agg(jsonb_build_object('channel', channel, 'audience', audience, 'reach', reach, 'engagement_rate', engagement_rate, 'date', metric_date)), '[]'::jsonb)
  INTO v_total_audience, v_channels FROM latest_per_channel;

  -- ANTES: SUM(reach) sobre a janela, o que somava contador acumulado.
  SELECT COALESCE(SUM(k.r), 0) INTO v_weekly_reach FROM (
    SELECT CASE c.metric_kind
             WHEN 'cumulative' THEN greatest(
                 (array_agg(d.reach ORDER BY d.metric_date DESC) FILTER (WHERE d.reach IS NOT NULL))[1]
               - (array_agg(d.reach ORDER BY d.metric_date ASC)  FILTER (WHERE d.reach IS NOT NULL))[1], 0)
             ELSE COALESCE(SUM(d.reach), 0)
           END AS r
    FROM public.comms_metrics_daily d
    JOIN public.comms_channel_config c ON c.channel = d.channel
    WHERE d.metric_date >= CURRENT_DATE - 7
    GROUP BY d.channel, c.metric_kind
  ) k;

  WITH eng AS (
    SELECT DISTINCT ON (channel) channel, engagement_rate, audience
    FROM public.comms_metrics_daily WHERE engagement_rate IS NOT NULL ORDER BY channel, metric_date DESC
  )
  SELECT CASE WHEN SUM(audience) > 0 THEN SUM(engagement_rate * audience) / SUM(audience) ELSE 0 END
  INTO v_avg_engagement FROM eng;

  v_this_week_audience := v_total_audience;
  SELECT COALESCE(SUM(sub.audience), 0) INTO v_last_week_audience
  FROM (SELECT DISTINCT ON (channel) channel, audience FROM public.comms_metrics_daily WHERE metric_date <= CURRENT_DATE - 7 ORDER BY channel, metric_date DESC) sub;

  IF v_last_week_audience > 0 THEN
    v_growth_pct := ROUND(((v_this_week_audience - v_last_week_audience)::numeric / v_last_week_audience) * 100, 1);
  END IF;

  v_result := jsonb_build_object(
    'total_audience', v_total_audience, 'weekly_reach', v_weekly_reach,
    'avg_engagement', ROUND(v_avg_engagement, 4), 'audience_growth_pct', v_growth_pct,
    'channel_breakdown', v_channels,
    'media_count', (SELECT COUNT(*) FROM public.comms_media_items)::int,
    'top_media_count', (SELECT COUNT(*) FROM public.comms_media_items WHERE published_at >= NOW() - interval '30 days')::int
  );
  RETURN v_result;
END;
$fn$;

NOTIFY pgrst, 'reload schema';

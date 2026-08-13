-- ============================================================================
-- #1590 onda C — o comitê ganha superfície: enxergar o rodízio, cadastrar a
--                agenda, e pausar sem destruir configuração
-- ============================================================================
--
-- Nas palavras do PM (13/08): entram na tela de seleção presidentes, admin da plataforma, gestão
-- e quem estiver listado no comitê — e é no comitê que se define quem observa e quem avalia.
-- Isso torna o comitê o MECANISMO DE CONTROLE DE ACESSO, e um mecanismo de segurança que só o
-- dono do banco opera é a mesma classe de defeito que o #1710 acabou de fechar.
--
-- Medido em 13/08/2026, ciclo `cycle4-2026` (aberto), ANTES desta migration:
--   - comitê: 3 avaliadores roteáveis (todos por `committee_override`) + 4 observadores sem URL
--   - 94 despachos; desde 31/07 o rodízio deu 8 / 5 / 4
--   - 0 linhas em `selection_interviewer_blackouts` — a onda B subiu a tabela SEM escrita
--   - 2 de 87 membros ativos têm `manage_member` (e as MESMAS 2 têm `promote`: divergência zero)
--   - `selection_committee.interview_booking_url` decide 30 dos 30 últimos despachos de
--     researcher e não tem tela, não tem MCP, e foi preenchido por SQL direto
--
-- O caso que nomeia a onda: o avaliador cuja agenda recebe o candidato NÃO consegue cadastrar a
-- própria agenda em lugar nenhum. A única tela que edita URL de agenda é `/admin/members/[id]`
-- (tier superadmin) e ela edita `members.interview_booking_url`, o caminho de MENOR precedência.
--
-- Decisões do PM nesta volta:
--   1. URL de agenda: AUTOSSERVIÇO (a própria linha) + GP para qualquer um.
--   2. Painel visível às 11 pessoas que já entram na tela; URL crua só na própria linha e p/ GP.
--
-- O que esta migration NÃO faz: não mexe no rodízio. O desempate por `member_id` que concentra
-- despachos quando o lote inteiro sai na MESMA transação (medido: 5 despachos com timestamp
-- idêntico em 06/08/2026, 3 deles para o menor `member_id`) fica em issue própria — corrigir o
-- picker aqui misturaria "dar superfície" com "mudar quem recebe candidato".
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 1. A leitura: quem está cadastrado para roteamento, sem abrir o banco
-- ─────────────────────────────────────────────────────────────────────────────
--
-- ⚠️ O público do servidor aqui é o público DECLARADO NA TELA (comitê ∪ sponsor ∪ GP ∪ superadmin),
-- não o público da RPC vizinha `get_selection_dashboard` (`view_internal_analytics` ∪ comitê). A
-- onda A mediu que espelhar o predicado daquela RPC abriria 6 `chapter_liaison` numa rota de PII de
-- candidato por uma porta que o menu nunca ofereceu. Medido em 13/08 sobre ESTE predicado: 11
-- pessoas — as mesmas 11 que a tela já deixa entrar, zero a mais nas duas direções.
--
-- A URL crua sai só para a PRÓPRIA linha e para quem tem `manage_member`: um link de Appointment
-- Schedule é uma porta para a agenda de alguém, e o resto do público vê "tem agenda / não tem".
--
-- Três decisões de forma, todas contra armadilhas já pagas neste repositório:
--   - `url_source` usa as MESMAS palavras que `selection_dispatch_url_log.resolution_path`
--     (`committee_override` / `member_global`), para a tela não inventar um terceiro vocabulário;
--   - `not_routable_reasons` é lista de motivos, não booleano mudo: "não roteável" tem quatro
--     causas possíveis, e o silêncio entre elas é o que obrigou a editar o banco na mão;
--   - `dispatch_count` usa os MESMOS filtros do lookback do picker (mesmo ciclo, track researcher):
--     contar por outro recorte publicaria um número que não é o que decide o rodízio;
--   - os totais saem do JSON já montado (`json_array_elements`), não de um segundo predicado —
--     duas implementações da mesma pergunta divergem, e foi assim que a taxa de presença passou
--     meses dizendo 100%.

CREATE OR REPLACE FUNCTION public.get_selection_routing_overview(p_cycle_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller record;
  v_cycle record;
  v_is_committee boolean;
  v_can_manage boolean;
  v_committee_role text;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_members json;
  v_routable int;
  v_blocked int;
BEGIN
  SELECT m.id, m.designations, m.is_superadmin INTO v_caller
  FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller.id IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  SELECT c.id, c.cycle_code, c.status, c.interview_booking_url INTO v_cycle
  FROM public.selection_cycles c WHERE c.id = p_cycle_id;
  IF v_cycle.id IS NULL THEN
    RETURN json_build_object('error', 'Cycle not found');
  END IF;

  SELECT sc.role INTO v_committee_role
  FROM public.selection_committee sc
  WHERE sc.cycle_id = p_cycle_id AND sc.member_id = v_caller.id;
  v_is_committee := v_committee_role IS NOT NULL;
  v_can_manage := public.can_by_member(v_caller.id, 'manage_member');

  IF NOT (
    v_is_committee
    OR v_can_manage
    OR COALESCE(v_caller.is_superadmin, false)
    OR ('sponsor' = ANY(COALESCE(v_caller.designations, '{}'::text[])))
  ) THEN
    RETURN json_build_object('error', 'Unauthorized');
  END IF;

  SELECT COALESCE(json_agg(t.obj ORDER BY t.nome), '[]'::json) INTO v_members
  FROM (
    SELECT
      m.name AS nome,
      json_build_object(
        'member_id', sc.member_id,
        'name', m.name,
        'operational_role', m.operational_role,
        'role', sc.role,
        'can_interview', sc.can_interview,
        'is_self', sc.member_id = v_caller.id,
        'url_source', CASE
          WHEN sc.interview_booking_url IS NOT NULL THEN 'committee_override'
          WHEN m.interview_booking_url IS NOT NULL THEN 'member_global'
          ELSE NULL END,
        'has_url', COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL,
        'booking_url', CASE
          WHEN v_can_manage OR sc.member_id = v_caller.id
          THEN COALESCE(sc.interview_booking_url, m.interview_booking_url)
          ELSE NULL END,
        'committee_url', CASE
          WHEN v_can_manage OR sc.member_id = v_caller.id THEN sc.interview_booking_url
          ELSE NULL END,
        'routable_now', (
          sc.role IN ('evaluator', 'lead')
          AND sc.can_interview
          AND COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NOT NULL
          AND NOT COALESCE(blk.blocked_now, false)
        ),
        'not_routable_reasons', (
          SELECT COALESCE(json_agg(z.r), '[]'::json) FROM (
            SELECT 'role_not_routable'::text AS r WHERE sc.role NOT IN ('evaluator', 'lead')
            UNION ALL SELECT 'permanently_off' WHERE NOT sc.can_interview
            UNION ALL SELECT 'no_booking_url'
              WHERE COALESCE(sc.interview_booking_url, m.interview_booking_url) IS NULL
            UNION ALL SELECT 'blocked_window' WHERE COALESCE(blk.blocked_now, false)
          ) z
        ),
        'blocked_now', COALESCE(blk.blocked_now, false),
        'blocks', COALESCE(blk.blocks, '[]'::json),
        'dispatch_count', COALESCE(d.n, 0),
        'last_dispatched_at', d.last
      ) AS obj
    FROM public.selection_committee sc
    JOIN public.members m ON m.id = sc.member_id
    LEFT JOIN LATERAL (
      SELECT
        COALESCE(json_agg(json_build_object(
          'id', b.id,
          'starts_on', b.starts_on,
          'ends_on', b.ends_on,
          'reason', b.reason,
          'created_by_name', cb.name,
          'created_by_self', b.created_by = b.member_id,
          'active', v_hoje >= b.starts_on AND (b.ends_on IS NULL OR v_hoje <= b.ends_on)
        ) ORDER BY b.starts_on), '[]'::json) AS blocks,
        bool_or(v_hoje >= b.starts_on AND (b.ends_on IS NULL OR v_hoje <= b.ends_on)) AS blocked_now
      FROM public.selection_interviewer_blackouts b
      LEFT JOIN public.members cb ON cb.id = b.created_by
      WHERE b.cycle_id = sc.cycle_id
        AND b.member_id = sc.member_id
        AND (b.ends_on IS NULL OR b.ends_on >= v_hoje)
    ) blk ON true
    LEFT JOIN LATERAL (
      SELECT count(*) AS n, max(l.dispatched_at) AS last
      FROM public.selection_dispatch_url_log l
      WHERE l.cycle_id = sc.cycle_id
        AND l.track = 'researcher'
        AND l.resolved_evaluator_id = sc.member_id
    ) d ON true
    WHERE sc.cycle_id = p_cycle_id
  ) t;

  SELECT
    count(*) FILTER (WHERE (e->>'routable_now')::boolean),
    count(*) FILTER (WHERE (e->>'blocked_now')::boolean)
  INTO v_routable, v_blocked
  FROM json_array_elements(v_members) e;

  RETURN json_build_object(
    'cycle', json_build_object(
      'id', v_cycle.id,
      'cycle_code', v_cycle.cycle_code,
      'status', v_cycle.status,
      'has_fallback_url', v_cycle.interview_booking_url IS NOT NULL,
      'fallback_url', CASE WHEN v_can_manage THEN v_cycle.interview_booking_url ELSE NULL END
    ),
    'caller', json_build_object(
      'member_id', v_caller.id,
      'committee_role', v_committee_role,
      'can_manage', v_can_manage
    ),
    'local_date', v_hoje,
    'routable_now', v_routable,
    'blocked_now', v_blocked,
    'members', v_members
  );
END;
$function$;

COMMENT ON FUNCTION public.get_selection_routing_overview(uuid) IS
  '#1590 onda C — quem esta cadastrado para roteamento neste ciclo, por pessoa: papel, os tres eixos (can_interview / URL / janelas de bloqueio), motivo explicito de nao-roteavel, contagem e data do ultimo despacho. Publico = comite do ciclo, designacao sponsor, manage_member ou superadmin (o publico DECLARADO NA TELA, medido em 11 pessoas). A URL crua so sai para a propria linha e para manage_member. NAO publica proximo da fila: o desempate do picker concentra despachos quando o lote sai na mesma transacao.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. A pausa: bloquear e desbloquear, autosserviço + GP
-- ─────────────────────────────────────────────────────────────────────────────
--
-- ⚠️ GATE POR RECURSO, não por papel. As duas funções recebem um alvo concreto (`p_member_id` /
-- `p_block_id`), e um gate que só pergunta "o chamador é alguém?" alcança o recurso de qualquer
-- um: foi assim no #1728, e no #1710 mediu-se 622 pares (líder, evento) indevidos antes de expor
-- o botão. Aqui o gate compara o alvo com o chamador ANTES de qualquer escrita.
--
-- `starts_on` nulo = a partir de hoje no fuso LOCAL. `CURRENT_DATE` é UTC e das 21h à meia-noite em
-- Brasília ele já virou o dia — a mesma borda que a onda B mediu no picker (#1727).
--
-- `clear` APAGA a linha em vez de encerrá-la por `ends_on`: encerrar esbarraria no CHECK
-- (ends_on >= starts_on) para um bloqueio começado hoje, e um bloqueio criado por engano ficaria
-- visível para sempre. O histórico vive em `admin_audit_log`, com a janela inteira no metadata.

CREATE OR REPLACE FUNCTION public.set_interviewer_routing_block(
  p_cycle_id uuid,
  p_member_id uuid,
  p_starts_on date DEFAULT NULL,
  p_ends_on date DEFAULT NULL,
  p_reason text DEFAULT NULL
)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_can_manage boolean;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_starts date;
  v_org uuid;
  v_role text;
  v_id uuid;
  v_reason text;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;

  v_can_manage := public.can_by_member(v_caller, 'manage_member');
  IF p_member_id IS DISTINCT FROM v_caller AND NOT v_can_manage THEN
    RETURN json_build_object('error', 'Unauthorized: blocking another interviewer requires manage_member');
  END IF;

  SELECT sc.role, c.organization_id INTO v_role, v_org
  FROM public.selection_committee sc
  JOIN public.selection_cycles c ON c.id = sc.cycle_id
  WHERE sc.cycle_id = p_cycle_id AND sc.member_id = p_member_id;
  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Member is not in this cycle committee');
  END IF;

  v_starts := COALESCE(p_starts_on, v_hoje);
  IF p_ends_on IS NOT NULL AND p_ends_on < v_starts THEN
    RETURN json_build_object('error', 'ends_on must be on or after starts_on');
  END IF;
  v_reason := nullif(trim(COALESCE(p_reason, '')), '');

  INSERT INTO public.selection_interviewer_blackouts
    (cycle_id, member_id, starts_on, ends_on, reason, created_by, organization_id)
  VALUES (p_cycle_id, p_member_id, v_starts, p_ends_on, v_reason, v_caller, v_org)
  RETURNING id INTO v_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (
    v_caller, 'selection.routing_block_set', 'member', p_member_id,
    jsonb_build_object(
      'cycle_id', p_cycle_id,
      'block_id', v_id,
      'starts_on', v_starts,
      'ends_on', p_ends_on,
      'reason', v_reason,
      'committee_role', v_role,
      'self_service', p_member_id = v_caller,
      'local_date', v_hoje
    )
  );

  RETURN json_build_object(
    'success', true,
    'block_id', v_id,
    'cycle_id', p_cycle_id,
    'member_id', p_member_id,
    'starts_on', v_starts,
    'ends_on', p_ends_on,
    'active_today', v_hoje >= v_starts AND (p_ends_on IS NULL OR v_hoje <= p_ends_on),
    'self_service', p_member_id = v_caller
  );
END;
$function$;

COMMENT ON FUNCTION public.set_interviewer_routing_block(uuid, uuid, date, date, text) IS
  '#1590 onda C — tira um entrevistador do rodizio por PERIODO (decisao do PM: autosservico na propria linha, manage_member para qualquer um). Gate POR RECURSO: compara p_member_id com o chamador antes de escrever. starts_on nulo = hoje no fuso America/Sao_Paulo; ends_on nulo = bloqueio aberto. Nao apaga a URL de agenda: os tres eixos seguem separados (onda B). Auditado.';

CREATE OR REPLACE FUNCTION public.clear_interviewer_routing_block(p_block_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller uuid;
  v_can_manage boolean;
  v_row record;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller IS NULL THEN
    RETURN json_build_object('error', 'Not authenticated');
  END IF;
  v_can_manage := public.can_by_member(v_caller, 'manage_member');

  SELECT b.id, b.cycle_id, b.member_id, b.starts_on, b.ends_on, b.reason, b.created_by
  INTO v_row
  FROM public.selection_interviewer_blackouts b
  WHERE b.id = p_block_id;

  IF NOT FOUND OR (v_row.member_id IS DISTINCT FROM v_caller AND NOT v_can_manage) THEN
    RETURN json_build_object('error', 'Block not found or unauthorized');
  END IF;

  DELETE FROM public.selection_interviewer_blackouts WHERE id = p_block_id;

  INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
  VALUES (
    v_caller, 'selection.routing_block_cleared', 'member', v_row.member_id,
    jsonb_build_object(
      'cycle_id', v_row.cycle_id,
      'block_id', v_row.id,
      'starts_on', v_row.starts_on,
      'ends_on', v_row.ends_on,
      'reason', v_row.reason,
      'created_by', v_row.created_by,
      'self_service', v_row.member_id = v_caller,
      'local_date', v_hoje
    )
  );

  RETURN json_build_object(
    'success', true,
    'block_id', v_row.id,
    'cycle_id', v_row.cycle_id,
    'member_id', v_row.member_id,
    'self_service', v_row.member_id = v_caller
  );
END;
$function$;

COMMENT ON FUNCTION public.clear_interviewer_routing_block(uuid) IS
  '#1590 onda C — devolve o entrevistador ao rodizio apagando a janela (autosservico na propria linha, manage_member para qualquer uma). O historico fica em admin_audit_log (selection.routing_block_cleared), com a janela inteira no metadata. Nao existe oraculo de existencia: bloqueio inexistente e bloqueio alheio devolvem a MESMA mensagem.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. O campo que roteia ganha porta: `manage_selection_committee` aceita a URL
-- ─────────────────────────────────────────────────────────────────────────────
--
-- DROP + CREATE porque a contagem de parâmetros muda (GC-097). Duas consequências que a assinatura
-- antiga escondia:
--
--   (a) `p_role` deixa de ter default 'evaluator' e passa a ser NULL. Com o default antigo, a ação
--       'update' não conseguia distinguir "não mandou papel" de "mandou avaliador", e um
--       autosserviço que só troca a URL rebaixaria/promoveria o papel sem pedir. O branch 'add'
--       aplica COALESCE(p_role,'evaluator'), então a chamada de 4 argumentos não muda de sentido.
--   (b) o DROP zera os GRANTs — e é bom que zere: medido em 13/08, `manage_selection_committee`
--       (RPC de ESCRITA) tinha EXECUTE para `anon` e para PUBLIC, deriva da classe do #1592.
--
-- ⚠️ Os três gates do branch 'update' são desenhados contra a armadilha do #1748 (ampliar o portão
-- de escrita herda o que a coluna traz de default):
--   - trocar PAPEL exige `promote` — senão um observador se promove a avaliador e entra no rodízio;
--   - RELIGAR `can_interview` exige `manage_member` — desligar-se é autosserviço, religar-se depois
--     de um desligamento do GP seria desfazer decisão alheia. O gate olha a TRANSIÇÃO, não o valor,
--     para não recusar um `true` redundante que é no-op;
--   - a URL é autosserviço na própria linha, que é a decisão do PM desta volta.
--
-- O observador que cadastra a própria URL continua FORA do rodízio: o picker exige
-- role IN (evaluator,lead). Autosserviço não é caminho para dentro da fila.
--
-- A URL vira `href` numa tela de admin, então o esquema é validado no SERVIDOR (`^https://`), onde
-- web e MCP não podem divergir: `javascript:` escapa de qualquer escape de HTML.

DROP FUNCTION IF EXISTS public.manage_selection_committee(uuid, text, uuid, text);

CREATE OR REPLACE FUNCTION public.manage_selection_committee(
  p_cycle_id uuid,
  p_action text,
  p_member_id uuid,
  p_role text DEFAULT NULL,
  p_interview_booking_url text DEFAULT NULL,
  p_can_interview boolean DEFAULT NULL
)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_caller_id uuid;
  v_can_promote boolean;
  v_can_manage boolean;
  v_url_provided boolean := p_interview_booking_url IS NOT NULL;
  v_url text := nullif(trim(COALESCE(p_interview_booking_url, '')), '');
  v_before record;
BEGIN
  SELECT id INTO v_caller_id FROM public.members WHERE auth_id = auth.uid();
  IF v_caller_id IS NULL THEN RETURN json_build_object('error','Not authenticated'); END IF;

  IF v_url IS NOT NULL AND v_url !~* '^https://' THEN
    RETURN json_build_object('error','interview_booking_url must start with https://');
  END IF;

  v_can_promote := public.can_by_member(v_caller_id, 'promote');
  v_can_manage  := public.can_by_member(v_caller_id, 'manage_member');

  IF p_action = 'add' THEN
    IF NOT v_can_promote THEN RETURN json_build_object('error','Unauthorized: requires promote permission'); END IF;
    INSERT INTO public.selection_committee (cycle_id, member_id, role, can_interview, interview_booking_url)
    VALUES (p_cycle_id, p_member_id, COALESCE(p_role,'evaluator'), COALESCE(p_can_interview, true), v_url)
    ON CONFLICT (cycle_id, member_id) DO UPDATE SET
      role = COALESCE(p_role, selection_committee.role),
      can_interview = COALESCE(p_can_interview, selection_committee.can_interview),
      interview_booking_url = CASE WHEN v_url_provided THEN v_url
                                   ELSE selection_committee.interview_booking_url END;
    RETURN json_build_object('success', true, 'action', 'added', 'member_id', p_member_id);

  ELSIF p_action = 'remove' THEN
    IF NOT v_can_promote THEN RETURN json_build_object('error','Unauthorized: requires promote permission'); END IF;
    DELETE FROM public.selection_committee WHERE cycle_id = p_cycle_id AND member_id = p_member_id;
    RETURN json_build_object('success', true, 'action', 'removed', 'member_id', p_member_id);

  ELSIF p_action = 'update' THEN
    IF p_member_id IS DISTINCT FROM v_caller_id AND NOT v_can_manage THEN
      RETURN json_build_object('error','Unauthorized: updating another committee member requires manage_member');
    END IF;

    SELECT sc.role, sc.can_interview, sc.interview_booking_url INTO v_before
    FROM public.selection_committee sc
    WHERE sc.cycle_id = p_cycle_id AND sc.member_id = p_member_id;
    IF NOT FOUND THEN
      RETURN json_build_object('error','Member is not in this cycle committee');
    END IF;

    IF p_role IS NOT NULL AND p_role IS DISTINCT FROM v_before.role AND NOT v_can_promote THEN
      RETURN json_build_object('error','Unauthorized: changing committee role requires promote permission');
    END IF;
    IF p_can_interview IS TRUE AND NOT v_before.can_interview AND NOT v_can_manage THEN
      RETURN json_build_object('error','Unauthorized: re-enabling an interviewer requires manage_member');
    END IF;

    UPDATE public.selection_committee sc SET
      role = COALESCE(p_role, sc.role),
      can_interview = COALESCE(p_can_interview, sc.can_interview),
      interview_booking_url = CASE WHEN v_url_provided THEN v_url ELSE sc.interview_booking_url END
    WHERE sc.cycle_id = p_cycle_id AND sc.member_id = p_member_id;

    INSERT INTO public.admin_audit_log (actor_id, action, target_type, target_id, metadata)
    VALUES (
      v_caller_id, 'selection.committee_routing_updated', 'member', p_member_id,
      jsonb_build_object(
        'cycle_id', p_cycle_id,
        'self_service', p_member_id = v_caller_id,
        'role_before', v_before.role,
        'role_after', COALESCE(p_role, v_before.role),
        'can_interview_before', v_before.can_interview,
        'can_interview_after', COALESCE(p_can_interview, v_before.can_interview),
        'url_before_present', v_before.interview_booking_url IS NOT NULL,
        'url_after_present', CASE WHEN v_url_provided THEN v_url IS NOT NULL
                                  ELSE v_before.interview_booking_url IS NOT NULL END,
        'url_changed', v_url_provided AND v_url IS DISTINCT FROM v_before.interview_booking_url
      )
    );

    RETURN json_build_object(
      'success', true, 'action', 'updated', 'member_id', p_member_id,
      'role', COALESCE(p_role, v_before.role),
      'can_interview', COALESCE(p_can_interview, v_before.can_interview),
      'has_url', CASE WHEN v_url_provided THEN v_url IS NOT NULL
                      ELSE v_before.interview_booking_url IS NOT NULL END
    );

  ELSE
    RETURN json_build_object('error', 'Invalid action. Use add, remove or update.');
  END IF;
END;
$function$;

COMMENT ON FUNCTION public.manage_selection_committee(uuid, text, uuid, text, text, boolean) IS
  '#1590 onda C — add/remove (promote, comportamento inalterado) + update (NOVO): a URL de agenda que decide o rodizio passa a ter porta. Gates do update, por recurso: propria linha ou manage_member; trocar papel exige promote; RELIGAR can_interview exige manage_member (desligar-se e autosservico). URL validada como https:// no servidor. Update e auditado (selection.committee_routing_updated), sem gravar a URL no log.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. `CREATE FUNCTION` nasce com EXECUTE para PUBLIC — revogar na MESMA migration
-- ─────────────────────────────────────────────────────────────────────────────
--
-- #1710 / #1592: uma RPC de escrita publicada para `anon` depende de o gate interno nunca falhar.
-- `manage_selection_committee` estava exatamente assim antes desta migration (medido em 13/08:
-- EXECUTE para `anon` e para PUBLIC numa RPC que escreve no comitê).

REVOKE EXECUTE ON FUNCTION public.get_selection_routing_overview(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_interviewer_routing_block(uuid, uuid, date, date, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.clear_interviewer_routing_block(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.manage_selection_committee(uuid, text, uuid, text, text, boolean) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_selection_routing_overview(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_interviewer_routing_block(uuid, uuid, date, date, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.clear_interviewer_routing_block(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.manage_selection_committee(uuid, text, uuid, text, text, boolean) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

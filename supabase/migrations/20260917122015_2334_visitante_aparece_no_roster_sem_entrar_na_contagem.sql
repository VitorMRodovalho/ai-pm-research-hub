-- #2334 fase 2 (fatia 1) — o lider em formacao APARECE na tribo visitada, sem entrar na contagem.
--
-- O CASO: a partir do ciclo 4 o lider aprovado passa o semestre como visitante em tribos existentes
-- para conhecer modelos de conducao antes de formar a propria. O vinculo e feito com engajamento
-- `observer`, que de proposito NAO consome vaga (v_tribe_active_members filtra `volunteer`), NAO
-- popula members.tribe_id (o trigger declara isso) e NAO viola AH_research_tribe_single_active.
--
-- O QUE FALTAVA: ele nao aparecia na lista de membros da tribo. `v_initiative_roster` exclui
-- observer nas DUAS pontas (`role <> 'observer' AND kind <> 'observer'`), e a tela bebe dela.
--
-- ⚠️ POR QUE ESTA MIGRATION NAO ABRE A VIEW, que seria o caminho obvio:
--   `v_initiative_roster` e consumida por 12 funcoes (medido em 17/09 por varredura de prosrc;
--   `pg_depend` confirma que nenhuma OUTRA view depende dela). Duas delas sao PORTOES DE AUTORIDADE:
--     * `_can_sign_gate`          — decide quem assina cadeia de aprovacao
--     * `_can_manage_recurring_rule` — decide quem administra reuniao recorrente
--   Outras cinco CONTAM (roster_count, tribe_stats, initiative_stats, tribe_gamification,
--   initiative_gamification) e cinco alimentam paineis.
--
--   Abrir a view mudaria as 12 de uma vez. Os dois portoes hoje sao seguros porque exigem
--   `role = 'leader'` explicitamente — medido, e foi a duvida que valia medir antes de prometer.
--   Mas bastaria UM consumidor de contagem esquecido para o visitante passar a contar EM SILENCIO,
--   que e o modo de falha que esta onda inteira perseguiu (#2323, #2325, #2286).
--
--   ⇒ A view fica INTACTA. So a RPC da tela passa a unir os visitantes, com marcador proprio.
--     O risco cai de 12 consumidores para 1.
--
-- O CONTRATO NOVO: cada linha ganha `is_visitor` (boolean). Quem le a RPC decide o que fazer com
-- ele; quem nao ler continua vendo exatamente o mesmo conjunto de antes MAIS os visitantes, e por
-- isso a tela precisa do rotulo (vai na mesma PR).
--
-- PRECEDENCIA: quem for volunteer E observer na MESMA iniciativa aparece como membro efetivo
-- (`is_visitor = false`). O `DISTINCT ON (person_id)` com ordem por prioridade garante isso, e o
-- visitante recebe ordem 9 para cair depois de qualquer papel efetivo.
--
-- Atributos preservados: plpgsql, STABLE, SECURITY DEFINER, search_path, e o gate
-- `rls_can_see_initiative` na primeira linha (ADR-0105: iniciativa confidencial nao vaza roster).
--
-- Cross-ref: #2334, #2333, ADR-0105, AH_research_tribe_single_active_engagement.

CREATE OR REPLACE FUNCTION public.get_initiative_roster_members(p_initiative_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.rls_can_see_initiative(p_initiative_id) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(row_to_json(x) ORDER BY x.is_visitor, x.name), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT DISTINCT ON (u.person_id)
      pm.id,
      pm.name,
      pm.photo_url,
      pm.chapter,
      pm.operational_role,
      pm.designations,
      pm.tribe_id,
      pm.initiative_id,
      pm.share_whatsapp,
      pm.current_cycle_active,
      pm.is_active,
      u.is_visitor
    FROM (
      -- Membros efetivos: a view segue sendo a fonte, e segue intacta.
      SELECT r.person_id, r.member_id, false AS is_visitor,
             CASE r.role
               WHEN 'leader' THEN 0
               WHEN 'comms_leader' THEN 1
               WHEN 'coordinator' THEN 2
               WHEN 'participant' THEN 3
               ELSE 4
             END AS ord
      FROM public.v_initiative_roster r
      WHERE r.initiative_id = p_initiative_id

      UNION ALL

      -- Visitantes: lidos direto de engagements, porque a view os exclui de proposito.
      -- Ordem 9 para caírem depois de qualquer papel efetivo no DISTINCT ON.
      SELECT e.person_id, m.id AS member_id, true AS is_visitor, 9 AS ord
      FROM public.engagements e
      JOIN public.members m ON m.person_id = e.person_id
      WHERE e.initiative_id = p_initiative_id
        AND e.status = 'active'
        AND (e.kind = 'observer' OR e.role = 'observer')
    ) u
    JOIN public.public_members pm ON pm.id = u.member_id
    ORDER BY u.person_id, u.ord
  ) x;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$function$;

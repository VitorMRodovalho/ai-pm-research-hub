-- #2970: _gate_threshold_met, limiar 'all': a contagem de elegíveis para assim que passa das assinaturas, e a busca
-- começa pelos que o cache de preview aponta. Mesmo resultado; os outros ramos ficam como na 20260805000303.

CREATE OR REPLACE FUNCTION public._gate_threshold_met(p_chain_id uuid, p_gate jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    -- #2970: 'all' continua sendo "assinaturas >= elegíveis ativos" (S >= E), mas a contagem de
    -- elegíveis para em S+1: min(E, S+1) <= S equivale a E <= S. Com o portão ainda aberto (o caso
    -- comum), bastam S+1 elegíveis para saber que não foi atingido, em vez de rodar _can_sign_gate
    -- para todo membro ativo. Para achar os elegíveis cedo, a busca começa por quem
    -- preview_gate_eligibles_cache (ADR-0016 Emenda 3) aponta para o tipo. O cache só ORDENA a busca:
    -- todo membro contado passa por _can_sign_gate ao vivo, e um cache velho só deixa a busca mais
    -- longa, nunca muda a resposta.
    WHEN (p_gate->>'threshold') = 'all' THEN
      (SELECT count(*) FROM (
         SELECT 1
         FROM (SELECT m.id FROM public.members m
               WHERE m.is_active
               ORDER BY EXISTS (SELECT 1 FROM public.preview_gate_eligibles_cache c
                                WHERE c.member_id = m.id
                                  AND (p_gate->>'kind') = ANY (c.eligible_gates)) DESC,
                        m.id
               OFFSET 0) m
         WHERE public._can_sign_gate(m.id, p_chain_id, p_gate->>'kind')
         LIMIT (SELECT count(*) FROM public.approval_signoffs s
                 WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind')
                   AND s.signoff_type IN ('approval','acknowledge')) + 1
       ) e)
      <= (SELECT count(*) FROM public.approval_signoffs s
            WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind')
              AND s.signoff_type IN ('approval','acknowledge'))
    -- #975 PR-3 (WA2): committee_majority — maioria ESTRITA das aprovações sobre o
    -- roster pinado em gate_state na ativação (NÃO live _can_sign_gate, que encolheria
    -- mid-flight se um membro saísse de função). Roster vazio/ausente => não atingido
    -- (quórum falha; dormente até §7.1). Conta só signoff_type='approval'.
    WHEN (p_gate->>'threshold') = 'majority' THEN
      (SELECT r.n >= 1
          AND (SELECT count(*) FROM public.approval_signoffs s
               WHERE s.approval_chain_id = p_chain_id
                 AND s.gate_kind = (p_gate->>'kind')
                 AND s.signoff_type = 'approval'
                 AND s.signer_id = ANY(r.roster))
              > floor(r.n::numeric / 2)
       FROM (
         SELECT roster, cardinality(roster) AS n
         FROM (
           SELECT COALESCE(ARRAY(
             SELECT (jsonb_array_elements_text(
                       ac.gate_state -> (p_gate->>'kind') -> 'committee_roster_ids'))::uuid
           ), ARRAY[]::uuid[]) AS roster
           FROM public.approval_chains ac WHERE ac.id = p_chain_id
         ) q
       ) r)
    -- #975 PR-3 (WA2): partner_consultation — consultivo janelado NÃO-bloqueante.
    -- Atingido quando a janela auto-fechou (cron escreveu auto_closed_at) OU todos os
    -- elegíveis responderam (QUALQUER signoff_type — approval/abstain/rejection; uma
    -- rejeição é registrada mas NUNCA veta). eligible_snapshot ausente => não atingido.
    WHEN (p_gate->>'threshold') = 'window_optional' THEN
      (SELECT (ac.gate_state -> (p_gate->>'kind') ->> 'auto_closed_at') IS NOT NULL
          OR (
            (ac.gate_state -> (p_gate->>'kind') ->> 'eligible_snapshot') IS NOT NULL
            -- review fix (BLOCKER, 4 lentes): guard eligible_snapshot > 0. Com 0 parceiros
            -- elegíveis o gate consultivo NÃO pode auto-satisfazer via count(0)>=0 — só fecha
            -- por auto_closed_at (cron, após os 15 úteis), preservando a janela de observação
            -- mandatória da Política 12.2.2. Espelha o guard n>=1 do branch committee_majority.
            AND (ac.gate_state -> (p_gate->>'kind') ->> 'eligible_snapshot')::int > 0
            -- count DISTINCT signer (o UNIQUE existente approval_signoffs(chain,gate,signer) já
            -- garante 1 linha/membro, mas DISTINCT é a intenção correta e auto-documentada:
            -- "todos os elegíveis responderam" = respondentes distintos >= snapshot).
            AND (SELECT count(DISTINCT s.signer_id) FROM public.approval_signoffs s
                 WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind'))
                >= (ac.gate_state -> (p_gate->>'kind') ->> 'eligible_snapshot')::int
          )
       FROM public.approval_chains ac WHERE ac.id = p_chain_id)
    WHEN (p_gate->>'threshold') ~ '^[0-9]+$' AND (p_gate->>'threshold')::int > 0 THEN
      (SELECT count(*) FROM public.approval_signoffs s
         WHERE s.approval_chain_id = p_chain_id AND s.gate_kind = (p_gate->>'kind')
           AND s.signoff_type IN ('approval','acknowledge'))
      >= (p_gate->>'threshold')::int
    ELSE true
  END;
$function$;

-- #2970: _prior_gates_satisfied avalia primeiro os portões anteriores baratos e para no primeiro não atingido. Mesmo
-- resultado (todos os anteriores atingidos); muda só a ordem em que eles são olhados.

CREATE OR REPLACE FUNCTION public._prior_gates_satisfied(p_chain_id uuid, p_gate_kind text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_ordem int;
  v_gate  jsonb;
BEGIN
  -- A ordem do portão pedido. Sem ela (tipo fora da cadeia, cadeia inexistente) não há anterior, e a resposta é
  -- true, como na forma em SQL que esta substitui.
  SELECT (g->>'order')::int INTO v_ordem
  FROM public.approval_chains ac2, jsonb_array_elements(ac2.gates) g
  WHERE ac2.id = p_chain_id AND g->>'kind' = p_gate_kind
  LIMIT 1;

  -- "Todos os anteriores atingidos" é uma conjunção: a ordem não muda a resposta, só o custo. O limiar 'all' é o
  -- único que pode varrer os membros ativos (quando já está atingido), então fica por último; um portão numérico ou
  -- de janela responde em uma leitura. Dentro de cada grupo, a ordem do próprio portão.
  FOR v_gate IN
    SELECT gp
    FROM public.approval_chains ac, jsonb_array_elements(ac.gates) gp
    WHERE ac.id = p_chain_id
      AND (gp->>'order')::int < v_ordem
    ORDER BY ((gp->>'threshold') = 'all'), (gp->>'order')::int
  LOOP
    IF NOT public._gate_threshold_met(p_chain_id, v_gate) THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END;
$function$;

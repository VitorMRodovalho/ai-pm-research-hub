-- ADR-0016 Amendment 2 C9 backlog: CHECK constraint em approval_chains.gates jsonb shape.
-- Previne gates malformados mesmo sob bypass RLS (defense-in-depth).
-- Shape esperado: jsonb array não-vazio, cada elemento {kind, order, threshold}.
-- - kind: string do enum gate_kinds conhecidos
-- - order: integer >= 1
-- - threshold: integer >= 0 OU string 'all'

CREATE OR REPLACE FUNCTION public._validate_gates_shape(p_gates jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    jsonb_typeof(p_gates) = 'array'
    AND jsonb_array_length(p_gates) > 0
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_gates) g
      WHERE NOT (
        jsonb_typeof(g) = 'object'
        AND g ? 'kind' AND g ? 'order' AND g ? 'threshold'
        AND (g->>'kind') IN (
          'curator','leader','leader_awareness','submitter_acceptance',
          'chapter_witness','president_go','president_others',
          'volunteers_in_role_active','member_ratification','external_signer'
        )
        AND jsonb_typeof(g->'order') = 'number'
        AND (g->>'order')::int >= 1
        AND (
          (jsonb_typeof(g->'threshold') = 'number' AND (g->>'threshold')::int >= 0)
          OR (jsonb_typeof(g->'threshold') = 'string' AND g->>'threshold' = 'all')
        )
      )
    );
$$;

COMMENT ON FUNCTION public._validate_gates_shape(jsonb) IS
  'ADR-0016 C9: valida shape de approval_chains.gates — array non-empty de {kind, order, threshold}. Usado no CHECK constraint da tabela.';

ALTER TABLE public.approval_chains
  DROP CONSTRAINT IF EXISTS approval_chains_gates_shape;

ALTER TABLE public.approval_chains
  ADD CONSTRAINT approval_chains_gates_shape
  CHECK (public._validate_gates_shape(gates));

COMMENT ON CONSTRAINT approval_chains_gates_shape ON public.approval_chains IS
  'ADR-0016 Amendment 2 C9: gates jsonb must be non-empty array of {kind, order, threshold} objects. Prevents malformed gates under any access path (including service_role). Validates kind enum + order>=1 + threshold int>=0 or "all".';

NOTIFY pgrst, 'reload schema';

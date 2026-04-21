-- ============================================================================
-- Security hardening — reject_artifacts_insert SET search_path (issue #82 WARN)
--
-- Supabase advisor flaggeou: "Function public.reject_artifacts_insert has a role
-- mutable search_path". SECURITY DEFINER functions sem search_path podem ser
-- exploitadas via search_path injection (role malicioso cria tabela shadow em
-- schema próprio e muda search_path antes de invocar).
--
-- Esta função é trigger AFTER INSERT em public.artifacts (tabela frozen per
-- ADR-0012). Fix trivial: adicionar SET search_path no CREATE OR REPLACE.
-- Corpo inalterado — só policy.
--
-- Contexto: é a ÚNICA função restante sem search_path em public (todas as
-- outras foram corrigidas em sweeps anteriores — items P1 antigos do backlog
-- `can()`, `can_by_member()`, `export_my_data()` já resolvidos).
--
-- Issue: #82 (architecture audit opportunities).
-- ADR: ADR-0012 (schema consolidation — artifacts frozen).
-- Rollback: CREATE OR REPLACE sem SET search_path (não recomendado).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reject_artifacts_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = 'public', 'pg_temp'
AS $function$
BEGIN
  RAISE EXCEPTION 'artifacts table is frozen (ADR-0012 Princípio 4). New submissions must use publication_submissions.'
    USING ERRCODE = 'check_violation';
END;
$function$;

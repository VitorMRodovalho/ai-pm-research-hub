-- Recaptura do corpo VIVO de offboard_member() — sem mudanca de comportamento.
--
-- Por que este arquivo existe: a DDL real rodou em 20260803233204 (arquivo
-- irmao, escrito no mesmo PR). O gate Phase C elege a captura vencedora pela
-- ORDEM ALFABETICA do nome do arquivo, e 20260803233204 ordena ANTES de
-- 20260805000078, que carrega a assinatura antiga do wrapper (a que aceitava
-- p_effective_date e descartava). Sem esta recaptura, a captura canonica de
-- offboard_member continuaria sendo a versao morta.
--
-- CREATE OR REPLACE idempotente: o corpo abaixo ja e o corpo vivo em producao.

CREATE OR REPLACE FUNCTION public.offboard_member(
  p_member_id uuid,
  p_new_status text,
  p_reason text,
  p_effective_date date DEFAULT NULL::date
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  RETURN public.admin_offboard_member(
    p_member_id       => p_member_id,
    p_new_status      => p_new_status,
    p_reason_category => 'other',
    p_reason_detail   => p_reason,
    p_reassign_to     => NULL,
    p_effective_date  => p_effective_date
  );
END;
$function$;

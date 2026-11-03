-- #2946 (decisão do GP em 02/11/2026): selection_coi_recused alinhado à ADR-0109 §3.
--
-- A ADR-0109 §3 diz que o impedimento por conflito de interesse acaba quando a candidatura vira terminal
-- ("rejected/withdrawn/approved -> não mais candidato no ciclo"), e o helper só tratava como terminais
-- rejected, withdrawn e cancelled. Com isso, quem já foi aprovado no ciclo seguia impedido das visões de
-- seleção daquele ciclo enquanto ele estivesse aberto. Agora approved e converted (aprovado que virou membro)
-- também são terminais para a recusa.
--
-- Os outros status do domínio (screening, objective_eval, objective_cutoff, interview_*, final_eval,
-- waitlist) seguem recusando: a decisão do GP cobre só approved e converted.
--
-- O comando é o da captura vigente (20260805000287), com a troca só na lista de status: assinatura,
-- LANGUAGE sql, STABLE, SECURITY DEFINER, search_path, a isenção de manage_platform e o casamento por
-- members.email e member_emails ficam iguais. Os REVOKE e o GRANT são os vigentes, repetidos.
-- As 14 funções que chamam o helper passam a seguir a regra sem mudança nelas.

CREATE OR REPLACE FUNCTION public.selection_coi_recused(p_caller_id uuid, p_cycle_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    p_cycle_id IS NOT NULL
    AND p_caller_id IS NOT NULL
    AND NOT public.can_by_member(p_caller_id, 'manage_platform')
    AND EXISTS (
      SELECT 1
      FROM public.selection_applications sa
      JOIN public.members m ON m.id = p_caller_id
      WHERE sa.cycle_id = p_cycle_id
        AND sa.status NOT IN ('rejected','withdrawn','cancelled','approved','converted')
        AND sa.email IS NOT NULL
        AND (
          lower(sa.email) = lower(m.email)
          OR EXISTS (
            SELECT 1 FROM public.member_emails me
            WHERE me.member_id = m.id AND lower(me.email) = lower(sa.email)
          )
        )
    );
$function$;

REVOKE ALL ON FUNCTION public.selection_coi_recused(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.selection_coi_recused(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.selection_coi_recused(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.selection_coi_recused(uuid, uuid) TO service_role;

NOTIFY pgrst, 'reload schema';

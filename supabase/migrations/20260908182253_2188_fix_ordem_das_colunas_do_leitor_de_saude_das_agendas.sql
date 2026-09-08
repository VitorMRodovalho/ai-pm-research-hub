-- #2188 — o leitor da saude das agendas.
--
-- POR QUE ESTE ARQUIVO EXISTE SEPARADO. Na aplicacao de 08/09 esta funcao saiu na tracking row
-- `20260908182226` com a ordem de `can_interview` e `cycle_id` TROCADA no RETURN QUERY contra o
-- RETURNS TABLE. Postgres so casa as colunas de um RETURN QUERY em tempo de EXECUCAO, entao
-- `apply_migration` devolveu sucesso e a funcao teria levantado erro de tipo (boolean na posicao
-- de uuid) na primeira chamada real. A tracking row `20260908182253` e o conserto.
--
-- O corpo abaixo e o FINAL, ja com a ordem certa, e reaplica-lo e idempotente. A licao fica no
-- comentario em vez de no codigo: sucesso do executor nao e pos-condicao, quem prova e chamar.
-- Verificado em 08/09 chamando a funcao como o GP: 4 agendas, e ela ja mostrava o
-- `routing_blocked` do avaliador pausado.

-- 4. O leitor
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_interview_agenda_health()
RETURNS TABLE (
  booking_url text,
  member_id uuid,
  member_name text,
  cycle_id uuid,
  can_interview boolean,
  routing_blocked boolean,
  probed_at timestamptz,
  days_open integer,
  slots_visible integer,
  probe_ok boolean,
  probe_error text,
  dispatches_total bigint,
  bookings_total bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid;
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  SELECT m.id INTO v_caller FROM public.members m WHERE m.auth_id = auth.uid();
  IF v_caller IS NULL OR NOT public.can_by_member(v_caller, 'manage_member') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  RETURN QUERY
  WITH agendas AS (
    SELECT DISTINCT ON (url)
      url, m_id AS member_id, c_id AS cycle_id, pode
    FROM (
      SELECT sc.interview_booking_url AS url, sc.member_id AS m_id, sc.cycle_id AS c_id,
             sc.can_interview AS pode, 1 AS prio
      FROM public.selection_committee sc
      JOIN public.selection_cycles c ON c.id = sc.cycle_id
      WHERE sc.interview_booking_url IS NOT NULL AND c.status = 'open'
      UNION ALL
      SELECT m.interview_booking_url, m.id, NULL::uuid, NULL::boolean, 2
      FROM public.members m WHERE m.interview_booking_url IS NOT NULL
      UNION ALL
      SELECT c.interview_booking_url, NULL::uuid, c.id, NULL::boolean, 3
      FROM public.selection_cycles c
      WHERE c.interview_booking_url IS NOT NULL AND c.status = 'open'
    ) t
    ORDER BY url, prio
  )
  SELECT
    a.url,
    a.member_id,
    m.name,
    a.cycle_id,
    a.pode,
    EXISTS (
      SELECT 1 FROM public.selection_interviewer_blackouts b
      WHERE b.member_id = a.member_id AND b.cycle_id = a.cycle_id
        AND v_hoje >= b.starts_on AND (b.ends_on IS NULL OR v_hoje <= b.ends_on)
    ),
    p.probed_at, p.days_open, p.slots_visible, p.ok, p.error,
    (SELECT count(*) FROM public.selection_dispatch_url_log l WHERE l.resolved_url = a.url),
    (SELECT count(*) FROM public.selection_dispatch_url_log l
      WHERE l.resolved_url = a.url AND l.booked_at IS NOT NULL)
  FROM agendas a
  LEFT JOIN public.members m ON m.id = a.member_id
  LEFT JOIN LATERAL (
    SELECT pr.probed_at, pr.days_open, pr.slots_visible, pr.ok, pr.error
    FROM public.interview_agenda_probes pr
    WHERE pr.booking_url = a.url
    ORDER BY pr.probed_at DESC
    LIMIT 1
  ) p ON true
  ORDER BY a.url;
END;
$$;

REVOKE ALL ON FUNCTION public.get_interview_agenda_health() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_interview_agenda_health() TO authenticated, service_role;

COMMENT ON FUNCTION public.get_interview_agenda_health() IS

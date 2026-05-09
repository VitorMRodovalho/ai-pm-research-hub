-- p131 T-3 C3 step 1: criar selection_application_service_history
-- ============================================================================
--
-- Driver: auditoria pós T-3 cron compliance (handoff p131). Tabela é
-- referenciada pelo worker `pmi-vep-sync` (cloudflare-workers/pmi-vep-sync/
-- src/db.ts insertServiceHistory + script-mapper.ts) mas a migration
-- correspondente nunca foi aplicada — código TS é orfão sem destino.
-- Resultado: chamadas insertServiceHistory falham silenciosamente, e
-- o histórico de service por candidato (multi-chapter, multi-cycle PMI)
-- não é capturado.
--
-- Schema espelha types.ts ServiceHistoryInsert:
--   application_id (FK selection_applications)
--   chapter_name (NOT FK por design — chapters multi-org não normalizados)
--   role_name (text — research/leader/manager/etc)
--   start_date / end_date (date — datas individuais por candidato)
--   source ('pmi_community' | 'pmi_vep' | 'manual')
--   captured_at (when worker scraped this row)
--
-- Append-only via UNIQUE INDEX (application_id, chapter_name, COALESCE(start_date,'1900-01-01')).
-- ON CONFLICT DO NOTHING permite re-import idempotente sem dup rows.
--
-- LGPD: dados sensitivos = histórico de filiação institucional. RLS rpc-only.
-- Cleanup retention: alinhado com selection_applications retention (5y pós cycle close).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.selection_application_service_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES public.selection_applications(id) ON DELETE CASCADE,
  chapter_name text NOT NULL,
  role_name text,
  start_date date,
  end_date date,
  source text NOT NULL CHECK (source IN ('pmi_community','pmi_vep','manual')),
  captured_at timestamptz NOT NULL DEFAULT now(),
  organization_id uuid REFERENCES public.organizations(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Idempotency UNIQUE per (application_id, chapter_name, start_date)
-- COALESCE para tratar NULL start_date como '1900-01-01' (evita duplicatas
-- quando worker rode rows sem startDate confirmado)
CREATE UNIQUE INDEX IF NOT EXISTS uq_service_history_app_chapter_start
  ON public.selection_application_service_history (
    application_id, chapter_name, COALESCE(start_date, '1900-01-01'::date)
  );

-- Lookup por application_id (consulta principal: dado um candidato, buscar histórico)
CREATE INDEX IF NOT EXISTS idx_service_history_application_id
  ON public.selection_application_service_history(application_id);

-- Lookup por end_date (cron compliance: vencendo em N dias)
CREATE INDEX IF NOT EXISTS idx_service_history_end_date
  ON public.selection_application_service_history(end_date)
  WHERE end_date IS NOT NULL;

ALTER TABLE public.selection_application_service_history ENABLE ROW LEVEL SECURITY;

-- RLS: pattern selection_applications (rpc-only deny all + V4 org scope)
CREATE POLICY rpc_only_deny_all ON public.selection_application_service_history
  AS PERMISSIVE FOR ALL TO PUBLIC
  USING (false) WITH CHECK (false);

GRANT INSERT, UPDATE, DELETE, SELECT ON public.selection_application_service_history TO service_role;
GRANT SELECT ON public.selection_application_service_history TO authenticated;

COMMENT ON TABLE public.selection_application_service_history IS
  'p131 T-3: append-only history of PMI volunteer service per candidate (multi-chapter, multi-role, multi-cycle). Source = pmi_community (Community API) | pmi_vep (VEP scraper) | manual (admin). Populated by pmi-vep-sync worker via insertServiceHistory. UNIQUE (application_id, chapter_name, COALESCE(start_date,1900-01-01)) for idempotent re-imports. RLS rpc-only.';

NOTIFY pgrst, 'reload schema';

-- Seed: First official Change Request + schema evolution for governance fields
-- Date: 2026-03-17
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Evolve change_requests with governance-grade columns
--    The original table only had: id, cr_number, title, description, priority,
--    requested_by (FK members), status, created_at, updated_at.
--    Adding structured fields for the PMI governance rite.
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.change_requests
  ADD COLUMN IF NOT EXISTS proposed_changes text,
  ADD COLUMN IF NOT EXISTS justification text,
  ADD COLUMN IF NOT EXISTS requested_by_role text,
  ADD COLUMN IF NOT EXISTS reviewed_by uuid REFERENCES public.members(id),
  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
  ADD COLUMN IF NOT EXISTS review_notes text;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Expand status CHECK to include governance lifecycle values
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.change_requests DROP CONSTRAINT IF EXISTS change_requests_status_check;
ALTER TABLE public.change_requests ADD CONSTRAINT change_requests_status_check
  CHECK (status IN (
    'draft', 'open', 'pending_review', 'in_review',
    'approved', 'rejected', 'implemented', 'closed', 'cancelled'
  ));

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Seed the first Change Request — CPO directive
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO public.change_requests (
  cr_number,
  title,
  description,
  proposed_changes,
  justification,
  status,
  priority,
  requested_by_role
) VALUES (
  'CR-2026-001',
  'Formalização da Esteira Digital de Curadoria, Rubricas e SLAs',
  'Atualização das seções 4.2 e 5.3 do Manual de Governança para formalizar o uso do sistema digital na avaliação técnica de artefatos pelo Comitê de Curadoria.',
  '1. SLA de 7 dias corridos para o Comitê avaliar cada artefato submetido.
2. Avaliação via Rubrica Digital (JSONB) dos 5 critérios: Clareza, Originalidade, Aderência, Relevância, Ética.
3. Fluxo de "Return to Origin" — artefatos devolvidos retornam ao quadro da tribo com feedback estruturado.
4. Audit Trail obrigatório: toda decisão gera registro em curation_review_log com scores, feedback e timestamps.
5. Badge visual de SLA vencido no Super-Kanban para visibilidade do comitê.',
  'Evitar gargalos de produção na esteira de conhecimento, eliminar trânsito de e-mails e arquivos avulsos entre tribos e comitê, e garantir o Audit Trail exigido pelo Compliance do PMI para publicação de artefatos institucionais.',
  'pending_review',
  'high',
  'CPO / Gerente de Projeto'
)
ON CONFLICT DO NOTHING;

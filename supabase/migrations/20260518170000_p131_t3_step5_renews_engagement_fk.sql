-- p131 T-3 C3 step 5: FK selection_applications.renews_engagement_id
-- Permite reconhecer "renovação" auditável quando voluntário re-cadastra via VEP.
-- Modelo Q-D=C2: explícito > heurística (email match + date proximity).

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS renews_engagement_id uuid REFERENCES public.engagements(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.selection_applications.renews_engagement_id IS
  'p131 T-3 C3 step 5: FK explícita para engagement que esta application está renovando (Q-D C2). Populado: (a) auto pelo trigger trg_link_renewal_application quando email + person matches engagement existente próximo de end_date; (b) manual via admin UI/RPC. NULL = não é renovação (vínculo novo). Usado pela ball-in-court logic do GP — quando renews_engagement_id != NULL, a corte do nudge de renovação transfere do voluntário (precisava se cadastrar) para o GP (precisa rodar selection process + ativar antes de end_date vencer).';

CREATE INDEX IF NOT EXISTS idx_selection_applications_renews_engagement
  ON public.selection_applications(renews_engagement_id)
  WHERE renews_engagement_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';

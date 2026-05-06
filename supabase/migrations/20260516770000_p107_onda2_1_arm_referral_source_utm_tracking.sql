-- ARM Onda 2.1: instrumentação de funil — referral_source + UTM em selection_applications
--
-- Estado pré: apenas vep_opportunity_id text (tracking VEP). Sem source genérico
-- ou UTM data → expansão é blind quanto à origem dos candidatos.
--
-- Mudanças:
--   1) ADD COLUMN referral_source text — origem alta-nível
--      (vep | landing_page | direct_link | social | newsletter | referral | other)
--   2) ADD COLUMN referrer_member_id uuid — FK opcional para member que referiu
--   3) ADD COLUMN utm_data jsonb — payload UTM completo (source/medium/campaign/content/term)
--   4) Backfill: existing VEP-origin rows recebem referral_source='vep' baseado em
--      vep_opportunity_id IS NOT NULL (heurística segura)
--
-- Rollback:
--   ALTER TABLE selection_applications
--     DROP COLUMN referral_source, DROP COLUMN referrer_member_id, DROP COLUMN utm_data;

ALTER TABLE public.selection_applications
  ADD COLUMN IF NOT EXISTS referral_source text,
  ADD COLUMN IF NOT EXISTS referrer_member_id uuid REFERENCES public.members(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS utm_data jsonb;

COMMENT ON COLUMN public.selection_applications.referral_source IS
  'Origem alta-nível do candidato. Valores conhecidos: vep | landing_page | direct_link | social | newsletter | referral | other. NULL = não capturado (legacy ou origem desconhecida). ARM Onda 2.1 (#137 do audit p107).';

COMMENT ON COLUMN public.selection_applications.referrer_member_id IS
  'Member que referiu este candidato (quando referral_source=referral). FK opcional → members. ON DELETE SET NULL para não bloquear member offboarding.';

COMMENT ON COLUMN public.selection_applications.utm_data IS
  'Payload UTM completo da landing page (source/medium/campaign/content/term). jsonb para flexibilidade. NULL = não capturado.';

-- Backfill heurístico: aplicações com vep_opportunity_id têm origem 'vep'
UPDATE public.selection_applications
SET referral_source = 'vep'
WHERE referral_source IS NULL
  AND vep_opportunity_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';

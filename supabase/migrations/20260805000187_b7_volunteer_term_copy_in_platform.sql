-- B7 (Pré-Onboarding Journey, #740 / discovery 2026-06-16): corrigir a cópia
-- desatualizada do passo `volunteer_term` no checklist de onboarding.
--
-- A descrição dizia "Baixe o Termo pré-preenchido, assine via gov.br e faça
-- upload do assinado" (fluxo ANTIGO, pré-plataforma). O fluxo REAL é assinatura
-- digital in-platform em `/volunteer-agreement` (`sign_volunteer_agreement`,
-- hash SHA-256) — e o CTA do OnboardingChecklist.tsx já aponta para lá. A cópia
-- enganava o candidato (sair da plataforma à procura de download/gov.br/upload).
--
-- Conteúdo (DML) — surfaceado por get_my_onboarding → OnboardingChecklist
-- (getDesc lê description_pt/en/es). Idempotente.
UPDATE public.onboarding_steps
SET
  description_pt = 'Assine o Termo de Voluntariado digitalmente aqui na plataforma — sem baixar, sem gov.br e sem upload.',
  description_en = 'Sign the Volunteer Agreement digitally here on the platform — no download, no gov.br, no upload.',
  description_es = 'Firme el Acuerdo de Voluntariado digitalmente aquí en la plataforma — sin descarga, sin gov.br y sin carga.'
WHERE id = 'volunteer_term';

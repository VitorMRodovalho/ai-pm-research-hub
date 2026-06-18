-- #106 PR2 — chapter outreach script (Bloco 4): editable trilingual divulgation copy.
--
-- Stored in platform_settings (key-value, JSONB) as the GLOBAL key 'chapter_outreach_script'
-- (MVP global per SPEC; per-chapter is a deferred follow-up). The GP edits it via the EXISTING
-- admin_update_setting(p_key, p_new_value jsonb, p_reason) RPC (gate manage_platform) on
-- /admin/settings; chapter directors COPY it (read-only) on /admin/chapter.
--
-- platform_settings has deny-all RLS for authenticated + get_platform_setting is service_role-only,
-- so this adds a NARROW SECDEF reader that returns ONLY this one (non-sensitive) key to authenticated
-- members — without broadening get_platform_setting to expose every setting.

-- Seed the default (idempotent — never overwrite a value the GP has already customized).
INSERT INTO public.platform_settings (key, value, description, change_reason)
VALUES (
  'chapter_outreach_script',
  jsonb_build_object(
    'pt-BR', E'📣 O Núcleo de IA está com inscrições abertas!\n\nSe você é profissional de gestão de projetos e quer pesquisar e aplicar IA na prática, junte-se a nós: participação voluntária, certificados PMI e uma comunidade ativa.\n\n👉 Inscreva-se: [link]\n\nDúvidas? Fale com a diretoria do seu capítulo.',
    'en-US', E'📣 The AI Hub is open for applications!\n\nIf you are a project management professional who wants to research and apply AI in practice, join us: volunteer participation, PMI certificates, and an active community.\n\n👉 Apply: [link]\n\nQuestions? Reach out to your chapter board.',
    'es-LATAM', E'📣 ¡El Núcleo de IA tiene inscripciones abiertas!\n\nSi eres profesional de gestión de proyectos y quieres investigar y aplicar IA en la práctica, únete: participación voluntaria, certificados PMI y una comunidad activa.\n\n👉 Inscríbete: [link]\n\n¿Dudas? Habla con la directiva de tu capítulo.'
  ),
  'Script de divulgação trilíngue, editável pelo GP, copiável pelos diretores de capítulo (#106 Bloco 4).',
  'seed inicial #106 PR2'
)
ON CONFLICT (key) DO NOTHING;

-- Narrow SECDEF reader: returns ONLY the outreach script key (non-sensitive), to any authenticated
-- member. Does NOT broaden the service-role-only get_platform_setting.
CREATE OR REPLACE FUNCTION public.get_chapter_outreach_script()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE((SELECT value FROM public.platform_settings WHERE key = 'chapter_outreach_script'), '{}'::jsonb);
$function$;

REVOKE ALL ON FUNCTION public.get_chapter_outreach_script() FROM public;
GRANT EXECUTE ON FUNCTION public.get_chapter_outreach_script() TO authenticated;

-- ROLLBACK: DROP FUNCTION public.get_chapter_outreach_script();
--           DELETE FROM public.platform_settings WHERE key = 'chapter_outreach_script';

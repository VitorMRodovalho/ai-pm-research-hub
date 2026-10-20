-- #2741 (pedido do GP, 19/10/2026): dois cursos OPCIONAIS de IA agêntica na trilha, como complementares,
-- fora dos 6 obrigatórios.
-- Fonte lida em 19/10/2026 em pmi.org (página do curso, não o post que a anunciou):
--   EL405 "PMI® Foundations: Agentic AI for Project Managers": 4 PDUs, 4 horas
--   EL406 "PMI® Essentials: Agentic AI Build Lab for Project Managers": 3 PDUs, 3 horas
--   ambos "Member Price USD $0 / Full Price USD $19"
-- is_free = false: gratuito só para membro PMI (o AI_PATTERNS, gratuito para todos, é true).
-- is_trail = false e credly_badge_name NULL: não entram na % da trilha nem no total de 6, porque
-- calc_trail_completion_pct, get_public_trail_ranking e os demais leitores filtram is_trail = true.
-- sort_order 10 e 11: depois dos complementares atuais (5, 6, 9); Foundations antes do Build Lab.
-- Rollback: DELETE FROM public.courses WHERE code IN ('AGENTIC_FOUNDATIONS', 'AGENTIC_BUILD_LAB');

INSERT INTO public.courses (
  code, name, category, is_free, url, sort_order, credly_badge_name, is_trail, tier, organization_id
) VALUES
  (
    'AGENTIC_FOUNDATIONS',
    'PMI Foundations: Agentic AI for Project Managers',
    'complementary',
    false,
    'https://www.pmi.org/shop/p-/elearning/pmi-foundations-agentic-ai-for-project-managers/el405',
    10,
    NULL,
    false,
    'complementary',
    '2b4f58ab-7c45-4170-8718-b77ee69ff906'
  ),
  (
    'AGENTIC_BUILD_LAB',
    'PMI Essentials: Agentic AI Build Lab for Project Managers',
    'complementary',
    false,
    'https://www.pmi.org/shop/p-/elearning/pmi-essentials-agentic-ai-build-lab-for-project-managers-/el406',
    11,
    NULL,
    false,
    'complementary',
    '2b4f58ab-7c45-4170-8718-b77ee69ff906'
  )
ON CONFLICT (code) DO NOTHING;

-- #819/#820 Camada 1 — speaker (palestrante externo de webinar/evento) é um kind
-- initiative-scoped cujo engagement não concedia NENHUMA escrita de board, então
-- promover um speaker a role='leader' na iniciativa era inerte (a UI já foi alinhada
-- em #829 para honrar write_board via canFor, mas um speaker sem papel org não tinha
-- write_board em scope nenhum).
--
-- Concede a capability de contribuidor de board (write_board) em scope='initiative'
-- APENAS — espelha o padrão *participant* de workgroup_member/committee_member, e
-- deliberadamente NÃO o padrão *leader* (que carrega manage_member/view_pii/
-- manage_board_admin/write e seria escalada de privilégio, anti-pattern do
-- procedimento V4 authority audit em docs/reference/V4_AUTHORITY_MODEL.md).
--
-- Efeito: um speaker pode editar o board de planejamento do webinar específico em que
-- palestra (board_items na sua iniciativa), nada além disso.
--
-- NB: checklists/assignments de card usam rls_can('write_board') (org/tribe-scope,
-- pré-existente) e não honram grant initiative-scoped — limitação pré-existente que
-- afeta todos os contribuidores initiative-scoped por igual; fora do escopo desta seed.
INSERT INTO public.engagement_kind_permissions (kind, role, action, scope, description, organization_id)
SELECT 'speaker', r.role, 'write_board', 'initiative',
       'Speaker can use the event/webinar planning board (initiative-scoped)',
       '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid
FROM (VALUES ('leader'),('lead_presenter'),('co_presenter'),('participant')) AS r(role)
ON CONFLICT (kind, role, action) DO NOTHING;

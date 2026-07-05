-- DRAFT (preparado 04/07/2026) — aplicar SÓ NO DIA 9, via apply_migration + arquivo local + repair (Q-C).
-- Nome sugerido: <timestamp>_c4_roll_forward_member_cycle_history.sql
-- Coorte medida 04/07: 31 continuantes − Débora = 30. RE-ATERRAR no dia 9 (BEFORE abaixo).

-- ============ BEFORE (capturar e colar no PR/handoff) ============
-- SELECT count(*) FROM member_cycle_history WHERE cycle_code='cycle_3' AND cycle_end IS NULL;  -- esperado 63
-- SELECT count(*) FROM member_cycle_history WHERE cycle_code='cycle_4';                        -- esperado 0
-- WITH c AS (<coorte abaixo>) SELECT count(*) FROM c;                                          -- esperado ~30

BEGIN;

-- 1) Fechar TODAS as rows C3 abertas (63 em 04/07) — o ciclo terminou 08/07.
UPDATE member_cycle_history
SET cycle_end = DATE '2026-07-08'
WHERE cycle_code = 'cycle_3' AND cycle_end IS NULL;

-- 2) Roll-forward dos continuantes → row cycle_4 (snapshot atual).
--    Critério (plano §4.3): member ativo + histórico C3 + engagement volunteer ativo com
--    end_date NULL ou ≥ 2026-12-01. EXCLUI Débora (exit no dia 9, runbook passo 4).
WITH coorte AS (
  SELECT DISTINCT m.id, m.name, m.operational_role, m.designations, m.tribe_id, m.chapter
  FROM members m
  JOIN member_cycle_history h ON h.member_id = m.id AND h.cycle_code = 'cycle_3'
  JOIN persons p ON p.legacy_member_id = m.id
  JOIN engagements e ON e.person_id = p.id
    AND e.kind = 'volunteer' AND e.status = 'active' AND e.revoked_at IS NULL
    AND (e.end_date IS NULL OR e.end_date >= DATE '2026-12-01')
  WHERE m.is_active = true
    AND m.id <> 'a8c9af17-d9f8-4a0e-85bc-a0b13b0f8ad7'  -- Débora Moura (exit end_of_cycle)
)
INSERT INTO member_cycle_history
  (member_id, member_name_snapshot, cycle_code, cycle_label, cycle_start, cycle_end,
   operational_role, designations, tribe_id, tribe_name, chapter, is_active, notes)
SELECT c.id, c.name, 'cycle_4', 'Ciclo 4 (2026/2)', DATE '2026-07-09', NULL,
       c.operational_role, c.designations, c.tribe_id, t.name, c.chapter, true,
       'roll-forward C3→C4 (runbook §4.3, migration governada)'
FROM coorte c
LEFT JOIN tribes t ON t.id = c.tribe_id
WHERE NOT EXISTS (
  SELECT 1 FROM member_cycle_history h2
  WHERE h2.member_id = c.id AND h2.cycle_code = 'cycle_4'
);

-- 3) members.cycles: NADA A FAZER — aterrado 04/07: a coluna usa o formato de cohort tag
--    ('cycle4-2026', não 'cycle_4') e os 30 da coorte JÁ o têm (30/30). O passo "append
--    cycle_4 em members.cycles" do plano §4.3 está SUPERSEDED por este achado — appendear
--    'cycle_4' criaria um segundo formato na mesma coluna.

COMMIT;

-- ============ AFTER (capturar) ============
-- SELECT count(*) FROM member_cycle_history WHERE cycle_code='cycle_3' AND cycle_end IS NULL;  -- esperado 0
-- SELECT count(*) FROM member_cycle_history WHERE cycle_code='cycle_4';                        -- esperado ~30
-- ATENÇÃO: entrantes C4 (40) NÃO entram por esta migration — o fluxo deles registra na assinatura/onboarding.
--          Conferir se algum entrante já tem row cycle_4 antes de validar o AFTER com ~30.

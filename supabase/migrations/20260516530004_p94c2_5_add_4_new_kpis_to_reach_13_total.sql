-- p94 Phase C.2.5: add 4 new KPIs to reach 13 total of TAP §16
-- Trigger: TAP §16 lists 13 critérios sucesso, only 9 in annual_kpi_targets
-- Unique constraint is (cycle, kpi_key) — not (cycle, year, kpi_key)

INSERT INTO annual_kpi_targets (cycle, year, kpi_key, kpi_label_pt, kpi_label_en, kpi_label_es, category, target_value, current_value, target_unit, baseline_value, display_order, notes)
VALUES
(3, 2026, 'lim_lima_accepted',
  'KPI: LATAM LIM Lima 2026 (Sessão Aceita)',
  'KPI: LATAM LIM Lima 2026 (Session Accepted)',
  'KPI: LATAM LIM Lima 2026 (Sesión Aceptada)',
  'submissions', 1, 1, 'count', 0, 10,
  'TAP §16 Critério 10. Sessão aceita Aug/2026. Manual update.'),

(3, 2026, 'detroit_submission',
  'KPI: PMI Global Summit Detroit 2026 (Submissão)',
  'KPI: PMI Global Summit Detroit 2026 (Submission)',
  'KPI: PMI Global Summit Detroit 2026 (Sumisión)',
  'submissions', 1, 0, 'count', 0, 11,
  'TAP §16 Critério 11. Em planejamento Out/2026. Manual update on submit.'),

(3, 2026, 'ip_policy_ratified',
  'KPI: Política IP aprovada Comitê de Curadoria',
  'KPI: IP Policy Ratified by Curation Committee',
  'KPI: Política PI Ratificada por Comité de Curaduría',
  'governance', 1, 0, 'count', 0, 12,
  'TAP §16 Critério 12. Auto: governance_documents.current_ratified_at IS NOT NULL. Doc id cfb15185-2800-4441-9ff1-f36096e83aa8.'),

(3, 2026, 'cooperation_agreements_signed',
  'KPI: Acordos de Cooperação Bilateral assinados',
  'KPI: Bilateral Cooperation Agreements Signed',
  'KPI: Acuerdos de Cooperación Bilateral Firmados',
  'governance', 4, 4, 'count', 0, 13,
  'TAP §16 Critério 13. PMI-GO <-> CE/DF/MG/RS. Manual=4 (no structured table).')

ON CONFLICT (cycle, kpi_key) DO NOTHING;

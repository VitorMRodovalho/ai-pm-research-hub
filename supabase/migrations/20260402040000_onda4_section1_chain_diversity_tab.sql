-- Sprint 12 — Onda 4: Strategic Positioning (CR-029, CR-040)
-- Applied live via execute_sql. This migration records the changes for git history.

-- ═══ CR-029: R3 §1 — Research-to-Impact Chain ═══
-- Appended "Cadeia Pesquisa → Impacto" section with 4 stages:
-- Pesquisa → Produção → Publicação → Impacto
-- R3 §1 now covers: Missão, Visão, Framework Teórico (Intelligence Stack + EAA),
-- Objectivos Estratégicos, and the full research chain.

-- ═══ CR-040: Diversity Dashboard mounted on admin selection ═══
-- DiversityDashboard.tsx component already existed (unmounted)
-- Now mounted as 4th tab "Diversidade" in /admin/selection
-- Uses get_diversity_dashboard RPC (by_gender, by_chapter, by_sector, by_seniority, by_region)
-- LGPD Art. 11 compliance note displayed

NOTIFY pgrst, 'reload schema';

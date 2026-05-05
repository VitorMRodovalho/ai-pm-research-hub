-- p90.c Phase 2 — 5 material fixes v6 across 5 docs Round 6
-- Decisions Vitor 2026-05-05: NOT wait Ângelina; apply ready-to-validate texts
-- Spec doc: docs/specs/p90-comms/round6_material_fixes_proposed_text_with_trailback.md
-- M1 Aceite tácito (Termo §15.4 + Adendo Retificativo §3º) — CC art. 111 + 423
-- M2 LGPD §2.5.5 3 regimes BR/UE-EEE/UK (Política IP) — future-proof
-- M3 Cláusula plataforma → Anexo Técnico cross-ref (Adendo PI Cooperação Art 8 simplification)
-- M4 Disclaimer marca PMI® (Política IP nova Cláusula 16)
-- M5 PMOGA + entidades externas (Acordo Cooperação Bilateral nova Cláusula 12)

-- Body applied via apply_migration MCP. See spec doc for full content + trailback.
-- Versions resulting:
--   Política IP: v6 v2.6-p90c-material-fixes (M2 + M4)
--   Termo de Adesão: v6 R3-C3-IP v2.6-p90c-material-fixes (M1)
--   Adendo Retificativo: v6 v2.6-p90c-material-fixes (M1)
--   Adendo PI Cooperação: v5 v2.5-p90c-material-fixes (M3)
--   Acordo Cooperação Bilateral: v5 v1.4-p90c-material-fixes (M5)

-- Pendência verificação Ângelina (4 itens):
-- 1. Status adequacy decision Brasil ↔ UE/EEE via ANPD + EU Commission
-- 2. UK Addendum / IDTA versão atual via ICO
-- 3. Chapter Operating Guidelines PMI Global — uso de marca por iniciativas inter-capítulos
-- 4. PMOGA — instrumento institucional para parcerias com iniciativas de capítulos PMI

SELECT 'p90.c Phase 2 material fixes - applied via mcp apply_migration; reference body via supabase query' AS info;

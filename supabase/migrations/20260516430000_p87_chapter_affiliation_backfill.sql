-- ============================================================================
-- p87 #118 backfill — chapter_affiliation → chapter normalization
-- ============================================================================
-- Worker pmi-vep-sync ingere chapter_affiliation raw do PMI VEP form
-- (campo answer text livre). UI usa selection_applications.chapter
-- (canônico, hifenizado). Mapping nunca foi populado para casos onde
-- chapter_affiliation tem strings tipo "PMIRS", "PMI _DF", "Sim, capítulo CE."
--
-- Worker fix paralelo (mapper.ts normalizeChapterAffiliation): future
-- ingestions são normalized at ingest. Este migration backfilla candidatos
-- atuais.
--
-- Idempotente: WHERE chapter IS NULL — segunda execução não toca registros
-- já normalizados.
--
-- Resultado backfill p87 (2026-05-01):
--   Mayanna Duarte    → PMI-CE  (de "Sim, capítulo CE.")
--   Vanessa Andrade   → PMI-DF  (de "PMI _DF")
--   Ricardo Santos    → PMI-MG  (de "Eu sou filiado ao capítulo MG e RJ m...")
--   João Uzejka       → PMI-RS  (de "PMIRS" — caso original PM report)
--
-- 23 outros candidatos com chapter NULL permanecem (chapter_affiliation
-- texto livre tipo "Não", "Não sou filiado", etc — legitimately não-afiliados).
-- ============================================================================

UPDATE public.selection_applications
SET chapter = CASE
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*RS\M' THEN 'PMI-RS'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*GO\M' THEN 'PMI-GO'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*CE\M' THEN 'PMI-CE'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*DF\M' THEN 'PMI-DF'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*MG\M' THEN 'PMI-MG'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*PE\M' THEN 'PMI-PE'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*SP\M' THEN 'PMI-SP'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*RJ\M' THEN 'PMI-RJ'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*PR\M' THEN 'PMI-PR'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*SC\M' THEN 'PMI-SC'
  WHEN chapter_affiliation ~* 'PMI\s*[-_ ]?\s*BA\M' THEN 'PMI-BA'
  WHEN chapter_affiliation ~* 'cap[ií]tulo\s+(do\s+)?CE\M' THEN 'PMI-CE'
  WHEN chapter_affiliation ~* 'cap[ií]tulo\s+(do\s+)?MG\M' THEN 'PMI-MG'
  ELSE chapter
END,
updated_at = now()
WHERE chapter IS NULL AND chapter_affiliation IS NOT NULL;

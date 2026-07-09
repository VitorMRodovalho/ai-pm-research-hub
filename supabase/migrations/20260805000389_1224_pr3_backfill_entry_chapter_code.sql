-- #1224 PR3 — sweep cosmético: backfill de members.entry_chapter_code (campo de governança)
--
-- Contexto: o PR1 (mig 20260805000386) passou a DERIVAR entry_chapter_code do enriquecimento
-- PMI no approve_selection_application quando há exatamente 1 afiliação BR ativa. Membros
-- aprovados ANTES do PR1 (C3 + parte do C4 + role-accounts) têm member_chapter_affiliations
-- (SSOT, ADR-0104) e members.chapter corretos, mas entry_chapter_code ficou NULL — o campo de
-- governança nunca foi carimbado. Este backfill fecha essa lacuna aplicando a MESMA regra do PR1.
--
-- Regra (consistente com #1224 PR1): só deriva quando há EXATAMENTE UMA afiliação (não-ambíguo).
-- Membros com >1 afiliação (ambiguous) ficam NULL de propósito — capítulo de entrada é escolha
-- (set_my_entry_chapter, desempate). Membros com 0 afiliação (chapter='Outro'/Externo) ficam NULL
-- — fallback honesto, não é bug (auditado: 9/9 'Outro' sem SSOT resolvível).
--
-- Idempotente: WHERE entry_chapter_code IS NULL. members.chapter NÃO muda (já consistente com o
-- código do SSOT para todos os alvos — verificado 44/44, 0 drift). Trigger T1 (mig 195) recomputa
-- members.chapter a partir do COALESCE, que já é o valor atual → no-op.
--
-- Grounding vivo (2026-07-09, projeto ldrfrvwhxsmgaabwmaik):
--   BEFORE: 126 membros, 77 com entry_chapter_code NULL, 44 alvos (todos chapter-consistentes), 0 violações.
--   AFTER : 33 NULL (-44), re-aplicação toca 0 linhas, 0 violações, 0 drift chapter↔entry.

WITH single_aff AS (
  SELECT person_id, min(chapter_code) AS the_code
  FROM public.member_chapter_affiliations
  GROUP BY person_id
  HAVING count(*) = 1
)
UPDATE public.members m
SET entry_chapter_code = s.the_code
FROM single_aff s
WHERE m.person_id = s.person_id
  AND m.entry_chapter_code IS NULL;

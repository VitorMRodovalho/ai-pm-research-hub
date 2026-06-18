-- C4 (#740 / ADR-0104) — seed the PMI Paraíba (PB) chapter into chapter_registry.
--
-- Context: completes the participating Brazil chapter set. After Amazonas (mig
-- 20260805000211) the registry had 14; the PM confirmed PMI Paraíba (PB) as the 15th
-- participating chapter on 2026-06-18. This adds it so it becomes a valid entry-chapter
-- choice (set_my_entry_chapter) and a valid FK target for member_chapter_affiliations /
-- members.entry_chapter_code. Now 15 participating BR chapters.
--
-- Non-contracting (PMI-GO stays the ONLY contracting chapter — the volunteer term signatory
-- is always derived from chapter_registry.is_contracting_chapter). CNPJ omitted: only the
-- contracting chapter needs it. Idempotent (ON CONFLICT DO NOTHING).
--
-- No backfill: 0 members had members.chapter = 'PMI-PB' at apply time (queried 2026-06-18).
--
-- Rollback: DELETE FROM public.chapter_registry WHERE chapter_code = 'PB';
--   (safe only while no member_chapter_affiliations / members.entry_chapter_code reference 'PB'.)

INSERT INTO public.chapter_registry (chapter_code, legal_name, state, country, is_contracting_chapter, is_active, display_order)
VALUES ('PB', 'PMI Paraíba, Brazil Chapter', 'Paraíba', 'BR', false, true, 15)
ON CONFLICT (chapter_code) DO NOTHING;

-- C4 (#740 / ADR-0104) — seed the PMI Amazonas (AM) chapter into chapter_registry.
--
-- Context: chapter_registry held the 13 participating Brazil chapters (Wave 3a migration
-- 20260805000190). Amazonas (https://pmiam.org/) was missing from the participating set;
-- the PM confirmed the canonical list on 2026-06-18. This adds the 14th chapter so it
-- becomes a valid entry-chapter choice (set_my_entry_chapter) and a valid FK target for
-- member_chapter_affiliations / members.entry_chapter_code.
--
-- Non-contracting (PMI-GO stays the ONLY contracting chapter — the volunteer term signatory
-- is always derived from chapter_registry.is_contracting_chapter). CNPJ omitted: only the
-- contracting chapter needs it. Idempotent (ON CONFLICT DO NOTHING).
--
-- No backfill: 0 members had members.chapter = 'PMI-AM' at apply time (queried 2026-06-18).
--
-- Rollback: DELETE FROM public.chapter_registry WHERE chapter_code = 'AM';
--   (safe only while no member_chapter_affiliations / members.entry_chapter_code reference 'AM'.)

INSERT INTO public.chapter_registry (chapter_code, legal_name, state, country, is_contracting_chapter, is_active, display_order)
VALUES ('AM', 'PMI Amazonas, Brazil Chapter', 'Amazonas', 'BR', false, true, 14)
ON CONFLICT (chapter_code) DO NOTHING;

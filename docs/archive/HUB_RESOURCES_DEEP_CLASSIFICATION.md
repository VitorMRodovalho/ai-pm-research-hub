# Hub Resources Deep Classification — Execution Log
**Date: 2026-03-15 | Executed via Supabase MCP | For: Claude Code commit**

---

## Summary

323 hub_resources items audited, classified across 3 taxonomic levels, junk removed.

| Metric | Before | After |
|--------|--------|-------|
| Active items | 323 | 240 |
| Deactivated (junk) | 0 | 83 |
| asset_type "other" | 141 (44%) | 0 (0%) |
| Asset types in use | 4 | 7 |
| Items with origin tag | 0 | 240 (100%) |
| Items with tribe_id | 136 | 142 |
| Items with cycle_code | 0 | 64 |
| Items with author_id | 0 | 6 |
| Junk tag "meeting_minutes" | 280+ items | 0 |

---

## Layer 1: Junk Removal (83 items deactivated)

| Pattern | Count | Rule |
|---------|-------|------|
| Numeric-only titles (spreadsheet row numbers) | 27 | `title ~ '^\d+$'` |
| WhatsApp Image exports | 25 | `title LIKE 'WhatsApp Image%'` |
| Numbered member names (attendance artifacts) | 8 | `title ~ '^\d+ [A-Z]'` with name match |
| Photo timestamps | 4 | `title ~ '^\d{8}_\d{6}$'` |
| Analytics/export artifacts | 3 | `title LIKE 'chat_%'`, `master_%`, `resource_%` |
| Unnamed/untitled files | 3 | `title LIKE 'unnamed%'` or `title = 'Untitled'` |
| LinkedIn profile URLs as titles | 7 | `title LIKE 'linkedin.com%'` from miro_import |
| Misc junk (single chars, bare URLs, screenshots) | 6 | Various patterns |

All deactivated items: `is_active = false, curation_status = 'rejected'`

---

## Layer 2: Tag Cleanup

Removed 3 junk tags from ALL active items:
- `meeting_minutes` — was on 280+ items as bulk-import artifact, removed globally
- `archived` — archival tracked by `is_active` column, not tags
- `miro_library` — source tracked by `source` column, not tags

---

## Layer 3: Asset Type Reclassification

### Migration applied: `expand_hub_resources_asset_types`
Constraint expanded from `[course, reference, webinar, other]` to:
`[course, reference, webinar, other, article, presentation, governance, certificate, template]`

### Reclassification rules applied:

| From → To | Count | Rule |
|-----------|-------|------|
| other/reference → certificate | 11 | `title ILIKE '%certificado%'` |
| other/reference → governance | 17 | cooperation agreements, changelog, metas, TAP, selection, PMI submission, opportunity exports |
| reference → presentation | 6 | title with 'apresentaç' + presentation tag |
| reference → article | 5 | title with 'article'/'artigo' + doc compartilhado links |
| other → reference | ~60 | cronograma, planejamento, ata, risk, agile, survey, tools |
| other → course | 2 | Microsoft Learn, PMI CPMAI |
| other → webinar | 2 | Sympla links |

---

## Layer 4: 3-Level Taxonomy (Origin Tags)

Every active item now has exactly one origin tag:

| Tag | Count | Description |
|-----|-------|-------------|
| `origin:external` | 158 (66%) | Academic papers, industry reports, external references |
| `origin:nucleo` | 53 (22%) | Created by nucleus members (certificates, governance, articles, prototypes) |
| `origin:pmi-global` | 29 (12%) | PMI official content (PMBOK, CPMAI, GenAI reports, submission guidelines) |

### Assignment rules:
- `origin:nucleo`: title contains núcleo/nucleo/tribo/ciclo/certificado/acordo/kickoff/EVA/modelagem/levantamento
- `origin:pmi-global`: title contains PMI/PMBOK/CPMAI/PBA/projectmanagement.com (excluding nucleo matches)
- `origin:external`: everything else

---

## Layer 5: Dimension Enrichment

### Author linkage (certificates)
6 certificates linked to member UUIDs via name matching in title:
- Vitor Rodovalho, Leticia Clemente, Marcos Moura, Débora Moura, Roberto Macêdo, João Coelho, Lídia Vale

### Cycle assignment
64 items assigned `cycle_code` from existing tags:
- ciclo-1: items tagged tribo-06 C1 references
- ciclo-2: items tagged ciclo-2 from Miro/Drive imports
- ciclo-3: kickoff and recent items

### Content-specific tags added
- `ai-agent`, `prototype` — for agent flowcharts and tools
- `comms` — for communication/marketing content
- `publication-guide` — for PMI submission guidelines
- `ai-tool` — for tool references (Firebase, Kaggle, etc.)
- `survey-data` — for research response spreadsheets
- `risk` — for risk management content
- `agile` — for agile methodology references

---

## Final Distribution

### By asset_type:
| Type | Count | With tribe | With author | With cycle |
|------|-------|-----------|-------------|-----------|
| reference | 197 | 133 | 0 | 60 |
| governance | 17 | 1 | 0 | 1 |
| certificate | 11 | 3 | 6 | 0 |
| presentation | 6 | 1 | 0 | 0 |
| article | 5 | 4 | 0 | 3 |
| webinar | 2 | 0 | 0 | 0 |
| course | 2 | 0 | 0 | 0 |

### By tribe (active items with tribe_id):
T1=16 | T2=8 | T3=5 | T4=10 | T5=19 | T6=52 | T7=23 | T8=1 | Cross-tribe=98

### 98 cross-tribe items (tribe_id NULL) breakdown:
- Governance docs (cooperation agreements, selection, changelog, TAP)
- Individual certificates (person-level, not tribe-level)
- PMI Global references (PMBOK, CPMAI, GenAI reports)
- Industry reports (Accenture, Bain, Deloitte, McKinsey, Microsoft)
- General AI+PM references (not specific to any tribe's research)
- Webinar recordings and event pages
- Presentations (institutional, not tribe-specific)

These are legitimately cross-tribe institutional resources.

---

## Governance Entries for Claude Code

```
GC-020: Hub resources deep classification — 83 junk items deactivated (WhatsApp images, spreadsheet artifacts, broken URLs). Patterns: numeric-only titles, photo timestamps, analytics exports, unnamed files.

GC-021: Hub resources tag cleanup — Removed 3 bulk-import artifact tags (meeting_minutes, archived, miro_library) from all active items. Tags now carry semantic meaning only.

GC-022: Hub resources asset type expansion — Migration expand_hub_resources_asset_types added 5 new types (article, presentation, governance, certificate, template). 141 "other" items reclassified to 0.

GC-023: Hub resources 3-level taxonomy — All 240 active items tagged with origin (origin:nucleo 53, origin:pmi-global 29, origin:external 158). Content-specific tags added (ai-agent, prototype, comms, publication-guide, ai-tool, survey-data, risk, agile).

GC-024: Hub resources author/cycle enrichment — 6 certificates linked to member author_id. 64 items assigned cycle_code. Tribe assignment expanded from 136 to 142 items.
```

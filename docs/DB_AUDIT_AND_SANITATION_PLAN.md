# Database Audit & Sanitation Plan — AI & PM Research Hub
**Audit date: 2026-03-14 | Auditor: Claude (via Supabase MCP) | For: Claude Code execution**

---

## Audit Summary

| Metric | Value |
|--------|-------|
| Total tables | 93 |
| Empty tables (0 rows) | 37 (40%) |
| Tables with data | 56 |
| Total members | 68 (58 active, 10 inactive) |
| Total board_items | 363 |
| Total events | 69 |
| Duplicate board_items | 7 pairs (14 items) |
| Events with tribe_id NULL | 69/69 (100%) |
| Events typed "other" | 47/69 (68%) |
| Placeholder emails | 4 |
| Active members with no tribe | 15 (legitimate: sponsors, GP, liaisons) |

---

## PRIORITY 1: Data Sanitation (Safe SQL — Execute via Claude Code)

### 1A. Deduplicate Hub de Comunicação board_items

7 duplicates from merging two Trello boards. Keep `comunicacao_ciclo3` versions, archive `midias_sociais` duplicates.

```sql
-- Archive duplicate midias_sociais items where comunicacao_ciclo3 version exists
UPDATE board_items SET status = 'archived'
WHERE board_id = 'a6b78238-11aa-476a-b7e2-a674d224fd79'
AND source_board = 'midias_sociais'
AND title IN (
  'Assistente GPT', 'Briefing com GP', 'Ferramentas de apoio',
  'Insights', 'Referências de posts', 'Referências de vídeos'
);

-- Also archive the within-board duplicate Pílulas
-- Keep the one with POST number prefix, archive the plain one
UPDATE board_items SET status = 'archived'
WHERE id = '6c4a956a-87e2-47b3-8f0c-e842c2903387';
-- (this is the duplicate Serie: Pílulas without POST prefix)
```

### 1B. Reclassify events typed "other"

47 events are typed "other" but have clear patterns in their titles.

```sql
-- Interviews → type = 'interview'
UPDATE events SET type = 'interview'
WHERE type = 'other' AND title ILIKE '%entrevista%';

-- Kick-offs → type = 'kickoff'  
UPDATE events SET type = 'kickoff'
WHERE type = 'other' AND title ILIKE '%kick%off%' OR title ILIKE '%abertura%';

-- Strategic alignment → type = 'leadership_meeting'
UPDATE events SET type = 'leadership_meeting'
WHERE type = 'other' AND (title ILIKE '%alinhamento%' OR title ILIKE '%liderança%' OR title ILIKE '%estratégic%');

-- Discussion/Conversa → type = 'general_meeting'
UPDATE events SET type = 'general_meeting'
WHERE type = 'other' AND (title ILIKE '%discussão%' OR title ILIKE '%conversar%' OR title ILIKE '%reunião%');

-- PMI events → type = 'external_event'
UPDATE events SET type = 'external_event'
WHERE type = 'other' AND (title ILIKE '%PMI%Congress%' OR title ILIKE '%PMI%National%');
```

### 1C. Fix placeholder emails

4 members have `@placeholder.local` emails. These are founders/guests who may never log in, but placeholder emails should be flagged.

```sql
-- Add a tag or note for placeholder emails (don't change the email, it may be used for dedup)
-- Just document: Carlos Magno, Rafael Camilo, Vitor Lopes, Vitoria Araujo
-- These are operational_role = 'guest' or 'none' — acceptable.
-- ACTION: No change needed, just awareness.
```

### 1D. Clean empty/orphan boards

```sql
-- "Mídias sociais" board is empty (all items merged into Hub de Comunicação)
-- "Articles" board is empty (content is in Publicações & Submissões)
-- "Notion Backlog - Tribo 8" is empty (items went to T8 Entregas)
-- RECOMMENDATION: Archive these 3 boards (add is_active = false or delete)

-- Check if project_boards has is_active column:
-- If yes: UPDATE project_boards SET is_active = false WHERE id IN (...);
-- If no: Consider adding one, or just leave as documentation.
```

---

## PRIORITY 2: Data Enrichment (from Miro/Drive/WhatsApp exploration)

### 2A. Add Canva design links to Hub de Comunicação board_items

From WhatsApp analysis: 25+ unique Canva designs identified. Link them to the appropriate board_items as attachments.

```sql
-- Example: Link Canva carousels to their board_items
UPDATE board_items 
SET attachments = attachments || '[{"type":"canva","url":"https://www.canva.com/design/DAHC5JjnYLw","label":"Canva: Pesquisadores Bloco I"}]'::jsonb
WHERE board_id = 'a6b78238-11aa-476a-b7e2-a674d224fd79'
AND title ILIKE '%pesquisadores%ciclo%3%bloco%I%'
AND source_board = 'comunicacao_ciclo3';

-- Full list of Canva link → board_item mappings:
-- DAG1r2LEuTk → Pesquisadores Ciclo 3 (template)
-- DAHC5JjnYLw → Bloco I (published)
-- DAHDFjGEyNQ → Bloco II (published)
-- DAHDiw2P-AE → Bloco III (in design)
-- DAHDlsRgVMI → Bloco IV (in design)
-- DAHCXh1cQTM → Apresentação de Lideranças
-- DAGugs84hhc → Capa Sympla Webinar
-- DAG5XaDDg-E → Carrosel Webinar
-- DAG7km2cVbU → Celebração Ciclo 2
-- DAG_oc8v-rY → Tribo 3 Priorização
```

### 2B. Populate tribes.miro_url from Miro exploration

```sql
-- All tribe miro_urls are currently NULL
-- The Miro board uXjVJ5HAbog= contains Ciclo 2 data
-- Set it as a reference URL at project level (not individual tribes since it's cross-tribe)
-- Could go in global_links or site_config:
INSERT INTO site_config (key, value) VALUES 
('miro_ciclo2_board', 'https://miro.com/app/board/uXjVJ5HAbog=/')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

### 2C. Enrich hub_resources tribe assignments

187/323 hub_resources have no tribe_id. Claude Code should:
1. Query hub_resources WHERE tribe_id IS NULL
2. Attempt to match by title keywords to tribes
3. Generate UPDATE statements for GP review

---

## PRIORITY 3: Schema Cleanup (DDL — via Claude Code migration)

### 3A. Empty table triage

**Keep (active features, just no data yet):**
- announcements, campaign_recipients, campaign_sends (W131 ready)
- certificates, onboarding_progress (W124 ready)
- visitor_leads (W130 ready)
- selection_interviews, selection_diversity_snapshots (W124 ready)
- curation_review_log (W90 ready)
- board_sla_config, board_taxonomy_alerts (BoardEngine features)
- data_anomaly_log, data_quality_audit_snapshots (W98 ready)
- notification_preferences (planned)
- meeting_artifacts (planned)

**Consider dropping (speculative, never used, 0 rows):**
- `ingestion_alert_events` (0 rows)
- `ingestion_alert_remediation_rules` (0 rows)
- `ingestion_alert_remediation_runs` (0 rows)
- `ingestion_alerts` (0 rows)
- `ingestion_apply_locks` (0 rows)
- `ingestion_batch_files` (0 rows)
- `ingestion_batches` (0 rows)
- `ingestion_provenance_signatures` (0 rows)
- `ingestion_rollback_plans` (0 rows)
- `ingestion_run_ledger` (0 rows)
- `rollback_audit_events` (0 rows)
- `readiness_slo_alerts` (0 rows)
- `release_readiness_history` (0 rows)
- `governance_bundle_snapshots` (0 rows)
- `legacy_member_links` (0 rows)
- `legacy_tribe_board_links` (0 rows)
- `notion_import_staging` (0 rows)
- `publication_submission_events` (0 rows)
- `presentations` (0 rows)
- `member_chapter_affiliations` (0 rows)
- `comms_token_alerts` (0 rows)
- `portfolio_data_sanity_runs` (0 rows)

**Total: 22 tables with 0 rows that appear speculative/unused.**

**GP Decision needed:** Drop these 22 tables? Or archive to a `z_archive` schema?
Recommendation: `ALTER TABLE x SET SCHEMA z_archive;` — reversible, cleans up public schema.

### 3B. Tables with minimal/reference data to review

| Table | Rows | Notes |
|-------|------|-------|
| admin_links | 1 | Single entry — still needed? |
| home_schedule | 1 | Single entry — static config? |
| board_lifecycle_events | 1 | Feature exists but barely used |
| change_requests | 1 | Single change request logged |
| ia_pilots | 1 | Hub itself as pilot #1 |
| knowledge_assets | 1 | Knowledge Hub W5 prototype |
| knowledge_chunks | 1 | Knowledge Hub W5 prototype |
| blog_posts | 1 | First blog post draft |
| release_readiness_policies | 1 | Policy defined but no runs |
| tribe_continuity_overrides | 2 | Tribe lineage mapping |
| tribe_lineage | 2 | Tribe lineage mapping |

---

## PRIORITY 4: Comms Team Onboarding

### 4A. Create comms onboarding guide page

Claude Code should create a help_journey entry for the comms team and/or a static page at `/workspace/comms-guide` that explains:
- Where to find the Hub de Comunicação board
- How to create board_items for new content pieces
- How to use campaign_templates
- How blog posts work
- Where Canva designs are linked

### 4B. Add Mayanna and Letícia assignee_ids to their active board_items

```sql
-- Get Mayanna's and Letícia's UUIDs
-- Mayanna: bb499ca6-254d-43bc-b38a-81ee986dbe3d
-- Letícia: (query needed)
-- Andressa: (query needed)

-- Assign Hub de Comunicação active items to Mayanna (primary content creator)
-- Items in DESIGN, REDAÇÃO, REVISÃO → Mayanna or Andressa
-- Items in PUBLICAÇÃO → Letícia
```

---

## PRIORITY 5: Dimension Reference Integrity

### 5A. Tribes dimension check (DONE in this session)
- ✅ All 8 tribes have aligned leader_member_id ↔ operational_role
- ✅ T3 fixed: Marcel Fleming
- ✅ T8 fixed: Ana Carla Cavalcante

### 5B. Members → Tribes referential integrity
- ✅ 43 active researchers/leaders have tribe assignments
- ✅ 15 active non-tribe members are legitimate (sponsors, GP, liaisons, guests, founders)
- ✅ 10 inactive members are Ciclo 2 alumni (tribe_id properly NULL)

### 5C. Events → Tribes (NEEDS WORK)
- ❌ 69/69 events have tribe_id = NULL
- Some events are tribe-specific meetings but not linked
- Claude Code should: parse event titles for tribe references and suggest updates

### 5D. Board_items → Members (assignees)
- ❌ 333/363 board_items have no assignee (91%)
- T8 is the only board with full assignee coverage (9/9)
- For imported items: bulk-assign tribe_leader as default assignee

### 5E. Volunteer applications → Members mapping
- 143 volunteer applications, 92 matched to members by email
- 51 unmatched = applicants who weren't accepted or used different emails
- This is expected, no action needed

---

## Execution Order for Claude Code

```
Phase 1 — Safe data fixes (no schema changes):
  1. Deduplicate Hub de Comunicação (7 items → archived)
  2. Reclassify events (47 "other" → proper types)
  3. Add Canva URLs as attachments to board_items
  4. Assign Mayanna/Letícia/Andressa to Hub de Comunicação items

Phase 2 — Enrichment:
  5. Create comms team onboarding help_journey
  6. Bulk-assign tribe_leaders as default assignee for imported items
  7. Hub_resources tribe assignment suggestions

Phase 3 — Schema cleanup (migration):
  8. Archive 3 empty boards
  9. Create z_archive schema + move 22 empty speculative tables
  10. Drop or archive legacy_tribes (6 rows, Ciclo 2 data — already in Miro extraction doc)

Phase 4 — Documentation:
  11. Update GOVERNANCE_CHANGELOG.md with all changes
  12. Commit extraction docs to repo
```

---

## Data Sources Connected (this session)

| Source | Access | Content found |
|--------|--------|---------------|
| Supabase | ✅ Direct SQL | Full DB audit |
| Notion (Vitor workspace) | ✅ | T8 Neuro-Advantage Framework + research page |
| Notion (Ana Carla workspace) | ❌ 404 | Needs guest invite or reconnection |
| Miro board (Ciclo 2) | ✅ | 32 frames, 6 tribes, 300+ items |
| Google Drive (T8) | ✅ | 3 folders, 1 empty doc, 2 proposals |
| Google Drive (Ciclo 2 articles) | ✅ | 3 articles (ClickUp Brain, ML Pred, EAA Framework) |
| Canva | ✅ | 13+ designs found |
| WhatsApp (Comms team) | ✅ | 4,745 messages analyzed |
| WhatsApp (Webinar prep) | ✅ | 927 messages analyzed |
| Trello (2 boards) | ✅ | Already imported (54 items in Hub de Comunicação) |

---

## Files Produced This Session

1. `MIRO_DRIVE_EXTRACTION_CICLO2.md` — Full extraction of Miro + Drive + Notion content
2. `COMMS_TEAM_FRICTION_ANALYSIS.md` — WhatsApp friction analysis + migration plan
3. `DB_AUDIT_AND_SANITATION_PLAN.md` — This document (for Claude Code execution)

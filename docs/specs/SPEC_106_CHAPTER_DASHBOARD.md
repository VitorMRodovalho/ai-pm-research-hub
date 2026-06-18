# SPEC #106 — Chapter-facing dashboard (Diretores de Voluntariado)

- **Status:** v2 — council reviewed GO-with-changes ×3 (product-leader + ux-leader + data-architect, 2026-06-18); changes incorporated below. legal-counsel sign-off on Bloco 2 (LGPD) é pré-condição do PR1.
- **Issue:** #106 (OPEN) — Item 7, handoff 2026-04-25 (Lorena Souza, PMI-GO voluntariado_director)
- **Date:** 2026-06-18
- **Author:** Vitor Maia Rodovalho (Assisted-By: Claude)
- **PM decision:** completar os 5 blocos do #106 (não fatia mínima) — 2026-06-18
- **Refs:** ADR-0007 (`can()`/`can_by_member` autoridade) · ADR-0030 (precedente de gate own-chapter) · ADR-0009 (config-driven) · GC-162 (RLS/LGPD) · `get_chapter_dashboard` (RPC existente)

## Context — o que JÁ existe (grounded live 2026-06-18, `ldrfrvwhxsmgaabwmaik`)

A premissa original da issue (2026-04-25) está **vencida**, e o dashboard está ~60-70% shipado:

1. **Dashboard existe**: RPC `get_chapter_dashboard(p_chapter)` (6976 chars) → snapshot (active/observers/alumni + `by_role`), output (board cards, publicações), attendance (engagement/reliability/avg), hours/PDU, certifications, partnerships, gamification (avg_xp + top 3), lista de membros, `available_chapters`. Rota `/admin/chapter.astro` (+en/es) + componente `ChapterDashboard.tsx`.
2. **Acesso own-chapter já modelado**: o gate V4 da RPC = `can_by_member(caller, 'view_internal_analytics')` → cross-chapter; senão `p_chapter IS NULL OR = caller_chapter` → só o próprio. O componente trata `isGP=false → próprio capítulo`.
3. **A persona já alcança**: a designation `chapter_board` concede `admin.access` + `admin.analytics.chapter` (`permissions.ts:237-241`); o middleware NÃO gateia `/admin`; o item de menu "Meu Capítulo" (`/admin/chapter`) aparece sob `admin.analytics.chapter`. **Lorena Souza** (`11b8c3a7`, designations `[chapter_board, voluntariado_director]`) **já loga** (a issue dizia "auth_id null" — vencido) e já resolve a permissão → vê e abre o dashboard hoje.

**Conclusão:** #106 não é "construir o dashboard" — é **(a)** corrigir um bug + **(b)** adicionar os 4 blocos chapter-facing que faltam. Nenhuma rota nova, nenhum gate novo de acesso.

## Gap vs os 5 blocos do #106

| Bloco | Estado | Trabalho |
|---|---|---|
| 1. Snapshot (ativos/status/papel) | ✅ existe; falta "por tribo" | estender RPC com `by_tribe` |
| 2. Movimentações 30d (entradas/saídas + motivo) | ❌ ausente | novo bloco RPC + FE (LIVE: PMI-GO 8 in / 2 out em 30d) |
| 3. Pipeline de seleção (vagas/deadline/link) | ❌ ausente | novo bloco RPC + FE (coorte ociosa agora: 0 apps ativos → estado vazio gracioso) |
| 4. Script de divulgação trilíngue editável | ❌ ausente | `platform_settings` key + RPC GP-edit + FE |
| 5. Export CSV | ❌ ausente (só `@media print`) | FE-only (dados já carregados) |
| 🐛 Bug | RPC hardcoda `'cycle', 3` | derivar de `cycles WHERE is_current` |

## Decisão de design

### Bug — ciclo hardcoded (correctness, barato)
`get_chapter_dashboard` retorna `'cycle', 3` literal → todo relatório diz "ciclo 3". Corpo canônico atual = mig `20260805000072` (data-architect). Fonte canônica do ciclo: `cycles` (PK `cycle_code`, flag `is_current`). **Fix:** declarar `v_current_cycle record; SELECT cycle_code, cycle_label INTO v_current_cycle FROM cycles WHERE is_current = true LIMIT 1;` no DECLARE (evita 2 subselects) e expor `'cycle_code'` + `'cycle_label'` no header. **+ Invariante `GA_single_current_cycle`** (data-architect): `count(*) FROM cycles WHERE is_current` deve ser `=1` — o hardcode teria sido pego antes se existisse. Adicionar no PR1 (bump dos 3 testes que pinam o total de invariantes).

### Bloco 1 — snapshot por tribo
Adicionar `by_tribe` ao objeto `people` (hoje só `by_role`). Agregar ativos do capítulo por `tribe_id`→`tribe_name`. **Bucket "Sem tribo"** obrigatório (ux R6): membros `tribe_id IS NULL` (guest/chapter_board sem tribo) entram em bucket explícito — **invariante de display:** `sum(by_tribe) == people.active`. Mantém `by_role`.

### Bloco 2 — movimentações 30d (o bloco que motivou a issue)
Novo objeto `movements` na RPC:
- **Entradas**: `members` do capítulo com `created_at >= now()-30d AND anonymized_at IS NULL` → `[{name, created_at, operational_role}]`.
- **Saídas com motivo**: `member_offboarding_records` JOIN `members m` onde `chapter_at_offboard = v_chapter AND offboarded_at >= now()-30d AND m.anonymized_at IS NULL` (data-architect: excluir anonimizados) → `[{name, offboarded_at, reason_category_code, return_interest}]`.
- **LGPD (legal-counsel GO-with-conditions):** expor SÓ `reason_category_code` (categoria) + nome + data + `return_interest`. **NÃO** projetar `reason_detail`/`exit_interview_full_text`/`lessons_learned`/`recommendation_for_future`/`attachment_urls`. A RPC é SECDEF `search_path=''` (bypassa RLS) → a política de colunas é enforced NO CORPO. `reason_category_code` NULL → FE mostra "Não categorizado" (`COALESCE`).
- **C2 RESOLVIDA — neutralização de categorias sensíveis (BLOQUEANTE p/ PR1):** o domínio `offboard_reason_categories` (9 códigos) inclui **`health`** ("Questão de saúde" → Art. 11 dado de saúde) e **`policy_violation`** (`is_volunteer_fault=true` → conduta disciplinar). A projeção chapter-facing **DEVE** mapear `CASE WHEN code IN ('health','policy_violation') THEN 'other' ELSE code END` (o GP vê o motivo real via `get_offboarding_dashboard`, surface restrita). Não aparecem nos dados reais ainda (usados: `end_of_cycle` 14 / `other` 12 / `personal_agenda` 1), mas o domínio permite → neutralizar por design.
- **Labels trilíngues já no DB (resolve ux R7):** `offboard_reason_categories.label_pt/label_en/label_es` — o FE NÃO hardcoda mapa; a RPC pode retornar o label do idioma OU o FE resolve via o catálogo. Recomendado: RPC retorna o `code` (já neutralizado) + o FE mapeia pelo catálogo carregado, ou a RPC já devolve `label_pt/en/es` do código neutralizado.
- **C1 (legal):** comentário de base legal na migration — `Art. 7 IX (legítimo interesse) + Art. 10 proporcionalidade; minimização: só categoria neutralizada, exclui texto livre + anonimizados; SECDEF own-chapter gate`.
- **C3/R4 (legal, não-bloqueante → backlog):** verificar aviso de coleta do `return_interest` (transparência Art. 6 VI/IX) + confirmar que o cron de anonimização 5y cobre `member_offboarding_records` (retenção Art. 15).
- Contadores: `joined_30d`, `left_30d`, `net`.
- **Limitação conhecida (documentar):** `chapter_at_offboard` pode ser NULL se o membro nunca teve capítulo → saída não aparece no filtro `= v_chapter` (silent, 0 esperado p/ PMI-GO).

### Bloco 3 — pipeline de seleção (RPC SEPARADA, lazy-load)
**Não inflar o monólito** (data-architect): RPC nova `get_chapter_selection_summary(p_chapter text)` SECDEF, mesmo gate V4 own-chapter, chamada em paralelo pelo FE. **Filtro por `selection_cycles.contracting_chapter = v_chapter`** (NÃO `selection_applications.chapter`, que é palpite arbitrário p/ multi-chapter — mig `20260805000189`). Retorna o ciclo `status IN ('open','evaluation','interview','decision')` mais recente do capítulo → `{cycle_code, title, close_date (deadline), interview_booking_url, open_apps: count(*) WHERE cycle_id=sc.id}`; NULL se nenhum. **Estado vazio gracioso** (ux R2): título "Processo Seletivo", ícone neutro, "Nenhum ciclo de seleção em andamento", data do último ciclo encerrado, link p/ página pública de seleção como ação secundária.

### Bloco 4 — script de divulgação trilíngue editável
Armazenar em `platform_settings` (key-value, value JSONB). **MVP global** (espírito ADR-0009; per-chapter = follow-up sob demanda): key `chapter_outreach_script`, value `{ "pt-BR": "...", "en-US": "...", "es-LATAM": "..." }`. Seed via INSERT na migration. **RPC de edição já existe: `admin_update_setting(p_key text, p_new_value jsonb, p_reason text)`** gate `manage_platform` (mig `20260427020000`) — NÃO criar `set_platform_setting`. Leitura no dashboard: `COALESCE((SELECT value FROM platform_settings WHERE key='chapter_outreach_script'), '{}'::jsonb)` (FE trata `{}`).
- **Split de superfícies (ux R4):** `/admin/chapter` = read-only, abas pt/en/es + botão "Copiar" por idioma (a persona chapter_board copia, NÃO edita). `/admin/settings` (GP) = editor 3 textareas + save (reusar two-click confirm das SLA windows). chapter_board NUNCA vê o editor.

### Bloco 5 — export CSV (PR1, FE-only)
Botão "Exportar CSV" que serializa `data.members` (name, operational_role, tribe, attendance_pct, total_xp, trail_count) → blob download. **Colisão com "Imprimir" (ux R5):** agrupar as 2 ações à direita do header; em 375px colapsar em menu "...". Evento de tracking `chapter_csv_exported` (ver Instrumentação).

## UX — ordem canônica dos blocos (ux R1, blocker)
A persona (chapter_board) abre p/ responder "quantos ativos / quem entrou-saiu". Ordem vertical no `/admin/chapter`:
1. Header (capítulo, ciclo derivado, grupo de ações print/CSV)
2. **Resumo executivo** (cards ativos/observadores/alumni + **net 30d entraram/saíram** em número grande)
3. **Movimentações 30d** (entradas + saídas com motivo — card-list, NÃO tabela; badge de categoria via mapa de labels por idioma, ux R3/R7; mobile 375px coluna)
4. **Script de divulgação** (read-only, copy-to-clipboard, abas idioma; `aria-live` no "Copiado!")
5. **Pipeline de seleção** (estado-vazio gracioso)
6. Detalhe (gráfico comparativo Hub, top contributors, tabela de membros) — ruído p/ a persona, vai p/ o fim

## Instrumentação (product-leader — pré-req do PR1, não pós-hoc)
- `chapter_dashboard_viewed` (`chapter_code`, `is_own_chapter`, `designation`) — métrica primária: sessões de chapter_board/voluntariado_director em `/admin/chapter` nas 4 semanas pós-launch (baseline 0).
- `chapter_csv_exported` — proxy de "substituiu a planilha manual".
- Sinal de falha: 0 eventos em 30d = nasceu sem uso (precedente buddy 0/0, entry_chapter 0/48) → plano de ativação (DM Lorena + 1 diretora no dia do launch).

## Schema / índices (data-architect — no PR correspondente)
- PR1: `CREATE INDEX IF NOT EXISTS idx_offboarding_chapter_at ON member_offboarding_records (chapter_at_offboard, offboarded_at DESC) WHERE chapter_at_offboard IS NOT NULL;`
- PR1: `CREATE INDEX IF NOT EXISTS idx_members_chapter_created_at ON members (chapter, created_at DESC) WHERE chapter IS NOT NULL;`
- `get_chapter_dashboard`: assinatura inalterada `(p_chapter text DEFAULT NULL)` → CREATE OR REPLACE (corpo verbatim do arquivo, Phase-C).

## Permissionamento (sem mudança de acesso)
- **Leitura** dos blocos novos: herdada do gate own-chapter da `get_chapter_dashboard` + a RPC nova de seleção replica o MESMO gate. chapter_board/chapter_liaison → próprio; GP → cross.
- **Escrita** (só Bloco 4): `admin_update_setting` gate `manage_platform` (GP). chapter_board NÃO edita.

## Slices (1 PR cada, GC-097 + contrato + council code-reviewer)
1. **PR1 (DB+FE, combo mínimo completo)** — bug do ciclo + invariante `GA_single_current_cycle` + Bloco 1 (`by_tribe`+sem-tribo) + Bloco 2 (movimentações 30d, só categoria, exclui anonimizado) + 2 índices + Bloco 5 (CSV) + instrumentação + reordenação UX dos blocos. **legal-counsel sign-off (LGPD Bloco 2) ANTES de abrir o PR.**
2. **PR2 (DB+FE)** — Bloco 4 (script trilíngue: seed `platform_settings` + read-only copy no `/admin/chapter` + editor GP no `/admin/settings` via `admin_update_setting`).
3. **PR3 (DB+FE)** — Bloco 3 (RPC separada `get_chapter_selection_summary`, filtro `contracting_chapter`, estado-vazio). Por último: coorte ociosa (0 apps).

## QA/validação por PR
- `npx astro build` verde; `npm test` 0 fail; contrato novo por PR (`106-chapter-*`).
- DDL via `apply_migration` + Write do arquivo local + `migration repair --status applied` + DELETE shadow por name + `NOTIFY pgrst`. Corpo da RPC = CREATE OR REPLACE verbatim (assinatura inalterada).
- Probe live PMI-GO: movimentações 8 in/2 out, snapshot 25 ativos.

## Non-goals
- NÃO criar rota nova `/chapters/[code]` (o `/admin/chapter` + acesso own-chapter já servem a persona).
- NÃO afrouxar acesso (gate own-chapter já existe).
- NÃO per-chapter script no MVP (global; reavaliar sob demanda).
- NÃO expor texto livre de exit-interview (LGPD) — só categoria; excluir anonimizados.
- NÃO inflar o monólito com o bloco de seleção (RPC separada lazy-load).

# ADR-0111 — Tier `institutional_auditor` + action `view_aggregate_analytics` (allowlist-by-construção)

**Status:** Accepted (2026-06-29, Onda 2 FU-3, #952)
**Relacionado:** ADR-0007 (V4 `can()` autoridade) · ADR-0009 (kinds = config) · ADR-0023 (ladder parity → **Amendment C**) · ADR-0106 (sem auth-gate SSR; fronteira = RLS + SECDEF + `canFor()`) · ADR-0110 (split read/write FU-1) · plano `~/.claude/plans/onda-2-auditoria-keen-kahn.md` (achado **F4**) · `docs/reference/V4_AUTHORITY_MODEL.md`.
**Migration:** `20260805000292_onda2_fu3_institutional_auditor.sql`.

## Contexto

O plano da Onda 2 (FU-3, achado **F4**) propunha um tier `institutional_auditor` (revisor externo — ex.: PMI LATAM/Global) seedando **`view_internal_analytics` + `view_chapter_dashboards` "agregados"**, criado **dormant antes da apresentação do LIM**.

Antes de aplicar, foi feita uma **auditoria ao vivo** do que essas duas actions realmente abrem (todas as RPCs SECDEF + RLS que as referenciam, classificadas quanto a PII individual e escrita). **A premissa "agregadas" é falsa:**

- `view_internal_analytics` é um grant amplo de "analista interno", não agregado. Das **62 RPCs reachable**, **37 retornam PII individual ou escrevem** — incluindo, com gate ÚNICO na action (sem branch `view_pii`/`manage_platform` que esconda o dado):
  - `admin_list_members` (diretório completo: nome, **email**, foto, auth_id, credly), `get_member_detail`, `get_org_chart` (nomes), `get_selection_dashboard` (candidatos: nome/email/phone/scores), `get_tribe_gamification` (XP por membro **com nome**), `list_initiative_engagements_by_kind`, etc.
  - **5 escritas** gateadas por `view_internal_analytics`: `mark_vep_reconciled` (UPDATE em `selection_applications`), `capture_vep_baseline`, `trigger_ai_calibration_run`, `submit_chapter_need`, `record_drive_discovery`.
- **RLS**: `members_read_by_members` é PERMISSIVE `USING (is_active AND rls_is_authoritative_member())`. `rls_is_authoritative_member()` = membro ativo com `operational_role NOT IN (NULL,'guest')`. Um auditor que fosse membro ativo com `operational_role='institutional_auditor'` leria **todo o diretório de PII por PostgREST direto**, independente do seed (org-fence é no-op — 1 org).

Logo, o seed ingênuo daria a um parceiro **externo** o diretório de PII + dados de seleção + 5 escritas — o oposto de "R(agg) sem PII individual" e da minimização LGPD que motiva a Onda 2.

Decisão do PM (`AskUserQuestion`, 2026-06-29): **"Capacidade agregada real agora"** — construir o tier com acesso agregado REAL e seguro, não um scaffold vazio nem o endurecimento amplo das RPCs existentes (esse último = escopo do FU-2 restante, maior blast radius, muda comportamento de papéis atuais).

## Decisão

**Action dedicada, genuinamente agregada, com allowlist por construção — nunca reusar `view_internal_analytics`.**

1. **Novo `engagement_kind` `institutional_auditor`** (role `auditor`), config-driven (ADR-0009). `legal_basis='legitimate_interest'`, `requires_agreement=false` (família institucional read-only sponsor/observer/chapter_board; satisfaz o invariante de catálogo p235/#323 — um kind com `requires_agreement=true` precisa nomear um `agreement_template`). `end_date` **obrigatório** via CHECK `engagements_institutional_auditor_end_date_check` (espelha `engagements_speaker_role_check`).
2. **Nova action `view_aggregate_analytics`** (scope `organization`), seedada **APENAS** a `institutional_auditor×auditor` — uma única action, read puro.
3. **8 RPCs live-verificadas como zero-PII / zero-escrita** passam a honrar a nova action (gate ganha `OR can_by_member(_, 'view_aggregate_analytics')`):
   `get_cycle_report`, `get_annual_kpis`, `get_selection_pipeline_metrics` (counts do funil), `get_diversity_dashboard` (agregados por gênero/região — counts, não indivíduos), `get_portfolio_items` (+ gate de confidencial #785), `get_in_dashboard` (pipeline MOU de capítulos = dado institucional), `get_comms_to_adoption_funnel` (alcance/funil), `exec_role_transitions` (matriz role→role, sem nomes).
   As **37 RPCs com PII/escrita NÃO são tocadas** — a action não as abre (allowlist, não denylist).
4. **Ladder** (`sync_operational_role_cache` + `check_schema_invariants` A3, paridade byte-a-byte **ADR-0023 Amendment C**): nova cláusula `WHEN bool_or(ae.kind='institutional_auditor') THEN 'institutional_auditor'` **após `external_signer`** (persona externa read-only, abaixo dos papéis operacionais).
5. **RLS carve-out**: `rls_is_authoritative_member()` passa a excluir `institutional_auditor` (`NOT IN ('guest','institutional_auditor')`) — o auditor é autoritativo para a action agregada (via SECDEF) mas **NÃO** ganha o diretório de PII baseline. Subtrativo só para o novo papel; behavior-neutral.
6. **Client (3 camadas, F9-aware)**: `permissions.ts` novo tier `institutional_auditor` em `OperationalTier`/`TIER_PERMISSIONS` (analytics agregado: `admin.analytics`, `admin.analytics.chapter`, `admin.portfolio`, `data.view_analytics`, `content.view_publications`, `workspace.access` — **sem** `admin.access`, diretório, finanças/parceiro, governança ou escrita; espelha o padrão `chapter_liaison` visibilidade-sem-shell) + `TIER_LABELS`/`TIER_COLORS` ("Auditor Institucional" 🔎) + `ADMIN_TIER_ACTIONS += view_aggregate_analytics` (canForAdminEntry). `admin/constants.ts`: `OPROLE_LABELS`/`OPROLE_COLORS` + `getAccessTier→'observer'` + `ROUTE_ALLOWED_OPERATIONAL_ROLES.admin_analytics += institutional_auditor`. i18n `role.institutional_auditor` nas 3.

### Dormância

Comportamento-neutro na população atual: **zero** membros `institutional_auditor`. Grants aditivos; cláusula da ladder só afeta futuros auditores; carve-out RLS subtrativo só para o novo papel; CHECK sem linhas do kind. Dormância garantida por **nenhum engagement atribuído** — **provisionar** um auditor (INSERT de engagement + `end_date`) é GP-only, sob acordo de cooperação formal = **pré-requisito governança/FU-4**, não este ADR.

## Alternativas rejeitadas

- **Reusar `view_internal_analytics` + endurecer as 37 RPCs com vazamento** (Opção 3): fecharia F2 também para sponsor/liaison/curator, mas é o maior blast radius e muda o comportamento de papéis ATUAIS — escopo do FU-2 restante, não do FU-3.
- **Scaffold dormante com seed vazio** (Opção 1): seguro, mas o PM pediu capacidade real.
- **PII individual para o auditor**: fora de escopo. Se algum dia necessário, exige action própria + base legal formal (Art. 7º,V ou LIA) + log `pii_access_log` + ateste — nunca alargar `view_aggregate_analytics`.

## Verificação (ao vivo, 2026-06-29)

- `funcs_with_view_aggregate_analytics` = **exatamente as 8** curadas; **0** das RPCs de PII conhecidas honram a action (prova de 2 lados).
- `auditor_seed` = `view_aggregate_analytics@organization` (única).
- `rls_is_authoritative_member` contém o carve-out; A3 violations = **0**; nenhum invariante `high` não-zero.
- Drift: `drifted_definite=0`, `orphan_true=0` (file == live para as 10 funções). `role-ladder-parity` verde (paridade A3↔trigger). `permissions.test` verde (12 tiers, auditor read-only).
- Bloco `DO` fail-closed in-tx (kind, seed único, CHECK, dormância=0, carve-out, ladder ×2, 8 gates, A3=0).

## Mecânica de entrega

- Aplicado ao remoto via MCP `apply_migration` usando transformações `replace()` verificadas (cada anchor validado para casar exatamente 1×) dos corpos live de `pg_get_functiondef`; o **arquivo** `…292` é o SSOT literal (corpos pós-apply, byte-fiéis — gates `role-ladder-parity` + `rpc-migration-coverage` Phase-C parseiam os `CREATE OR REPLACE` literais). `migration repair --status applied 20260805000292` + `NOTIFY pgrst`.
- Teste de contrato forward-defense `tests/contracts/institutional-auditor-aggregate-scope.test.mjs`.

## Invariantes respeitados

function-anchored (papel, nunca indivíduo) · read ≠ write (action read-only; 37 RPCs de PII/escrita intocadas) · member-lifecycle = GP-only (LGPD Art. 18) · minimização LGPD (parceiro externo = só agregado) · confidenciais #785 (`get_portfolio_items` mantém `rls_can_see_initiative`) · **NÃO** seed-expandir actions destrutivas · ADR-0023 paridade A3 · DDL via `apply_migration` + sync de migration local + repair (database.md).

---

## Amendment (2026-06-29) — superfície agregada 8 → 12 + supressão de célula pequena (k=5)

**Status:** Accepted · **Migration:** `20260805000294_onda2_adr0111_amend_aggregate_chapter_comms_rpcs.sql` · **#952.**

A capacidade agregada do auditor foi estendida de **8 → 12 RPCs**, adicionando dashboards de capítulo + métricas de comms agregadas (decisão do PM via `AskUserQuestion`, 2026-06-29). As 4 novas: `exec_chapter_dashboard`, `exec_chapter_comparison`, `get_chapter_selection_summary`, `comms_metrics_latest_by_channel`.

### Por que não foi um simples grant repetido

Antes de aplicar, rodou-se uma **revisão adversarial por-RPC** (8 sub-agentes: auditor de fidelidade + cético de refutação por RPC, todos consultando o DB ao vivo). Ela pegou o que a verificação de fidelidade (leitura campo-a-campo) **não** pega — um problema **comportamental** de LGPD:

- `exec_chapter_dashboard` e `exec_chapter_comparison` **quebram membros por capítulo**. Ao vivo, **3 capítulos têm 1 único membro ativo** (PMI-PR, PMI-SP, Outro) e `members.chapter` **não tem CHECK/enum** (texto livre). Para esses capítulos, o "agregado" entregue a um auditor **externo** É o registro de um indivíduo re-identificável (role/tribo/cert/horas) — exatamente o "risco de re-identificação reconhecido" que o RoPA/LIA do FU-4 condiciona à supressão de célula pequena (§2.3/§8 do doc de cooperação), que até então **não estava implementada**.

### Decisão (PM, `AskUserQuestion`): construir a supressão em código, não diferir

- **Predicado de auditor externo (inline, sem helper)**: `can_by_member(_, 'view_aggregate_analytics') AND NOT can_by_member(_, 'view_internal_analytics')`. Mantém o invariante elegante do teste (`carriers == SAFE_RPCS`); controladores internos nunca disparam supressão → **behavior-neutral** (ao vivo: 0 membros atuais alcançam o branch; tier dormante).
- `exec_chapter_dashboard`: auditor externo + capítulo com `<5` ativos → marcador `{suppressed:true, reason:'small_cell_below_threshold', threshold:5}` (sem detalhe).
- `exec_chapter_comparison`: auditor externo → capítulos `<5` ativos colapsam num único bucket `"Outros (<5 ativos)"` (counts somados). Caminho interno = query original **verbatim** (split IF/ELSE → zero regressão à UI admin ao vivo).
- `get_chapter_selection_summary`: só `count(*)` + metadados de ciclo (sem quebra de membro) → sem supressão necessária.
- `comms_metrics_latest_by_channel`: gate `OR` **inline** (não modifica o helper compartilhado `can_view_comms_analytics`, que vazaria `comms_top_media`/`comms_channel_status` transitivamente). O `payload` jsonb opaco (controlado por ingestão) é **NULL no caminho do auditor** (forward-defense do achado da revisão).

### Verificação (ao vivo, 2026-06-29)

- `carriers` da action = **exatamente 12** (8 + 4); teste de contrato verde (`deepEqual(carriers, SAFE_RPCS)`).
- **2 lados:** GP (Vitor, via `request.jwt.claims`) → `exec_chapter_dashboard('PMI-SP')` retorna detalhe **completo** (não suprimido) e `exec_chapter_comparison()` lista **11 capítulos nomeados** (regressão zero). Auditor (branch standalone) → PMI-SP suprimido; capítulos `<5` colapsados em "Outros (<5 ativos)" (total 8 / ativos 7).
- **Dormância:** `holders_of_action=0`, `route_to_suppression=0` (nenhum membro atual alcança a supressão).
- Mecânica: DO-block `replace()` + asserção match-único no `exec_chapter_dashboard` (18KB, zero transcrição); CREATE OR REPLACE pleno nos 3 menores; arquivo `…294` = SSOT literal pós-apply (Phase-C file==live); phantom-row do apply renomeada para a version canônica.

### Lição (cross-ref pt12 / [LL] #588)

Revisão adversarial **comportamental** (lente de domínio: security/LGPD) e validação de **fidelidade** (drift/Phase-C) são **camadas ortogonais**: o gate estava byte-fiel a live E ainda assim entregaria PII por célula pequena. Ambas necessárias.

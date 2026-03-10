# Permissions Matrix (RBAC)

> **Governança**: Este documento é a fonte de verdade para permissões do sistema.
> Qualquer alteração de acesso deve ser refletida aqui, no `navigation.config.ts`,
> e nas RLS policies do Supabase antes de ser deployada.
>
> Última atualização: 2026-03-11 (Wave 15 audit: cycle-config hardening revalidated against current ACL/site hierarchy)

---

## 1. Tier Model

O sistema usa um modelo de 6 níveis (tiers) hierárquicos, onde cada tier
herda todas as permissões dos tiers inferiores.

| Rank | Tier        | Quem é                                         | Função `has_min_tier()` |
|------|-------------|-------------------------------------------------|------------------------|
| 5    | superadmin  | `is_superadmin = true`                          | `has_min_tier(5)`      |
| 4    | admin       | `manager`, `deputy_manager`, ou `co_gp`         | `has_min_tier(4)`      |
| 3    | leader      | `tribe_leader`                                   | `has_min_tier(3)`      |
| 2    | observer    | `sponsor`, `curator`, `chapter_liaison`           | `has_min_tier(2)`      |
| 1    | member      | `researcher`, `facilitator`, `communicator`       | `has_min_tier(1)`      |
| 0    | visitor     | Sem role, sem designação, ou não autenticado       | —                      |

**Implementação backend**: `get_my_member_record()` → `has_min_tier(N)` (SECURITY DEFINER).
**Implementação frontend**: `resolveTierFromMember(member)` → `hasMinimumTier(tier, required)`.

---

## 2. Designations (Eixo Complementar)

Designações são atribuições **adicionais** ao tier. Um `researcher` (tier 1)
pode ter a designação `comms_member`, ganhando acesso ao dashboard de comunicação
sem subir de tier.

| Designação       | Acesso Extra                                   |
|------------------|-------------------------------------------------|
| `comms_leader`   | `/admin/comms`, métricas de comunicação, painel editorial |
| `comms_member`   | `/admin/comms`, métricas de comunicação (read-only)        |
| `co_gp`          | Eleva tier para `admin` (rank 4)               |
| `sponsor`        | Eleva tier para `observer` (rank 2)            |
| `curator`        | Eleva tier para `observer` (rank 2)            |
| `chapter_liaison`| Eleva tier para `observer` (rank 2)            |
| `ambassador`     | Sem elevação de tier; listado no Staff          |
| `founder`        | Sem elevação de tier; listado no Staff          |

---

## 3. Matriz de Permissões por Funcionalidade

Legenda: **V** = Visualiza | **A** = Ação (criar/editar/enviar) | **—** = Sem acesso

### 3.1 Navegação e Páginas

| Funcionalidade             | Visitor | Member | Observer | Leader | Admin | Superadmin | Designações Extras              |
|----------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|----------------------------------|
| Home (index, KPIs, agenda) |    V    |   V    |    V     |   V    |   V   |     V      |                                  |
| Workspace                  |    V    |   V    |    V     |   V    |   V   |     V      |                                  |
| Onboarding (Profile Drawer)|    —    |   V    |    V     |   V    |   V   |     V      | Drawer only (not main nav)       |
| Artifacts                  |    V    |  V/A   |   V/A    |  V/A   |  V/A  |    V/A     |                                  |
| Gamification               |    V    |   V    |    V     |   V    |   V   |     V      |                                  |
| Attendance                 |    —    |  V/A   |   V/A    |  V/A   |  V/A  |    V/A     |                                  |
| Minha Tribo `/tribe/[id]`  |    —    |   V    |    V     |  V/A   |  V/A  |    V/A     |                                  |
| Profile                    |    —    |  V/A   |   V/A    |  V/A   |  V/A  |    V/A     |                                  |
| Admin Panel `/admin`       |    —    |   —    |    V     |   V    |  V/A  |    V/A     |                                  |
| Admin Analytics            |    —    |   —    |    —     |   —    |   V   |     V      |                                  |
| Admin Comms Dashboard      |    —    |   —    |    —     |   —    |   V   |     V      | `comms_leader`, `comms_member`: V |
| Help `/help`               |    —    |   V    |    V     |   V    |   V   |     V      | LGPD topics hidden for non-admin |
| Admin Webinars (Em Breve)  |    —    |   —    |    —     |   —    |   V   |     V      | Placeholder / Coming Soon        |
| Admin Member Edit          |    —    |   —    |    —     |   —    |   —   |    V/A     |                                  |

### 3.2 Comunicação (Wave 3)

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Notas                                |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
| Broadcast de E-mail — Enviar       |    —    |   —    |    —     |   A¹   |   A   |     A      | ¹ Apenas para sua própria tribo      |
| Broadcast de E-mail — Ver Histórico|    —    |   —    |    —     |   V¹   |   V   |     V      | ¹ Apenas da sua tribo                |
| WhatsApp Grupo — Ver CTA           |    —    |   V²   |    —     |   V    |   V   |     V      | ² Apenas se alocado na tribo         |
| WhatsApp Peer-to-Peer — Ver botão  |    —    |   V³   |    —     |   V    |   V   |     V      | ³ Apenas se peer optou-in + mesma tribo |
| WhatsApp — Opt-in toggle           |    —    |   A    |    A     |   A    |   A   |     A      | Cada membro controla o seu           |

### 3.3 Dados e Segurança (Wave 1 — LGPD)

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Backend (RLS)                        |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
| `members` (tabela completa c/ PII) |    —    |  self  |   self   | tribo¹ |   V   |    V/A     | `get_my_member_record()` based       |
| `public_members` (VIEW sem PII)    |    V    |   V    |    V     |   V    |   V   |     V      | `security_invoker = false`           |
| Editar próprio perfil              |    —    |   A    |    A     |   A    |   A   |     A      | `members_update_own` policy          |
| Editar qualquer membro             |    —    |   —    |    —     |   —    |   A   |     A      | `members_update_admin` policy        |
| Deletar membro                     |    —    |   —    |    —     |   —    |   —   |     A      | `members_delete_superadmin` policy   |
| ¹ Leader vê dados dos membros da sua tribo via RLS `members_select_tribe_leader` |

### 3.4 Métricas de Comunicação

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Designações Extras                   |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
| `comms_metrics_daily` — Leitura    |    —    |   —    |    —     |   —    |   V   |     V      | `comms_leader`, `comms_member`: V    |
| `comms_metrics_daily` — Escrita    |    —    |   —    |    —     |   —    |   A   |     A      | `comms_leader`: A                    |
| `comms_metrics_ingestion_log`      |    —    |   —    |    —     |   —    |   V   |     V      | `comms_leader`, `comms_member`: V    |

### 3.5 Gamificação e Presença

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|
| Ver leaderboard / ranking          |    V    |   V    |    V     |   V    |   V   |     V      |
| Ver próprio XP / achievements      |    —    |   V    |    V     |   V    |   V   |     V      |
| Registrar presença (própria)       |    —    |   A    |    A     |   A    |   A   |     A      |
| Criar evento                       |    —    |   —    |    —     |   A    |   A   |     A      |
| Sync Attendance Points             |    —    |   —    |    —     |   —    |   A   |     A      |
| Sync Credly Badges                 |    —    |   —    |    —     |   —    |   A   |     A      |
| Verificar Credly (próprio)         |    —    |   A    |    A     |   A    |   A   |     A      |

### 3.6 Staff Section (TeamSection)

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|
| Ver listagem de Staff              |    V    |   V    |    V     |   V    |   V   |     V      |
| Aparecer como Staff                |    —    |   —    |    —     |   V    |   V   |     V      |
| Editar roles/designações do time   |    —    |   —    |    —     |   —    |   —   |     A      |

> **Quem aparece**: Membros com `operational_role` != guest e `current_cycle_active = true`,
> agrupados por: GP/Deputy → Comms Team → Tribe Leaders → Researchers → Ambassadors →
> Curators → Sponsors/Chapter Liaisons → Founders.

### 3.7 Knowledge Hub (Wave 5 — Planejado)

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|
| Consumir artigos/recursos          |    V    |   V    |    V     |   V    |   V   |     V      |
| Publicar artigo                    |    —    |   A    |    A     |   A    |   A   |     A      |
| Curar/aprovar artigos              |    —    |   —    |    A¹    |   —    |   A   |     A      |
| Administrar tags/categorias        |    —    |   —    |    —     |   —    |   A   |     A      |
| ¹ Observers com designação `curator` |

### 3.8 Configurações de Sistema

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|
| Secrets/API Keys (Resend, etc.)    |    —    |   —    |    —     |   —    |   —   |     A      |
| Domínios e DNS                     |    —    |   —    |    —     |   —    |   —   |     A      |
| Supabase Dashboard                 |    —    |   —    |    —     |   —    |   —   |     A      |
| Cycles (criar/editar ciclos)       |    —    |   —    |    —     |   —    |   A   |     A      |
| Announcements (banners)            |    —    |   —    |    —     |   —    |   A   |     A      |
| Hub Resources (CRUD)               |    —    |   —    |    —     |   —    |   A   |     A      |

### 3.9 Supabase Storage (`documents` bucket)

|| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Backend (RLS)                        |
||------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
|| Ler ficheiros públicos             |    V    |   V    |    V     |   V    |   V   |     V      | `documents_public_read` policy       |
|| Upload (`knowledge-pdfs/`)         |    —    |   A    |    A     |   A    |   A   |     A      | `documents_auth_upload` (authenticated) |
|| Deletar ficheiros                  |    —    |   —    |    —     |   —    |   A   |     A      | `documents_admin_delete` policy      |

> Bucket criado via migration `20260309220000_storage_documents_bucket.sql`.
> Upload validado no frontend com limite de 15MB e formatos `.pdf,.pptx,.png,.jpg,.jpeg`.

### 3.10 LGPD Contact Data

|| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Backend                              |
||------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
|| `get_tribe_member_contacts` RPC    |    —    |   —    |    —     |  V¹    |   V   |     V      | SECURITY DEFINER, ¹ leader da tribo  |
|| Ver email/telefone em `/tribe/[id]`|    —    |   —    |    —     |  V¹    |   V   |     V      | Frontend consome RPC acima           |
|| Máscara LGPD (`***-*** LGPD`)      |    —    |   V    |    V     |   —    |   —   |     —      | Membros sem privilégio veem máscara  |

### 3.11 Lifecycle Management (S-ADM3)

|| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Backend                              |
||------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
|| `admin_move_member_tribe` RPC      |    —    |   —    |    —     |   —    |   —   |     A      | SECURITY DEFINER, `is_superadmin`    |
|| `admin_deactivate_member` RPC      |    —    |   —    |    —     |   —    |   —   |     A      | SECURITY DEFINER, `is_superadmin`    |
|| `admin_change_tribe_leader` RPC    |    —    |   —    |    —     |   —    |   —   |     A      | SECURITY DEFINER, `is_superadmin`    |
|| `admin_deactivate_tribe` RPC       |    —    |   —    |    —     |   —    |   —   |     A      | SECURITY DEFINER, `is_superadmin`    |

### 3.12 Presentation Module (S-PRES1)

|| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Notas                                |
||------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
|| Presentation Toggle (Home)         |    —    |   —    |    —     |   —    |   A   |     A      | Tier 4+ only on index.astro          |
|| Presentation Toggle (Tribe)        |    —    |   —    |    —     |   A¹   |   A   |     A      | ¹ tribe_leader of that tribe only    |
|| `save_presentation_snapshot` RPC   |    —    |   —    |    —     |   A¹   |   A   |     A      | ¹ leader-scoped with p_tribe_id      |
|| `list_meeting_artifacts` RPC       |    —    |   V    |    V     |   V    |   V   |     V      | Optional p_tribe_id filter           |
|| Ver `/presentations` histórico     |    —    |   V    |    V     |   V    |   V   |     V      | Filterable by tribe                  |

### 3.13 Tribe Project Boards (Wave 8)

|| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Notas                                |
||------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
|| Ver Quadro de Projeto em `/tribe/[id]` | —  |   V    |    V     |   V    |   V   |     V      | 5 colunas Kanban                     |
|| Criar board / mover itens          |    —    |   —    |    —     |   A¹   |   A   |     A      | ¹ leader da tribo                   |
|| `list_board_items`, `move_board_item` | —    |   —    |    —     |   V/A¹ |  V/A  |    V/A     | RPCs com RLS                         |

### 3.14 Selection Process (Wave 9 — LGPD)

|| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Backend                              |
||------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
|| `/admin/selection` página          |    —    |   —    |    —     |   —    |   V   |     V      | lgpdSensitive — oculto se não-admin  |
|| `list_volunteer_applications` RPC  |    —    |   —    |    —     |   —    |   V   |     V      | SECURITY DEFINER, admin check        |
|| `volunteer_funnel_summary` RPC     |    —    |   —    |    —     |   —    |   V   |     V      | Agregados sem PII em analytics       |

### 3.15 Progressive Disclosure (Wave 8)

Itens de navegação com tier insuficiente: visíveis mas desabilitados (opacidade + ícone cadeado + tooltip "Requer [tier]"). Itens com `lgpdSensitive: true` permanecem completamente ocultos para não-autorizados.

### 3.16 Site Config (Wave 11 — S-RM5)

| Funcionalidade                     | Visitor | Member | Observer | Leader | Admin | Superadmin | Backend                              |
|------------------------------------|:-------:|:------:|:--------:|:------:|:-----:|:----------:|--------------------------------------|
| `/admin/settings` página           |    —    |   —    |    —     |   —    |   —   |     V/A    | Superadmin only                      |
| `get_site_config` RPC (leitura)    |    —    |   —    |    —     |   —    |   V   |     V      | Admin tier pode ler                  |
| `set_site_config` RPC (escrita)    |    —    |   —    |    —     |   —    |   —   |     A      | Superadmin only, SECURITY DEFINER    |
| `site_config` tabela               |    —    |   —    |    —     |   —    |   V   |    V/A     | RLS: admin read, superadmin write    |

---

## 4. Mapeamento Código ↔ Matriz

### Frontend (`navigation.config.ts`)

| `key`            | `minTier`  | `allowedDesignations`            | Coerente? |
|------------------|------------|----------------------------------|-----------|
| `attendance`     | `member`   | —                                | ✅         |
| `my-tribe`       | `member`   | —                                | ✅         |
| `profile`        | `member`   | —                                | ✅         |
| `admin`          | `observer` | —                                | ✅         |
| `admin-analytics`   | `admin`    | —                                | ✅         |
| `admin-comms`      | `admin`    | `['comms_leader', 'comms_member']`| ✅ (lgpdSensitive) |
| `admin-curatorship`| `observer` | —                                | ✅         |
| `admin-selection`  | `admin`    | —                                | ✅ (lgpdSensitive) |
| `admin-settings`   | `superadmin` | —                             | ✅ (S-RM5)         |
| `help`             | `member`   | —                                | ✅         |
| `onboarding`     | `member`   | —                                | ✅ (drawer) |
| `admin-webinars` | `admin`    | —                                | ✅ (placeholder) |

### Backend (`has_min_tier` / RLS)

| Tabela / RPC                 | Policy                          | Tier Req | Coerente? |
|------------------------------|---------------------------------|----------|-----------|
| `members` SELECT             | `members_select_own`            | self     | ✅         |
| `members` SELECT             | `members_select_admin`          | 4 (admin)| ✅         |
| `members` SELECT             | `members_select_tribe_leader`   | 3 (leader, own tribe)| ✅ |
| `members` UPDATE             | `members_update_own`            | self     | ✅         |
| `members` UPDATE             | `members_update_admin`          | 4 (admin)| ✅         |
| `members` DELETE             | `members_delete_superadmin`     | 5 (SA)   | ✅         |
| `broadcast_log` SELECT       | `broadcast_log_read_sender`     | self     | ✅         |
| `broadcast_log` SELECT       | `broadcast_log_read_tribe_leader`| 3 (leader, own tribe)| ✅ |
| `broadcast_log` SELECT       | `broadcast_log_read_admin`      | 4 (admin)| ✅         |
| `broadcast_log` INSERT       | service_role only               | —        | ✅         |
| `comms_metrics_daily` SELECT | `comms_metrics_admin_read`      | 4 OR comms desig | ✅ |
| `comms_metrics_daily` WRITE  | `can_manage_comms_metrics()`    | 4 OR comms desig | ✅ |

### Edge Functions

| Function                | Auth                          | Autorização                        | Coerente? |
|-------------------------|-------------------------------|------------------------------------|-----------|
| `send-tribe-broadcast`  | JWT via `getUser()`           | SA, manager, deputy OR tribe_leader of target tribe | ✅ |
| `sync-attendance-points`| Bearer token                  | Authenticated (admin-triggered)    | ✅         |
| `sync-credly-all`       | Bearer token                  | Authenticated (admin-triggered)    | ✅         |
| `verify-credly`         | Bearer token                  | Authenticated (self)               | ✅         |

---

## 5. Divergências Identificadas

Nenhuma divergência crítica encontrada. O `navigation.config.ts`, as RLS policies,
e as Edge Functions estão alinhados com esta matriz.

**Observações menores (todas resolvidas em S-COM1)**:
1. ~~`TeamSection.astro` filtra comms team por designação `comms_team` (legada).~~
   **Resolvido**: Filtro atualizado para `comms_leader || comms_member || comms_team` (backward compat). Backfill executado.
2. ~~`sync-attendance-points` e `sync-credly-all` aceitam qualquer Bearer token.~~
   **Resolvido**: Ambas as Edge Functions agora verificam `is_superadmin || operational_role in (manager, deputy_manager)` antes de executar sincronizações em massa. Não-admins em `sync-attendance-points` só sincronizam seus próprios pontos.

---

## 6. Changelog

| Data       | Alteração                                              |
|------------|--------------------------------------------------------|
| 2026-03-09 | Legacy Ingestion: admin_links (Tier 4/5 ACL), trello_import_log, import-trello-legacy + import-calendar-legacy Edge Functions. list_tribe_deliverables auth hardening. |
| 2026-03-09 | Wave 4 Expansion: /admin/comms (ranking + broadcasts), /admin/webinars, webinars schema, sb.functions.invoke eliminated. |
| 2026-03-09 | S-COM1: Divergências #1 e #2 resolvidas. Backfill de designações + blindagem de Edge Functions. |
| 2026-03-09 | Documento criado (Wave 4). Cobertura: W1–W3 + W4.10.  |
| 2026-03-11 | Wave 8-10: Admin Curatorship, Admin Selection, Admin Analytics nav. Sections 3.13-3.15 (Tribe Kanban, Selection LGPD, Progressive disclosure). Code mapping table complete. |
| 2026-03-11 | Wave 11: Section 3.16 Site Config (admin-settings superadmin). Wave 12: Agent docs, release workflow, screenshot script. |
| 2026-03-11 | Wave 14 audit: site hierarchy/ACL revalidated after admin hygiene; `admin_webinars` route key aligned in shared constants. |
| 2026-03-11 | Wave 15 audit: cycle-config hardening in admin/profile/tribe completed with no tier or visibility regression; matrix remains aligned with current routes. |

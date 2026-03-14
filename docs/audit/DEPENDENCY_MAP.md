# W139 — Dependency Map (per route)

**Data:** 2026-03-14
**Método:** Análise estática de imports, `.rpc()`, `.from()`, `fetch()` em todas as páginas e componentes React

---

## Páginas Públicas

### / (Homepage)
**File:** `src/pages/index.astro`
**Auth:** Não
**Imports:** KpiSection, HeroSection, NucleoSection, VisionSection (Astro components)

**RPC calls:**
| RPC | Called From | Purpose |
|-----|-----------|---------|
| `get_homepage_stats` | index.astro (script) | Stats do hero |
| `get_near_events` | index.astro (script) | Próximos eventos |
| `get_public_impact_data` | index.astro (script) | Dados de impacto público |
| `get_public_publications` | index.astro (script) | Publicações recentes |
| `exec_portfolio_health` | KpiSection.astro | KPI progress bars |

**Direct table queries:** `home_schedule`, `tribes`

---

### /blog
**File:** `src/pages/blog/index.astro`
**Auth:** Não
**RPC calls:** Nenhum
**Direct table queries:** `blog_posts` (select with status='published')

---

### /blog/[slug]
**File:** `src/pages/blog/[slug].astro`
**Auth:** Não
**RPC calls:** Nenhum
**Direct table queries:** `blog_posts` (select by slug)

---

### /library
**File:** `src/pages/library.astro`
**Auth:** Não
**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `search_knowledge` | Busca em hub_resources |

**Direct table queries:** `hub_resources`, `courses`, `course_progress`

---

### /help
**File:** `src/pages/help.astro`
**Auth:** Não
**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `get_help_journeys` | Jornadas de ajuda |
| `get_member_by_auth` | Verificar membro autenticado |
| `dismiss_onboarding` | Dismiss popup de boas-vindas |

---

### /gamification
**File:** `src/pages/gamification.astro`
**Auth:** Não (dados públicos + features autenticadas)
**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `get_member_by_auth` | Auth check |
| `get_member_cycle_xp` | XP do ciclo |
| `exec_cert_timeline` | Timeline de certificações |

**Direct table queries:** `gamification_leaderboard` (view), `gamification_points`, `certificates`, `course_progress`, `courses`, `members`, `tribes`
**Edge Functions:** `sync-attendance-points`, `sync-credly-all`

---

### /projects
**File:** `src/pages/projects.astro`
**Auth:** Não
**RPC calls:** Nenhum
**Direct table queries:** `ia_pilots`
**Facades:** Botão `btn-register-pilot` sem handler (admin-only)

---

## Páginas Autenticadas

### /workspace
**File:** `src/pages/workspace.astro`
**Auth:** Sim
**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `get_member_by_auth` | Auth check |
| `get_near_events` | Próximos eventos |
| `list_active_boards` | Boards ativos |
| `get_board_by_domain` | Board por domínio |
| `list_admin_links` | Links admin |
| `get_onboarding_status` | Status de onboarding |
| `get_dropout_risk_members` | Membros em risco |
| `detect_operational_alerts` | Alertas operacionais |
| `get_my_notifications` | Notificações |
| `get_kpi_dashboard` | KPIs |
| `export_my_data` | Export LGPD |

**Direct table queries:** `tribe_meeting_slots`, `active_members` ⚠️ (NÃO EXISTE), `announcements`

---

### /profile
**File:** `src/pages/profile.astro`
**Auth:** Sim
**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `get_member_by_auth` | Auth |
| `member_self_update` | Atualizar perfil |
| `update_notification_preferences` | Preferências de notificação |
| `get_member_attendance_hours` | Horas de presença |
| `get_member_cycle_xp` | XP do ciclo |

**Direct table queries:** `members`, `notification_preferences`, `certificates`
**Edge Functions:** `verify-credly`

---

### /attendance
**File:** `src/pages/attendance.astro`
**Auth:** Sim
**Imports:** AttendanceForm.tsx, AttendanceDashboard.tsx

**RPC calls (page):**
| RPC | Purpose |
|-----|---------|
| `get_events_with_attendance` | Eventos com presença |
| `register_own_presence` | Registrar própria presença |
| `get_attendance_summary` | Resumo de presença |
| `create_event` | Criar evento |
| `create_recurring_weekly_events` | Criar eventos recorrentes |
| `update_event` | Atualizar evento |
| `register_attendance_batch` | Registrar presença em lote |
| `update_event_duration` | Atualizar duração |
| `mark_member_present` | Marcar membro presente |
| `admin_bulk_mark_attendance` | Marcação em lote (admin) |

**RPC calls (AttendanceForm.tsx):**
| RPC | Purpose |
|-----|---------|
| `get_recent_events` | Eventos recentes |
| `register_attendance_batch` | Registro em lote |

**Direct table queries:** `attendance`, `active_members` ⚠️ (NÃO EXISTE), `events`

---

### /tribe/[id]
**File:** `src/pages/tribe/[id].astro`
**Auth:** Sim
**Imports:** TribeKanbanIsland.tsx

**RPC calls (page):**
| RPC | Purpose |
|-----|---------|
| `get_board` | Board da tribo |
| `get_tribe_member_contacts` | Contatos dos membros |
| `get_tribe_event_roster` | Roster de eventos |
| `list_tribe_deliverables` | Entregas da tribo |
| `upsert_tribe_deliverable` | Criar/atualizar entrega |
| `count_tribe_slots` | Slots da tribo |
| `select_tribe` | Selecionar tribo |
| `deselect_tribe` | Desselecionar |
| `resolve_whatsapp_link` | WhatsApp do líder |
| `save_presentation_snapshot` | Snapshot de apresentação |

**RPC calls (TribeKanbanIsland.tsx):**
| RPC | Purpose |
|-----|---------|
| `list_project_boards` | Boards do projeto |
| `list_board_items` | Items do board |
| `list_legacy_board_items_for_tribe` | Items legados |
| `move_board_item` | Mover item |
| `advance_board_item_curation` | Avançar curadoria |
| `upsert_board_item` | Upsert item |
| `admin_archive_board_item` | Arquivar item |

**Direct table queries:** `tribes`, `tribe_selections`, `public_members`
**Edge Functions:** `send-tribe-broadcast`

---

### /publications
**File:** `src/pages/publications.astro`
**Auth:** Sim (leader+)
**Imports:** PublicationsBoardIsland.tsx

**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `get_public_publications` | Publicações públicas |
| `list_project_boards` | Boards (publicações) |
| `list_board_items` | Items do board |
| `move_board_item` | Mover item |
| `upsert_publication_submission_event` | Submissão de publicação |

**Direct table queries:** `publication_submission_events` ⚠️ (NÃO EXISTE)

---

## Páginas Admin (seleção das mais complexas)

### /admin (Painel Principal)
**File:** `src/pages/admin/index.astro` (~4000 linhas)
**Auth:** Sim (observer+)

**RPC calls (26 RPCs):**
`admin_list_members`, `admin_list_tribes`, `admin_get_tribe_allocations`, `admin_force_tribe_selection`, `admin_update_member`, `admin_inactivate_member`, `admin_reactivate_member`, `admin_set_tribe_active`, `admin_upsert_tribe`, `admin_detect_data_anomalies`, `admin_get_anomaly_report`, `admin_resolve_anomaly`, `admin_run_portfolio_data_sanity`, `admin_detect_board_taxonomy_drift`, `get_site_config`, `set_site_config`, `get_executive_kpis`, `exec_funnel_summary`, `exec_skills_radar`, `list_radar_global`, `exec_portfolio_board_summary`, `exec_portfolio_health`, `get_dropout_risk_members`, `detect_operational_alerts`, `get_gp_whatsapp`, `list_volunteer_applications`

**Edge Functions:** `import-trello-legacy`, `import-calendar-legacy`, `send-allocation-notify`, `send-global-onboarding`

**Direct table queries:** `members`, `tribes`, `events`, `gamification_points`

---

### /admin/comms
**File:** `src/pages/admin/comms.astro`
**Auth:** Sim (admin + comms designations)

**RPC calls:**
| RPC | Purpose | Funciona? |
|-----|---------|-----------|
| `comms_metrics_latest_by_channel` | Métricas por canal | ✅ (5 rows) |
| `tribe_impact_ranking` | Ranking de impacto | ✅ |
| `broadcast_history` | Histórico de broadcast | ✅ (21 rows) |
| `comms_channel_status` | Status dos canais | ✅ (3 canais) |
| `admin_manage_comms_channel` | Configurar canal | ✅ |
| `comms_check_token_expiry` | Alertas de token | ✅ |
| `comms_acknowledge_alert` | Acknowledge alerta | ✅ |
| `get_member_by_auth` | Auth | ✅ |

**Nota:** Todos os RPCs funcionam. Tokens de API social estão null (sem sync automático), mas dados seed existem e dashboard renderiza corretamente.

---

### /admin/campaigns
**File:** `src/pages/admin/campaigns.astro`
**Auth:** Sim (admin + comms_team)

**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `admin_preview_campaign` | Preview de campanha |
| `admin_send_campaign` | Enviar campanha |
| `admin_get_campaign_stats` | Estatísticas |
| `get_member_by_auth` | Auth |

**Direct table queries:** `campaign_templates`, `campaign_sends`
**Edge Functions:** `send-campaign`

---

### /admin/selection
**File:** `src/pages/admin/selection.astro`
**Auth:** Sim (admin)

**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `get_selection_pipeline_metrics` | Pipeline do seletivo |
| `get_diversity_dashboard` | Dashboard de diversidade |
| `admin_list_members` | Lista de membros |
| `volunteer_funnel_summary` | Funil de voluntários |

**Imports:** DiversityDashboard.tsx (calls `get_diversity_dashboard`)

---

### /admin/analytics
**File:** `src/pages/admin/analytics.astro`
**Auth:** Sim (admin + designations)

**RPC calls:**
| RPC | Purpose |
|-----|---------|
| `get_executive_kpis` | KPIs executivos |
| `exec_funnel_summary` | Funil de produção |
| `exec_portfolio_board_summary` | Boards do portfólio |
| `exec_cert_timeline` | Timeline de certificações |
| `exec_skills_radar` | Radar de habilidades |
| `exec_portfolio_health` | Saúde do portfólio |
| `list_radar_global` | Radar global |

---

### /admin/sustainability ⚠️
**File:** `src/pages/admin/sustainability.astro`
**Auth:** Sim (admin + designations)
**RPC calls:** NENHUM
**Direct table queries:** NENHUM
**Status:** FACADE — 4 cards hardcoded com status "Planning"

---

*Para o mapa completo de todas as 42 rotas, ver os relatórios dos agentes de auditoria.*

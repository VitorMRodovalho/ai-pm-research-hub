// supabase/functions/nucleo-mcp/index.ts
// MCP server v2.13.0 — 94 tools (70R + 24W) + 1 prompt + 1 resource + usage logging
// v2.13.0: +8 card/checklist CRUD tools (issue #83 P0 — Fabrício T6 leader feedback)
// V4 Cutover: canWrite/canWriteBoard → canV4 (ADR-0007, engagement-derived authority)
// Transport: SDK 1.29.0 WebStandardStreamableHTTPServerTransport (native Streamable HTTP)
// GC-132/133: Phase 1+2 | GC-161: P1 | GC-164: P2

import { Hono } from "jsr:@hono/hono@4.12.9";
import { McpServer } from "npm:@modelcontextprotocol/sdk@1.29.0/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "npm:@modelcontextprotocol/sdk@1.29.0/server/webStandardStreamableHttp.js";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { z } from "npm:zod@^4.0";

const app = new Hono().basePath("/nucleo-mcp");

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

function createAuthenticatedClient(token?: string) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: token ? { Authorization: `Bearer ${token}` } : {} },
  });
}

function err(msg: string) {
  return { content: [{ type: "text" as const, text: `Error: ${msg}` }] };
}

function ok(data: unknown) {
  return { content: [{ type: "text" as const, text: JSON.stringify(data, null, 2) }] };
}

async function getMember(sb: ReturnType<typeof createClient>) {
  const { data, error } = await sb.rpc("get_my_member_record");
  if (error || !data) return null;
  if (Array.isArray(data)) return data.length > 0 ? data[0] : null;
  if (typeof data === "object" && data.id) return data;
  return null;
}

// V4: Authority gate via engagement-derived can() (ADR-0007)
// Replaces legacy canWrite/canWriteBoard with DB-driven permissions
async function canV4(sb: ReturnType<typeof createClient>, memberId: string, action: string, resourceType?: string, resourceId?: string): Promise<boolean> {
  const { data, error } = await sb.rpc("can_by_member", {
    p_member_id: memberId,
    p_action: action,
    p_resource_type: resourceType || null,
    p_resource_id: resourceId || null,
  });
  if (error) return false; // fail-closed
  return data === true;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function isUUID(v: string | undefined): boolean { return !!v && UUID_RE.test(v); }

const NO_TRIBE_HINT = "No tribe assigned. Pass tribe_id parameter (1-8) to specify which tribe. Use list_boards or get_portfolio_overview for board IDs.";

// V4: resolve legacy tribe_id → initiative UUID for _by_initiative RPCs
async function resolveInitiativeId(sb: ReturnType<typeof createClient>, tribeId: number): Promise<string | null> {
  const { data } = await sb.from("initiatives").select("id").eq("legacy_tribe_id", tribeId).single();
  return data?.id || null;
}

async function logUsage(sb: ReturnType<typeof createClient>, memberId: string | null, toolName: string, success: boolean, errorMsg?: string, startTime?: number) {
  try {
    const execMs = startTime ? Date.now() - startTime : null;
    await sb.rpc("log_mcp_usage", { p_auth_user_id: null, p_member_id: memberId, p_tool_name: toolName, p_success: success, p_error_message: errorMsg || null, p_execution_ms: execMs });
  } catch (_) { /* never break tool execution */ }
}

// --- Knowledge Layer: Prompts + Resources ---

function registerKnowledge(mcp: McpServer, sb: ReturnType<typeof createClient>) {

  // Dynamic prompt — adapts to authenticated member's role and permissions
  mcp.registerPrompt(
    "nucleo-guide",
    {
      title: "Guia do Núcleo IA",
      description: "Instruções personalizadas para o assistente baseadas no seu perfil, papel e permissões.",
    },
    async () => {
      const member = await getMember(sb);
      if (!member) {
        return { messages: [{ role: "user" as const, content: { type: "text" as const, text: "Usuário não autenticado. Peça para reconectar o MCP." } }] };
      }

      const role = member.operational_role || "member";
      const designations: string[] = member.designations || [];
      const isAdmin = await canV4(sb, member.id, 'manage_member');
      const isLeader = await canV4(sb, member.id, 'write');
      const isSponsor = await canV4(sb, member.id, 'manage_partner');
      const isComms = isLeader; // comms_leader has 'write' — covered by isLeader
      const isLiaison = isSponsor; // chapter_liaison/sponsor both have 'manage_partner' — covered by isSponsor
      const hasViewPii = await canV4(sb, member.id, 'view_pii');
      const isChapterBoard = isSponsor || hasViewPii; // board_member has 'view_pii' only (without 'manage_partner')
      const hasTribe = !!member.tribe_id;

      // Build personalized tool guide
      const sections: string[] = [];

      sections.push(`## Seu perfil
- **Nome:** ${member.name}
- **Papel:** ${role}${member.is_superadmin ? " (superadmin)" : ""}
- **Tribo:** ${hasTribe ? `Tribo ${member.tribe_id}` : "Sem tribo fixa (manager/founder)"}
- **Initiative:** ${member.initiative_id || "não vinculado"}
- **Designações:** ${designations.length > 0 ? designations.join(", ") : "nenhuma"}
- **Capítulo:** ${member.chapter || "não definido"}`);

      // Onboarding hint for new members
      if (!isAdmin && !isLeader) {
        sections.push(`## Bem-vindo ao Núcleo IA & GP
Se é sua primeira vez usando o MCP, aqui estão 3 comandos para começar:
1. **"Qual meu XP e posição no ranking?"** → usa \`get_my_xp_and_ranking\`
2. **"Quais eventos tenho esta semana?"** → usa \`get_upcoming_events\`
3. **"Buscar recursos sobre prompt engineering"** → usa \`search_hub_resources\`

Você pode perguntar em linguagem natural — o assistente escolhe a ferramenta certa automaticamente.`);
      }

      // Tier 1 — everyone
      sections.push(`## Ferramentas disponíveis para você

### Consultas pessoais (sempre disponíveis)
- \`get_my_profile\` — Seu perfil completo
- \`get_my_xp_and_ranking\` — Seu XP e posição no ranking
- \`get_my_notifications\` — Notificações não lidas
- \`get_my_attendance_history\` — Seu histórico de presença
- \`get_my_certificates\` — Suas certificações e badges
- \`get_upcoming_events\` — Eventos dos próximos 7 dias
- \`get_near_events\` — Eventos nas próximas horas (janela configurável)
- \`get_hub_announcements\` — Avisos ativos do Hub
- \`search_hub_resources\` — Busca na biblioteca (247+ itens)
- \`get_public_impact_data\` — Dados de impacto público, timeline, reconhecimentos
- \`get_pilots_summary\` — Resumo dos pilotos de IA
- \`get_current_release\` — Versão atual da plataforma
- \`get_my_credly_status\` — Seus badges Credly e certificação CPMAI
- \`get_my_attendance_hours\` — Horas de presença no ciclo`);

      if (hasTribe) {
        sections.push(`### Consultas da sua tribo
- \`get_my_tribe_members\` — Membros ativos da sua tribo
- \`get_my_tribe_attendance\` — Grade de presença da tribo
- \`get_my_board_status\` — Cards do board agrupados por status
- \`get_meeting_notes\` — Últimas atas de reunião
- \`search_board_cards\` — Busca full-text em cards
- \`list_tribe_webinars\` — Webinars da tribo
- \`get_event_detail\` — Detalhe de evento (agenda, ata, action items) — passe event_id`);
      } else {
        sections.push(`### Nota sobre rotas de tribo/iniciativa
Seu perfil não tem tribo fixa. Para consultar dados de uma iniciativa específica, use ferramentas que aceitam \`tribe_id\` (inteiro 1-8, legado) ou \`initiative_id\` (UUID, V4) como parâmetro:
- \`get_tribe_dashboard\` com \`tribe_id=1\` a \`8\`
- \`get_tribe_deliverables\` com \`tribe_id=1\` a \`8\`
Rotas como \`get_my_tribe_members\` retornarão "No tribe assigned" — isso é esperado.
**V4:** Internamente, as RPCs \`_by_initiative\` usam initiative UUIDs. O campo \`initiative_id\` está disponível em todos os registros via dual-write.`);
      }

      if (isLeader) {
        sections.push(`### Escrita (líder/gestor)
- \`create_board_card\` — Criar card no board da tribo
- \`update_card_status\` — Mover card entre colunas (backlog→in_progress→review→done)
- \`create_meeting_notes\` — Criar ata de reunião (precisa event_id)
- \`register_attendance\` — Registrar presença (precisa event_id + member_id)
- \`register_showcase\` — Registrar protagonismo em reunião geral (event_id + member_id + tipo: case_study/tool_review/prompt_week/quick_insight/awareness). Premia 15-25 XP.
- \`send_notification_to_tribe\` — Notificar toda a tribo
- \`create_tribe_event\` — Criar reunião ou evento`);
      }

      if (isLiaison) {
        sections.push(`### Capítulo (ponto focal)
- \`get_chapter_kpis\` — KPIs do seu capítulo (${member.chapter || "especifique: GO, CE, DF, MG, RS"})
- Você pode consultar KPIs de outros capítulos também.`);
      }

      if (isComms) {
        sections.push(`### Comunicação
- \`get_comms_dashboard\` — Dashboard: publicações por status/formato, backlog, overdue
- \`get_campaign_analytics\` — Métricas de email: opens, clicks, bounces
- \`get_comms_metrics_by_channel\` — LinkedIn, Instagram, YouTube (últimos N dias)
- \`get_comms_pending_webinars\` — Webinars pendentes de ação de comunicação`);
      }

      if (isSponsor) {
        sections.push(`### Patrocinador/Sponsor
- \`get_partner_pipeline\` — Pipeline de parcerias: status, contatos, alertas de estagnação
- \`get_annual_kpis\` — KPIs anuais: metas vs realizado
- \`get_portfolio_health\` — Saúde do portfólio: semáforo por KPI trimestral
- \`get_public_impact_data\` — Dados de impacto para apresentações`);
      }

      if (isChapterBoard) {
        sections.push(`### Diretoria do Capítulo
Você é membro da diretoria do ${member.chapter || "capítulo"}. Seu acesso é read-only, focado em dados de impacto e acompanhamento.
- \`get_public_impact_data\` — Dados de impacto público: capítulos, membros, publicações, timeline
- \`get_chapter_kpis\` — KPIs do seu capítulo (${member.chapter || "especifique: GO, CE, DF, MG, RS"})
- \`get_attendance_ranking\` — Ranking geral de presença (agregado)
- \`get_pilots_summary\` — Resumo dos pilotos de IA
- \`get_current_release\` — Versão atual da plataforma
- \`search_hub_resources\` — Busca na biblioteca de recursos (247+ itens)
- \`get_governance_docs\` — Documentos de governança
- \`get_manual_section\` — Seções do Manual de Governança

- \`get_chapter_needs\` — Ver necessidades reportadas pelo seu capítulo
- \`submit_chapter_need\` — Reportar uma necessidade ou solicitação para o projeto

**Nota:** Como membro de diretoria, você não tem acesso a dados individuais de presença (detractors/at-risk) ou gestão de membros. Use \`submit_chapter_need\` para reportar necessidades ao projeto.`);
      }

      if (isAdmin) {
        sections.push(`### Gestão/GP (Admin)
- \`get_tribe_dashboard\` — Dashboard completo de qualquer tribo (tribe_id 1-8 ou initiative_id UUID)
- \`get_tribe_deliverables\` — Entregas por tribo e ciclo
- \`get_portfolio_overview\` — Visão executiva: todos os boards e cards
- \`get_operational_alerts\` — Alertas: inatividade, cards atrasados, drift
- \`get_cycle_report\` — Relatório completo do ciclo
- \`get_annual_kpis\` — KPIs anuais
- \`get_portfolio_health\` — Saúde trimestral do portfólio
- \`get_adoption_metrics\` — Métricas de adoção do MCP: saúde por rota
- \`get_curation_dashboard\` — Workflow de curadoria: pendentes, SLA
- \`get_anomaly_report\` — Anomalias de dados
- \`get_attendance_ranking\` — Ranking de presença
- \`get_volunteer_funnel\` — Funil de seleção de voluntários
- \`get_partner_pipeline\` — Pipeline de parcerias
- \`get_campaign_analytics\` — Métricas de campanhas de email
- \`get_comms_dashboard\` — Dashboard de comunicação
- \`get_comms_metrics_by_channel\` — Métricas por canal social
- \`get_admin_dashboard\` — Dashboard admin: membros, tribos, atividade
- \`get_ghost_visitors\` — Visitantes fantasma: usuários autenticados sem vínculo com membro
- \`get_board_activities\` — Atividades recentes dos boards (lifecycle events)
- \`search_members\` — Buscar membros por nome, tribo, tier ou status
- \`list_boards\` — Lista todos os boards ativos com IDs
- \`manage_partner\` — Criar ou atualizar parceiro no pipeline`);
      }

      sections.push(`## Workflows recomendados

### "Como está minha tribo?"
1. \`get_tribe_dashboard\`${hasTribe ? "" : " (passe tribe_id)"} → visão geral
2. \`get_tribe_deliverables\` → entregas pendentes
3. \`get_my_tribe_attendance\` → quem está participando

### "Preciso preparar um relatório"
1. \`get_cycle_report\` → dados do ciclo atual
2. \`get_annual_kpis\` → metas vs realizado
3. \`get_portfolio_health\` → semáforo trimestral

### "O que tenho para hoje?"
1. \`get_near_events\` → eventos nas próximas horas
2. \`get_my_notifications\` → notificações pendentes
3. \`get_hub_announcements\` → avisos ativos

### "Como estão as comunicações?"
1. \`get_comms_dashboard\` → backlog e status
2. \`get_comms_pending_webinars\` → webinars sem comunicação
3. \`get_comms_metrics_by_channel\` → métricas por rede social

## Erros comuns e como lidar
- **"No tribe assigned"** — Seu perfil não tem tribo fixa. Use rotas com parâmetro \`tribe_id\`.
- **"Unauthorized"** — A ferramenta requer um papel que você não tem. Não insista.
- **"Not authenticated"** — Token expirado. O auto-refresh deve resolver automaticamente, mas se persistir, peça para reconectar o MCP.

## Sobre o Núcleo IA & GP
O Núcleo de IA Aplicada à Gestão de Projetos é uma iniciativa de pesquisa do PMI Brasil (5 capítulos: GO, CE, DF, MG, RS) com 50+ colaboradores organizados em 8 tribos. A plataforma é nucleoia.vitormr.dev.`);

      return {
        messages: [{
          role: "user" as const,
          content: { type: "text" as const, text: sections.join("\n\n") }
        }]
      };
    }
  );

  // Static resource — full tool reference (always available, not role-filtered)
  mcp.registerResource(
    "tool-reference",
    "nucleo://tools/reference",
    {
      title: "Referência completa de ferramentas",
      description: "Lista todas as 76 ferramentas do Núcleo MCP com parâmetros e permissões.",
      mimeType: "text/markdown",
    },
    async () => ({
      contents: [{
        uri: "nucleo://tools/reference",
        text: `# Núcleo IA MCP — Referência de Ferramentas (v2.11.0)

## 76 ferramentas: 61 leitura + 15 escrita

### Tier 1 — Todos os membros (27 leitura)
| # | Ferramenta | Parâmetros | Descrição |
|---|-----------|-----------|-----------|
| 1 | get_my_profile | — | Perfil: nome, papel, tribo, XP, badges |
| 2 | get_my_board_status | board_id?, tribe_id? | Cards do board agrupados por status |
| 3 | get_my_tribe_attendance | tribe_id? | Grade de presença da tribo |
| 4 | get_my_tribe_members | tribe_id? | Membros ativos com papéis |
| 5 | get_upcoming_events | — | Eventos dos próximos 7 dias |
| 6 | get_my_xp_and_ranking | — | XP por categoria + posição |
| 7 | get_meeting_notes | tribe_id?, limit? | Últimas atas de reunião |
| 8 | get_my_notifications | — | Notificações não lidas |
| 9 | search_board_cards | query, tribe_id? | Busca full-text em cards |
| 10 | get_hub_announcements | — | Avisos ativos do Hub |
| 11 | get_my_attendance_history | limit? | Histórico pessoal de presença |
| 12 | list_tribe_webinars | status? | Webinars da tribo/capítulo |
| 13 | get_comms_pending_webinars | — | Webinars pendentes de comunicação |
| 14 | get_my_certificates | — | Certificações, badges, trilhas |
| 15 | search_hub_resources | query, asset_type?, limit? | Biblioteca de recursos (247+) |
| 16 | get_attendance_ranking | — | Ranking de presença |
| 17 | get_event_detail | event_id | Detalhe: agenda, ata, ações |
| 18 | get_public_impact_data | — | Impacto público, timeline, reconhecimentos |
| 19 | get_pilots_summary | — | Pilotos de IA: status e métricas |
| 20 | get_near_events | window_hours? | Eventos nas próximas horas |
| 21 | get_current_release | — | Versão atual da plataforma |
| 22 | get_my_attendance_hours | — | Horas de presença no ciclo |
| 23 | get_my_credly_status | — | Badges Credly e CPMAI |
| 24 | get_my_assigned_cards | — | Cards atribuídos a você (cross-board) |
| 25 | get_my_selection_result | — | Status e scores da sua candidatura |
| 26 | get_person | person_id? | Perfil V4 (PII só p/ próprio ou view_pii) |
| 27 | get_active_engagements | person_id? | Engagements ativos (ADR-0006) |

### Tier 1 — Todos os membros (mais 10 leitura contextuais)
| # | Ferramenta | Parâmetros | Descrição |
|---|-----------|-----------|-----------|
| 28 | get_board_activities | board_id?, limit? | Atividades recentes dos boards |
| 29 | list_boards | — | Lista boards ativos com IDs |
| 30 | get_governance_docs | doc_type? | Documentos de governança |
| 31 | get_manual_section | section?, lang? | Seções do Manual de Governança |
| 32 | get_comms_dashboard | — | Dashboard de comunicação |
| 33 | get_comms_metrics_by_channel | days? | Métricas por canal social |
| 34 | get_tribe_stats_ranked | tribe_id | Stats da tribo com ranking per-member |
| 35 | search_wiki | query, limit?, domain?, tag? | Busca full-text na wiki |
| 36 | get_wiki_page | path | Página completa da wiki |
| 37 | get_decision_log | filter? | ADRs (decisões arquiteturais) |

### Tier 2 — Líderes (14 escrita)
| # | Ferramenta | Parâmetros | Permissão | Descrição |
|---|-----------|-----------|-----------|-----------|
| 38 | create_board_card | title, description?, priority?, due_date?, tags?, board_id? | write_board | Criar card |
| 39 | update_card_status | card_id, status | write_board | Mover card entre colunas |
| 40 | create_meeting_notes | event_id, content, decisions?, action_items? | write | Criar/editar ata |
| 41 | register_attendance | event_id, member_id, present | write | Registrar presença |
| 42 | register_showcase | event_id, member_id, showcase_type, title?, notes?, duration_min? | write | Protagonismo (15-25 XP) |
| 43 | send_notification_to_tribe | title, body, link? | write | Notificar toda a tribo |
| 44 | create_tribe_event | title, date, type?, duration_minutes? | write | Criar reunião ou evento |
| 45 | drop_event_instance | event_id | write | Cancelar evento (rejeita se tem presença) |
| 46 | update_event_instance | event_id, new_date?, new_time_start?, new_duration_minutes?, meeting_link?, notes?, agenda_text? | write | Editar evento |
| 47 | mark_member_excused | event_id, member_id, excused?, reason? | write | Marcar falta justificada |
| 48 | bulk_mark_excused | member_id, date_from, date_to, reason? | write | Justificar período inteiro |
| 49 | manage_partner | action, id?, name?, entity_type?, status?, contact_name?, contact_email?, notes?, chapter? | manage_partner | Criar/atualizar parceria |
| 50 | submit_chapter_need | category, title, description? | manage_partner | Reportar necessidade do capítulo |
| 51 | promote_to_leader_track | application_id, create_leader_app? | promote | Promover candidato p/ track líder |

### Tier 3 — GP/Admin (23 leitura)
| # | Ferramenta | Parâmetros | Permissão | Descrição |
|---|-----------|-----------|-----------|-----------|
| 52 | get_tribe_dashboard | tribe_id? | — | Dashboard completo da tribo |
| 53 | get_tribe_deliverables | tribe_id?, cycle_code? | — | Entregas por tribo e ciclo |
| 54 | get_portfolio_overview | — | manage_member | Visão executiva: boards e cards |
| 55 | get_operational_alerts | — | manage_member | Alertas: inatividade, atrasos |
| 56 | get_cycle_report | — | manage_member | Relatório do ciclo |
| 57 | get_annual_kpis | — | manage_member \\| manage_partner | KPIs anuais |
| 58 | get_portfolio_health | cycle_code? | manage_member \\| manage_partner | Saúde trimestral |
| 59 | get_adoption_metrics | — | manage_member | Métricas de adoção MCP |
| 60 | get_curation_dashboard | — | manage_member | Curadoria: pendentes, SLA |
| 61 | get_anomaly_report | — | manage_member | Anomalias de dados |
| 62 | get_volunteer_funnel | cycle? | manage_member | Funil de seleção |
| 63 | get_campaign_analytics | send_id? | manage_member \\| write | Métricas de email |
| 64 | get_partner_pipeline | — | manage_partner | Pipeline de parcerias |
| 65 | get_admin_dashboard | — | manage_member | Dashboard admin geral |
| 66 | get_ghost_visitors | — | manage_member | Visitantes fantasma |
| 67 | search_members | query?, tribe_id?, tier?, status? | manage_member | Buscar membros |
| 68 | get_chapter_kpis | chapter? | manage_member \\| manage_partner (cross-chapter) | KPIs por capítulo |
| 69 | get_chapter_needs | chapter? | — | Necessidades do capítulo |
| 70 | get_tribes_comparison | — | — | Comparação cross-tribe |
| 71 | get_research_pipeline | — | — | Pipeline de pesquisa global |
| 72 | get_selection_rankings | cycle_code?, track? | manage_member | Rankings de seleção (CR-047) |
| 73 | get_application_score_breakdown | application_id | manage_member | Breakdown de scores individuais |
| 74 | get_wiki_health | — | — | Relatório de saúde da wiki |
| 75 | list_initiatives | kind?, status? | — | Lista iniciativas (filtro por tipo/status) |
| 76 | manage_initiative_engagement | initiative_id, person_id, kind, role?, action | manage_member | Add/remove/update membro em iniciativa |

## Notas
- Escrita usa \`canV4(action)\` — permissão derivada de engagements (ADR-0007)
- create_board_card/update_card_status: \`write_board\` inclui researcher/facilitator/communicator na própria tribo
- manage_partner: sponsors e chapter_liaisons
- submit_chapter_need: chapter_board, sponsors, chapter_liaisons via \`manage_partner\`
- \`initiative_id\` (UUID) é o identificador canônico V4. \`tribe_id\` (1-8) mantido por dual-write.
- Todas as chamadas logadas em mcp_usage_log
`,
      }],
    })
  );
}

// --- Register 94 tools (70R + 24W) ---

function registerTools(mcp: McpServer, sb: ReturnType<typeof createClient>) {

  // ===== READ TOOLS (1-10, 16-19, 20-23) =====

  // TOOL 1: get_my_profile
  mcp.tool("get_my_profile", "Returns your member profile: name, role, tribe, XP, badges, certifications.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_profile", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.from("members").select("name, operational_role, designations, tribe_id, chapter, is_active, current_cycle_active, credly_url, cpmai_certified").eq("id", member.id).single();
    if (error) { await logUsage(sb, member.id, "get_my_profile", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_profile", true, undefined, start);
    return ok(data);
  });

  // TOOL 2: get_my_board_status
  mcp.tool("get_my_board_status", "Returns board cards grouped by status.", { board_id: z.string().optional().describe("Board UUID. If omitted, returns your tribe's default board."), tribe_id: z.number().optional().describe("Tribe ID (1-8). If omitted, uses your assigned tribe.") }, async (params: { board_id?: string; tribe_id?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_board_status", false, "Not authenticated", start); return err("Not authenticated"); }
    let boardId = params.board_id;
    if (boardId && !isUUID(boardId)) { await logUsage(sb, member.id, "get_my_board_status", false, "Invalid board_id", start); return err("board_id must be a UUID (e.g. '550e8400-e29b-...'). Did you mean tribe_id? Use list_boards to find board UUIDs."); }
    if (!boardId) {
      const tribeId = params.tribe_id || member.tribe_id;
      if (!tribeId) { await logUsage(sb, member.id, "get_my_board_status", false, "No tribe", start); return err(NO_TRIBE_HINT); }
      const initiativeId = await resolveInitiativeId(sb, tribeId);
      if (!initiativeId) { await logUsage(sb, member.id, "get_my_board_status", false, "Initiative not found", start); return err("Initiative not found for tribe " + tribeId); }
      const { data: b, error: bErr } = await sb.from("project_boards").select("id").eq("initiative_id", initiativeId).limit(1).maybeSingle();
      if (bErr) { await logUsage(sb, member.id, "get_my_board_status", false, bErr.message, start); return err(bErr.message); }
      boardId = b?.id;
    }
    if (!boardId) { await logUsage(sb, member.id, "get_my_board_status", false, "No board", start); return err("No board found for this tribe. Use list_boards to see available boards."); }
    const { data: items, error } = await sb.from("board_items").select("id, title, status, tags, due_date").eq("board_id", boardId).neq("status", "archived").order("position", { ascending: true });
    if (error) { await logUsage(sb, member.id, "get_my_board_status", false, error.message, start); return err(error.message); }
    const grouped = { backlog: items.filter((i: any) => i.status === "backlog"), in_progress: items.filter((i: any) => i.status === "in_progress"), review: items.filter((i: any) => i.status === "review"), done: items.filter((i: any) => i.status === "done") };
    await logUsage(sb, member.id, "get_my_board_status", true, undefined, start);
    return ok(grouped);
  });

  // TOOL 3: get_my_tribe_attendance
  mcp.tool("get_my_tribe_attendance", "Returns attendance grid for your tribe members.", { tribe_id: z.number().optional().describe("Tribe ID (1-8). If omitted, uses your assigned tribe.") }, async (params: { tribe_id?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_tribe_attendance", false, "Not authenticated", start); return err("Not authenticated"); }
    const tribeId = params.tribe_id || member.tribe_id;
    if (!tribeId) { await logUsage(sb, member.id, "get_my_tribe_attendance", false, "No tribe", start); return err(NO_TRIBE_HINT); }
    const initiativeId = await resolveInitiativeId(sb, tribeId);
    if (!initiativeId) { await logUsage(sb, member.id, "get_my_tribe_attendance", false, "Initiative not found", start); return err("Initiative not found for tribe " + tribeId); }
    const { data, error } = await sb.rpc("get_initiative_attendance_grid", { p_initiative_id: initiativeId });
    if (error) { await logUsage(sb, member.id, "get_my_tribe_attendance", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_tribe_attendance", true, undefined, start);
    return ok(data);
  });

  // TOOL 4: get_my_tribe_members
  mcp.tool("get_my_tribe_members", "Returns the list of active members in your tribe with their roles.", { tribe_id: z.number().optional().describe("Tribe ID (1-8). If omitted, uses your assigned tribe.") }, async (params: { tribe_id?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_tribe_members", false, "Not authenticated", start); return err("Not authenticated"); }
    const tribeId = params.tribe_id || member.tribe_id;
    if (!tribeId) { await logUsage(sb, member.id, "get_my_tribe_members", false, "No tribe", start); return err(NO_TRIBE_HINT); }
    const { data, error } = await sb.from("public_members").select("name, operational_role, designations, chapter, current_cycle_active").eq("tribe_id", tribeId).eq("current_cycle_active", true).order("name");
    if (error) { await logUsage(sb, member.id, "get_my_tribe_members", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_tribe_members", true, undefined, start);
    return ok(data);
  });

  // TOOL 5: get_upcoming_events
  mcp.tool("get_upcoming_events", "Returns events scheduled in the next 7 days.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    const today = new Date().toISOString().split("T")[0];
    const nextWeek = new Date(Date.now() + 7 * 86400000).toISOString().split("T")[0];
    const { data, error } = await sb.from("events").select("id, title, date, type, initiative:initiatives(legacy_tribe_id), duration_minutes, meeting_link").gte("date", today).lte("date", nextWeek).order("date");
    if (error) { await logUsage(sb, member?.id, "get_upcoming_events", false, error.message, start); return err(error.message); }
    const flattened = (data || []).map((ev: any) => ({ ...ev, tribe_id: ev.initiative?.legacy_tribe_id ?? null, initiative: undefined }));
    await logUsage(sb, member?.id, "get_upcoming_events", true, undefined, start);
    return ok(flattened);
  });

  // TOOL 6: get_my_xp_and_ranking
  mcp.tool("get_my_xp_and_ranking", "Returns your XP breakdown by category and your position in the leaderboard.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_xp_and_ranking", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_member_cycle_xp", { p_member_id: member.id });
    if (error) { await logUsage(sb, member.id, "get_my_xp_and_ranking", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_xp_and_ranking", true, undefined, start);
    return ok(data);
  });

  // TOOL 7: get_meeting_notes (unified — reads from events.minutes_text)
  mcp.tool("get_meeting_notes", "Returns recent meeting notes/minutes for your tribe. Full Markdown content from events.", { tribe_id: z.number().optional().describe("Tribe ID (1-8). If omitted, uses your assigned tribe."), limit: z.number().optional().describe("Number of recent notes. Default: 5") }, async (params: { tribe_id?: number; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_meeting_notes", false, "Not authenticated", start); return err("Not authenticated"); }
    const tribeId = params.tribe_id || member.tribe_id;
    if (!tribeId) { await logUsage(sb, member.id, "get_meeting_notes", false, "No tribe", start); return err(NO_TRIBE_HINT); }
    const initiativeId = await resolveInitiativeId(sb, tribeId);
    if (!initiativeId) { await logUsage(sb, member.id, "get_meeting_notes", false, "Initiative not found", start); return err("Initiative not found for tribe " + tribeId); }
    const { data, error } = await sb.from("events")
      .select("id, title, date, type, initiative_id, minutes_text, minutes_posted_at, minutes_posted_by, minutes_edited_at, agenda_text, youtube_url, duration_minutes")
      .eq("initiative_id", initiativeId)
      .not("minutes_text", "is", null)
      .order("date", { ascending: false })
      .limit(params.limit || 5);
    if (error) { await logUsage(sb, member.id, "get_meeting_notes", false, error.message, start); return err(error.message); }
    // Enrich with posted_by name and attendee count
    const enriched = await Promise.all((data || []).map(async (ev: any) => {
      let posted_by_name = null;
      if (ev.minutes_posted_by) {
        const { data: m } = await sb.from("members").select("name").eq("id", ev.minutes_posted_by).maybeSingle();
        posted_by_name = m?.name || null;
      }
      const { count } = await sb.from("attendance").select("id", { count: "exact", head: true }).eq("event_id", ev.id);
      return { ...ev, tribe_id: tribeId, minutes_posted_by_name: posted_by_name, attendee_count: count || 0 };
    }));
    await logUsage(sb, member.id, "get_meeting_notes", true, undefined, start);
    return ok(enriched);
  });

  // TOOL 8: get_my_notifications
  mcp.tool("get_my_notifications", "Returns your unread notifications.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    const { data, error } = await sb.rpc("get_my_notifications");
    if (error) { await logUsage(sb, member?.id, "get_my_notifications", false, error.message, start); return err(error.message); }
    await logUsage(sb, member?.id, "get_my_notifications", true, undefined, start);
    return ok(data);
  });

  // TOOL 9: search_board_cards
  mcp.tool("search_board_cards", "Full-text search across board cards. Specify tribe_id or searches your tribe.", { query: z.string().describe("Search term"), tribe_id: z.number().optional().describe("Tribe ID (1-8). If omitted, uses your assigned tribe.") }, async (params: { query: string; tribe_id?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "search_board_cards", false, "Not authenticated", start); return err("Not authenticated"); }
    const tribeId = params.tribe_id || member.tribe_id;
    if (!tribeId) { await logUsage(sb, member.id, "search_board_cards", false, "No tribe", start); return err(NO_TRIBE_HINT); }
    const initiativeId = await resolveInitiativeId(sb, tribeId);
    if (!initiativeId) { await logUsage(sb, member.id, "search_board_cards", false, "Initiative not found", start); return err("Initiative not found for tribe " + tribeId); }
    const { data, error } = await sb.rpc("search_initiative_board_items", { p_query: params.query, p_initiative_id: initiativeId });
    if (error) { await logUsage(sb, member.id, "search_board_cards", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "search_board_cards", true, undefined, start);
    return ok(data);
  });

  // TOOL 10: get_hub_announcements
  mcp.tool("get_hub_announcements", "Returns active announcements from the Hub.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    const now = new Date().toISOString();
    const { data, error } = await sb.from("announcements").select("id, title, message, message_en, message_es, type, link_url, link_text, starts_at, ends_at").eq("is_active", true).lte("starts_at", now).order("created_at", { ascending: false }).limit(5);
    if (error) { await logUsage(sb, member?.id, "get_hub_announcements", false, error.message, start); return err(error.message); }
    await logUsage(sb, member?.id, "get_hub_announcements", true, undefined, start);
    return ok(data);
  });

  // ===== WRITE TOOLS (11-15, 18) =====

  // TOOL 11: create_board_card
  mcp.tool("create_board_card", "Create a new card on a board. If board_id is omitted, uses your tribe's default board.", { title: z.string().describe("Card title"), description: z.string().optional().describe("Card description"), priority: z.string().optional().describe("low|medium|high|urgent"), due_date: z.string().optional().describe("Due date YYYY-MM-DD"), tags: z.string().optional().describe("Comma-separated tags"), board_id: z.string().optional().describe("UUID of the board. Required if you have no tribe_id.") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "create_board_card", false, "Not authenticated", start); return err("Not authenticated"); }
    let boardId = params.board_id;
    if (boardId && !isUUID(boardId)) { await logUsage(sb, member.id, "create_board_card", false, "Invalid board_id", start); return err("board_id must be a UUID. Use list_boards to find board UUIDs."); }
    if (!boardId) {
      if (!member.tribe_id) { await logUsage(sb, member.id, "create_board_card", false, "No board", start); return err("No tribe assigned. Pass board_id explicitly. Use list_boards to find board UUIDs."); }
      const initiativeId = await resolveInitiativeId(sb, member.tribe_id);
      if (!initiativeId) { await logUsage(sb, member.id, "create_board_card", false, "Initiative not found", start); return err("Initiative not found for your tribe."); }
      const { data: board, error: boardErr } = await sb.from("project_boards").select("id").eq("initiative_id", initiativeId).limit(1).maybeSingle();
      if (boardErr) { await logUsage(sb, member.id, "create_board_card", false, boardErr.message, start); return err(boardErr.message); }
      if (!board) { await logUsage(sb, member.id, "create_board_card", false, "No board", start); return err("No board found for your tribe."); }
      boardId = board.id;
    }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "create_board_card", false, "Unauthorized", start); return err("Unauthorized — researchers can only create cards on their own tribe's board."); }
    const tags = params.tags ? String(params.tags).split(",").map((t: string) => t.trim()) : [];
    if (params.priority && params.priority !== "medium") tags.push(`priority:${params.priority}`);
    const { data: cardId, error } = await sb.rpc("create_board_item", { p_board_id: boardId, p_title: params.title, p_description: params.description || null, p_tags: tags, p_due_date: params.due_date || null });
    if (error) { await logUsage(sb, member.id, "create_board_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "create_board_card", true, undefined, start);
    return ok({ action: "create_board_card", status: "created", id: cardId });
  });

  // TOOL 12: update_card_status
  mcp.tool("update_card_status", "Move a card to a different status column.", { card_id: z.string().describe("UUID of the card"), status: z.string().describe("backlog|in_progress|review|done|archived") }, async (params: { card_id: string; status: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "update_card_status", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "update_card_status", false, "Unauthorized", start); return err("Unauthorized — researchers can only move cards on their own tribe's board."); }
    const { error } = await sb.rpc("move_board_item", { p_item_id: params.card_id, p_new_status: params.status });
    if (error) { await logUsage(sb, member.id, "update_card_status", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "update_card_status", true, undefined, start);
    return ok({ action: "update_card_status", status: "updated", card_id: params.card_id, new_status: params.status });
  });

  // TOOL 13: create_meeting_notes (unified — writes to events.minutes_text via upsert_event_minutes RPC)
  mcp.tool("create_meeting_notes", "Create or update meeting minutes for a tribe meeting. Writes to events.minutes_text with audit trail.", { event_id: z.string().describe("UUID of the event"), content: z.string().describe("Notes content (Markdown)"), decisions: z.string().optional().describe("Key decisions (comma-separated) — appended to content"), action_items: z.string().optional().describe("Action items (comma-separated) — appended to content") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "create_meeting_notes", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "create_meeting_notes", false, "Unauthorized", start); return err("Unauthorized"); }
    // Build full content with optional decisions and action items
    let fullContent = params.content;
    const decisions = params.decisions ? String(params.decisions).split(",").map((s: string) => s.trim()).filter(Boolean) : [];
    const actionItems = params.action_items ? String(params.action_items).split(",").map((s: string) => s.trim()).filter(Boolean) : [];
    if (decisions.length > 0) fullContent += "\n\n### Decisões\n" + decisions.map((d: string) => `- ${d}`).join("\n");
    if (actionItems.length > 0) fullContent += "\n\n### Ações\n" + actionItems.map((a: string) => `- [ ] ${a}`).join("\n");
    // Use the unified upsert_event_minutes RPC (has audit log + edit history + researcher timeframe)
    const { data, error } = await sb.rpc("upsert_event_minutes", { p_event_id: params.event_id, p_text: fullContent });
    if (error) { await logUsage(sb, member.id, "create_meeting_notes", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "create_meeting_notes", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "create_meeting_notes", true, undefined, start);
    return ok({ action: "create_meeting_notes", status: "saved", event_id: params.event_id });
  });

  // TOOL 14: register_attendance
  mcp.tool("register_attendance", "Register attendance for a member at an event.", { event_id: z.string().describe("UUID of the event"), member_id: z.string().describe("UUID of the member"), present: z.boolean().describe("Whether present") }, async (params: { event_id: string; member_id: string; present: boolean }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "register_attendance", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "register_attendance", false, "Unauthorized", start); return err("Unauthorized"); }
    if (!params.present) { await logUsage(sb, member.id, "register_attendance", true, undefined, start); return ok({ action: "register_attendance", status: "skipped", note: "Absent — no record created." }); }
    const { data: count, error } = await sb.rpc("register_attendance_batch", { p_event_id: params.event_id, p_member_ids: [params.member_id], p_registered_by: member.id });
    if (error) { await logUsage(sb, member.id, "register_attendance", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "register_attendance", true, undefined, start);
    return ok({ action: "register_attendance", status: "registered", records_affected: count });
  });

  // TOOL 14b: register_showcase
  mcp.tool("register_showcase", "Register a showcase/protagonist presentation for a member at a general meeting. Awards 15-25 XP depending on type.", { event_id: z.string().describe("UUID of the event"), member_id: z.string().describe("UUID of the presenting member"), showcase_type: z.enum(["case_study", "tool_review", "prompt_week", "quick_insight", "awareness"]).describe("Type: case_study (25XP), tool_review (20XP), prompt_week (20XP), quick_insight (15XP), awareness (15XP)"), title: z.string().optional().describe("Title of the presentation"), notes: z.string().optional().describe("Brief description"), duration_min: z.number().optional().describe("Duration in minutes") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "register_showcase", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "register_showcase", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data, error } = await sb.rpc("register_event_showcase", { p_event_id: params.event_id, p_member_id: params.member_id, p_showcase_type: params.showcase_type, p_title: params.title || null, p_notes: params.notes || null, p_duration_min: params.duration_min || null });
    if (error) { await logUsage(sb, member.id, "register_showcase", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "register_showcase", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "register_showcase", true, undefined, start);
    return ok({ action: "register_showcase", ...data });
  });

  // TOOL 15: send_notification_to_tribe
  mcp.tool("send_notification_to_tribe", "Send a notification to all active members of your tribe.", { title: z.string().describe("Notification title"), body: z.string().describe("Notification message"), link: z.string().optional().describe("URL link") }, async (params: { title: string; body: string; link?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "send_notification_to_tribe", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "send_notification_to_tribe", false, "Unauthorized", start); return err("Unauthorized"); }
    if (!member.tribe_id && !member.is_superadmin) { await logUsage(sb, member.id, "send_notification_to_tribe", false, "No tribe", start); return err("No tribe assigned."); }
    const query = sb.from("members").select("id").eq("is_active", true).eq("current_cycle_active", true).neq("id", member.id);
    if (!member.is_superadmin) query.eq("tribe_id", member.tribe_id);
    const { data: members, error: membersErr } = await query;
    if (membersErr) { await logUsage(sb, member.id, "send_notification_to_tribe", false, membersErr.message, start); return err(membersErr.message); }
    if (!members?.length) { await logUsage(sb, member.id, "send_notification_to_tribe", false, "No members", start); return err("No active tribe members found."); }
    let sent = 0;
    for (const m of members) { const { error: e } = await sb.rpc("create_notification", { p_recipient_id: m.id, p_type: "tribe_broadcast", p_title: params.title, p_body: params.body, p_link: params.link || null }); if (!e) sent++; }
    await logUsage(sb, member.id, "send_notification_to_tribe", true, undefined, start);
    return ok({ action: "send_notification_to_tribe", status: "sent", recipients: sent, total_members: members.length });
  });

  // ===== GC-161 TOOLS (16-19) =====

  // TOOL 16: get_my_attendance_history
  mcp.tool("get_my_attendance_history", "Returns your personal attendance history — which meetings you attended or missed.", { limit: z.number().optional().describe("Number of recent events. Default: 30") }, async (params: { limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_attendance_history", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_attendance_history", { p_limit: params.limit || 30 });
    if (error) { await logUsage(sb, member.id, "get_my_attendance_history", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_attendance_history", true, undefined, start);
    const attended = (data || []).filter((r: any) => r.present).length;
    const total = (data || []).length;
    return ok({ summary: { attended, total, rate_percent: total > 0 ? Math.round((attended / total) * 100) : 0 }, events: data });
  });

  // TOOL 17: list_tribe_webinars
  mcp.tool("list_tribe_webinars", "Returns webinars for your tribe or chapter.", { status: z.string().optional().describe("planned|confirmed|completed|cancelled") }, async (params: { status?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_tribe_webinars", false, "Not authenticated", start); return err("Not authenticated"); }
    const rpcParams: any = {};
    if (params.status) rpcParams.p_status = params.status;
    if (member.tribe_id) rpcParams.p_tribe_id = member.tribe_id;
    const { data, error } = await sb.rpc("list_webinars_v2", rpcParams);
    if (error) { await logUsage(sb, member.id, "list_tribe_webinars", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_tribe_webinars", true, undefined, start);
    return ok(data);
  });

  // TOOL 18: create_tribe_event (WRITE)
  mcp.tool("create_tribe_event", "Create a new tribe meeting or event. Leaders and managers only.", { title: z.string().describe("Event title"), date: z.string().describe("YYYY-MM-DD"), type: z.string().optional().describe("tribo|webinar|comms|lideranca"), duration_minutes: z.number().optional().describe("Duration in minutes. Default: 90") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "create_tribe_event", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "create_tribe_event", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data, error } = await sb.rpc("create_event", { p_type: params.type || "tribo", p_title: params.title, p_date: params.date, p_duration_minutes: params.duration_minutes || 90, p_tribe_id: member.tribe_id });
    if (error) { await logUsage(sb, member.id, "create_tribe_event", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "create_tribe_event", true, undefined, start);
    return ok({ action: "create_tribe_event", status: "created", result: data });
  });

  // TOOL 19: get_comms_pending_webinars
  mcp.tool("get_comms_pending_webinars", "Returns webinars that need communication action.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_comms_pending_webinars", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("webinars_pending_comms");
    if (error) { await logUsage(sb, member.id, "get_comms_pending_webinars", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_comms_pending_webinars", true, undefined, start);
    return ok(data);
  });

  // ===== GC-164 TOOLS (20-23) =====

  // TOOL 20: get_my_certificates
  mcp.tool("get_my_certificates", "Returns your certifications, badges, and trails.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_certificates", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_certificates");
    if (error) { await logUsage(sb, member.id, "get_my_certificates", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_certificates", true, undefined, start);
    const certs = data?.certificates || data || [];
    return ok({ total: Array.isArray(certs) ? certs.length : 0, certificates: certs });
  });

  // TOOL 21: search_hub_resources
  mcp.tool("search_hub_resources", "Search the resource library (247+ items) by keyword.", { query: z.string().describe("Search term"), asset_type: z.string().optional().describe("article|video|tool|template|course|book|podcast|other"), limit: z.number().optional().describe("Max results. Default: 15") }, async (params: { query: string; asset_type?: string; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "search_hub_resources", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("search_hub_resources", { p_query: params.query, p_asset_type: params.asset_type || null, p_limit: params.limit || 15 });
    if (error) { await logUsage(sb, member.id, "search_hub_resources", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "search_hub_resources", true, undefined, start);
    return ok({ query: params.query, results: (data || []).length, resources: data });
  });

  // TOOL 22: get_adoption_metrics
  mcp.tool("get_adoption_metrics", "Returns MCP adoption metrics. Admin/GP only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_adoption_metrics", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_adoption_metrics", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("get_mcp_adoption_stats");
    if (error) { await logUsage(sb, member.id, "get_adoption_metrics", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_adoption_metrics", true, undefined, start);
    return ok(data);
  });

  // TOOL 23: get_chapter_kpis
  mcp.tool("get_chapter_kpis", "Returns KPIs for a chapter. Liaisons and admins can query any chapter.", { chapter: z.string().optional().describe("Chapter code: GO|CE|DF|MG|RS") }, async (params: { chapter?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_chapter_kpis", false, "Not authenticated", start); return err("Not authenticated"); }
    let chapter = params.chapter || member.chapter;
    if (!chapter) { await logUsage(sb, member.id, "get_chapter_kpis", false, "No chapter", start); return err("No chapter assigned. Specify: GO, CE, DF, MG, RS."); }
    const isPrivileged = (await canV4(sb, member.id, 'manage_member')) || (await canV4(sb, member.id, 'manage_partner'));
    if (!isPrivileged && chapter !== member.chapter) { await logUsage(sb, member.id, "get_chapter_kpis", false, "Cross-chapter denied", start); return err("You can only view your own chapter."); }
    const { data, error } = await sb.rpc("get_chapter_dashboard", { p_chapter: chapter });
    if (error) { await logUsage(sb, member.id, "get_chapter_kpis", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_chapter_kpis", true, undefined, start);
    return ok({ chapter, kpis: data });
  });

  // ===== SPRINT 7 TOOLS (24-26) =====

  // TOOL 24: get_tribe_dashboard
  mcp.tool("get_tribe_dashboard", "Returns a full tribe dashboard: members, cards, attendance, XP, meetings. Leaders and admins.", { tribe_id: z.number().optional().describe("Tribe ID (1-8). If omitted, uses your tribe.") }, async (params: { tribe_id?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_tribe_dashboard", false, "Not authenticated", start); return err("Not authenticated"); }
    const tribeId = params.tribe_id || member.tribe_id;
    if (!tribeId) { await logUsage(sb, member.id, "get_tribe_dashboard", false, "No tribe", start); return err(NO_TRIBE_HINT); }
    const initiativeId = await resolveInitiativeId(sb, tribeId);
    if (!initiativeId) { await logUsage(sb, member.id, "get_tribe_dashboard", false, "Initiative not found", start); return err("Initiative not found for tribe " + tribeId); }
    const { data, error } = await sb.rpc("exec_initiative_dashboard", { p_initiative_id: initiativeId });
    if (error) { await logUsage(sb, member.id, "get_tribe_dashboard", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_tribe_dashboard", true, undefined, start);
    return ok(data);
  });

  // TOOL 25: get_attendance_ranking
  mcp.tool("get_attendance_ranking", "Returns the attendance ranking — members sorted by attendance rate and total meetings.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_attendance_ranking", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_attendance_panel");
    if (error) { await logUsage(sb, member.id, "get_attendance_ranking", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_attendance_ranking", true, undefined, start);
    return ok(data);
  });

  // TOOL 26: get_portfolio_overview
  mcp.tool("get_portfolio_overview", "Returns the executive portfolio overview — all boards, cards, statuses, and overdue items. Admin/GP only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_portfolio_overview", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_portfolio_overview", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("get_portfolio_dashboard");
    if (error) { await logUsage(sb, member.id, "get_portfolio_overview", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_portfolio_overview", true, undefined, start);
    return ok(data);
  });

  // ===== SPRINT 9 TOOLS (27-29) — Tier 2 =====

  // TOOL 27: get_operational_alerts
  mcp.tool("get_operational_alerts", "Returns operational alerts — inactivity, overdue cards, taxonomy drift. Admin/GP only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_operational_alerts", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_operational_alerts", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("detect_operational_alerts");
    if (error) { await logUsage(sb, member.id, "get_operational_alerts", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_operational_alerts", true, undefined, start);
    return ok(data);
  });

  // TOOL 28: get_cycle_report
  mcp.tool("get_cycle_report", "Returns a full cycle report — members, tribes, attendance, deliverables, KPIs. Admin/GP only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_cycle_report", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_cycle_report", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("exec_cycle_report");
    if (error) { await logUsage(sb, member.id, "get_cycle_report", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_cycle_report", true, undefined, start);
    return ok(data);
  });

  // TOOL 29: get_annual_kpis
  mcp.tool("get_annual_kpis", "Returns annual KPIs — targets vs actuals across all areas. Admin/Sponsor only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_annual_kpis", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member')) && !(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "get_annual_kpis", false, "Unauthorized", start); return err("Unauthorized: admin/sponsor only."); }
    const { data, error } = await sb.rpc("get_annual_kpis");
    if (error) { await logUsage(sb, member.id, "get_annual_kpis", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_annual_kpis", true, undefined, start);
    return ok(data);
  });

  // ===== P1 WAVE — 7 new tools (30-36) =====

  // TOOL 30: get_event_detail — All authenticated members
  mcp.tool("get_event_detail", "Returns full event detail: agenda, minutes, action items, attendance.", { event_id: z.string().describe("UUID of the event") }, async (params: { event_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_event_detail", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_event_detail", { p_event_id: params.event_id });
    if (error) { await logUsage(sb, member.id, "get_event_detail", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "get_event_detail", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "get_event_detail", true, undefined, start);
    return ok(data);
  });

  // TOOL 31: get_comms_dashboard — Comms team + Admin
  mcp.tool("get_comms_dashboard", "Returns communications dashboard: publications by status/format, backlog, overdue items. Requires comms_leader, admin, or manager role.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_comms_dashboard", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member')) && !(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "get_comms_dashboard", false, "Unauthorized", start); return err("Unauthorized: admin/comms only."); }
    const { data, error } = await sb.rpc("get_comms_dashboard_metrics");
    if (error) { await logUsage(sb, member.id, "get_comms_dashboard", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_comms_dashboard", true, undefined, start);
    return ok(data);
  });

  // TOOL 32: get_campaign_analytics — Comms team + Admin
  mcp.tool("get_campaign_analytics", "Returns email campaign analytics: opens, clicks, bounces. Admin/Comms only.", { send_id: z.string().optional().describe("UUID of specific campaign send. If omitted, returns all campaigns.") }, async (params: { send_id?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_campaign_analytics", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member')) && !(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "get_campaign_analytics", false, "Unauthorized", start); return err("Unauthorized: admin/comms only."); }
    const { data, error } = await sb.rpc("get_campaign_analytics", { p_send_id: params.send_id || null });
    if (error) { await logUsage(sb, member.id, "get_campaign_analytics", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_campaign_analytics", true, undefined, start);
    return ok(data);
  });

  // TOOL 33: get_partner_pipeline — Sponsors + Admin
  mcp.tool("get_partner_pipeline", "Returns partner pipeline: entities by status, stale alerts, contact info. Sponsors/Admin only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_partner_pipeline", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "get_partner_pipeline", false, "Unauthorized", start); return err("Unauthorized: sponsors/admin only."); }
    const { data, error } = await sb.rpc("get_partner_pipeline");
    if (error) { await logUsage(sb, member.id, "get_partner_pipeline", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_partner_pipeline", true, undefined, start);
    return ok(data);
  });

  // TOOL 34: get_public_impact_data — All authenticated members
  mcp.tool("get_public_impact_data", "Returns public impact data: chapters, members, publications, partners, timeline, recognitions.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_public_impact_data", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_public_impact_data");
    if (error) { await logUsage(sb, member.id, "get_public_impact_data", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_public_impact_data", true, undefined, start);
    return ok(data);
  });

  // TOOL 35: get_curation_dashboard — GP/Admin
  mcp.tool("get_curation_dashboard", "Returns curation workflow dashboard: pending items, SLA compliance, reviewer stats. Admin only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_curation_dashboard", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_curation_dashboard", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("get_curation_dashboard");
    if (error) { await logUsage(sb, member.id, "get_curation_dashboard", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_curation_dashboard", true, undefined, start);
    return ok(data);
  });

  // TOOL 36: get_tribe_deliverables — Leaders + Admin
  mcp.tool("get_tribe_deliverables", "Returns deliverables for a tribe: status, deadlines, cycle tracking.", { tribe_id: z.number().optional().describe("Tribe ID (1-8). If omitted, uses your tribe."), cycle_code: z.string().optional().describe("Cycle code. Default: current cycle.") }, async (params: { tribe_id?: number; cycle_code?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_tribe_deliverables", false, "Not authenticated", start); return err("Not authenticated"); }
    const tribeId = params.tribe_id || member.tribe_id;
    if (!tribeId) { await logUsage(sb, member.id, "get_tribe_deliverables", false, "No tribe", start); return err(NO_TRIBE_HINT); }
    const initiativeId = await resolveInitiativeId(sb, tribeId);
    if (!initiativeId) { await logUsage(sb, member.id, "get_tribe_deliverables", false, "Initiative not found", start); return err("Initiative not found for tribe " + tribeId); }
    const { data, error } = await sb.rpc("list_initiative_deliverables", { p_initiative_id: initiativeId, p_cycle_code: params.cycle_code || null });
    if (error) { await logUsage(sb, member.id, "get_tribe_deliverables", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_tribe_deliverables", true, undefined, start);
    return ok(data);
  });

  // ===== P2 WAVE — 4 new tools (37-40) =====

  // TOOL 37: get_pilots_summary — Sponsors + Admin
  mcp.tool("get_pilots_summary", "Returns AI pilot projects summary: status, metrics, hypothesis, progress.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_pilots_summary", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_pilots_summary");
    if (error) { await logUsage(sb, member.id, "get_pilots_summary", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_pilots_summary", true, undefined, start);
    return ok(data);
  });

  // TOOL 38: get_comms_metrics_by_channel — Comms team + Admin
  mcp.tool("get_comms_metrics_by_channel", "Returns latest communication metrics by channel (LinkedIn, Instagram, YouTube). Comms/Admin only.", { days: z.number().optional().describe("Lookback period in days. Default: 14") }, async (params: { days?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_comms_metrics_by_channel", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("comms_metrics_latest_by_channel", { p_days: params.days || 14 });
    if (error) { await logUsage(sb, member.id, "get_comms_metrics_by_channel", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_comms_metrics_by_channel", true, undefined, start);
    return ok(data);
  });

  // TOOL 39: get_anomaly_report — Admin only
  mcp.tool("get_anomaly_report", "Returns data quality anomaly report: inconsistencies, duplicates, drift. Admin only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_anomaly_report", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_anomaly_report", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("admin_get_anomaly_report");
    if (error) { await logUsage(sb, member.id, "get_anomaly_report", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_anomaly_report", true, undefined, start);
    return ok(data);
  });

  // TOOL 40: get_portfolio_health — Admin/Sponsor
  mcp.tool("get_portfolio_health", "Returns quarterly portfolio health: KPIs with targets vs actuals, traffic-light status. Admin/Sponsor only.", { cycle_code: z.string().optional().describe("Cycle code. Default: cycle3-2026") }, async (params: { cycle_code?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_portfolio_health", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member')) && !(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "get_portfolio_health", false, "Unauthorized", start); return err("Unauthorized: admin/sponsor only."); }
    const { data, error } = await sb.rpc("exec_portfolio_health", { p_cycle_code: params.cycle_code || "cycle3-2026" });
    if (error) { await logUsage(sb, member.id, "get_portfolio_health", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_portfolio_health", true, undefined, start);
    return ok(data);
  });

  // ===== P3 WAVE — 2 new tools (41-42) =====

  // TOOL 41: get_volunteer_funnel — Admin/Selection committee
  mcp.tool("get_volunteer_funnel", "Returns selection funnel (selection_applications): by_cycle/by_status/certifications/geography.", { cycle_code: z.string().optional().describe("Selection cycle code (e.g. cycle3-2026, cycle3-2026-b2). Default: all cycles.") }, async (params: { cycle_code?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_volunteer_funnel", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_volunteer_funnel", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("volunteer_funnel_summary", { p_cycle_code: params.cycle_code ?? null });
    if (error) { await logUsage(sb, member.id, "get_volunteer_funnel", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_volunteer_funnel", true, undefined, start);
    return ok(data);
  });

  // TOOL 42: get_near_events — All authenticated members
  mcp.tool("get_near_events", "Returns events happening soon (within a time window). More immediate than get_upcoming_events.", { window_hours: z.number().optional().describe("Hours before/after now to search. Default: 2") }, async (params: { window_hours?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_near_events", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_near_events", { p_member_id: member.id, p_window_hours: params.window_hours || 2 });
    if (error) { await logUsage(sb, member.id, "get_near_events", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_near_events", true, undefined, start);
    return ok(data);
  });

  // ===== SPRINT 11 TOOLS (43-45) =====

  // TOOL 43: get_current_release — All authenticated members
  mcp.tool("get_current_release", "Returns the current platform release: version, title, date, type.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_current_release", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_current_release");
    if (error) { await logUsage(sb, member.id, "get_current_release", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_current_release", true, undefined, start);
    return ok(data);
  });

  // TOOL 44: get_admin_dashboard — Admin/GP only
  mcp.tool("get_admin_dashboard", "Returns the admin dashboard: member counts, tribe stats, recent activity, system health.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_admin_dashboard", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_admin_dashboard", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("get_admin_dashboard");
    if (error) { await logUsage(sb, member.id, "get_admin_dashboard", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_admin_dashboard", true, undefined, start);
    return ok(data);
  });

  // TOOL 45: get_my_attendance_hours — All authenticated members
  mcp.tool("get_my_attendance_hours", "Returns your attendance hours breakdown for the current cycle.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_attendance_hours", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_member_attendance_hours", { p_member_id: member.id });
    if (error) { await logUsage(sb, member.id, "get_my_attendance_hours", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_attendance_hours", true, undefined, start);
    return ok(data);
  });

  // TOOL 46: get_my_credly_status — All authenticated members
  mcp.tool("get_my_credly_status", "Returns your Credly badge status: badges, verification date, CPMAI certification.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_credly_status", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_credly_status");
    if (error) { await logUsage(sb, member.id, "get_my_credly_status", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "get_my_credly_status", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "get_my_credly_status", true, undefined, start);
    return ok(data);
  });

  // TOOL 47: get_board_activities — All authenticated members
  mcp.tool("get_board_activities", "Returns recent board lifecycle events: status changes, reviews, curation actions.", { board_id: z.string().optional().describe("UUID of the board. If omitted, returns activities across all boards."), limit: z.number().optional().describe("Max events. Default: 20") }, async (params: { board_id?: string; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_board_activities", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_board_activities", { p_board_id: params.board_id || null, p_limit: params.limit || 20 });
    if (error) { await logUsage(sb, member.id, "get_board_activities", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "get_board_activities", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "get_board_activities", true, undefined, start);
    return ok(data);
  });

  // TOOL 48: search_members — Admin/GP
  mcp.tool("search_members", "Search members by name, filter by tribe, tier, or status. Admin/GP only.", {
    query: z.string().optional().describe("Search by name (partial match)"),
    tribe_id: z.number().optional().describe("Filter by tribe (1-8)"),
    tier: z.string().optional().describe("Filter by tier: tier1|tier2|tier3"),
    status: z.string().optional().describe("active|inactive|all. Default: active")
  }, async (params: { query?: string; tribe_id?: number; tier?: string; status?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "search_members", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "search_members", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("admin_list_members", { p_search: params.query || null, p_tribe_id: params.tribe_id || null, p_tier: params.tier || null, p_status: params.status || "active" });
    if (error) { await logUsage(sb, member.id, "search_members", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "search_members", true, undefined, start);
    return ok(data);
  });

  // TOOL 49: list_boards — All authenticated members
  mcp.tool("list_boards", "Returns all active boards with their IDs, names, scope, and tribe. Use this to find board_id for create_board_card.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_boards", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.from("project_boards").select("id, board_name, board_scope, domain_key, initiative:initiatives(legacy_tribe_id)").eq("is_active", true).order("board_scope", { ascending: true });
    if (error) { await logUsage(sb, member.id, "list_boards", false, error.message, start); return err(error.message); }
    const flattened = (data || [])
      .map((b: any) => ({ id: b.id, board_name: b.board_name, board_scope: b.board_scope, domain_key: b.domain_key, tribe_id: b.initiative?.legacy_tribe_id ?? null }))
      .sort((a: any, b: any) => (a.tribe_id ?? 999) - (b.tribe_id ?? 999));
    await logUsage(sb, member.id, "list_boards", true, undefined, start);
    return ok(flattened);
  });

  // TOOL 50: get_governance_docs — All authenticated members
  mcp.tool("get_governance_docs", "Returns governance documents: manual, agreements, volunteer terms.", { doc_type: z.string().optional().describe("Filter: manual|cooperation_agreement|volunteer_term_template") }, async (params: { doc_type?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_governance_docs", false, "Not authenticated", start); return err("Not authenticated"); }
    let query = sb.from("governance_documents").select("id, doc_type, title, version, status, parties, valid_from, valid_until, pdf_url").eq("status", "active").order("created_at", { ascending: false });
    if (params.doc_type) query = query.eq("doc_type", params.doc_type);
    const { data, error } = await query;
    if (error) { await logUsage(sb, member.id, "get_governance_docs", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_governance_docs", true, undefined, start);
    return ok(data);
  });

  // TOOL 50.1: get_pending_ratifications — All authenticated members (RPC scopes by caller eligibility)
  mcp.tool("get_pending_ratifications", "Returns governance documents pending YOUR ratification signoff. Each row includes chain status, version label, locked date, gates config, and the list of gate_kinds you are eligible to sign (curator | leader | president_go | president_others | member_ratification | external_signer). Use sign_ip_ratification (via native UI) to actually sign.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_pending_ratifications", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_pending_ratifications");
    if (error) { await logUsage(sb, member.id, "get_pending_ratifications", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_pending_ratifications", true, undefined, start);
    return ok(data);
  });

  // TOOL 51: get_manual_section — All authenticated members
  mcp.tool("get_manual_section", "Returns a specific section of the Governance Manual by number or keyword search.", { section: z.string().optional().describe("Section number (e.g. '3.1') or keyword to search in title"), lang: z.string().optional().describe("pt|en|es. Default: pt") }, async (params: { section?: string; lang?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_manual_section", false, "Not authenticated", start); return err("Not authenticated"); }
    const langSuffix = params.lang === "en" ? "_en" : params.lang === "es" ? "_es" : "_pt";
    let query = sb.from("manual_sections").select(`section_number, title${langSuffix}, content${langSuffix}, manual_version, page_start, page_end`).eq("is_current", true).order("sort_order");
    if (params.section) {
      // Try exact section number first, then keyword search
      if (/^\d/.test(params.section)) {
        query = query.eq("section_number", params.section);
      } else {
        query = query.ilike(`title${langSuffix}`, `%${params.section}%`);
      }
    }
    const { data, error } = await query.limit(5);
    if (error) { await logUsage(sb, member.id, "get_manual_section", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_manual_section", true, undefined, start);
    return ok(data);
  });

  // TOOL 52: manage_partner — Write: create/update partner entities
  mcp.tool("manage_partner", "Create or update a partner entity in the pipeline. Sponsors/Admin only.", {
    action: z.string().describe("create|update"),
    id: z.string().optional().describe("UUID of partner (required for update)"),
    name: z.string().optional().describe("Partner name (required for create)"),
    entity_type: z.string().optional().describe("pmi_chapter|academia|empresa|community|research|association|outro"),
    status: z.string().optional().describe("prospect|contact|negotiation|active|inactive|churned"),
    contact_name: z.string().optional().describe("Contact person name"),
    contact_email: z.string().optional().describe("Contact email"),
    notes: z.string().optional().describe("Free-text notes"),
    chapter: z.string().optional().describe("Chapter code (e.g. US-WDC, GO, CE)")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "manage_partner", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "manage_partner", false, "Unauthorized", start); return err("Unauthorized — requires admin, sponsor, or chapter liaison role."); }
    const { data, error } = await sb.rpc("admin_manage_partner_entity", {
      p_action: params.action,
      p_id: params.id || null,
      p_name: params.name || null,
      p_entity_type: params.entity_type || null,
      p_status: params.status || null,
      p_contact_name: params.contact_name || null,
      p_contact_email: params.contact_email || null,
      p_notes: params.notes || null,
      p_chapter: params.chapter || null,
    });
    if (error) { await logUsage(sb, member.id, "manage_partner", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "manage_partner", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "manage_partner", true, undefined, start);
    return ok(data);
  });

  // TOOL 53: get_ghost_visitors — Admin only: audit ghost logins (authenticated users without member record)
  mcp.tool("get_ghost_visitors", "Returns ghost visitors: authenticated users with no linked member record. Includes fuzzy member name match. Admin/GP only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_ghost_visitors", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_ghost_visitors", false, "Unauthorized", start); return err("Unauthorized — admin only."); }
    const { data, error } = await sb.rpc("get_ghost_visitors");
    if (error) { await logUsage(sb, member.id, "get_ghost_visitors", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_ghost_visitors", true, undefined, start);
    return ok({ ghost_count: (data || []).length, ghosts: data });
  });

  // TOOL 54: get_chapter_needs — Chapter board, sponsors, liaisons, admin
  mcp.tool("get_chapter_needs", "Returns chapter needs/requests submitted by chapter board members. Shows needs for your chapter (or all for admin).", { chapter: z.string().optional().describe("Chapter code: GO|CE|DF|MG|RS. If omitted, uses your chapter.") }, async (params: { chapter?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_chapter_needs", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_chapter_needs", { p_chapter: params.chapter ? `PMI-${params.chapter.toUpperCase()}` : null });
    if (error) { await logUsage(sb, member.id, "get_chapter_needs", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_chapter_needs", true, undefined, start);
    return ok(data);
  });

  // TOOL 55: submit_chapter_need — Chapter board, sponsors, liaisons (write)
  mcp.tool("submit_chapter_need", "Submit a need or request for your chapter. Board members, sponsors, and liaisons only.", {
    category: z.enum(["research", "tools", "events", "training", "communication", "other"]).describe("Category: research|tools|events|training|communication|other"),
    title: z.string().describe("Short title of the need"),
    description: z.string().optional().describe("Detailed description"),
  }, async (params: { category: string; title: string; description?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "submit_chapter_need", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "submit_chapter_need", false, "Unauthorized", start); return err("Unauthorized: requires chapter board, sponsor, or liaison role."); }
    const { data, error } = await sb.rpc("submit_chapter_need", { p_category: params.category, p_title: params.title, p_description: params.description || null });
    if (error) { await logUsage(sb, member.id, "submit_chapter_need", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "submit_chapter_need", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "submit_chapter_need", true, undefined, start);
    return ok(data);
  });

  // TOOL 57: drop_event_instance — Cancel a specific event occurrence
  mcp.tool("drop_event_instance", "Cancel/delete a specific event instance (e.g. a tribe meeting that didn't happen). Requires tribe leader of that tribe, or admin/manager. By default rejects if attendance exists; pass force_delete_attendance=true to remove attendance records atomically first.", {
    event_id: z.string().describe("UUID of the event to delete"),
    force_delete_attendance: z.boolean().optional().describe("If true, also deletes attendance records in same transaction. Default: false")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "drop_event_instance", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "drop_event_instance", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data, error } = await sb.rpc("drop_event_instance", {
      p_event_id: params.event_id,
      p_force_delete_attendance: params.force_delete_attendance ?? false
    });
    if (error) { await logUsage(sb, member.id, "drop_event_instance", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "drop_event_instance", true, undefined, start);
    return ok(data);
  });

  // TOOL 58: update_event_instance — Edit a specific event occurrence
  mcp.tool("update_event_instance", "Edit a specific event instance (date, time, duration, link, notes). Requires tribe leader or admin/manager.", { event_id: z.string().describe("UUID of the event to update"), new_date: z.string().optional().describe("New date YYYY-MM-DD"), new_time_start: z.string().optional().describe("New start time HH:MM"), new_duration_minutes: z.number().optional().describe("New duration in minutes"), meeting_link: z.string().optional().describe("New meeting link URL"), notes: z.string().optional().describe("Notes about the change"), agenda_text: z.string().optional().describe("Updated agenda text") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "update_event_instance", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "update_event_instance", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data, error } = await sb.rpc("update_event_instance", { p_event_id: params.event_id, p_new_date: params.new_date || null, p_new_time_start: params.new_time_start || null, p_new_duration_minutes: params.new_duration_minutes || null, p_meeting_link: params.meeting_link || null, p_notes: params.notes || null, p_agenda_text: params.agenda_text || null });
    if (error) { await logUsage(sb, member.id, "update_event_instance", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "update_event_instance", true, undefined, start);
    return ok(data);
  });

  // TOOL 59: mark_member_excused — Mark a member as excused (justified absence) for an event
  mcp.tool("mark_member_excused", "Mark a member as excused (falta justificada) for an event. Tribe leaders can mark their own tribe members. Admins can mark anyone.", { event_id: z.string().describe("UUID of the event"), member_id: z.string().describe("UUID of the member"), excused: z.boolean().optional().describe("true to mark excused, false to remove. Default: true"), reason: z.string().optional().describe("Reason for the excused absence") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "mark_member_excused", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "mark_member_excused", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data, error } = await sb.rpc("mark_member_excused", { p_event_id: params.event_id, p_member_id: params.member_id, p_excused: params.excused !== false, p_reason: params.reason || null });
    if (error) { await logUsage(sb, member.id, "mark_member_excused", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "mark_member_excused", true, undefined, start);
    return ok(data);
  });

  // TOOL 60: bulk_mark_excused — Mark a member excused for all events in a date range
  mcp.tool("bulk_mark_excused", "Mark a member as excused for ALL eligible events in a date range (e.g. 'off the whole month'). Tribe leaders can mark own tribe. Admins can mark anyone.", { member_id: z.string().describe("UUID of the member"), date_from: z.string().describe("Start date YYYY-MM-DD"), date_to: z.string().describe("End date YYYY-MM-DD"), reason: z.string().optional().describe("Reason for the absence") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "bulk_mark_excused", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write'))) { await logUsage(sb, member.id, "bulk_mark_excused", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data, error } = await sb.rpc("bulk_mark_excused", { p_member_id: params.member_id, p_date_from: params.date_from, p_date_to: params.date_to, p_reason: params.reason || null });
    if (error) { await logUsage(sb, member.id, "bulk_mark_excused", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "bulk_mark_excused", true, undefined, start);
    return ok(data);
  });

  // TOOL 61: get_my_assigned_cards — Returns cards assigned to the caller across all boards
  mcp.tool("get_my_assigned_cards", "Returns all board cards assigned to you (in_progress, review, backlog). Shows title, status, tribe, role, due date.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_assigned_cards", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_cards");
    if (error) { await logUsage(sb, member.id, "get_my_assigned_cards", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_assigned_cards", true, undefined, start);
    return ok({ total: Array.isArray(data) ? data.length : 0, cards: data });
  });

  // TOOL 62: get_tribe_stats_ranked — Returns stats for a specific tribe with per-member ranking
  mcp.tool("get_tribe_stats_ranked", "Returns tribe stats: member count, attendance rate, impact hours, cards by status, and per-member attendance ranking.", { tribe_id: z.number().describe("Tribe ID (1-8)") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_tribe_stats_ranked", false, "Not authenticated", start); return err("Not authenticated"); }
    const initiativeId = await resolveInitiativeId(sb, params.tribe_id);
    if (!initiativeId) { await logUsage(sb, member.id, "get_tribe_stats_ranked", false, "Initiative not found", start); return err("Initiative not found for tribe " + params.tribe_id); }
    const { data, error } = await sb.rpc("get_initiative_stats", { p_initiative_id: initiativeId });
    if (error) { await logUsage(sb, member.id, "get_tribe_stats_ranked", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_tribe_stats_ranked", true, undefined, start);
    return ok(data);
  });

  // TOOL 63: get_tribes_comparison — Returns cross-tribe comparison for GP/admin
  mcp.tool("get_tribes_comparison", "Returns comparison of all tribes: attendance rate, cards done/progress, impact hours, events, last meeting. Admin/GP only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_tribes_comparison", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_cross_tribe_comparison");
    if (error) { await logUsage(sb, member.id, "get_tribes_comparison", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "get_tribes_comparison", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "get_tribes_comparison", true, undefined, start);
    return ok(data);
  });

  // TOOL 64: get_research_pipeline — Returns global research pipeline (in_progress + review cards)
  mcp.tool("get_research_pipeline", "Returns all research cards in progress or review across all tribes, with authors and status. Admin/GP only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_research_pipeline", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_research_pipeline", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("get_global_research_pipeline");
    if (error) { await logUsage(sb, member.id, "get_research_pipeline", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_research_pipeline", true, undefined, start);
    return ok(data);
  });

  // TOOL 65: get_my_selection_result — Candidate self-view (own scores + status, rank only after final)
  mcp.tool("get_my_selection_result", "Returns your own selection application status and scores. Rank is only shown after the final decision (approved/rejected/cutoff) to avoid anxiety during the process. Works for any member who applied through the selection pipeline.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_selection_result", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_selection_result");
    if (error) { await logUsage(sb, member.id, "get_my_selection_result", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_selection_result", true, undefined, start);
    return ok(data);
  });

  // TOOL 66: get_selection_rankings — Admin view of dual rankings (CR-047)
  mcp.tool("get_selection_rankings", "Returns selection rankings split by track (researcher or leader) per CR-047 dual-ranking system. Formula: research_score = obj + int; leader_score = research*0.7 + leader_extra*0.3. Standard Competition Ranking (ISO 80000-2). Admin/GP/curator only.", {
    cycle_code: z.string().optional().describe("Cycle code (e.g. cycle3-2026-b2). If omitted, uses most recent cycle."),
    track: z.enum(['researcher','leader','both']).optional().describe("Which ranking track to return. Default: both")
  }, async (params: { cycle_code?: string; track?: 'researcher' | 'leader' | 'both' }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_selection_rankings", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_selection_rankings", false, "Unauthorized", start); return err("Unauthorized: admin/GP only."); }
    const { data, error } = await sb.rpc("get_selection_rankings", {
      p_cycle_code: params.cycle_code || null,
      p_track: params.track || 'both'
    });
    if (error) { await logUsage(sb, member.id, "get_selection_rankings", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_selection_rankings", true, undefined, start);
    return ok(data);
  });

  // TOOL 67: get_application_score_breakdown — Detailed breakdown of a single application (admin)
  mcp.tool("get_application_score_breakdown", "Returns detailed score breakdown for a single application, including individual evaluator scores (objective, interview, leader_extra) and PERT consolidation. Admin/GP/curator only.", {
    application_id: z.string().describe("Selection application UUID")
  }, async (params: { application_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_application_score_breakdown", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_application_score_breakdown", false, "Unauthorized", start); return err("Unauthorized: admin/GP only."); }
    if (!isUUID(params.application_id)) { return err("application_id must be a UUID"); }
    const { data, error } = await sb.rpc("get_application_score_breakdown", { p_application_id: params.application_id });
    if (error) { await logUsage(sb, member.id, "get_application_score_breakdown", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_application_score_breakdown", true, undefined, start);
    return ok(data);
  });

  // TOOL 68 (WRITE): promote_to_leader_track — admin action to triage researcher → leader
  mcp.tool("promote_to_leader_track", "Promotes a researcher-track application to the leader track (CR-047 triaged_to_leader flow). Creates a new leader application cloned from the researcher one and links them bidirectionally. Admin/GP only.", {
    application_id: z.string().describe("Researcher application UUID to promote"),
    create_leader_app: z.boolean().optional().describe("If true (default), creates a new leader application cloned from the researcher. If false, only marks the researcher as triaged without creating the leader pair.")
  }, async (params: { application_id: string; create_leader_app?: boolean }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "promote_to_leader_track", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'promote'))) { await logUsage(sb, member.id, "promote_to_leader_track", false, "canV4 denied", start); return err("Unauthorized: only manager/deputy/superadmin"); }
    if (!isUUID(params.application_id)) { return err("application_id must be a UUID"); }
    const { data, error } = await sb.rpc("promote_to_leader_track", {
      p_application_id: params.application_id,
      p_create_leader_app: params.create_leader_app ?? true
    });
    if (error) { await logUsage(sb, member.id, "promote_to_leader_track", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "promote_to_leader_track", true, undefined, start);
    return ok(data);
  });

  // ===== V4 PERSON + ENGAGEMENT TOOLS (69-70) =====

  // TOOL 69: get_person — V4 person profile (ADR-0006)
  mcp.tool("get_person", "Returns the V4 person profile: name, location, credly badges, consent status. PII (email, phone) only visible for own record or with view_pii permission.", { person_id: z.string().optional().describe("Person UUID. If omitted, returns your own profile.") }, async (params: { person_id?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_person", false, "Not authenticated", start); return err("Not authenticated"); }
    const rpcParams: any = {};
    if (params.person_id) {
      if (!isUUID(params.person_id)) { return err("person_id must be a UUID"); }
      rpcParams.p_person_id = params.person_id;
    }
    const { data, error } = await sb.rpc("get_person", rpcParams);
    if (error) { await logUsage(sb, member.id, "get_person", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "get_person", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "get_person", true, undefined, start);
    return ok(data);
  });

  // TOOL 70: get_active_engagements — V4 engagement list (ADR-0006)
  mcp.tool("get_active_engagements", "Returns active engagements for a person: kind, role, initiative, dates, authority status. Own engagements always visible. Others require manage_member.", { person_id: z.string().optional().describe("Person UUID. If omitted, returns your own engagements.") }, async (params: { person_id?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_active_engagements", false, "Not authenticated", start); return err("Not authenticated"); }
    const rpcParams: any = {};
    if (params.person_id) {
      if (!isUUID(params.person_id)) { return err("person_id must be a UUID"); }
      rpcParams.p_person_id = params.person_id;
    }
    const { data, error } = await sb.rpc("get_active_engagements", rpcParams);
    if (error) { await logUsage(sb, member.id, "get_active_engagements", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "get_active_engagements", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "get_active_engagements", true, undefined, start);
    return ok(data);
  });

  // ===== WIKI & KNOWLEDGE TOOLS (71-73) =====

  // TOOL 71: search_wiki — full-text search across wiki pages
  mcp.tool("search_wiki", "Search the Núcleo wiki knowledge base. Returns ranked results with highlighted snippets. Covers governance documents, architectural decisions (ADRs), research, and narrative knowledge.", { query: z.string().describe("Search query (supports Portuguese natural language)"), limit: z.number().optional().describe("Max results. Default: 10"), domain: z.string().optional().describe("Filter by domain: research, governance, tribes, partnerships, platform, onboarding"), tag: z.string().optional().describe("Filter by tag (exact match)") }, async (params: { query: string; limit?: number; domain?: string; tag?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "search_wiki", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("search_wiki_pages", { p_query: params.query, p_limit: params.limit || 10, p_domain: params.domain || null, p_tag: params.tag || null });
    if (error) { await logUsage(sb, member.id, "search_wiki", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "search_wiki", true, undefined, start);
    return ok(data);
  });

  // TOOL 72: get_wiki_page — retrieve full wiki page by path
  mcp.tool("get_wiki_page", "Returns the full content of a wiki page by its path (e.g. 'governance/adr/ADR-0007.md'). Includes metadata: authors, license, IP track, tags.", { path: z.string().describe("Wiki page path, e.g. 'governance/manual.md' or 'governance/adr/ADR-0007.md'") }, async (params: { path: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_wiki_page", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_wiki_page", { p_path: params.path });
    if (error) { await logUsage(sb, member.id, "get_wiki_page", false, error.message, start); return err(error.message); }
    if (!data || (Array.isArray(data) && data.length === 0)) { await logUsage(sb, member.id, "get_wiki_page", false, "Page not found", start); return err(`Page not found: ${params.path}. Use search_wiki to find available pages.`); }
    await logUsage(sb, member.id, "get_wiki_page", true, undefined, start);
    return ok(data);
  });

  // TOOL 73: get_decision_log — list architectural decision records (ADRs)
  mcp.tool("get_decision_log", "Returns the list of Architectural Decision Records (ADRs). Optionally filter by keyword. ADRs document key architectural choices for the platform.", { filter: z.string().optional().describe("Optional keyword filter (e.g. 'authority', 'engagement', 'initiative')") }, async (params: { filter?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_decision_log", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_decision_log", { p_filter: params.filter || null });
    if (error) { await logUsage(sb, member.id, "get_decision_log", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_decision_log", true, undefined, start);
    return ok(data);
  });

  // TOOL 74: get_wiki_health — wiki lifecycle health report (staleness, PII, completeness)
  mcp.tool("get_wiki_health", "Returns wiki health report: stale pages (>90 days without update), PII warnings (emails, phones, CPFs in content), and incomplete metadata. Use to audit wiki quality.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_wiki_health", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("wiki_health_report");
    if (error) { await logUsage(sb, member.id, "get_wiki_health", false, error.message, start); return err(error.message); }
    const issues = Array.isArray(data) ? data : [];
    const summary = issues.length === 0
      ? "Wiki is healthy: no stale pages, no PII detected, all metadata complete."
      : `Found ${issues.length} issue(s): ${issues.filter((i: Record<string, string>) => i.check_type === 'pii_warning').length} PII warning(s), ${issues.filter((i: Record<string, string>) => i.check_type === 'stale').length} stale page(s), ${issues.filter((i: Record<string, string>) => i.check_type === 'incomplete').length} incomplete page(s).`;
    await logUsage(sb, member.id, "get_wiki_health", true, undefined, start);
    return ok({ summary, issues });
  });

  // TOOL 75: list_initiatives — list all initiatives (Tier 1 read)
  mcp.tool("list_initiatives", "Lists all initiatives in the platform, optionally filtered by kind and status. Returns id, title, kind, status, description, member_count.", {
    kind: z.string().optional().describe("Filter by initiative kind (e.g. 'workgroup', 'committee', 'study_group', 'research_tribe')"),
    status: z.string().optional().describe("Filter by status (draft, active, concluded, archived). Default: all.")
  }, async (params: { kind?: string; status?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_initiatives", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("list_initiatives", { p_kind: params.kind || null, p_status: params.status || null });
    if (error) { await logUsage(sb, member.id, "list_initiatives", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_initiatives", true, undefined, start);
    return ok(data);
  });

  // TOOL 76: manage_initiative_engagement — add/remove/update members (write, canV4 manage_member)
  mcp.tool("manage_initiative_engagement", "Add, remove, or update role of a member in an initiative. Requires manage_member permission for the initiative.", {
    initiative_id: z.string().describe("Initiative UUID"),
    person_id: z.string().describe("Person UUID to add/remove/update"),
    kind: z.string().describe("Engagement kind (e.g. 'workgroup_member', 'workgroup_coordinator', 'committee_member', 'volunteer')"),
    role: z.string().optional().describe("Role within engagement (e.g. 'leader', 'participant', 'coordinator'). Default: participant"),
    action: z.string().describe("Action: 'add', 'remove', or 'update_role'")
  }, async (params: { initiative_id: string; person_id: string; kind: string; role?: string; action: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "manage_initiative_engagement", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "manage_initiative_engagement", false, "Unauthorized", start); return err("Unauthorized: requires manage_member permission."); }
    const { data, error } = await sb.rpc("manage_initiative_engagement", {
      p_initiative_id: params.initiative_id,
      p_person_id: params.person_id,
      p_kind: params.kind,
      p_role: params.role || 'participant',
      p_action: params.action
    });
    if (error) { await logUsage(sb, member.id, "manage_initiative_engagement", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "manage_initiative_engagement", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "manage_initiative_engagement", true, undefined, start);
    return ok(data);
  });

  // ===== OFFBOARDING (issue #91 quick wins) =====

  // TOOL: offboard_member
  mcp.tool("offboard_member", "Transition a member to alumni / observer / inactive with structured reason. Admin only. Use 'alumni' for 'open door' departures (member can return via new selection), 'observer' for temporary pause, 'inactive' for terminal.", {
    member_id: z.string().describe("UUID of member"),
    new_status: z.enum(["alumni","observer","inactive"]).describe("Target status"),
    reason_category: z.enum(["personal_workload","personal_agenda","academic_conflict","health","relocation","end_of_cycle","external_priority","lack_of_fit","policy_violation","other"]).describe("Reason taxonomy — see offboard_reason_categories table"),
    reason_detail: z.string().describe("Free-text context (1-3 sentences)"),
    reassign_cards_to: z.string().optional().describe("Optional UUID to reassign open cards to")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "offboard_member", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "offboard_member", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("admin_offboard_member", {
      p_member_id: params.member_id,
      p_new_status: params.new_status,
      p_reason_category: params.reason_category,
      p_reason_detail: params.reason_detail,
      p_reassign_to: params.reassign_cards_to || null
    });
    if (error) { await logUsage(sb, member.id, "offboard_member", false, error.message, start); return err(error.message); }
    if (data?.error) { await logUsage(sb, member.id, "offboard_member", false, data.error, start); return err(data.error); }
    await logUsage(sb, member.id, "offboard_member", true, undefined, start);
    return ok(data);
  });

  // TOOL: get_role_transitions
  mcp.tool("get_role_transitions", "Returns cycle-over-cycle analytics on member role transitions (offboards, promotions, demotions). Admin/Sponsor only.", {
    cycle_code: z.string().optional().describe("Cycle code, e.g. 'cycle3-2026'. Default: current"),
    tribe_id: z.number().optional().describe("Filter by tribe 1-8"),
    chapter: z.string().optional().describe("Filter by chapter code (PMI-GO etc.)")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_role_transitions", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member')) && !(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "get_role_transitions", false, "Unauthorized", start); return err("Unauthorized: admin or sponsor only."); }
    const { data, error } = await sb.rpc("exec_role_transitions", {
      p_cycle_code: params.cycle_code || null,
      p_tribe_id: params.tribe_id || null,
      p_chapter: params.chapter || null
    });
    if (error) { await logUsage(sb, member.id, "get_role_transitions", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_role_transitions", true, undefined, start);
    return ok(data);
  });

  // ===== ONBOARDING (issue #86 — persona "new member" unblock) =====

  // TOOL: get_my_onboarding
  mcp.tool("get_my_onboarding", "Returns your onboarding progress — step list with status (pending/in_progress/completed) and next action.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_onboarding", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_onboarding");
    if (error) { await logUsage(sb, member.id, "get_my_onboarding", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_onboarding", true, undefined, start);
    return ok(data);
  });

  // TOOL: complete_onboarding_step
  mcp.tool("complete_onboarding_step", "Marks an onboarding step as completed. Optionally attach metadata (evidence URL, notes).", {
    step_id: z.string().describe("Step ID (e.g. 'sign_volunteer_agreement', 'complete_profile', 'first_meeting')"),
    metadata: z.any().optional().describe("Optional JSON metadata (evidence_url, notes, etc.)")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "complete_onboarding_step", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("complete_onboarding_step", {
      p_step_id: params.step_id,
      p_metadata: params.metadata || null
    });
    if (error) { await logUsage(sb, member.id, "complete_onboarding_step", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "complete_onboarding_step", true, undefined, start);
    return ok(data);
  });

  // TOOL: dismiss_onboarding
  mcp.tool("dismiss_onboarding", "Dismisses remaining onboarding prompts for experienced members who don't need guided flow.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "dismiss_onboarding", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("dismiss_onboarding");
    if (error) { await logUsage(sb, member.id, "dismiss_onboarding", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "dismiss_onboarding", true, undefined, start);
    return ok(data);
  });

  // TOOL: get_onboarding_dashboard
  mcp.tool("get_onboarding_dashboard", "Returns admin dashboard: how many members are at each onboarding step, who is overdue. Admin only.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_onboarding_dashboard", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_onboarding_dashboard", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("get_onboarding_dashboard");
    if (error) { await logUsage(sb, member.id, "get_onboarding_dashboard", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_onboarding_dashboard", true, undefined, start);
    return ok(data);
  });

  // TOOL: get_candidate_onboarding_progress
  mcp.tool("get_candidate_onboarding_progress", "Tribe leader or admin: follow up a specific new member's onboarding progress.", {
    member_id: z.string().describe("UUID of the member to inspect")
  }, async (params: { member_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_candidate_onboarding_progress", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'write')) && !(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "get_candidate_onboarding_progress", false, "Unauthorized", start); return err("Unauthorized: tribe leader or admin only."); }
    const { data, error } = await sb.rpc("get_candidate_onboarding_progress", { p_member_id: params.member_id });
    if (error) { await logUsage(sb, member.id, "get_candidate_onboarding_progress", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_candidate_onboarding_progress", true, undefined, start);
    return ok(data);
  });

  // TOOL: detect_onboarding_overdue
  mcp.tool("detect_onboarding_overdue", "Detects members whose onboarding steps passed SLA. Admin only. Returns list for follow-up action.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "detect_onboarding_overdue", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "detect_onboarding_overdue", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("detect_onboarding_overdue");
    if (error) { await logUsage(sb, member.id, "detect_onboarding_overdue", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "detect_onboarding_overdue", true, undefined, start);
    return ok(data);
  });

  // ===== CERTIFICATES PUBLIC (issue #86 — external verification) =====

  // TOOL: verify_certificate (public — no auth required by design)
  mcp.tool("verify_certificate", "Publicly verify a certificate authenticity by its verification code. Returns issuance details, issuer, recipient name, issue date. Use cases: HR validation, external auditors. Does NOT require authentication — intended for third-party verification.", {
    verification_code: z.string().describe("Unique verification code printed on the certificate PDF")
  }, async (params: { verification_code: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    const { data, error } = await sb.rpc("verify_certificate", { p_code: params.verification_code });
    if (error) { await logUsage(sb, member?.id || null, "verify_certificate", false, error.message, start); return err(error.message); }
    await logUsage(sb, member?.id || null, "verify_certificate", true, undefined, start);
    return ok(data);
  });

  // ===== BOARD/CARD/CHECKLIST CRUD (issue #83 P0 — Fabrício feedback, T6 leader) =====
  // Fecha gap MCP coverage <40% → ~95% em Card/Checklist operations.
  // 4 new RPCs (get_card_detail, add/update/delete_checklist_item) + 4 wraps existentes.

  // TOOL: get_card_detail — rich payload (card + checklist + assignments + timeline)
  mcp.tool("get_card_detail", "Returns rich card detail: card fields + checklist items + multi-assignees + last 10 timeline events. Single call instead of multiple — use for card investigation/LLM context.", {
    card_id: z.string().describe("UUID of the board_items card")
  }, async (params: { card_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_card_detail", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "get_card_detail", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    const { data, error } = await sb.rpc("get_card_detail", { p_card_id: params.card_id });
    if (error) { await logUsage(sb, member.id, "get_card_detail", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_card_detail", true, undefined, start);
    return ok(data);
  });

  // TOOL: list_card_checklist — flat list (MCP tool uses direct SELECT — RLS allows any authenticated member)
  mcp.tool("list_card_checklist", "Returns the checklist (activities) for a card, ordered by position. Lightweight read — for full card context use get_card_detail.", {
    card_id: z.string().describe("UUID of the board_items card")
  }, async (params: { card_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_card_checklist", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "list_card_checklist", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    const { data, error } = await sb.from("board_item_checklists")
      .select("id, text, is_completed, position, assigned_to, target_date, completed_at, completed_by, assigned_at, assigned_by, created_at")
      .eq("board_item_id", params.card_id)
      .order("position", { ascending: true });
    if (error) { await logUsage(sb, member.id, "list_card_checklist", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_card_checklist", true, undefined, start);
    return ok(data);
  });

  // TOOL: update_card_fields — partial update via RPC update_board_item(jsonb)
  mcp.tool("update_card_fields", "Update one or more card fields partially: title, description, assignee_id, due_date, tags (array), labels (jsonb), reviewer_id, baseline_date, forecast_date, is_portfolio_item. RPC checks field-level permissions (e.g., only Leader/GP can change assignee).", {
    card_id: z.string().describe("UUID of the card"),
    title: z.string().optional().describe("New title"),
    description: z.string().optional().describe("New description"),
    assignee_id: z.string().optional().describe("Member UUID to assign (null/empty string to unassign)"),
    reviewer_id: z.string().optional().describe("Member UUID of reviewer"),
    due_date: z.string().optional().describe("YYYY-MM-DD or empty to clear"),
    tags: z.string().optional().describe("Comma-separated tags (replaces existing)"),
    baseline_date: z.string().optional().describe("YYYY-MM-DD — Leader/GP only"),
    forecast_date: z.string().optional().describe("YYYY-MM-DD"),
    is_portfolio_item: z.boolean().optional().describe("Mark as portfolio deliverable — Leader/GP only"),
    reason: z.string().optional().describe("Required when changing a locked baseline")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "update_card_fields", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "update_card_fields", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "update_card_fields", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const fields: Record<string, unknown> = {};
    if (params.title !== undefined) fields.title = params.title;
    if (params.description !== undefined) fields.description = params.description;
    if (params.assignee_id !== undefined) fields.assignee_id = params.assignee_id || null;
    if (params.reviewer_id !== undefined) fields.reviewer_id = params.reviewer_id || null;
    if (params.due_date !== undefined) fields.due_date = params.due_date || null;
    if (params.tags !== undefined) fields.tags = String(params.tags).split(",").map((t: string) => t.trim()).filter(Boolean);
    if (params.baseline_date !== undefined) fields.baseline_date = params.baseline_date || null;
    if (params.forecast_date !== undefined) fields.forecast_date = params.forecast_date || null;
    if (params.is_portfolio_item !== undefined) fields.is_portfolio_item = params.is_portfolio_item;
    if (params.reason !== undefined) fields.reason = params.reason;
    if (Object.keys(fields).length === 0) { await logUsage(sb, member.id, "update_card_fields", false, "No fields", start); return err("At least one field must be provided"); }
    const { error } = await sb.rpc("update_board_item", { p_item_id: params.card_id, p_fields: fields });
    if (error) { await logUsage(sb, member.id, "update_card_fields", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "update_card_fields", true, undefined, start);
    return ok({ action: "update_card_fields", status: "updated", card_id: params.card_id, fields_changed: Object.keys(fields) });
  });

  // TOOL: add_checklist_item — new RPC
  mcp.tool("add_checklist_item", "Add a checklist activity to a card. Optionally assign it to a member with target date. Auto-assigns position (end of list) if omitted.", {
    card_id: z.string().describe("UUID of the parent card (board_items)"),
    text: z.string().describe("Activity description"),
    position: z.number().optional().describe("Optional position (defaults to end of list)"),
    assigned_to: z.string().optional().describe("Member UUID to assign"),
    target_date: z.string().optional().describe("YYYY-MM-DD target date")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "add_checklist_item", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "add_checklist_item", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "add_checklist_item", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { data, error } = await sb.rpc("add_checklist_item", {
      p_board_item_id: params.card_id,
      p_text: params.text,
      p_position: params.position ?? null,
      p_assigned_to: params.assigned_to || null,
      p_target_date: params.target_date || null,
    });
    if (error) { await logUsage(sb, member.id, "add_checklist_item", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "add_checklist_item", true, undefined, start);
    return ok({ action: "add_checklist_item", status: "created", checklist_item_id: data });
  });

  // TOOL: update_checklist_item — new RPC
  mcp.tool("update_checklist_item", "Update a checklist item: text, position, target_date. Use assign_checklist_item to change assignee or complete_checklist_item to toggle done.", {
    checklist_item_id: z.string().describe("UUID of the checklist item"),
    text: z.string().optional().describe("New activity description"),
    position: z.number().optional().describe("New position (reorder)"),
    target_date: z.string().optional().describe("YYYY-MM-DD")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "update_checklist_item", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.checklist_item_id)) { await logUsage(sb, member.id, "update_checklist_item", false, "Invalid id", start); return err("checklist_item_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "update_checklist_item", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("update_checklist_item", {
      p_checklist_item_id: params.checklist_item_id,
      p_text: params.text ?? null,
      p_position: params.position ?? null,
      p_target_date: params.target_date || null,
    });
    if (error) { await logUsage(sb, member.id, "update_checklist_item", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "update_checklist_item", true, undefined, start);
    return ok({ action: "update_checklist_item", status: "updated", checklist_item_id: params.checklist_item_id });
  });

  // TOOL: assign_checklist_item — wrap existing RPC
  mcp.tool("assign_checklist_item", "Assign a checklist activity to a member with an optional target date. Wraps RPC that already validates leader/GP/card-owner authority.", {
    checklist_item_id: z.string().describe("UUID of the checklist item"),
    assigned_to: z.string().describe("Member UUID to assign"),
    target_date: z.string().optional().describe("YYYY-MM-DD")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "assign_checklist_item", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.checklist_item_id)) { await logUsage(sb, member.id, "assign_checklist_item", false, "Invalid id", start); return err("checklist_item_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "assign_checklist_item", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("assign_checklist_item", {
      p_checklist_item_id: params.checklist_item_id,
      p_assigned_to: params.assigned_to,
      p_target_date: params.target_date || null,
    });
    if (error) { await logUsage(sb, member.id, "assign_checklist_item", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "assign_checklist_item", true, undefined, start);
    return ok({ action: "assign_checklist_item", status: "assigned", checklist_item_id: params.checklist_item_id });
  });

  // TOOL: complete_checklist_item — wrap existing RPC
  mcp.tool("complete_checklist_item", "Toggle a checklist activity as completed (or reopen). RPC allows the activity owner (assigned_to) and also leader/GP/card owner.", {
    checklist_item_id: z.string().describe("UUID of the checklist item"),
    completed: z.boolean().optional().describe("True to mark done (default), false to reopen")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "complete_checklist_item", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.checklist_item_id)) { await logUsage(sb, member.id, "complete_checklist_item", false, "Invalid id", start); return err("checklist_item_id must be a UUID"); }
    // Note: RPC does own authority check (activity owner can complete own). Do NOT gate via canV4 here.
    const { error } = await sb.rpc("complete_checklist_item", {
      p_checklist_item_id: params.checklist_item_id,
      p_completed: params.completed ?? true,
    });
    if (error) { await logUsage(sb, member.id, "complete_checklist_item", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "complete_checklist_item", true, undefined, start);
    return ok({ action: "complete_checklist_item", status: params.completed === false ? "reopened" : "completed", checklist_item_id: params.checklist_item_id });
  });

  // TOOL: delete_checklist_item — new RPC
  mcp.tool("delete_checklist_item", "Permanently delete a checklist item. Optional reason is recorded in the card timeline.", {
    checklist_item_id: z.string().describe("UUID of the checklist item"),
    reason: z.string().optional().describe("Optional reason for deletion (audit)")
  }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "delete_checklist_item", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.checklist_item_id)) { await logUsage(sb, member.id, "delete_checklist_item", false, "Invalid id", start); return err("checklist_item_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "delete_checklist_item", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("delete_checklist_item", {
      p_checklist_item_id: params.checklist_item_id,
      p_reason: params.reason || null,
    });
    if (error) { await logUsage(sb, member.id, "delete_checklist_item", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "delete_checklist_item", true, undefined, start);
    return ok({ action: "delete_checklist_item", status: "deleted", checklist_item_id: params.checklist_item_id });
  });

  // ===== BOARD/CARD CRUD (issue #83 P1) =====
  // 7 wrappers of existing RPCs — no new SQL.
  // move_card / delete_card / duplicate_card / move_card_to_board / get_card_timeline / list_board_cards / get_board_detail.

  // TOOL: move_card — wrap move_board_item (status + position + reason). Superset of update_card_status.
  mcp.tool("move_card", "Move a card to a different status column, optionally setting position within the column and a reason for audit trail. Richer than update_card_status (which only changes status). Use this when you need to record why a card moved.", {
    card_id: z.string().describe("UUID of the card"),
    new_status: z.string().describe("Target status column (e.g., backlog|in_progress|review|done|archived)"),
    new_position: z.number().optional().describe("Optional 0-based position within the target column. Defaults to 0 (top)."),
    reason: z.string().optional().describe("Optional reason recorded in card timeline (audit).")
  }, async (params: { card_id: string; new_status: string; new_position?: number; reason?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "move_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "move_card", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "move_card", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("move_board_item", {
      p_item_id: params.card_id,
      p_new_status: params.new_status,
      p_new_position: params.new_position ?? 0,
      p_reason: params.reason || null,
    });
    if (error) { await logUsage(sb, member.id, "move_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "move_card", true, undefined, start);
    return ok({ action: "move_card", status: "moved", card_id: params.card_id, new_status: params.new_status, new_position: params.new_position ?? 0 });
  });

  // TOOL: delete_card — wrap delete_board_item. Reason is required (audit).
  mcp.tool("delete_card", "Permanently delete a card and its checklist/assignments. Reason is required for audit. Prefer archive_card (future) for soft-delete.", {
    card_id: z.string().describe("UUID of the card to delete"),
    reason: z.string().describe("Required reason — recorded in audit log.")
  }, async (params: { card_id: string; reason: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "delete_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "delete_card", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!params.reason || !params.reason.trim()) { await logUsage(sb, member.id, "delete_card", false, "Missing reason", start); return err("reason is required for delete_card"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "delete_card", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("delete_board_item", {
      p_item_id: params.card_id,
      p_reason: params.reason,
    });
    if (error) { await logUsage(sb, member.id, "delete_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "delete_card", true, undefined, start);
    return ok({ action: "delete_card", status: "deleted", card_id: params.card_id });
  });

  // TOOL: duplicate_card — wrap duplicate_board_item. target_board optional (defaults to same board).
  mcp.tool("duplicate_card", "Duplicate a card (copy title/description/tags/labels/due_date into a new card). Optionally place the copy on a different board. Checklist and assignments are NOT copied by default (RPC behavior).", {
    card_id: z.string().describe("UUID of the source card"),
    target_board_id: z.string().optional().describe("Optional UUID of a different target board. If omitted, copy lands on the same board as the source.")
  }, async (params: { card_id: string; target_board_id?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "duplicate_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "duplicate_card", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (params.target_board_id && !isUUID(params.target_board_id)) { await logUsage(sb, member.id, "duplicate_card", false, "Invalid target_board_id", start); return err("target_board_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "duplicate_card", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { data, error } = await sb.rpc("duplicate_board_item", {
      p_item_id: params.card_id,
      p_target_board_id: params.target_board_id || null,
    });
    if (error) { await logUsage(sb, member.id, "duplicate_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "duplicate_card", true, undefined, start);
    return ok({ action: "duplicate_card", status: "created", source_card_id: params.card_id, new_card_id: data });
  });

  // TOOL: move_card_to_board — wrap move_item_to_board. No reason param at RPC layer.
  mcp.tool("move_card_to_board", "Move a card from its current board to a different board. Preserves card content and checklist; reassigns board_id. Requires write_board on both source and target boards (enforced by RPC).", {
    card_id: z.string().describe("UUID of the card to move"),
    target_board_id: z.string().describe("UUID of the destination board")
  }, async (params: { card_id: string; target_board_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "move_card_to_board", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "move_card_to_board", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!isUUID(params.target_board_id)) { await logUsage(sb, member.id, "move_card_to_board", false, "Invalid target_board_id", start); return err("target_board_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "move_card_to_board", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("move_item_to_board", {
      p_item_id: params.card_id,
      p_target_board_id: params.target_board_id,
    });
    if (error) { await logUsage(sb, member.id, "move_card_to_board", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "move_card_to_board", true, undefined, start);
    return ok({ action: "move_card_to_board", status: "moved", card_id: params.card_id, target_board_id: params.target_board_id });
  });

  // TOOL: get_card_timeline — wrap get_card_timeline. Read-only, no canV4 gate (RLS via authenticated).
  mcp.tool("get_card_timeline", "Returns the full audit timeline for a card: status transitions, reviews, SLA events, with actor and reason. Ordered oldest → newest. Use to explain history to members or audit decisions.", {
    card_id: z.string().describe("UUID of the card"),
    limit: z.number().optional().describe("Optional cap on events returned (applied client-side; omit for full history).")
  }, async (params: { card_id: string; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_card_timeline", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "get_card_timeline", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    const { data, error } = await sb.rpc("get_card_timeline", { p_item_id: params.card_id });
    if (error) { await logUsage(sb, member.id, "get_card_timeline", false, error.message, start); return err(error.message); }
    const rows = Array.isArray(data) ? data : [];
    const sliced = typeof params.limit === "number" && params.limit > 0 ? rows.slice(0, params.limit) : rows;
    await logUsage(sb, member.id, "get_card_timeline", true, undefined, start);
    return ok({ card_id: params.card_id, count: sliced.length, events: sliced });
  });

  // TOOL: list_board_cards — wrap list_board_items. Cross-board read (complements get_my_board_status).
  mcp.tool("list_board_cards", "List all cards on a specific board, optionally filtered by status. Cross-board read (any board the caller can see via RLS). For the caller's own tribe board use get_my_board_status instead.", {
    board_id: z.string().describe("UUID of the board"),
    status: z.string().optional().describe("Optional status filter (e.g., backlog|in_progress|review|done|archived). Omit for all statuses.")
  }, async (params: { board_id: string; status?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_board_cards", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.board_id)) { await logUsage(sb, member.id, "list_board_cards", false, "Invalid board_id", start); return err("board_id must be a UUID"); }
    const { data, error } = await sb.rpc("list_board_items", {
      p_board_id: params.board_id,
      p_status: params.status || null,
    });
    if (error) { await logUsage(sb, member.id, "list_board_cards", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_board_cards", true, undefined, start);
    return ok({ board_id: params.board_id, count: Array.isArray(data) ? data.length : 0, cards: data });
  });

  // TOOL: get_board_detail — compose get_board + get_board_members + get_board_tags.
  mcp.tool("get_board_detail", "Returns rich board detail: board fields (columns, scope, initiative, SLA config) + members with roles + available tags. Single call — use for board investigation/LLM context before operating on cards.", {
    board_id: z.string().describe("UUID of the board")
  }, async (params: { board_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_board_detail", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.board_id)) { await logUsage(sb, member.id, "get_board_detail", false, "Invalid board_id", start); return err("board_id must be a UUID"); }
    const [boardRes, membersRes, tagsRes] = await Promise.all([
      sb.rpc("get_board", { p_board_id: params.board_id }),
      sb.rpc("get_board_members", { p_board_id: params.board_id }),
      sb.rpc("get_board_tags", { p_board_id: params.board_id }),
    ]);
    if (boardRes.error) { await logUsage(sb, member.id, "get_board_detail", false, boardRes.error.message, start); return err(boardRes.error.message); }
    if (membersRes.error) { await logUsage(sb, member.id, "get_board_detail", false, membersRes.error.message, start); return err(membersRes.error.message); }
    if (tagsRes.error) { await logUsage(sb, member.id, "get_board_detail", false, tagsRes.error.message, start); return err(tagsRes.error.message); }
    await logUsage(sb, member.id, "get_board_detail", true, undefined, start);
    return ok({
      board_id: params.board_id,
      board: boardRes.data,
      members: membersRes.data,
      tags: tagsRes.data,
    });
  });

  // ===== BOARD/CARD CRUD (issue #83 P2) =====
  // 5 wrappers of existing SECURITY DEFINER RPCs — admin + portfolio operations.
  // archive_card / restore_card / advance_card_curation / create_mirror_card / update_card_forecast.
  // Tool layer gates with write_board (baseline); each RPC enforces stricter authority internally
  // (admin_*, portfolio forecast edits typically require Leader/GP or higher).

  // TOOL: archive_card — wrap admin_archive_board_item. Soft-delete with audit.
  mcp.tool("archive_card", "Soft-archive a card (status='archived') with audit reason. Preserves the row — use delete_card for permanent deletion. RPC performs the admin/leader authority check.", {
    card_id: z.string().describe("UUID of the card to archive"),
    reason: z.string().optional().describe("Optional audit reason (recommended)")
  }, async (params: { card_id: string; reason?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "archive_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "archive_card", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "archive_card", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { data, error } = await sb.rpc("admin_archive_board_item", {
      p_item_id: params.card_id,
      p_reason: params.reason || null,
    });
    if (error) { await logUsage(sb, member.id, "archive_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "archive_card", true, undefined, start);
    return ok({ action: "archive_card", status: "archived", card_id: params.card_id, result: data });
  });

  // TOOL: restore_card — wrap admin_restore_board_item. Reverse of archive.
  mcp.tool("restore_card", "Restore an archived card back to an active column. Default target status is 'backlog'. RPC performs the admin/leader authority check.", {
    card_id: z.string().describe("UUID of the archived card"),
    restore_status: z.string().optional().describe("Target status column (default: 'backlog'). Use any valid board column: backlog|in_progress|review|done."),
    reason: z.string().optional().describe("Optional audit reason")
  }, async (params: { card_id: string; restore_status?: string; reason?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "restore_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "restore_card", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "restore_card", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { data, error } = await sb.rpc("admin_restore_board_item", {
      p_item_id: params.card_id,
      p_restore_status: params.restore_status || 'backlog',
      p_reason: params.reason || null,
    });
    if (error) { await logUsage(sb, member.id, "restore_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "restore_card", true, undefined, start);
    return ok({ action: "restore_card", status: "restored", card_id: params.card_id, restored_to: params.restore_status || 'backlog', result: data });
  });

  // TOOL: advance_card_curation — wrap advance_board_item_curation. Review pipeline step.
  mcp.tool("advance_card_curation", "Move a card through its curation review pipeline: assign/approve/reject/request_changes. RPC enforces curator authority and current stage rules.", {
    card_id: z.string().describe("UUID of the card under curation"),
    action: z.string().describe("Curation action (e.g., assign|approve|reject|request_changes) — exact vocabulary is enforced by the RPC"),
    reviewer_id: z.string().optional().describe("Optional UUID of the reviewer (member) to assign for the next step")
  }, async (params: { card_id: string; action: string; reviewer_id?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "advance_card_curation", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "advance_card_curation", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (params.reviewer_id && !isUUID(params.reviewer_id)) { await logUsage(sb, member.id, "advance_card_curation", false, "Invalid reviewer_id", start); return err("reviewer_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "advance_card_curation", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("advance_board_item_curation", {
      p_item_id: params.card_id,
      p_action: params.action,
      p_reviewer_id: params.reviewer_id || null,
    });
    if (error) { await logUsage(sb, member.id, "advance_card_curation", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "advance_card_curation", true, undefined, start);
    return ok({ action: "advance_card_curation", status: "advanced", card_id: params.card_id, curation_action: params.action });
  });

  // TOOL: create_mirror_card — wrap create_mirror_card. Cross-board visibility copy.
  mcp.tool("create_mirror_card", "Create a mirror of a card on a different board. The mirror is a linked copy for cross-board visibility (e.g., portfolio mirror of a tribe card). RPC enforces write access to the target board.", {
    source_card_id: z.string().describe("UUID of the source card"),
    target_board_id: z.string().describe("UUID of the board to mirror into"),
    target_status: z.string().optional().describe("Initial status of the mirror card (default: 'backlog')"),
    notes: z.string().optional().describe("Optional notes to attach to the mirror copy")
  }, async (params: { source_card_id: string; target_board_id: string; target_status?: string; notes?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "create_mirror_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.source_card_id)) { await logUsage(sb, member.id, "create_mirror_card", false, "Invalid source_card_id", start); return err("source_card_id must be a UUID"); }
    if (!isUUID(params.target_board_id)) { await logUsage(sb, member.id, "create_mirror_card", false, "Invalid target_board_id", start); return err("target_board_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "create_mirror_card", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { data, error } = await sb.rpc("create_mirror_card", {
      p_source_item_id: params.source_card_id,
      p_target_board_id: params.target_board_id,
      p_target_status: params.target_status || 'backlog',
      p_notes: params.notes || null,
    });
    if (error) { await logUsage(sb, member.id, "create_mirror_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "create_mirror_card", true, undefined, start);
    return ok({ action: "create_mirror_card", status: "mirrored", source_card_id: params.source_card_id, mirror_card_id: data });
  });

  // TOOL: update_card_forecast — wrap update_card_forecast. Portfolio forecast edit with justification.
  mcp.tool("update_card_forecast", "Update the forecast_date of a card with a mandatory justification. Used to renegotiate a portfolio-tracked deadline. RPC typically requires Leader/GP authority and records the justification in the timeline.", {
    card_id: z.string().describe("UUID of the card (board_items)"),
    new_forecast_date: z.string().describe("New forecast date in YYYY-MM-DD format"),
    justification: z.string().describe("Required justification — recorded in card timeline")
  }, async (params: { card_id: string; new_forecast_date: string; justification: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "update_card_forecast", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.card_id)) { await logUsage(sb, member.id, "update_card_forecast", false, "Invalid card_id", start); return err("card_id must be a UUID"); }
    if (!params.justification || !params.justification.trim()) { await logUsage(sb, member.id, "update_card_forecast", false, "Missing justification", start); return err("justification is required for update_card_forecast"); }
    if (!(await canV4(sb, member.id, 'write_board'))) { await logUsage(sb, member.id, "update_card_forecast", false, "Unauthorized", start); return err("Unauthorized — write_board required."); }
    const { error } = await sb.rpc("update_card_forecast", {
      p_board_item_id: params.card_id,
      p_new_forecast: params.new_forecast_date,
      p_justification: params.justification,
    });
    if (error) { await logUsage(sb, member.id, "update_card_forecast", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "update_card_forecast", true, undefined, start);
    return ok({ action: "update_card_forecast", status: "updated", card_id: params.card_id, new_forecast_date: params.new_forecast_date });
  });

  // ───────────────────────────────────────────────────────────────
  // LGPD + AUDIT + ORPHAN TRIAGE TOOLS (p41 Onda B + G7 surface)
  // ───────────────────────────────────────────────────────────────

  // get_audit_log — unified admin audit reader (members + boards + settings + partnerships)
  // Gate: RPC internal (is_superadmin OR can_by_member('manage_platform'))
  mcp.tool("get_audit_log", "Unified audit log: member status/role transitions, board lifecycle, platform settings, partnership interactions. Admin only (manage_platform). Supports filters by actor, target, action keyword, date range.", {
    actor_id: z.string().optional().describe("UUID of actor to filter by"),
    target_id: z.string().optional().describe("UUID of target to filter by"),
    action: z.string().optional().describe("Substring match on action/category/name"),
    date_from: z.string().optional().describe("ISO timestamp — include entries after this"),
    date_to: z.string().optional().describe("ISO timestamp — include entries before this"),
    limit: z.number().optional().describe("Max rows to return. Default 50, max 500"),
    offset: z.number().optional().describe("Pagination offset. Default 0")
  }, async (params: { actor_id?: string; target_id?: string; action?: string; date_from?: string; date_to?: string; limit?: number; offset?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_audit_log", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_audit_log", {
      p_actor_id: params.actor_id ?? null,
      p_target_id: params.target_id ?? null,
      p_action: params.action ?? null,
      p_date_from: params.date_from ?? null,
      p_date_to: params.date_to ?? null,
      p_limit: Math.min(params.limit ?? 50, 500),
      p_offset: params.offset ?? 0,
    });
    if (error) { await logUsage(sb, member.id, "get_audit_log", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_audit_log", true, undefined, start);
    return ok(data);
  });

  // get_my_pii_access_log — LGPD Art. 18 direct-subject access to who read their PII
  mcp.tool("get_my_pii_access_log", "LGPD Art. 18 — returns a log of who accessed YOUR personally-identifiable data (name/email/phone/etc.), with accessor name/role, fields accessed, context, and timestamp.", {
    limit: z.number().optional().describe("Max rows to return. Default 50, max 500")
  }, async (params: { limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_pii_access_log", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_pii_access_log", {
      p_limit: Math.min(params.limit ?? 50, 500),
    });
    if (error) { await logUsage(sb, member.id, "get_my_pii_access_log", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_pii_access_log", true, undefined, start);
    return ok(data);
  });

  // get_pii_access_log_admin — DPO/manager-level PII access reader
  // Gate: RPC internal (is_superadmin OR manager OR deputy_manager)
  mcp.tool("get_pii_access_log_admin", "DPO view: PII access log across the platform with accessor/target/fields. Admin only. Filters by target_member_id, accessor_id, days window.", {
    target_member_id: z.string().optional().describe("Filter by specific member whose PII was accessed"),
    accessor_id: z.string().optional().describe("Filter by specific accessor"),
    days: z.number().optional().describe("Lookback window in days. Default 30"),
    limit: z.number().optional().describe("Max rows. Default 500, capped at 2000")
  }, async (params: { target_member_id?: string; accessor_id?: string; days?: number; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_pii_access_log_admin", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_pii_access_log_admin", {
      p_target_member_id: params.target_member_id ?? null,
      p_accessor_id: params.accessor_id ?? null,
      p_days: params.days ?? 30,
      p_limit: Math.min(params.limit ?? 500, 2000),
    });
    if (error) { await logUsage(sb, member.id, "get_pii_access_log_admin", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_pii_access_log_admin", true, undefined, start);
    return ok(data);
  });

  // export_audit_log_csv — DPO-facing CSV export for compliance audits
  // Gate: RPC internal
  mcp.tool("export_audit_log_csv", "DPO compliance export: audit log entries as CSV text. Filters by category (all/members/boards/settings/partnerships) and date range.", {
    category: z.string().optional().describe("Category filter: 'all' | 'members' | 'boards' | 'settings' | 'partnerships'. Default 'all'"),
    start_date: z.string().optional().describe("Start date YYYY-MM-DD"),
    end_date: z.string().optional().describe("End date YYYY-MM-DD")
  }, async (params: { category?: string; start_date?: string; end_date?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "export_audit_log_csv", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("export_audit_log_csv", {
      p_category: params.category ?? 'all',
      p_start_date: params.start_date ?? null,
      p_end_date: params.end_date ?? null,
    });
    if (error) { await logUsage(sb, member.id, "export_audit_log_csv", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "export_audit_log_csv", true, undefined, start);
    return ok(data);
  });

  // get_chain_audit_report — governance approval chain audit trail (ADR-0016)
  mcp.tool("get_chain_audit_report", "Returns the full audit trail for an IP ratification / cooperation agreement approval chain: signoff timeline + integrity summary. For governance review.", {
    chain_id: z.string().describe("UUID of the approval_chains row")
  }, async (params: { chain_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_chain_audit_report", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.chain_id)) { await logUsage(sb, member.id, "get_chain_audit_report", false, "Invalid chain_id", start); return err("chain_id must be a UUID"); }
    const { data, error } = await sb.rpc("get_chain_audit_report", { p_chain_id: params.chain_id });
    if (error) { await logUsage(sb, member.id, "get_chain_audit_report", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_chain_audit_report", true, undefined, start);
    return ok(data);
  });

  // list_orphan_card_assignments — #91 G7 surface: board_taxonomy_alerts of offboard orphans
  // Gate: RPC internal (can_by_member 'manage_member')
  mcp.tool("list_orphan_card_assignments", "Lists unresolved board cards still assigned to offboarded/inactive/observer members. Admin triage for reassignment. Filters by chapter or tribe_id.", {
    tribe_id: z.number().optional().describe("Filter by tribe ID"),
    chapter: z.string().optional().describe("Filter by chapter code (e.g. 'PMI-GO')"),
    limit: z.number().optional().describe("Max cards to return. Default 100, max 500")
  }, async (params: { tribe_id?: number; chapter?: string; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_orphan_card_assignments", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("list_orphan_card_assignments", {
      p_tribe_id: params.tribe_id ?? null,
      p_chapter: params.chapter ?? null,
      p_limit: Math.min(params.limit ?? 100, 500),
    });
    if (error) { await logUsage(sb, member.id, "list_orphan_card_assignments", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_orphan_card_assignments", true, undefined, start);
    return ok(data);
  });

  // ───────────────────────────────────────────────────────────────
  // GOVERNANCE WORKFLOW TOOLS — #85 Onda B bundle 2
  // Document comments, IP ratification signing, change requests
  // ───────────────────────────────────────────────────────────────

  // sign_ratification_gate — sign a gate on an IP ratification / cooperation approval chain
  // Gate: RPC internal (validates gate_kind role eligibility + UE consent when required)
  mcp.tool("sign_ratification_gate", "Sign a gate on an IP ratification or cooperation agreement approval chain (ADR-0016). signoff_type can be 'approval' or 'rejection'. Optional sections_verified jsonb and comment. UE consent flag required for external_signer gates.", {
    chain_id: z.string().describe("UUID of approval_chains row"),
    gate_kind: z.string().describe("Gate kind (e.g. 'curator', 'leader_awareness', 'submitter_acceptance', 'chapter_witness', 'president_go', 'member_ratification')"),
    signoff_type: z.string().optional().describe("'approval' (default) or 'rejection'"),
    sections_verified: z.string().optional().describe("JSON string listing which sections the signer verified"),
    comment_body: z.string().optional().describe("Optional comment posted alongside the signoff"),
    ue_consent_49_1_a: z.boolean().optional().describe("GDPR/LGPD Art. 49.1.a explicit consent (required for external_signer gates)")
  }, async (params: { chain_id: string; gate_kind: string; signoff_type?: string; sections_verified?: string; comment_body?: string; ue_consent_49_1_a?: boolean }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "sign_ratification_gate", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.chain_id)) { await logUsage(sb, member.id, "sign_ratification_gate", false, "Invalid chain_id", start); return err("chain_id must be a UUID"); }
    let sections: any = null;
    if (params.sections_verified) {
      try { sections = JSON.parse(params.sections_verified); }
      catch { await logUsage(sb, member.id, "sign_ratification_gate", false, "Invalid sections JSON", start); return err("sections_verified must be valid JSON"); }
    }
    const { data, error } = await sb.rpc("sign_ip_ratification", {
      p_chain_id: params.chain_id,
      p_gate_kind: params.gate_kind,
      p_signoff_type: params.signoff_type ?? 'approval',
      p_sections_verified: sections,
      p_comment_body: params.comment_body ?? null,
      p_ue_consent_49_1_a: params.ue_consent_49_1_a ?? null,
    });
    if (error) { await logUsage(sb, member.id, "sign_ratification_gate", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "sign_ratification_gate", true, undefined, start);
    return ok(data);
  });

  // add_document_comment — post a clause-anchored comment on a document version
  mcp.tool("add_document_comment", "Post a comment on a document version. Anchor to a clause identifier (e.g. '§2.5', 'Art. 4'). Visibility: 'public' (all viewers) | 'signers_only' (approval_chain roles) | 'private' (author only). Optional parent_id for threaded replies.", {
    version_id: z.string().describe("UUID of document_versions row"),
    clause_anchor: z.string().describe("Clause/section anchor (e.g. '§2.5', 'Art. 4', 'preamble')"),
    body: z.string().describe("Comment body text"),
    visibility: z.string().describe("'public' | 'signers_only' | 'private'"),
    parent_id: z.string().optional().describe("UUID of parent comment for threaded reply")
  }, async (params: { version_id: string; clause_anchor: string; body: string; visibility: string; parent_id?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "add_document_comment", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.version_id)) { await logUsage(sb, member.id, "add_document_comment", false, "Invalid version_id", start); return err("version_id must be a UUID"); }
    if (params.parent_id && !isUUID(params.parent_id)) { await logUsage(sb, member.id, "add_document_comment", false, "Invalid parent_id", start); return err("parent_id must be a UUID"); }
    const { data, error } = await sb.rpc("create_document_comment", {
      p_version_id: params.version_id,
      p_clause_anchor: params.clause_anchor,
      p_body: params.body,
      p_visibility: params.visibility,
      p_parent_id: params.parent_id ?? null,
    });
    if (error) { await logUsage(sb, member.id, "add_document_comment", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "add_document_comment", true, undefined, start);
    return ok(data);
  });

  // list_document_comments — read thread of comments on a document version
  mcp.tool("list_document_comments", "List comments on a document version. Returns threaded structure with clause_anchor + body + author + resolution state. By default excludes resolved comments.", {
    version_id: z.string().describe("UUID of document_versions row"),
    include_resolved: z.boolean().optional().describe("If true, also return resolved comments. Default false")
  }, async (params: { version_id: string; include_resolved?: boolean }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_document_comments", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.version_id)) { await logUsage(sb, member.id, "list_document_comments", false, "Invalid version_id", start); return err("version_id must be a UUID"); }
    const { data, error } = await sb.rpc("list_document_comments", {
      p_version_id: params.version_id,
      p_include_resolved: params.include_resolved ?? false,
    });
    if (error) { await logUsage(sb, member.id, "list_document_comments", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_document_comments", true, undefined, start);
    return ok(data);
  });

  // resolve_document_comment — mark a comment (and descendants) as resolved
  mcp.tool("resolve_document_comment", "Mark a document comment as resolved, with optional resolution note. Permission: original commenter OR document curator OR approval chain signer.", {
    comment_id: z.string().describe("UUID of document_comments row"),
    resolution_note: z.string().optional().describe("Optional note explaining how the comment was addressed")
  }, async (params: { comment_id: string; resolution_note?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "resolve_document_comment", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.comment_id)) { await logUsage(sb, member.id, "resolve_document_comment", false, "Invalid comment_id", start); return err("comment_id must be a UUID"); }
    const { data, error } = await sb.rpc("resolve_document_comment", {
      p_comment_id: params.comment_id,
      p_resolution_note: params.resolution_note ?? null,
    });
    if (error) { await logUsage(sb, member.id, "resolve_document_comment", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "resolve_document_comment", true, undefined, start);
    return ok(data);
  });

  // submit_change_request — create a new change_request (CR) targeting Manual sections / GCs
  mcp.tool("submit_change_request", "Submit a change request (CR) proposing edits to Manual sections or GC overrides. cr_type: 'manual_edit' | 'gc_override' | 'policy_update'. impact_level: 'low' | 'medium' | 'high' | 'critical'. Routes to review queue per type.", {
    title: z.string().describe("Short title"),
    description: z.string().describe("Detailed description of the change"),
    cr_type: z.string().describe("'manual_edit' | 'gc_override' | 'policy_update'"),
    manual_section_ids: z.array(z.string()).optional().describe("UUIDs of affected manual_sections (for manual_edit type)"),
    gc_references: z.array(z.string()).optional().describe("GC identifiers affected (e.g. ['GC-097','GC-162'])"),
    impact_level: z.string().optional().describe("'low' (default 'medium') | 'medium' | 'high' | 'critical'"),
    impact_description: z.string().optional().describe("Describe who/what is affected"),
    justification: z.string().optional().describe("Why this change is necessary")
  }, async (params: { title: string; description: string; cr_type: string; manual_section_ids?: string[]; gc_references?: string[]; impact_level?: string; impact_description?: string; justification?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "submit_change_request", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("submit_change_request", {
      p_title: params.title,
      p_description: params.description,
      p_cr_type: params.cr_type,
      p_manual_section_ids: params.manual_section_ids ?? null,
      p_gc_references: params.gc_references ?? null,
      p_impact_level: params.impact_level ?? 'medium',
      p_impact_description: params.impact_description ?? null,
      p_justification: params.justification ?? null,
    });
    if (error) { await logUsage(sb, member.id, "submit_change_request", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "submit_change_request", true, undefined, start);
    return ok(data);
  });

  // approve_change_request — signoff on a CR (approval or rejection), recorded with signature hash
  mcp.tool("approve_change_request", "Record your signoff on a change request. action: 'approve' | 'reject' | 'abstain'. Signature hash + timestamp captured for audit. Permissions: CR approver role assigned to the CR.", {
    cr_id: z.string().describe("UUID of change_requests row"),
    action: z.string().describe("'approve' | 'reject' | 'abstain'"),
    comment: z.string().optional().describe("Optional comment posted with the signoff")
  }, async (params: { cr_id: string; action: string; comment?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "approve_change_request", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.cr_id)) { await logUsage(sb, member.id, "approve_change_request", false, "Invalid cr_id", start); return err("cr_id must be a UUID"); }
    const { data, error } = await sb.rpc("approve_change_request", {
      p_cr_id: params.cr_id,
      p_action: params.action,
      p_comment: params.comment ?? null,
    });
    if (error) { await logUsage(sb, member.id, "approve_change_request", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "approve_change_request", true, undefined, start);
    return ok(data);
  });

  // review_change_request — intermediate review step (distinct from final approve)
  mcp.tool("review_change_request", "Post a review on a CR — intermediate step before final approval. action: 'request_changes' | 'ready_for_approval' | 'comment'.", {
    cr_id: z.string().describe("UUID of change_requests row"),
    action: z.string().describe("'request_changes' | 'ready_for_approval' | 'comment'"),
    notes: z.string().describe("Review notes body")
  }, async (params: { cr_id: string; action: string; notes: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "review_change_request", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.cr_id)) { await logUsage(sb, member.id, "review_change_request", false, "Invalid cr_id", start); return err("cr_id must be a UUID"); }
    const { data, error } = await sb.rpc("review_change_request", {
      p_cr_id: params.cr_id,
      p_action: params.action,
      p_notes: params.notes,
    });
    if (error) { await logUsage(sb, member.id, "review_change_request", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "review_change_request", true, undefined, start);
    return ok(data);
  });

  // list_change_requests — list CRs filterable by status / type
  mcp.tool("list_change_requests", "List change requests with optional status/type filters. Status: 'draft' | 'under_review' | 'approved' | 'rejected' | 'withdrawn'.", {
    status: z.string().optional().describe("Filter by status"),
    cr_type: z.string().optional().describe("Filter by CR type")
  }, async (params: { status?: string; cr_type?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_change_requests", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_change_requests", {
      p_status: params.status ?? null,
      p_cr_type: params.cr_type ?? null,
    });
    if (error) { await logUsage(sb, member.id, "list_change_requests", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_change_requests", true, undefined, start);
    return ok(data);
  });

  // ───────────────────────────────────────────────────────────────
  // PARTNERSHIP LIFECYCLE TOOLS — #85 Onda B bundle 3
  // ───────────────────────────────────────────────────────────────

  // log_partner_interaction — record a meeting/call/email with a partner entity
  mcp.tool("log_partner_interaction", "Log an interaction (meeting/call/email/doc) with a partner entity. Optional outcome + next_action + follow_up_date for pipeline tracking.", {
    partner_id: z.string().describe("UUID of partner_entities row"),
    interaction_type: z.string().describe("'meeting' | 'call' | 'email' | 'document' | 'whatsapp' | 'other'"),
    summary: z.string().describe("Short summary of the interaction"),
    details: z.string().optional().describe("Long-form notes"),
    outcome: z.string().optional().describe("Outcome or decision"),
    next_action: z.string().optional().describe("Planned next step"),
    follow_up_date: z.string().optional().describe("Follow-up date YYYY-MM-DD")
  }, async (params: { partner_id: string; interaction_type: string; summary: string; details?: string; outcome?: string; next_action?: string; follow_up_date?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "log_partner_interaction", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.partner_id)) { await logUsage(sb, member.id, "log_partner_interaction", false, "Invalid partner_id", start); return err("partner_id must be a UUID"); }
    const { data, error } = await sb.rpc("add_partner_interaction", {
      p_partner_id: params.partner_id,
      p_interaction_type: params.interaction_type,
      p_summary: params.summary,
      p_details: params.details ?? null,
      p_outcome: params.outcome ?? null,
      p_next_action: params.next_action ?? null,
      p_follow_up_date: params.follow_up_date ?? null,
    });
    if (error) { await logUsage(sb, member.id, "log_partner_interaction", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "log_partner_interaction", true, undefined, start);
    return ok(data);
  });

  // list_partner_interactions — chronological feed of a partner's interactions
  mcp.tool("list_partner_interactions", "List all interactions for a partner entity, newest first.", {
    partner_id: z.string().describe("UUID of partner_entities row")
  }, async (params: { partner_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_partner_interactions", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.partner_id)) { await logUsage(sb, member.id, "list_partner_interactions", false, "Invalid partner_id", start); return err("partner_id must be a UUID"); }
    const { data, error } = await sb.rpc("get_partner_interactions", { p_partner_id: params.partner_id });
    if (error) { await logUsage(sb, member.id, "list_partner_interactions", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_partner_interactions", true, undefined, start);
    return ok(data);
  });

  // list_partner_attachments — attachments linked to a partner entity
  mcp.tool("list_partner_attachments", "List attachments (proposals, MoUs, draft contracts, meeting notes) filed against a partner entity.", {
    partner_id: z.string().describe("UUID of partner_entities row")
  }, async (params: { partner_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_partner_attachments", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.partner_id)) { await logUsage(sb, member.id, "list_partner_attachments", false, "Invalid partner_id", start); return err("partner_id must be a UUID"); }
    const { data, error } = await sb.rpc("get_partner_entity_attachments", { p_entity_id: params.partner_id });
    if (error) { await logUsage(sb, member.id, "list_partner_attachments", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_partner_attachments", true, undefined, start);
    return ok(data);
  });

  // get_partner_followups — upcoming/overdue follow-ups across all partnerships
  mcp.tool("get_partner_followups", "Upcoming + overdue follow-ups across all partner entities (from partner_interactions.follow_up_date). Useful for 'what partner calls are due this week?'", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_partner_followups", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_partner_followups");
    if (error) { await logUsage(sb, member.id, "get_partner_followups", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_partner_followups", true, undefined, start);
    return ok(data);
  });

  // list_my_signatures — LGPD Art. 18 self-service signature history
  mcp.tool("list_my_signatures", "LGPD Art. 18 — returns YOUR signature history (approval chain gates + document ratifications). Includes document title, version, chain status, signed timestamp, certificate id.", {
    include_superseded: z.boolean().optional().describe("If true, include ratifications that were superseded by a later version. Default false (current only).")
  }, async (params: { include_superseded?: boolean }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_my_signatures", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_signatures", {
      p_include_superseded: params.include_superseded ?? false,
    });
    if (error) { await logUsage(sb, member.id, "list_my_signatures", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_my_signatures", true, undefined, start);
    return ok(data);
  });

  // list_document_versions — full version history of a governance document
  mcp.tool("list_document_versions", "Returns version history of a governance document (newest first). Each row has version_number, label, authored_by, locked_at, is_current, content_html_length, comments_total + comments_unresolved. Use for review UX and version diff setup.", {
    document_id: z.string().describe("UUID of governance_documents row")
  }, async (params: { document_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_document_versions", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.document_id)) { await logUsage(sb, member.id, "list_document_versions", false, "Invalid document_id", start); return err("document_id must be a UUID"); }
    const { data, error } = await sb.rpc("list_document_versions", { p_document_id: params.document_id });
    if (error) { await logUsage(sb, member.id, "list_document_versions", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_document_versions", true, undefined, start);
    return ok(data);
  });

  // get_version_diff — side-by-side content pair for two versions of the same document
  mcp.tool("get_version_diff", "Compare two document versions. Returns pre_computed_diff (chars_delta, lines_added/removed — auto-populated via trigger), version metadata, and optionally full content. Set include_content=false for lightweight response (~5% of full size) when you only need stats. Validates both versions belong to same document.", {
    version_a: z.string().describe("UUID of first document_versions row"),
    version_b: z.string().describe("UUID of second document_versions row"),
    include_content: z.boolean().optional().describe("If true (default), include content_html + content_markdown in response. Set false for stats-only (~95% smaller payload for large docs).")
  }, async (params: { version_a: string; version_b: string; include_content?: boolean }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_version_diff", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.version_a) || !isUUID(params.version_b)) { await logUsage(sb, member.id, "get_version_diff", false, "Invalid version id", start); return err("both version ids must be UUIDs"); }
    const { data, error } = await sb.rpc("get_version_diff", {
      p_version_a: params.version_a,
      p_version_b: params.version_b,
      p_include_content: params.include_content ?? true,
    });
    if (error) { await logUsage(sb, member.id, "get_version_diff", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_version_diff", true, undefined, start);
    return ok(data);
  });

  // get_document_detail — composite read (doc + current version + active chain + signoffs + comments)
  mcp.tool("get_document_detail", "Composite read: governance_document + current_version summary + active approval_chain (with signed_gates and pending_gates_for_me) + draft_versions list + comments_total/unresolved. Single round-trip for review UX. Use to pull everything about a document.", {
    document_id: z.string().describe("UUID of governance_documents row")
  }, async (params: { document_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_document_detail", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.document_id)) { await logUsage(sb, member.id, "get_document_detail", false, "Invalid document_id", start); return err("document_id must be a UUID"); }
    const { data, error } = await sb.rpc("get_document_detail", { p_document_id: params.document_id });
    if (error) { await logUsage(sb, member.id, "get_document_detail", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_document_detail", true, undefined, start);
    return ok(data);
  });

  // propose_new_version — create a new draft version of a governance document
  mcp.tool("propose_new_version", "Create a new DRAFT version of a governance document. version_number auto-incremented. Requires manage_member authority. Returns version_id + version_number + version_label. Does NOT start approval chain — use lock_document_version after content is final.", {
    document_id: z.string().describe("UUID of governance_documents row"),
    content_html: z.string().describe("Full version content in HTML (required, non-empty)"),
    content_markdown: z.string().optional().describe("Optional Markdown source"),
    version_label: z.string().optional().describe("Optional label (e.g., 'v2.2'). Default: auto-generated 'Rascunho vN'"),
    notes: z.string().optional().describe("Optional change notes / rationale for this version")
  }, async (params: { document_id: string; content_html: string; content_markdown?: string; version_label?: string; notes?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "propose_new_version", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.document_id)) { await logUsage(sb, member.id, "propose_new_version", false, "Invalid document_id", start); return err("document_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "propose_new_version", false, "Unauthorized", start); return err("Unauthorized — manage_member authority required"); }
    const { data, error } = await sb.rpc("upsert_document_version", {
      p_document_id: params.document_id,
      p_content_html: params.content_html,
      p_content_markdown: params.content_markdown ?? null,
      p_version_label: params.version_label ?? null,
      p_version_id: null,
      p_notes: params.notes ?? null,
    });
    if (error) { await logUsage(sb, member.id, "propose_new_version", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "propose_new_version", true, undefined, start);
    return ok(data);
  });

  // edit_document_version_draft — update content of an unlocked draft
  mcp.tool("edit_document_version_draft", "Update content of an EXISTING unlocked draft version. Fails if version is locked (immutability). Preserves version_number; optionally updates label/markdown/notes. Requires manage_member authority.", {
    version_id: z.string().describe("UUID of document_versions row to update"),
    content_html: z.string().describe("Updated HTML content (required, non-empty)"),
    content_markdown: z.string().optional().describe("Optional updated Markdown source"),
    version_label: z.string().optional().describe("Optional new label"),
    notes: z.string().optional().describe("Optional change notes")
  }, async (params: { version_id: string; content_html: string; content_markdown?: string; version_label?: string; notes?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "edit_document_version_draft", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.version_id)) { await logUsage(sb, member.id, "edit_document_version_draft", false, "Invalid version_id", start); return err("version_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "edit_document_version_draft", false, "Unauthorized", start); return err("Unauthorized — manage_member authority required"); }
    const { data: existing, error: lookupErr } = await sb.from("document_versions").select("document_id").eq("id", params.version_id).single();
    if (lookupErr || !existing) { await logUsage(sb, member.id, "edit_document_version_draft", false, "Version not found", start); return err("document_version not found"); }
    const { data, error } = await sb.rpc("upsert_document_version", {
      p_document_id: existing.document_id,
      p_content_html: params.content_html,
      p_content_markdown: params.content_markdown ?? null,
      p_version_label: params.version_label ?? null,
      p_version_id: params.version_id,
      p_notes: params.notes ?? null,
    });
    if (error) { await logUsage(sb, member.id, "edit_document_version_draft", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "edit_document_version_draft", true, undefined, start);
    return ok(data);
  });

  // lock_document_version — freeze a draft + open approval chain
  mcp.tool("lock_document_version", "LOCK a draft version (becomes immutable) + open an approval_chain with the provided gates. Sets governance_documents.current_version_id. Fails if version is already locked or if a chain exists. Enqueues gate notifications. Requires manage_member authority.", {
    version_id: z.string().describe("UUID of document_versions row to lock"),
    gates: z.array(z.object({
      kind: z.string().describe("gate kind: curator | leader_awareness | submitter_acceptance | chapter_witness | president_go | president_others | member_ratification | external_signer"),
      order: z.number().describe("Gate order in chain (1-indexed)"),
      threshold: z.union([z.string(), z.number()]).describe("'all' or integer N (minimum signatures required)")
    })).describe("Ordered gate sequence for this approval chain")
  }, async (params: { version_id: string; gates: Array<{ kind: string; order: number; threshold: string | number }> }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "lock_document_version", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.version_id)) { await logUsage(sb, member.id, "lock_document_version", false, "Invalid version_id", start); return err("version_id must be a UUID"); }
    if (!Array.isArray(params.gates) || params.gates.length === 0) { await logUsage(sb, member.id, "lock_document_version", false, "Invalid gates", start); return err("gates must be a non-empty array"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "lock_document_version", false, "Unauthorized", start); return err("Unauthorized — manage_member authority required"); }
    const { data, error } = await sb.rpc("lock_document_version", {
      p_version_id: params.version_id,
      p_gates: params.gates,
    });
    if (error) { await logUsage(sb, member.id, "lock_document_version", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "lock_document_version", true, undefined, start);
    return ok(data);
  });

  // delete_document_version_draft — remove an unlocked draft (emits audit log)
  mcp.tool("delete_document_version_draft", "DELETE an unlocked draft version permanently. Fails if the version is locked (locked versions are immutable). Records the deletion in admin_audit_log. Requires manage_member authority.", {
    version_id: z.string().describe("UUID of document_versions row to delete")
  }, async (params: { version_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "delete_document_version_draft", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.version_id)) { await logUsage(sb, member.id, "delete_document_version_draft", false, "Invalid version_id", start); return err("version_id must be a UUID"); }
    if (!(await canV4(sb, member.id, 'manage_member'))) { await logUsage(sb, member.id, "delete_document_version_draft", false, "Unauthorized", start); return err("Unauthorized — manage_member authority required"); }
    const { data, error } = await sb.rpc("delete_document_version_draft", { p_version_id: params.version_id });
    if (error) { await logUsage(sb, member.id, "delete_document_version_draft", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "delete_document_version_draft", true, undefined, start);
    return ok(data);
  });

  // get_governance_change_log — unified compliance timeline
  mcp.tool("get_governance_change_log", "Unified chronological feed across 6 governance sources (change_requests, document_versions, approval_chains, approval_signoffs, pii_access_log, admin_audit_log). Privileged callers (view_pii) see all events; non-privileged see only their own actor/target scope. Use for LGPD Art. 37 audit and compliance reviews.", {
    since: z.string().optional().describe("ISO-8601 timestamp cutoff. Default: 90 days ago"),
    limit: z.number().optional().describe("Max rows. Default 200, cap 1000")
  }, async (params: { since?: string; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_governance_change_log", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_governance_change_log", {
      p_since: params.since ?? null,
      p_limit: params.limit ?? 200,
    });
    if (error) { await logUsage(sb, member.id, "get_governance_change_log", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_governance_change_log", true, undefined, start);
    return ok(data);
  });

  // link_partner_to_card — UPSERT link between partner_entity and board_item
  mcp.tool("link_partner_to_card", "Link a partner entity to a board card (UPSERT — updates link_role+notes if link already exists). link_role must be one of: general | pipeline | deliverable | follow_up | contract | onboarding. Requires manage_partner authority.", {
    partner_entity_id: z.string().describe("UUID of partner_entities row"),
    board_item_id: z.string().describe("UUID of board_items row"),
    link_role: z.string().optional().describe("general | pipeline | deliverable | follow_up | contract | onboarding. Default 'general'"),
    notes: z.string().optional().describe("Optional link context/notes")
  }, async (params: { partner_entity_id: string; board_item_id: string; link_role?: string; notes?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "link_partner_to_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.partner_entity_id) || !isUUID(params.board_item_id)) { await logUsage(sb, member.id, "link_partner_to_card", false, "Invalid UUID", start); return err("partner_entity_id and board_item_id must be UUIDs"); }
    if (!(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "link_partner_to_card", false, "Unauthorized", start); return err("Unauthorized — manage_partner authority required"); }
    const { data, error } = await sb.rpc("link_partner_to_card", {
      p_partner_entity_id: params.partner_entity_id,
      p_board_item_id: params.board_item_id,
      p_link_role: params.link_role ?? 'general',
      p_notes: params.notes ?? null,
    });
    if (error) { await logUsage(sb, member.id, "link_partner_to_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "link_partner_to_card", true, undefined, start);
    return ok(data);
  });

  // unlink_partner_from_card — remove link
  mcp.tool("unlink_partner_from_card", "Remove a partner↔card link. Idempotent (returns success=false if no row matched). Requires manage_partner authority.", {
    partner_entity_id: z.string().describe("UUID of partner_entities row"),
    board_item_id: z.string().describe("UUID of board_items row")
  }, async (params: { partner_entity_id: string; board_item_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "unlink_partner_from_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.partner_entity_id) || !isUUID(params.board_item_id)) { await logUsage(sb, member.id, "unlink_partner_from_card", false, "Invalid UUID", start); return err("both ids must be UUIDs"); }
    if (!(await canV4(sb, member.id, 'manage_partner'))) { await logUsage(sb, member.id, "unlink_partner_from_card", false, "Unauthorized", start); return err("Unauthorized — manage_partner authority required"); }
    const { data, error } = await sb.rpc("unlink_partner_from_card", {
      p_partner_entity_id: params.partner_entity_id,
      p_board_item_id: params.board_item_id,
    });
    if (error) { await logUsage(sb, member.id, "unlink_partner_from_card", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "unlink_partner_from_card", true, undefined, start);
    return ok(data);
  });

  // list_partner_cards — board cards linked to a partner
  mcp.tool("list_partner_cards", "List all board cards linked to a partner entity. Returns link_role, board_item (title, status, due_date, assignee_name), board_name, partner_name, linked_by_name. Use to answer 'which cards is PMI-CE driving?' or 'what's the backlog for Partner X?'.", {
    partner_entity_id: z.string().describe("UUID of partner_entities row")
  }, async (params: { partner_entity_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_partner_cards", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.partner_entity_id)) { await logUsage(sb, member.id, "list_partner_cards", false, "Invalid partner_entity_id", start); return err("partner_entity_id must be a UUID"); }
    const { data, error } = await sb.rpc("list_partner_cards", { p_partner_entity_id: params.partner_entity_id });
    if (error) { await logUsage(sb, member.id, "list_partner_cards", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_partner_cards", true, undefined, start);
    return ok(data);
  });

  // list_card_partners — inverse: partners linked to a card
  mcp.tool("list_card_partners", "Inverse of list_partner_cards. Returns all partners linked to a given board card — useful for opening a card and understanding which partners are stakeholders. Returns link_role, partner_name, chapter, entity_type, status, contact_name, linked_by_name.", {
    board_item_id: z.string().describe("UUID of board_items row")
  }, async (params: { board_item_id: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "list_card_partners", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!isUUID(params.board_item_id)) { await logUsage(sb, member.id, "list_card_partners", false, "Invalid board_item_id", start); return err("board_item_id must be a UUID"); }
    const { data, error } = await sb.rpc("list_card_partners", { p_board_item_id: params.board_item_id });
    if (error) { await logUsage(sb, member.id, "list_card_partners", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_card_partners", true, undefined, start);
    return ok(data);
  });

  // search_partner_cards — cross-partner admin view with filters
  mcp.tool("search_partner_cards", "Cross-partner search of partner↔card links with optional filters. Use for queries like 'all deliverable cards across partners' or 'contract cards for PMI-CE chapter'. Returns full join: partner + card + board + assignee + linker.", {
    link_role: z.string().optional().describe("Filter by link_role: general | pipeline | deliverable | follow_up | contract | onboarding"),
    card_status: z.string().optional().describe("Filter by board_item status"),
    chapter: z.string().optional().describe("Filter by partner.chapter (e.g., 'PMI-CE')"),
    limit: z.number().optional().describe("Max rows. Default 100, cap 500")
  }, async (params: { link_role?: string; card_status?: string; chapter?: string; limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "search_partner_cards", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("search_partner_cards", {
      p_link_role: params.link_role ?? null,
      p_card_status: params.card_status ?? null,
      p_chapter: params.chapter ?? null,
      p_limit: params.limit ?? 100,
    });
    if (error) { await logUsage(sb, member.id, "search_partner_cards", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "search_partner_cards", true, undefined, start);
    return ok(data);
  });
}

// MCP endpoint — Native Streamable HTTP via WebStandardStreamableHTTPServerTransport
// SDK 1.29.0 handles all protocol details: initialize, session, tools/list, tool/call, SSE
app.all("/mcp", async (c) => {
  try {
    const authHeader = c.req.header("Authorization");
    const token = authHeader?.replace("Bearer ", "");

    const sb = createAuthenticatedClient(token);
    const mcp = new McpServer({ name: "nucleo-ia-hub", version: "2.23.1" });
    registerKnowledge(mcp, sb);
    registerTools(mcp, sb);

    const transport = new WebStandardStreamableHTTPServerTransport({
      sessionIdGenerator: undefined, // stateless mode — no session persistence
    });

    await mcp.connect(transport);
    const response = await transport.handleRequest(c.req.raw);
    transport.onclose = () => mcp.close();

    return response;
  } catch (e: any) {
    console.error("[MCP] Handler error:", e.message, e.stack?.substring(0, 300));
    return c.json({ jsonrpc: "2.0", id: null, error: { code: -32603, message: e.message } }, 500);
  }
});

// Health check
app.get("/health", (c) => c.json({ status: "ok", version: "2.23.1", tools: 138, transport: "native-streamable-http", sdk: "1.29.0" }));

Deno.serve(app.fetch);

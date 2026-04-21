// supabase/functions/nucleo-mcp/index.ts
// MCP server v2.11.0 — 76 tools (61R + 15W) + 1 prompt + 1 resource + usage logging
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

// --- Register 76 tools (61R + 15W) ---

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
}

// MCP endpoint — Native Streamable HTTP via WebStandardStreamableHTTPServerTransport
// SDK 1.29.0 handles all protocol details: initialize, session, tools/list, tool/call, SSE
app.all("/mcp", async (c) => {
  try {
    const authHeader = c.req.header("Authorization");
    const token = authHeader?.replace("Bearer ", "");

    const sb = createAuthenticatedClient(token);
    const mcp = new McpServer({ name: "nucleo-ia-hub", version: "2.11.0" });
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
app.get("/health", (c) => c.json({ status: "ok", version: "2.11.0", tools: 76, transport: "native-streamable-http", sdk: "1.29.0" }));

Deno.serve(app.fetch);

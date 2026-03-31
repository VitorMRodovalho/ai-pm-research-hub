// supabase/functions/nucleo-mcp/index.ts
// MCP server v2.8.0 — 52 tools (45R + 7W) + 1 prompt + 1 resource + usage logging
// Transport: SDK 1.28.0 WebStandardStreamableHTTPServerTransport (native Streamable HTTP)
// GC-132/133: Phase 1+2 | GC-161: P1 | GC-164: P2

import { Hono } from "jsr:@hono/hono";
import { McpServer } from "npm:@modelcontextprotocol/sdk@1.28.0/server/mcp.js";
import { WebStandardStreamableHTTPServerTransport } from "npm:@modelcontextprotocol/sdk@1.28.0/server/webStandardStreamableHttp.js";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { z } from "npm:zod@^3.25";

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

const WRITE_ROLES = ["manager", "deputy_manager", "tribe_leader"];

function canWrite(member: { operational_role: string; is_superadmin?: boolean }) {
  return member.is_superadmin || WRITE_ROLES.includes(member.operational_role);
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
      const isAdmin = member.is_superadmin || ["manager", "deputy_manager"].includes(role);
      const isLeader = WRITE_ROLES.includes(role) || member.is_superadmin;
      const isSponsor = designations.includes("sponsor") || role === "sponsor";
      const isComms = designations.includes("comms_lead");
      const isLiaison = designations.includes("chapter_liaison");
      const hasTribe = !!member.tribe_id;

      // Build personalized tool guide
      const sections: string[] = [];

      sections.push(`## Seu perfil
- **Nome:** ${member.name}
- **Papel:** ${role}${member.is_superadmin ? " (superadmin)" : ""}
- **Tribo:** ${hasTribe ? `Tribo ${member.tribe_id}` : "Sem tribo fixa (manager/founder)"}
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
        sections.push(`### Nota sobre rotas de tribo
Seu perfil não tem \`tribe_id\` fixo. Para consultar dados de uma tribo específica, use ferramentas que aceitam \`tribe_id\` como parâmetro:
- \`get_tribe_dashboard\` com \`tribe_id=1\` a \`8\`
- \`get_tribe_deliverables\` com \`tribe_id=1\` a \`8\`
Rotas como \`get_my_tribe_members\` retornarão "No tribe assigned" — isso é esperado.`);
      }

      if (isLeader) {
        sections.push(`### Escrita (líder/gestor)
- \`create_board_card\` — Criar card no board da tribo
- \`update_card_status\` — Mover card entre colunas (backlog→in_progress→review→done)
- \`create_meeting_notes\` — Criar ata de reunião (precisa event_id)
- \`register_attendance\` — Registrar presença (precisa event_id + member_id)
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

      if (isAdmin) {
        sections.push(`### Gestão/GP (Admin)
- \`get_tribe_dashboard\` — Dashboard completo de qualquer tribo (tribe_id 1-8)
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
      description: "Lista todas as 47 ferramentas do Núcleo MCP com parâmetros e permissões.",
      mimeType: "text/markdown",
    },
    async () => ({
      contents: [{
        uri: "nucleo://tools/reference",
        text: `# Núcleo IA MCP — Referência de Ferramentas (v2.8.0)

## 50 ferramentas: 43 leitura + 7 escrita

### Tier 1 — Todos os membros (17 leitura)
| # | Ferramenta | Parâmetros | Descrição |
|---|-----------|-----------|-----------|
| 1 | get_my_profile | — | Perfil: nome, papel, tribo, XP, badges |
| 2 | get_my_board_status | board_id? | Cards do board agrupados por status |
| 3 | get_my_tribe_attendance | — | Grade de presença da tribo |
| 4 | get_my_tribe_members | — | Membros ativos com papéis |
| 5 | get_upcoming_events | — | Eventos dos próximos 7 dias |
| 6 | get_my_xp_and_ranking | — | XP por categoria + posição |
| 7 | get_meeting_notes | limit? | Últimas atas de reunião |
| 8 | get_my_notifications | — | Notificações não lidas |
| 9 | search_board_cards | query | Busca full-text em cards |
| 10 | get_hub_announcements | — | Avisos ativos do Hub |
| 11 | get_my_attendance_history | limit? | Histórico pessoal de presença |
| 12 | list_tribe_webinars | status? | Webinars da tribo/capítulo |
| 13 | get_comms_pending_webinars | — | Webinars pendentes de comunicação |
| 14 | get_my_certificates | — | Certificações, badges, trilhas |
| 15 | search_hub_resources | query, asset_type?, limit? | Biblioteca de recursos (247+) |
| 16 | get_attendance_ranking | — | Ranking de presença |
| 17 | get_chapter_kpis | chapter? | KPIs por capítulo |

### Tier 2 — Líderes (6 escrita)
| # | Ferramenta | Parâmetros | Descrição |
|---|-----------|-----------|-----------|
| 18 | create_board_card | title, description?, priority?, due_date?, tags? | Criar card |
| 19 | update_card_status | card_id, status | Mover card |
| 20 | create_meeting_notes | event_id, content, decisions?, action_items? | Criar ata |
| 21 | register_attendance | event_id, member_id, present | Registrar presença |
| 22 | send_notification_to_tribe | title, body, link? | Notificar tribo |
| 23 | create_tribe_event | title, date, type?, duration_minutes? | Criar evento |

### Tier 3 — GP/Admin (12 leitura)
| # | Ferramenta | Parâmetros | Descrição |
|---|-----------|-----------|-----------|
| 24 | get_tribe_dashboard | tribe_id? | Dashboard completo da tribo |
| 25 | get_portfolio_overview | — | Visão executiva: boards e cards |
| 26 | get_operational_alerts | — | Alertas operacionais |
| 27 | get_cycle_report | — | Relatório do ciclo |
| 28 | get_annual_kpis | — | KPIs anuais (admin/sponsor) |
| 29 | get_adoption_metrics | — | Métricas de adoção MCP |
| 30 | get_curation_dashboard | — | Workflow de curadoria |
| 31 | get_tribe_deliverables | tribe_id?, cycle_code? | Entregas por tribo |
| 32 | get_anomaly_report | — | Anomalias de dados |
| 33 | get_portfolio_health | cycle_code? | Saúde trimestral |
| 34 | get_volunteer_funnel | cycle? | Funil de seleção |
| 35 | get_campaign_analytics | send_id? | Métricas de campanhas |

### Ferramentas Transversais (7 leitura)
| # | Ferramenta | Parâmetros | Descrição |
|---|-----------|-----------|-----------|
| 36 | get_event_detail | event_id | Detalhe: agenda, ata, ações |
| 37 | get_comms_dashboard | — | Dashboard de comunicação |
| 38 | get_comms_metrics_by_channel | days? | Métricas por canal social |
| 39 | get_partner_pipeline | — | Pipeline de parcerias (sponsor/admin) |
| 40 | get_public_impact_data | — | Impacto público, timeline |
| 41 | get_pilots_summary | — | Pilotos de IA |
| 42 | get_near_events | window_hours? | Eventos próximos |
| 43 | get_current_release | — | Versão atual da plataforma |
| 44 | get_admin_dashboard | — | Dashboard admin (Admin/GP) |
| 45 | get_my_attendance_hours | — | Horas de presença no ciclo |
| 46 | get_my_credly_status | — | Badges Credly e CPMAI |
| 47 | get_board_activities | board_id?, limit? | Atividades recentes dos boards |
| 48 | search_members | query?, tribe_id?, tier?, status? | Buscar membros (Admin/GP) |
| 49 | list_boards | — | Lista boards ativos com IDs |
| 50 | manage_partner | action, id?, name?, status?, notes? | Criar/atualizar parceria (Admin) |

## Notas
- Rotas de escrita (7 tools) requerem: manager, deputy_manager, tribe_leader ou superadmin
- manage_partner: também acessível por sponsors e chapter_liaisons
- Rotas Tier 3 requerem: manager, deputy_manager ou superadmin
- get_annual_kpis e get_portfolio_health também acessíveis por sponsors
- get_partner_pipeline acessível por sponsors e chapter_liaisons
- create_board_card aceita board_id para usuários sem tribe_id (use list_boards)
- Todas as chamadas são logadas em mcp_usage_log
`,
      }],
    })
  );
}

// --- Register 45 tools (39R + 6W) ---

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
  mcp.tool("get_my_board_status", "Returns your tribe's board cards grouped by status.", { board_id: z.string().optional().describe("Board UUID. If omitted, returns your tribe's default board.") }, async (params: { board_id?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_board_status", false, "Not authenticated", start); return err("Not authenticated"); }
    let boardId = params.board_id;
    if (!boardId) { const { data: b } = await sb.from("project_boards").select("id").eq("tribe_id", member.tribe_id).limit(1).single(); boardId = b?.id; }
    if (!boardId) { await logUsage(sb, member.id, "get_my_board_status", false, "No board", start); return err("No board found for your tribe."); }
    const { data: items, error } = await sb.from("board_items").select("id, title, status, tags, due_date").eq("board_id", boardId).neq("status", "archived").order("position", { ascending: true });
    if (error) { await logUsage(sb, member.id, "get_my_board_status", false, error.message, start); return err(error.message); }
    const grouped = { backlog: items.filter((i: any) => i.status === "backlog"), in_progress: items.filter((i: any) => i.status === "in_progress"), review: items.filter((i: any) => i.status === "review"), done: items.filter((i: any) => i.status === "done") };
    await logUsage(sb, member.id, "get_my_board_status", true, undefined, start);
    return ok(grouped);
  });

  // TOOL 3: get_my_tribe_attendance
  mcp.tool("get_my_tribe_attendance", "Returns attendance grid for your tribe members.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member?.tribe_id) { await logUsage(sb, member?.id, "get_my_tribe_attendance", false, "No tribe", start); return err("No tribe assigned."); }
    const { data, error } = await sb.rpc("get_tribe_attendance_grid", { p_tribe_id: member.tribe_id });
    if (error) { await logUsage(sb, member.id, "get_my_tribe_attendance", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_my_tribe_attendance", true, undefined, start);
    return ok(data);
  });

  // TOOL 4: get_my_tribe_members
  mcp.tool("get_my_tribe_members", "Returns the list of active members in your tribe with their roles.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member?.tribe_id) { await logUsage(sb, member?.id, "get_my_tribe_members", false, "No tribe", start); return err("No tribe assigned."); }
    const { data, error } = await sb.from("public_members").select("name, operational_role, designations, chapter, current_cycle_active").eq("tribe_id", member.tribe_id).eq("current_cycle_active", true).order("name");
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
    const { data, error } = await sb.from("events").select("id, title, date, type, tribe_id, duration_minutes, meeting_link").gte("date", today).lte("date", nextWeek).order("date");
    if (error) { await logUsage(sb, member?.id, "get_upcoming_events", false, error.message, start); return err(error.message); }
    await logUsage(sb, member?.id, "get_upcoming_events", true, undefined, start);
    return ok(data);
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

  // TOOL 7: get_meeting_notes
  mcp.tool("get_meeting_notes", "Returns recent meeting notes/minutes for your tribe.", { limit: z.number().optional().describe("Number of recent notes. Default: 5") }, async (params: { limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member?.tribe_id) { await logUsage(sb, member?.id, "get_meeting_notes", false, "No tribe", start); return err("No tribe assigned."); }
    const { data, error } = await sb.rpc("list_meeting_artifacts", { p_tribe_id: member.tribe_id, p_limit: params.limit || 5 });
    if (error) { await logUsage(sb, member.id, "get_meeting_notes", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_meeting_notes", true, undefined, start);
    return ok(data);
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
  mcp.tool("search_board_cards", "Full-text search across board cards in your tribe's board.", { query: z.string().describe("Search term") }, async (params: { query: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member?.tribe_id) { await logUsage(sb, member?.id, "search_board_cards", false, "No tribe", start); return err("No tribe assigned."); }
    const { data, error } = await sb.rpc("search_board_items", { p_query: params.query, p_tribe_id: member.tribe_id });
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
    if (!canWrite(member)) { await logUsage(sb, member.id, "create_board_card", false, "Unauthorized", start); return err("Unauthorized"); }
    let boardId = params.board_id;
    if (!boardId) {
      if (!member.tribe_id) { await logUsage(sb, member.id, "create_board_card", false, "No board", start); return err("No tribe assigned. Pass board_id explicitly. Use get_portfolio_overview to find board IDs."); }
      const { data: board } = await sb.from("project_boards").select("id").eq("tribe_id", member.tribe_id).limit(1).single();
      if (!board) { await logUsage(sb, member.id, "create_board_card", false, "No board", start); return err("No board found for your tribe."); }
      boardId = board.id;
    }
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
    const { error } = await sb.rpc("move_board_item", { p_item_id: params.card_id, p_new_status: params.status });
    if (error) { await logUsage(sb, member.id, "update_card_status", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "update_card_status", true, undefined, start);
    return ok({ action: "update_card_status", status: "updated", card_id: params.card_id, new_status: params.status });
  });

  // TOOL 13: create_meeting_notes
  mcp.tool("create_meeting_notes", "Create meeting minutes for a tribe meeting.", { event_id: z.string().describe("UUID of the event"), content: z.string().describe("Notes content"), decisions: z.string().optional().describe("Key decisions (comma-separated)"), action_items: z.string().optional().describe("Action items (comma-separated)") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "create_meeting_notes", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!canWrite(member)) { await logUsage(sb, member.id, "create_meeting_notes", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data: event } = await sb.from("events").select("title, date, tribe_id").eq("id", params.event_id).single();
    if (!event) { await logUsage(sb, member.id, "create_meeting_notes", false, "Event not found", start); return err("Event not found."); }
    const tribeId = member.is_superadmin ? (event.tribe_id || member.tribe_id) : member.tribe_id;
    const decisions = params.decisions ? String(params.decisions).split(",").map((s: string) => s.trim()) : [];
    const actionItems = params.action_items ? String(params.action_items).split(",").map((s: string) => s.trim()) : [];
    const { data, error } = await sb.from("meeting_artifacts").insert({ event_id: params.event_id, title: `Ata — ${event.title}`, meeting_date: event.date, tribe_id: tribeId, created_by: member.id, agenda_items: actionItems, deliberations: decisions, page_data_snapshot: { notes: params.content }, is_published: true, cycle_code: "cycle_3" }).select("id").single();
    if (error) { await logUsage(sb, member.id, "create_meeting_notes", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "create_meeting_notes", true, undefined, start);
    return ok({ action: "create_meeting_notes", status: "created", id: data.id });
  });

  // TOOL 14: register_attendance
  mcp.tool("register_attendance", "Register attendance for a member at an event.", { event_id: z.string().describe("UUID of the event"), member_id: z.string().describe("UUID of the member"), present: z.boolean().describe("Whether present") }, async (params: { event_id: string; member_id: string; present: boolean }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "register_attendance", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!canWrite(member)) { await logUsage(sb, member.id, "register_attendance", false, "Unauthorized", start); return err("Unauthorized"); }
    if (!params.present) { await logUsage(sb, member.id, "register_attendance", true, undefined, start); return ok({ action: "register_attendance", status: "skipped", note: "Absent — no record created." }); }
    const { data: count, error } = await sb.rpc("register_attendance_batch", { p_event_id: params.event_id, p_member_ids: [params.member_id], p_registered_by: member.id });
    if (error) { await logUsage(sb, member.id, "register_attendance", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "register_attendance", true, undefined, start);
    return ok({ action: "register_attendance", status: "registered", records_affected: count });
  });

  // TOOL 15: send_notification_to_tribe
  mcp.tool("send_notification_to_tribe", "Send a notification to all active members of your tribe.", { title: z.string().describe("Notification title"), body: z.string().describe("Notification message"), link: z.string().optional().describe("URL link") }, async (params: { title: string; body: string; link?: string }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "send_notification_to_tribe", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!canWrite(member)) { await logUsage(sb, member.id, "send_notification_to_tribe", false, "Unauthorized", start); return err("Unauthorized"); }
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
  mcp.tool("get_my_attendance_history", "Returns your personal attendance history — which meetings you attended or missed.", { limit: z.number().optional().describe("Number of recent events. Default: 20") }, async (params: { limit?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_my_attendance_history", false, "Not authenticated", start); return err("Not authenticated"); }
    const { data, error } = await sb.rpc("get_my_attendance_history", { p_limit: params.limit || 20 });
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
    if (!canWrite(member)) { await logUsage(sb, member.id, "create_tribe_event", false, "Unauthorized", start); return err("Unauthorized"); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_adoption_metrics", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    const isPrivileged = member.is_superadmin || ["manager", "deputy_manager"].includes(member.operational_role) || (member.designations || []).includes("chapter_liaison");
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
    if (!tribeId) { await logUsage(sb, member.id, "get_tribe_dashboard", false, "No tribe", start); return err("No tribe. Specify tribe_id (1-8)."); }
    const { data, error } = await sb.rpc("exec_tribe_dashboard", { p_tribe_id: tribeId });
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_portfolio_overview", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_operational_alerts", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_cycle_report", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager", "sponsor"].includes(member.operational_role) && !(member.designations || []).includes("sponsor")) { await logUsage(sb, member.id, "get_annual_kpis", false, "Unauthorized", start); return err("Unauthorized: admin/sponsor only."); }
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
  mcp.tool("get_comms_dashboard", "Returns communications dashboard: publications by status/format, backlog, overdue items.", {}, async () => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_comms_dashboard", false, "Not authenticated", start); return err("Not authenticated"); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role) && !(member.designations || []).includes("comms_lead")) { await logUsage(sb, member.id, "get_campaign_analytics", false, "Unauthorized", start); return err("Unauthorized: admin/comms only."); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_curation_dashboard", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    if (!tribeId) { await logUsage(sb, member.id, "get_tribe_deliverables", false, "No tribe", start); return err("No tribe. Specify tribe_id (1-8)."); }
    const { data, error } = await sb.rpc("list_tribe_deliverables", { p_tribe_id: tribeId, p_cycle_code: params.cycle_code || null });
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_anomaly_report", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager", "sponsor"].includes(member.operational_role) && !(member.designations || []).includes("sponsor")) { await logUsage(sb, member.id, "get_portfolio_health", false, "Unauthorized", start); return err("Unauthorized: admin/sponsor only."); }
    const { data, error } = await sb.rpc("exec_portfolio_health", { p_cycle_code: params.cycle_code || "cycle3-2026" });
    if (error) { await logUsage(sb, member.id, "get_portfolio_health", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "get_portfolio_health", true, undefined, start);
    return ok(data);
  });

  // ===== P3 WAVE — 2 new tools (41-42) =====

  // TOOL 41: get_volunteer_funnel — Admin/Selection committee
  mcp.tool("get_volunteer_funnel", "Returns volunteer selection funnel: applicants by stage, conversion rates.", { cycle: z.number().optional().describe("Selection cycle number. Default: latest.") }, async (params: { cycle?: number }) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "get_volunteer_funnel", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_volunteer_funnel", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
    const { data, error } = await sb.rpc("volunteer_funnel_summary", { p_cycle: params.cycle || null });
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "get_admin_dashboard", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    if (!member.is_superadmin && !["manager", "deputy_manager"].includes(member.operational_role)) { await logUsage(sb, member.id, "search_members", false, "Unauthorized", start); return err("Unauthorized: admin only."); }
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
    const { data, error } = await sb.from("project_boards").select("id, board_name, board_scope, tribe_id, domain_key").eq("is_active", true).order("tribe_id", { ascending: true, nullsFirst: false });
    if (error) { await logUsage(sb, member.id, "list_boards", false, error.message, start); return err(error.message); }
    await logUsage(sb, member.id, "list_boards", true, undefined, start);
    return ok(data);
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
}

// MCP endpoint — Native Streamable HTTP via WebStandardStreamableHTTPServerTransport
// SDK 1.28.0 handles all protocol details: initialize, session, tools/list, tool/call, SSE
app.all("/mcp", async (c) => {
  try {
    const authHeader = c.req.header("Authorization");
    const token = authHeader?.replace("Bearer ", "");

    const sb = createAuthenticatedClient(token);
    const mcp = new McpServer({ name: "nucleo-ia-hub", version: "2.8.0" });
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
app.get("/health", (c) => c.json({ status: "ok", version: "2.8.0", tools: 52, transport: "native-streamable-http", sdk: "1.28.0" }));

Deno.serve(app.fetch);

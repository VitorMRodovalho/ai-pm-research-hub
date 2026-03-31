// supabase/functions/nucleo-mcp/index.ts
// MCP server v2.6.0 — 29 tools (23R + 6W) + usage logging
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

// --- Register 23 tools (17R + 6W) ---

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
    const { data, error } = await sb.from("announcements").select("id, title, message, type, link_url, link_text, starts_at").eq("is_active", true).lte("starts_at", now).order("created_at", { ascending: false }).limit(5);
    if (error) { await logUsage(sb, member?.id, "get_hub_announcements", false, error.message, start); return err(error.message); }
    await logUsage(sb, member?.id, "get_hub_announcements", true, undefined, start);
    return ok(data);
  });

  // ===== WRITE TOOLS (11-15, 18) =====

  // TOOL 11: create_board_card
  mcp.tool("create_board_card", "Create a new card on your tribe's board.", { title: z.string().describe("Card title"), description: z.string().optional().describe("Card description"), priority: z.string().optional().describe("low|medium|high|urgent"), due_date: z.string().optional().describe("Due date YYYY-MM-DD"), tags: z.string().optional().describe("Comma-separated tags") }, async (params: any) => {
    const start = Date.now();
    const member = await getMember(sb);
    if (!member) { await logUsage(sb, null, "create_board_card", false, "Not authenticated", start); return err("Not authenticated"); }
    if (!canWrite(member)) { await logUsage(sb, member.id, "create_board_card", false, "Unauthorized", start); return err("Unauthorized"); }
    const { data: board } = await sb.from("project_boards").select("id").eq("tribe_id", member.tribe_id).limit(1).single();
    if (!board) { await logUsage(sb, member.id, "create_board_card", false, "No board", start); return err("No board found."); }
    const tags = params.tags ? String(params.tags).split(",").map((t: string) => t.trim()) : [];
    if (params.priority && params.priority !== "medium") tags.push(`priority:${params.priority}`);
    const { data: cardId, error } = await sb.rpc("create_board_item", { p_board_id: board.id, p_title: params.title, p_description: params.description || null, p_tags: tags, p_due_date: params.due_date || null });
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
}

// MCP endpoint — Native Streamable HTTP via WebStandardStreamableHTTPServerTransport
// SDK 1.28.0 handles all protocol details: initialize, session, tools/list, tool/call, SSE
app.all("/mcp", async (c) => {
  try {
    const authHeader = c.req.header("Authorization");
    const token = authHeader?.replace("Bearer ", "");

    const sb = createAuthenticatedClient(token);
    const mcp = new McpServer({ name: "nucleo-ia-hub", version: "2.6.0" });
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
app.get("/health", (c) => c.json({ status: "ok", version: "2.6.0", tools: 29, transport: "native-streamable-http", sdk: "1.28.0" }));

Deno.serve(app.fetch);

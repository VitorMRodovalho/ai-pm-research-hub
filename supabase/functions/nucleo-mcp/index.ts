// supabase/functions/nucleo-mcp/index.ts
// MCP server v2.1.0 — 19 tools (14 read + 5 write) + usage logging
// GC-132: Phase 1 | GC-133: Phase 2 | GC-161: P1 (4 tools + logging)

import { Hono } from "jsr:@hono/hono";
import { McpServer, StreamableHttpTransport } from "npm:mcp-lite@0.10.0";
import { createClient } from "jsr:@supabase/supabase-js@2";

const app = new Hono().basePath("/nucleo-mcp");

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

function createAuthenticatedClient(token?: string) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    },
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

// Usage logging — fire-and-forget, never breaks tool execution
async function logUsage(
  sb: ReturnType<typeof createClient>,
  memberId: string | null,
  toolName: string,
  success: boolean,
  errorMsg?: string,
  startTime?: number
) {
  try {
    const execMs = startTime ? Date.now() - startTime : null;
    await sb.rpc("log_mcp_usage", {
      p_auth_user_id: null,
      p_member_id: memberId,
      p_tool_name: toolName,
      p_success: success,
      p_error_message: errorMsg || null,
      p_execution_ms: execMs,
    });
  } catch (_) { /* never break tool execution */ }
}

// --- MCP Server with 19 tools (14 read + 5 write) ---

function registerTools(mcp: McpServer, sb: ReturnType<typeof createClient>) {

  // TOOL 1: get_my_profile
  mcp.tool("get_my_profile", {
    description: "Returns your member profile: name, role, tribe, XP, badges, certifications.",
    handler: async () => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "get_my_profile", false, "Not authenticated", start); return err("Not authenticated or no member record found."); }

      const { data, error } = await sb.from("members")
        .select("name, operational_role, designations, tribe_id, chapter, is_active, current_cycle_active, credly_url, cpmai_certified")
        .eq("id", member.id)
        .single();

      if (error) { await logUsage(sb, member.id, "get_my_profile", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "get_my_profile", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 2: get_my_board_status
  mcp.tool("get_my_board_status", {
    description: "Returns your tribe's board cards grouped by status (backlog, in_progress, review, done).",
    inputSchema: {
      type: "object" as const,
      properties: {
        board_id: { type: "string", description: "Board UUID. If omitted, returns your tribe's default board." },
      },
    },
    handler: async (params: { board_id?: string }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "get_my_board_status", false, "Not authenticated", start); return err("Not authenticated"); }

      let boardId = params.board_id;
      if (!boardId) {
        const { data: boards } = await sb.from("project_boards")
          .select("id")
          .eq("tribe_id", member.tribe_id)
          .limit(1)
          .single();
        boardId = boards?.id;
      }
      if (!boardId) { await logUsage(sb, member.id, "get_my_board_status", false, "No board found", start); return err("No board found for your tribe."); }

      const { data: items, error } = await sb.from("board_items")
        .select("id, title, status, tags, due_date")
        .eq("board_id", boardId)
        .neq("status", "archived")
        .order("position", { ascending: true });

      if (error) { await logUsage(sb, member.id, "get_my_board_status", false, error.message, start); return err(error.message); }

      const grouped = {
        backlog: items.filter((i: any) => i.status === "backlog"),
        in_progress: items.filter((i: any) => i.status === "in_progress"),
        review: items.filter((i: any) => i.status === "review"),
        done: items.filter((i: any) => i.status === "done"),
      };
      await logUsage(sb, member.id, "get_my_board_status", true, undefined, start);
      return ok(grouped);
    },
  });

  // TOOL 3: get_my_tribe_attendance
  mcp.tool("get_my_tribe_attendance", {
    description: "Returns attendance grid for your tribe members.",
    handler: async () => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member?.tribe_id) { await logUsage(sb, member?.id, "get_my_tribe_attendance", false, "No tribe", start); return err("No tribe assigned."); }

      const { data, error } = await sb.rpc("get_tribe_attendance_grid", { p_tribe_id: member.tribe_id });
      if (error) { await logUsage(sb, member.id, "get_my_tribe_attendance", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "get_my_tribe_attendance", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 4: get_my_tribe_members
  mcp.tool("get_my_tribe_members", {
    description: "Returns the list of active members in your tribe with their roles.",
    handler: async () => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member?.tribe_id) { await logUsage(sb, member?.id, "get_my_tribe_members", false, "No tribe", start); return err("No tribe assigned."); }

      const { data, error } = await sb.from("public_members")
        .select("name, operational_role, designations, chapter, current_cycle_active")
        .eq("tribe_id", member.tribe_id)
        .eq("current_cycle_active", true)
        .order("name");

      if (error) { await logUsage(sb, member.id, "get_my_tribe_members", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "get_my_tribe_members", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 5: get_upcoming_events
  mcp.tool("get_upcoming_events", {
    description: "Returns events scheduled in the next 7 days.",
    handler: async () => {
      const start = Date.now();
      const today = new Date().toISOString().split("T")[0];
      const nextWeek = new Date(Date.now() + 7 * 86400000).toISOString().split("T")[0];

      const { data, error } = await sb.from("events")
        .select("id, title, date, type, tribe_id, duration_minutes, meeting_link")
        .gte("date", today)
        .lte("date", nextWeek)
        .order("date");

      if (error) { await logUsage(sb, null, "get_upcoming_events", false, error.message, start); return err(error.message); }
      await logUsage(sb, null, "get_upcoming_events", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 6: get_my_xp_and_ranking
  mcp.tool("get_my_xp_and_ranking", {
    description: "Returns your XP breakdown by category and your position in the leaderboard.",
    handler: async () => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "get_my_xp_and_ranking", false, "Not authenticated", start); return err("Not authenticated"); }

      const { data, error } = await sb.rpc("get_member_cycle_xp", { p_member_id: member.id });
      if (error) { await logUsage(sb, member.id, "get_my_xp_and_ranking", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "get_my_xp_and_ranking", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 7: get_meeting_notes
  mcp.tool("get_meeting_notes", {
    description: "Returns recent meeting notes/minutes for your tribe.",
    inputSchema: {
      type: "object" as const,
      properties: {
        limit: { type: "number", description: "Number of recent notes to return. Default: 5" },
      },
    },
    handler: async (params: { limit?: number }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member?.tribe_id) { await logUsage(sb, member?.id, "get_meeting_notes", false, "No tribe", start); return err("No tribe assigned."); }

      const { data, error } = await sb.rpc("list_meeting_artifacts", {
        p_tribe_id: member.tribe_id,
        p_limit: params.limit || 5,
      });
      if (error) { await logUsage(sb, member.id, "get_meeting_notes", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "get_meeting_notes", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 8: get_my_notifications
  mcp.tool("get_my_notifications", {
    description: "Returns your unread notifications.",
    handler: async () => {
      const start = Date.now();
      const member = await getMember(sb);
      const { data, error } = await sb.rpc("get_my_notifications");
      if (error) { await logUsage(sb, member?.id, "get_my_notifications", false, error.message, start); return err(error.message); }
      await logUsage(sb, member?.id, "get_my_notifications", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 9: search_board_cards
  mcp.tool("search_board_cards", {
    description: "Full-text search across board cards in your tribe's board.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: { type: "string", description: "Search term to find in card titles and descriptions." },
      },
      required: ["query"],
    },
    handler: async (params: { query: string }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member?.tribe_id) { await logUsage(sb, member?.id, "search_board_cards", false, "No tribe", start); return err("No tribe assigned."); }

      const { data, error } = await sb.rpc("search_board_items", {
        p_query: params.query,
        p_tribe_id: member.tribe_id,
      });
      if (error) { await logUsage(sb, member.id, "search_board_cards", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "search_board_cards", true, undefined, start);
      return ok(data);
    },
  });

  // TOOL 10: get_hub_announcements
  mcp.tool("get_hub_announcements", {
    description: "Returns active announcements from the Hub.",
    handler: async () => {
      const start = Date.now();
      const now = new Date().toISOString();

      const { data, error } = await sb.from("announcements")
        .select("id, title, message, type, link_url, link_text, starts_at")
        .eq("is_active", true)
        .lte("starts_at", now)
        .order("created_at", { ascending: false })
        .limit(5);

      if (error) { await logUsage(sb, null, "get_hub_announcements", false, error.message, start); return err(error.message); }
      await logUsage(sb, null, "get_hub_announcements", true, undefined, start);
      return ok(data);
    },
  });

  // ===== WRITE TOOLS (11–15) =====

  // TOOL 11: create_board_card
  mcp.tool("create_board_card", {
    description: "Create a new card on your tribe's board.",
    inputSchema: {
      type: "object" as const,
      properties: {
        title: { type: "string", description: "Card title" },
        description: { type: "string", description: "Card description" },
        priority: { type: "string", description: "low|medium|high|urgent. Default: medium", enum: ["low", "medium", "high", "urgent"] },
        due_date: { type: "string", description: "Due date in YYYY-MM-DD format" },
        tags: { type: "array", items: { type: "string" }, description: "Tag labels" },
      },
      required: ["title"],
    },
    handler: async (params: { title: string; description?: string; priority?: string; due_date?: string; tags?: string[] }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "create_board_card", false, "Not authenticated", start); return err("Not authenticated"); }
      if (!canWrite(member)) { await logUsage(sb, member.id, "create_board_card", false, "Unauthorized", start); return err("Unauthorized: only managers and tribe leaders can create cards."); }

      const { data: board } = await sb.from("project_boards")
        .select("id, tribe_id")
        .eq("tribe_id", member.tribe_id)
        .limit(1)
        .single();
      if (!board) { await logUsage(sb, member.id, "create_board_card", false, "No board", start); return err("No board found for your tribe."); }

      const tags = params.tags ? [...params.tags] : [];
      if (params.priority && params.priority !== "medium") tags.push(`priority:${params.priority}`);

      const { data: cardId, error } = await sb.rpc("create_board_item", {
        p_board_id: board.id,
        p_title: params.title,
        p_description: params.description || null,
        p_tags: tags,
        p_due_date: params.due_date || null,
      });

      if (error) { await logUsage(sb, member.id, "create_board_card", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "create_board_card", true, undefined, start);
      return ok({
        action: "create_board_card",
        status: "created",
        id: cardId,
        preview: { title: params.title, board_id: board.id, priority: params.priority || "medium" },
      });
    },
  });

  // TOOL 12: update_card_status
  mcp.tool("update_card_status", {
    description: "Move a card to a different status column.",
    inputSchema: {
      type: "object" as const,
      properties: {
        card_id: { type: "string", description: "UUID of the card" },
        status: { type: "string", description: "New status", enum: ["backlog", "in_progress", "review", "done", "archived"] },
      },
      required: ["card_id", "status"],
    },
    handler: async (params: { card_id: string; status: string }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "update_card_status", false, "Not authenticated", start); return err("Not authenticated"); }

      const { error } = await sb.rpc("move_board_item", {
        p_item_id: params.card_id,
        p_new_status: params.status,
      });

      if (error) { await logUsage(sb, member.id, "update_card_status", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "update_card_status", true, undefined, start);
      return ok({
        action: "update_card_status",
        status: "updated",
        card_id: params.card_id,
        new_status: params.status,
      });
    },
  });

  // TOOL 13: create_meeting_notes
  mcp.tool("create_meeting_notes", {
    description: "Create meeting minutes/notes for a tribe meeting.",
    inputSchema: {
      type: "object" as const,
      properties: {
        event_id: { type: "string", description: "UUID of the event" },
        content: { type: "string", description: "Meeting notes content (plain text or markdown)" },
        decisions: { type: "array", items: { type: "string" }, description: "Key decisions made" },
        action_items: { type: "array", items: { type: "string" }, description: "Action items from the meeting" },
      },
      required: ["event_id", "content"],
    },
    handler: async (params: { event_id: string; content: string; decisions?: string[]; action_items?: string[] }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "create_meeting_notes", false, "Not authenticated", start); return err("Not authenticated"); }
      if (!canWrite(member)) { await logUsage(sb, member.id, "create_meeting_notes", false, "Unauthorized", start); return err("Unauthorized: only managers and tribe leaders can create meeting notes."); }

      const { data: event } = await sb.from("events")
        .select("title, date, tribe_id")
        .eq("id", params.event_id)
        .single();
      if (!event) { await logUsage(sb, member.id, "create_meeting_notes", false, "Event not found", start); return err("Event not found."); }

      const tribeId = member.is_superadmin ? (event.tribe_id || member.tribe_id) : member.tribe_id;

      const { data, error } = await sb.from("meeting_artifacts").insert({
        event_id: params.event_id,
        title: `Ata — ${event.title}`,
        meeting_date: event.date,
        tribe_id: tribeId,
        created_by: member.id,
        agenda_items: params.action_items || [],
        deliberations: params.decisions || [],
        page_data_snapshot: { notes: params.content },
        is_published: true,
        cycle_code: "cycle_3",
      }).select("id").single();

      if (error) { await logUsage(sb, member.id, "create_meeting_notes", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "create_meeting_notes", true, undefined, start);
      return ok({
        action: "create_meeting_notes",
        status: "created",
        id: data.id,
        preview: { event: event.title, date: event.date },
      });
    },
  });

  // TOOL 14: register_attendance
  mcp.tool("register_attendance", {
    description: "Register attendance for a member at an event (leader only).",
    inputSchema: {
      type: "object" as const,
      properties: {
        event_id: { type: "string", description: "UUID of the event" },
        member_id: { type: "string", description: "UUID of the member" },
        present: { type: "boolean", description: "Whether the member was present" },
      },
      required: ["event_id", "member_id", "present"],
    },
    handler: async (params: { event_id: string; member_id: string; present: boolean }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "register_attendance", false, "Not authenticated", start); return err("Not authenticated"); }
      if (!canWrite(member)) { await logUsage(sb, member.id, "register_attendance", false, "Unauthorized", start); return err("Unauthorized: only managers and tribe leaders can register attendance."); }

      if (!params.present) {
        await logUsage(sb, member.id, "register_attendance", true, undefined, start);
        return ok({
          action: "register_attendance",
          status: "skipped",
          note: "Member marked as absent (no record created — only present members are registered).",
        });
      }

      const { data: count, error } = await sb.rpc("register_attendance_batch", {
        p_event_id: params.event_id,
        p_member_ids: [params.member_id],
        p_registered_by: member.id,
      });

      if (error) { await logUsage(sb, member.id, "register_attendance", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "register_attendance", true, undefined, start);
      return ok({
        action: "register_attendance",
        status: "registered",
        records_affected: count,
        event_id: params.event_id,
        member_id: params.member_id,
      });
    },
  });

  // TOOL 15: send_notification_to_tribe
  mcp.tool("send_notification_to_tribe", {
    description: "Send a notification to all active members of your tribe.",
    inputSchema: {
      type: "object" as const,
      properties: {
        title: { type: "string", description: "Notification title" },
        body: { type: "string", description: "Notification message" },
        link: { type: "string", description: "URL to link in the notification" },
      },
      required: ["title", "body"],
    },
    handler: async (params: { title: string; body: string; link?: string }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "send_notification_to_tribe", false, "Not authenticated", start); return err("Not authenticated"); }
      if (!canWrite(member)) { await logUsage(sb, member.id, "send_notification_to_tribe", false, "Unauthorized", start); return err("Unauthorized: only managers and tribe leaders can send notifications."); }
      if (!member.tribe_id && !member.is_superadmin) { await logUsage(sb, member.id, "send_notification_to_tribe", false, "No tribe", start); return err("No tribe assigned."); }

      const query = sb.from("members")
        .select("id")
        .eq("is_active", true)
        .eq("current_cycle_active", true)
        .neq("id", member.id);

      if (!member.is_superadmin) {
        query.eq("tribe_id", member.tribe_id);
      }

      const { data: members, error: membersErr } = await query;
      if (membersErr) { await logUsage(sb, member.id, "send_notification_to_tribe", false, membersErr.message, start); return err(membersErr.message); }
      if (!members?.length) { await logUsage(sb, member.id, "send_notification_to_tribe", false, "No members", start); return err("No active tribe members found."); }

      let sent = 0;
      for (const m of members) {
        const { error: notifErr } = await sb.rpc("create_notification", {
          p_recipient_id: m.id,
          p_type: "tribe_broadcast",
          p_title: params.title,
          p_body: params.body,
          p_link: params.link || null,
        });
        if (!notifErr) sent++;
      }

      await logUsage(sb, member.id, "send_notification_to_tribe", true, undefined, start);
      return ok({
        action: "send_notification_to_tribe",
        status: "sent",
        recipients: sent,
        total_members: members.length,
        preview: { title: params.title },
      });
    },
  });

  // ===== GC-161: NEW READ TOOLS (16–19) =====

  // TOOL 16: get_my_attendance_history
  mcp.tool("get_my_attendance_history", {
    description: "Returns your personal attendance history — which meetings you attended, missed, or were excused from.",
    inputSchema: {
      type: "object" as const,
      properties: {
        limit: { type: "number", description: "Number of recent events. Default: 20" },
      },
    },
    handler: async (params: { limit?: number }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "get_my_attendance_history", false, "Not authenticated", start); return err("Not authenticated"); }

      const { data, error } = await sb.rpc("get_my_attendance_history", {
        p_limit: params.limit || 20,
      });

      if (error) { await logUsage(sb, member.id, "get_my_attendance_history", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "get_my_attendance_history", true, undefined, start);

      const attended = (data || []).filter((r: any) => r.present).length;
      const total = (data || []).length;
      const rate = total > 0 ? Math.round((attended / total) * 100) : 0;

      return ok({
        summary: { attended, total, rate_percent: rate },
        events: data,
      });
    },
  });

  // TOOL 17: list_tribe_webinars
  mcp.tool("list_tribe_webinars", {
    description: "Returns webinars for your tribe or chapter — with status, dates, organizer, and co-managers.",
    inputSchema: {
      type: "object" as const,
      properties: {
        status: { type: "string", description: "Filter by status: planned|confirmed|completed|cancelled", enum: ["planned", "confirmed", "completed", "cancelled"] },
      },
    },
    handler: async (params: { status?: string }) => {
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
    },
  });

  // TOOL 18: create_tribe_event
  mcp.tool("create_tribe_event", {
    description: "Create a new tribe meeting or event. Only tribe leaders and managers can use this.",
    inputSchema: {
      type: "object" as const,
      properties: {
        title: { type: "string", description: "Event title" },
        date: { type: "string", description: "Event date in YYYY-MM-DD format" },
        type: { type: "string", description: "Event type", enum: ["tribo", "webinar", "comms", "lideranca"], default: "tribo" },
        duration_minutes: { type: "number", description: "Duration in minutes. Default: 90" },
        meeting_link: { type: "string", description: "Google Meet / Zoom link" },
      },
      required: ["title", "date"],
    },
    handler: async (params: { title: string; date: string; type?: string; duration_minutes?: number; meeting_link?: string }) => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "create_tribe_event", false, "Not authenticated", start); return err("Not authenticated"); }
      if (!canWrite(member)) { await logUsage(sb, member.id, "create_tribe_event", false, "Unauthorized", start); return err("Unauthorized: only managers and tribe leaders can create events."); }

      const { data, error } = await sb.rpc("create_event", {
        p_type: params.type || "tribo",
        p_title: params.title,
        p_date: params.date,
        p_duration_minutes: params.duration_minutes || 90,
        p_tribe_id: member.tribe_id,
      });

      if (error) { await logUsage(sb, member.id, "create_tribe_event", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "create_tribe_event", true, undefined, start);
      return ok({
        action: "create_tribe_event",
        status: "created",
        result: data,
      });
    },
  });

  // TOOL 19: get_comms_pending_webinars
  mcp.tool("get_comms_pending_webinars", {
    description: "Returns webinars that need communication action — invites, reminders, follow-ups, replay announcements.",
    handler: async () => {
      const start = Date.now();
      const member = await getMember(sb);
      if (!member) { await logUsage(sb, null, "get_comms_pending_webinars", false, "Not authenticated", start); return err("Not authenticated"); }

      const { data, error } = await sb.rpc("webinars_pending_comms");

      if (error) { await logUsage(sb, member.id, "get_comms_pending_webinars", false, error.message, start); return err(error.message); }
      await logUsage(sb, member.id, "get_comms_pending_webinars", true, undefined, start);
      return ok(data);
    },
  });
}

// Create a single MCP server + transport for the /mcp endpoint
app.all("/mcp", async (c) => {
  const authHeader = c.req.header("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  const sb = createAuthenticatedClient(token);
  const mcp = new McpServer({ name: "nucleo-ia-hub", version: "2.1.0" });
  registerTools(mcp, sb);

  const transport = new StreamableHttpTransport();
  const handler = transport.bind(mcp);

  return handler(c.req.raw);
});

// OAuth 2.1 Authorization Server Metadata (MCP auth discovery)
app.get("/.well-known/oauth-authorization-server", (c) => {
  const projectRef = "ldrfrvwhxsmgaabwmaik";
  return c.json({
    issuer: `https://${projectRef}.supabase.co/auth/v1`,
    authorization_endpoint: `https://${projectRef}.supabase.co/auth/v1/oauth/authorize`,
    token_endpoint: `https://${projectRef}.supabase.co/auth/v1/oauth/token`,
    registration_endpoint: `https://${projectRef}.supabase.co/auth/v1/oauth/register`,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none"],
  });
});

// Health check
app.get("/health", (c) => c.json({ status: "ok", version: "2.1.0", tools: 19 }));

Deno.serve(app.fetch);

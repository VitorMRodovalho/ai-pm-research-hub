// supabase/functions/nucleo-mcp/index.ts
// MCP server for tribe leaders — 15 tools (10 read + 5 write) via Supabase Auth OAuth 2.1
// GC-132: W-MCP-1 Phase 1 | GC-133: W-MCP-1 Phase 2

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
  // Try RPC first; handle both array and object return shapes
  const { data, error } = await sb.rpc("get_my_member_record");
  if (error || !data) return null;
  if (Array.isArray(data)) return data.length > 0 ? data[0] : null;
  // supabase-js may return a single object for SETOF with LIMIT 1
  if (typeof data === "object" && data.id) return data;
  return null;
}

const WRITE_ROLES = ["manager", "deputy_manager", "tribe_leader"];

function canWrite(member: { operational_role: string; is_superadmin?: boolean }) {
  return member.is_superadmin || WRITE_ROLES.includes(member.operational_role);
}

// --- MCP Server with 15 tools (10 read + 5 write) ---

function registerTools(mcp: McpServer, sb: ReturnType<typeof createClient>) {

  // TOOL 1: get_my_profile
  mcp.tool("get_my_profile", {
    description: "Returns your member profile: name, role, tribe, XP, badges, certifications.",
    handler: async () => {
      const member = await getMember(sb);
      if (!member) return err("Not authenticated or no member record found.");

      const { data, error } = await sb.from("members")
        .select("name, operational_role, designations, tribe_id, chapter, is_active, current_cycle_active, credly_url, cpmai_certified")
        .eq("id", member.id)
        .single();

      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");

      let boardId = params.board_id;
      if (!boardId) {
        const { data: boards } = await sb.from("project_boards")
          .select("id")
          .eq("tribe_id", member.tribe_id)
          .limit(1)
          .single();
        boardId = boards?.id;
      }
      if (!boardId) return err("No board found for your tribe.");

      const { data: items, error } = await sb.from("board_items")
        .select("id, title, status, tags, due_date")
        .eq("board_id", boardId)
        .neq("status", "archived")
        .order("position", { ascending: true });

      if (error) return err(error.message);

      const grouped = {
        backlog: items.filter((i: any) => i.status === "backlog"),
        in_progress: items.filter((i: any) => i.status === "in_progress"),
        review: items.filter((i: any) => i.status === "review"),
        done: items.filter((i: any) => i.status === "done"),
      };
      return ok(grouped);
    },
  });

  // TOOL 3: get_my_tribe_attendance
  mcp.tool("get_my_tribe_attendance", {
    description: "Returns attendance grid for your tribe members.",
    handler: async () => {
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.rpc("get_tribe_attendance_grid", { p_tribe_id: member.tribe_id });
      if (error) return err(error.message);
      return ok(data);
    },
  });

  // TOOL 4: get_my_tribe_members
  mcp.tool("get_my_tribe_members", {
    description: "Returns the list of active members in your tribe with their roles.",
    handler: async () => {
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.from("public_members")
        .select("name, operational_role, designations, chapter, current_cycle_active")
        .eq("tribe_id", member.tribe_id)
        .eq("current_cycle_active", true)
        .order("name");

      if (error) return err(error.message);
      return ok(data);
    },
  });

  // TOOL 5: get_upcoming_events
  mcp.tool("get_upcoming_events", {
    description: "Returns events scheduled in the next 7 days.",
    handler: async () => {
      const today = new Date().toISOString().split("T")[0];
      const nextWeek = new Date(Date.now() + 7 * 86400000).toISOString().split("T")[0];

      const { data, error } = await sb.from("events")
        .select("id, title, date, type, tribe_id, duration_minutes, meeting_link")
        .gte("date", today)
        .lte("date", nextWeek)
        .order("date");

      if (error) return err(error.message);
      return ok(data);
    },
  });

  // TOOL 6: get_my_xp_and_ranking
  mcp.tool("get_my_xp_and_ranking", {
    description: "Returns your XP breakdown by category and your position in the leaderboard.",
    handler: async () => {
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");

      const { data, error } = await sb.rpc("get_member_cycle_xp", { p_member_id: member.id });
      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.rpc("list_meeting_artifacts", {
        p_tribe_id: member.tribe_id,
        p_limit: params.limit || 5,
      });
      if (error) return err(error.message);
      return ok(data);
    },
  });

  // TOOL 8: get_my_notifications
  mcp.tool("get_my_notifications", {
    description: "Returns your unread notifications.",
    handler: async () => {
      const { data, error } = await sb.rpc("get_my_notifications");
      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.rpc("search_board_items", {
        p_query: params.query,
        p_tribe_id: member.tribe_id,
      });
      if (error) return err(error.message);
      return ok(data);
    },
  });

  // TOOL 10: get_hub_announcements
  mcp.tool("get_hub_announcements", {
    description: "Returns active announcements from the Hub.",
    handler: async () => {
      const now = new Date().toISOString();

      const { data, error } = await sb.from("announcements")
        .select("id, title, message, type, link_url, link_text, starts_at")
        .eq("is_active", true)
        .lte("starts_at", now)
        .order("created_at", { ascending: false })
        .limit(5);

      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");
      if (!canWrite(member)) return err("Unauthorized: only managers and tribe leaders can create cards.");

      // Resolve tribe's default board
      const { data: board } = await sb.from("project_boards")
        .select("id, tribe_id")
        .eq("tribe_id", member.tribe_id)
        .limit(1)
        .single();
      if (!board) return err("No board found for your tribe.");

      // Build tags with priority
      const tags = params.tags ? [...params.tags] : [];
      if (params.priority && params.priority !== "medium") tags.push(`priority:${params.priority}`);

      const { data: cardId, error } = await sb.rpc("create_board_item", {
        p_board_id: board.id,
        p_title: params.title,
        p_description: params.description || null,
        p_tags: tags,
        p_due_date: params.due_date || null,
      });

      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");

      const { error } = await sb.rpc("move_board_item", {
        p_item_id: params.card_id,
        p_new_status: params.status,
      });

      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");
      if (!canWrite(member)) return err("Unauthorized: only managers and tribe leaders can create meeting notes.");

      // Get event details for title and date
      const { data: event } = await sb.from("events")
        .select("title, date, tribe_id")
        .eq("id", params.event_id)
        .single();
      if (!event) return err("Event not found.");

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

      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");
      if (!canWrite(member)) return err("Unauthorized: only managers and tribe leaders can register attendance.");

      if (!params.present) {
        // RPC only marks present; for absent, just return a note
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

      if (error) return err(error.message);
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
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");
      if (!canWrite(member)) return err("Unauthorized: only managers and tribe leaders can send notifications.");
      if (!member.tribe_id && !member.is_superadmin) return err("No tribe assigned.");

      // Get active tribe members
      const query = sb.from("members")
        .select("id")
        .eq("is_active", true)
        .eq("current_cycle_active", true)
        .neq("id", member.id); // don't notify self

      if (!member.is_superadmin) {
        query.eq("tribe_id", member.tribe_id);
      }

      const { data: members, error: membersErr } = await query;
      if (membersErr) return err(membersErr.message);
      if (!members?.length) return err("No active tribe members found.");

      // Send notification to each member via RPC
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

      return ok({
        action: "send_notification_to_tribe",
        status: "sent",
        recipients: sent,
        total_members: members.length,
        preview: { title: params.title },
      });
    },
  });
}

// Create a single MCP server + transport for the /mcp endpoint
// StreamableHttpTransport handles initialize, tools/list, tools/call, etc.
app.all("/mcp", async (c) => {
  const authHeader = c.req.header("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  const sb = createAuthenticatedClient(token);
  const mcp = new McpServer({ name: "nucleo-ia-hub", version: "1.0.0" });
  registerTools(mcp, sb);

  const transport = new StreamableHttpTransport();
  const handler = transport.bind(mcp);

  return handler(c.req.raw);
});

// OAuth 2.1 Authorization Server Metadata (MCP auth discovery)
// Claude Code needs this to know where to start the OAuth flow
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
app.get("/health", (c) => c.json({ status: "ok", version: "2.0.0", tools: 15 }));

Deno.serve(app.fetch);

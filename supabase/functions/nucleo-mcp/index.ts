// supabase/functions/nucleo-mcp/index.ts
// MCP server for tribe leaders — 10 read-only tools via Supabase Auth OAuth 2.1
// GC-132: W-MCP-1 Phase 1

import { Hono } from "jsr:@hono/hono";
import { McpServer } from "npm:mcp-lite";
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
  if (error) return null;
  return data;
}

// --- MCP Server with 10 tools ---

function registerTools(mcp: McpServer, sb: ReturnType<typeof createClient>) {

  // TOOL 1: get_my_profile
  mcp.tool(
    "get_my_profile",
    "Returns your member profile: name, role, tribe, XP, badges, certifications.",
    {},
    async () => {
      const { data, error } = await sb.rpc("get_my_member_record");
      if (error) return err(error.message);
      const safe = {
        name: data.name,
        operational_role: data.operational_role,
        designations: data.designations,
        tribe_id: data.tribe_id,
        chapter: data.chapter,
        is_active: data.is_active,
        current_cycle_active: data.current_cycle_active,
        credly_url: data.credly_url,
        cpmai_certified: data.cpmai_certified,
      };
      return ok(safe);
    }
  );

  // TOOL 2: get_my_board_status
  mcp.tool(
    "get_my_board_status",
    "Returns your tribe's board cards grouped by status (backlog, in_progress, review, done).",
    {
      board_id: { type: "string", description: "Board UUID. If omitted, returns your tribe's default board." },
    },
    async (params: { board_id?: string }) => {
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
    }
  );

  // TOOL 3: get_my_tribe_attendance
  mcp.tool(
    "get_my_tribe_attendance",
    "Returns attendance grid for your tribe members.",
    {},
    async () => {
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.rpc("get_tribe_attendance_grid", { p_tribe_id: member.tribe_id });
      if (error) return err(error.message);
      return ok(data);
    }
  );

  // TOOL 4: get_my_tribe_members
  mcp.tool(
    "get_my_tribe_members",
    "Returns the list of active members in your tribe with their roles.",
    {},
    async () => {
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.from("public_members")
        .select("name, operational_role, designations, chapter, current_cycle_active")
        .eq("tribe_id", member.tribe_id)
        .eq("current_cycle_active", true)
        .order("name");

      if (error) return err(error.message);
      return ok(data);
    }
  );

  // TOOL 5: get_upcoming_events
  mcp.tool(
    "get_upcoming_events",
    "Returns events scheduled in the next 7 days.",
    {},
    async () => {
      const today = new Date().toISOString().split("T")[0];
      const nextWeek = new Date(Date.now() + 7 * 86400000).toISOString().split("T")[0];

      const { data, error } = await sb.from("events")
        .select("id, title, date, type, tribe_id, duration_minutes, location")
        .gte("date", today)
        .lte("date", nextWeek)
        .order("date");

      if (error) return err(error.message);
      return ok(data);
    }
  );

  // TOOL 6: get_my_xp_and_ranking
  mcp.tool(
    "get_my_xp_and_ranking",
    "Returns your XP breakdown by category and your position in the leaderboard.",
    {},
    async () => {
      const member = await getMember(sb);
      if (!member) return err("Not authenticated");

      const { data, error } = await sb.rpc("get_member_cycle_xp", { p_member_id: member.id });
      if (error) return err(error.message);
      return ok(data);
    }
  );

  // TOOL 7: get_meeting_notes
  mcp.tool(
    "get_meeting_notes",
    "Returns recent meeting notes/minutes for your tribe.",
    {
      limit: { type: "number", description: "Number of recent notes to return. Default: 5" },
    },
    async (params: { limit?: number }) => {
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.rpc("list_meeting_artifacts", {
        p_tribe_id: member.tribe_id,
        p_limit: params.limit || 5,
      });
      if (error) return err(error.message);
      return ok(data);
    }
  );

  // TOOL 8: get_my_notifications
  mcp.tool(
    "get_my_notifications",
    "Returns your unread notifications.",
    {},
    async () => {
      const { data, error } = await sb.rpc("get_my_notifications");
      if (error) return err(error.message);
      return ok(data);
    }
  );

  // TOOL 9: search_board_cards
  mcp.tool(
    "search_board_cards",
    "Full-text search across board cards in your tribe's board.",
    {
      query: { type: "string", description: "Search term to find in card titles and descriptions." },
    },
    async (params: { query: string }) => {
      const member = await getMember(sb);
      if (!member?.tribe_id) return err("No tribe assigned.");

      const { data, error } = await sb.rpc("search_board_items", {
        p_query: params.query,
        p_tribe_id: member.tribe_id,
      });
      if (error) return err(error.message);
      return ok(data);
    }
  );

  // TOOL 10: get_hub_announcements
  mcp.tool(
    "get_hub_announcements",
    "Returns active announcements from the Hub.",
    {},
    async () => {
      const now = new Date().toISOString();

      const { data, error } = await sb.from("announcements")
        .select("id, title, message, type, link_url, link_text, starts_at")
        .eq("is_active", true)
        .lte("starts_at", now)
        .order("created_at", { ascending: false })
        .limit(5);

      if (error) return err(error.message);
      return ok(data);
    }
  );
}

// MCP endpoint — Streamable HTTP
app.post("/mcp", async (c) => {
  const authHeader = c.req.header("Authorization");
  const token = authHeader?.replace("Bearer ", "");

  const sb = createAuthenticatedClient(token);
  const mcp = new McpServer({ name: "nucleo-ia-hub", version: "1.0.0" });
  registerTools(mcp, sb);

  // Use mcp-lite's built-in transport
  const body = await c.req.json();
  const result = await mcp.handleRequest(body);
  return c.json(result);
});

// SSE endpoint for MCP clients that use SSE transport
app.get("/sse", (c) => {
  const authHeader = c.req.header("Authorization");
  const token = authHeader?.replace("Bearer ", "");
  const sb = createAuthenticatedClient(token);
  const mcp = new McpServer({ name: "nucleo-ia-hub", version: "1.0.0" });
  registerTools(mcp, sb);

  // Return SSE stream
  return new Response(
    new ReadableStream({
      start(controller) {
        controller.enqueue(`data: ${JSON.stringify({ type: "endpoint", url: "/nucleo-mcp/mcp" })}\n\n`);
      },
    }),
    { headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" } }
  );
});

// Health check
app.get("/health", (c) => c.json({ status: "ok", version: "1.0.0", tools: 10 }));

Deno.serve(app.fetch);

/// <reference types="https://esm.sh/@supabase/functions-js/src/edge-runtime.d.ts" />
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const POSTHOG_API_KEY = Deno.env.get("POSTHOG_PERSONAL_API_KEY")!;
const POSTHOG_PROJECT_ID = "334261";
const POSTHOG_HOST = "https://us.posthog.com";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const ALLOWED_ENDPOINTS = ["insights", "dashboards", "annotations"] as const;

const ALLOWED_QUERIES = [
  "dau_wau",
  "top_pages",
  "traffic_sources",
  "rage_clicks",
  "retention_weekly",
] as const;

type AllowedQuery = typeof ALLOWED_QUERIES[number];

function isAllowedQuery(q: string): q is AllowedQuery {
  return ALLOWED_QUERIES.includes(q as AllowedQuery);
}

async function verifyAdmin(authHeader: string): Promise<boolean> {
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) return false;

  const { data: member } = await supabase
    .from("members")
    .select("operational_role, is_superadmin")
    .eq("auth_id", user.id)
    .single();

  if (!member) return false;
  return member.is_superadmin ||
    ["manager", "deputy_manager"].includes(member.operational_role);
}

function buildQuery(queryType: AllowedQuery, days: number): object {
  switch (queryType) {
    case "dau_wau":
      return {
        kind: "TrendsQuery",
        dateRange: { date_from: `-${days}d` },
        interval: "day",
        series: [
          { kind: "EventsNode", event: "$pageview", math: "dau", custom_name: "DAU" },
          { kind: "EventsNode", event: "$pageview", math: "weekly_active", custom_name: "WAU" },
        ],
        trendsFilter: { display: "ActionsLineGraph" },
      };

    case "top_pages":
      return {
        kind: "TrendsQuery",
        dateRange: { date_from: `-${days}d` },
        interval: "month",
        series: [
          { kind: "EventsNode", event: "$pageview", math: "total", custom_name: "Views" },
        ],
        breakdownFilter: {
          breakdowns: [{ property: "$pathname", type: "event" }],
          breakdown_limit: 15,
        },
        trendsFilter: { display: "ActionsBarValue" },
      };

    case "traffic_sources":
      return {
        kind: "TrendsQuery",
        dateRange: { date_from: `-${days}d` },
        interval: "month",
        series: [
          { kind: "EventsNode", event: "$pageview", math: "dau", custom_name: "Users" },
        ],
        breakdownFilter: {
          breakdowns: [{ property: "$referring_domain", type: "event" }],
          breakdown_limit: 10,
        },
        trendsFilter: { display: "ActionsPie" },
      };

    case "rage_clicks":
      return {
        kind: "TrendsQuery",
        dateRange: { date_from: `-${days}d` },
        interval: "day",
        series: [
          { kind: "EventsNode", event: "$rageclick", math: "total", custom_name: "Rage Clicks" },
        ],
        trendsFilter: { display: "ActionsLineGraph" },
      };

    case "retention_weekly":
      return {
        kind: "RetentionQuery",
        dateRange: { date_from: `-${days}d` },
        retentionFilter: {
          period: "Week",
          totalIntervals: Math.min(Math.ceil(days / 7), 8),
          targetEntity: { id: "$pageview", name: "$pageview", type: "events" },
          returningEntity: { id: "$pageview", name: "$pageview", type: "events" },
          retentionType: "retention_first_time",
          retentionReference: "total",
          cumulative: false,
        },
        filterTestAccounts: false,
      };
  }
}

function simplifyResults(queryType: AllowedQuery, raw: any): object {
  if (queryType === "retention_weekly") {
    const result = raw.result || raw.results || [];
    return {
      query_type: queryType,
      retention: Array.isArray(result) ? result.map((cohort: any) => ({
        date: cohort.date,
        label: cohort.label,
        values: cohort.values?.map((v: any) => ({ count: v.count })),
        cohort_size: cohort.values?.[0]?.count || 0,
      })) : [],
    };
  }

  const results = raw.result || raw.results || [];
  // Normalize breakdown_value: can be string (old API), array (new multi-breakdown), or undefined
  const normalizeBreakdown = (s: any): string | undefined => {
    const bv = s.breakdown_value ?? s.breakdowns;
    if (bv === undefined || bv === null) return undefined;
    if (Array.isArray(bv)) return String(bv[0] ?? '');
    return String(bv);
  };
  return {
    query_type: queryType,
    series: Array.isArray(results) ? results.map((s: any) => ({
      label: s.label || s.action?.custom_name || "Unknown",
      custom_name: s.action?.custom_name || s.label,
      data: s.data || [],
      labels: s.labels || s.days || [],
      count: s.count || 0,
      breakdown_value: normalizeBreakdown(s),
    })) : [],
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const isAdmin = await verifyAdmin(authHeader);
  if (!isAdmin) {
    return new Response(JSON.stringify({ error: "Forbidden: admin only" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const action = url.searchParams.get("action");

  // ─── Phase 2: Query API ───
  if (action === "query") {
    const queryType = url.searchParams.get("q");
    if (!queryType || !isAllowedQuery(queryType)) {
      return new Response(
        JSON.stringify({ error: `Invalid query. Allowed: ${ALLOWED_QUERIES.join(", ")}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const days = Math.min(parseInt(url.searchParams.get("days") || "30"), 90);
    const query = buildQuery(queryType, days);

    try {
      const phResponse = await fetch(
        `${POSTHOG_HOST}/api/projects/${POSTHOG_PROJECT_ID}/query/`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${POSTHOG_API_KEY}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ query }),
        }
      );

      if (!phResponse.ok) {
        const errText = await phResponse.text();
        console.error(`PostHog Query API error: ${phResponse.status} ${errText}`);
        return new Response(
          JSON.stringify({ error: "PostHog query error", status: phResponse.status, detail: errText.slice(0, 500), query_kind: (query as any).kind }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      const rawData = await phResponse.json();
      const simplified = simplifyResults(queryType, rawData);

      return new Response(JSON.stringify(simplified), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "private, max-age=300" },
      });
    } catch (err) {
      console.error("PostHog query proxy error:", err);
      return new Response(
        JSON.stringify({ error: "Internal proxy error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  }

  // ─── Phase 1: REST API (GET) ───
  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const endpoint = url.searchParams.get("endpoint");
  const resourceId = url.searchParams.get("id");

  if (!endpoint || !ALLOWED_ENDPOINTS.includes(endpoint as any)) {
    return new Response(
      JSON.stringify({ error: `Invalid endpoint. Allowed: ${ALLOWED_ENDPOINTS.join(", ")}` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let phUrl = `${POSTHOG_HOST}/api/projects/${POSTHOG_PROJECT_ID}/${endpoint}/`;
  if (resourceId) phUrl += `${resourceId}/`;

  const limit = url.searchParams.get("limit");
  const offset = url.searchParams.get("offset");
  const phParams = new URLSearchParams();
  if (limit) phParams.set("limit", limit);
  if (offset) phParams.set("offset", offset);
  if (phParams.toString()) phUrl += `?${phParams.toString()}`;

  try {
    const phResponse = await fetch(phUrl, {
      headers: { Authorization: `Bearer ${POSTHOG_API_KEY}`, "Content-Type": "application/json" },
    });

    if (!phResponse.ok) {
      const errText = await phResponse.text();
      console.error(`PostHog API error: ${phResponse.status} ${errText}`);
      return new Response(
        JSON.stringify({ error: "PostHog API error", status: phResponse.status }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const data = await phResponse.json();
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "private, max-age=300" },
    });
  } catch (err) {
    console.error("PostHog proxy error:", err);
    return new Response(
      JSON.stringify({ error: "Internal proxy error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

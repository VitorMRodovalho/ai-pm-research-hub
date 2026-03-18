import { defineMiddleware } from "astro:middleware";
import { createClient } from "@supabase/supabase-js";

// GC-089 / B4: SSR auth middleware for protected routes
// Primary security is Supabase RLS — this is defense-in-depth to avoid
// serving admin HTML shell to unauthenticated visitors.

const SUPABASE_URL = import.meta.env.PUBLIC_SUPABASE_URL || "https://ldrfrvwhxsmgaabwmaik.supabase.co";
const SUPABASE_ANON_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcmZydndoeHNtZ2FhYndtYWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjU5NDQsImV4cCI6MjA4ODMwMTk0NH0.gzibKd7Jyck3Ya61vzrloX1YZt-0pNReTuefdi4mAmw";

const ADMIN_ROLES = new Set(["manager", "deputy_manager", "stakeholder", "tribe_leader", "curator"]);

// Routes that require authentication
function isProtectedRoute(path: string): boolean {
  return path.startsWith("/admin") || path.startsWith("/workspace") || path.startsWith("/profile");
}

// Routes that require admin-level access
function isAdminRoute(path: string): boolean {
  return path.startsWith("/admin");
}

export const onRequest = defineMiddleware(async (context, next) => {
  const { pathname } = context.url;

  // Skip non-protected routes (public pages, API, assets)
  if (!isProtectedRoute(pathname)) {
    return next();
  }

  // Bypass for test/CI environments with mock Supabase
  if (SUPABASE_URL.includes("//mock") || SUPABASE_URL.includes("//localhost")) {
    return next();
  }

  // Read access token from cookie (synced by Nav.astro client-side)
  const token = context.cookies.get("sb-access-token")?.value;

  if (!token) {
    return context.redirect(`/?auth=required`);
  }

  try {
    // Verify token with Supabase Auth API
    const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: { user }, error: authError } = await sb.auth.getUser(token);

    if (authError || !user) {
      // Clear stale cookie and redirect
      context.cookies.delete("sb-access-token", { path: "/" });
      return context.redirect(`/?auth=expired`);
    }

    // For admin routes, verify the user has an appropriate role
    if (isAdminRoute(pathname)) {
      const { data: member } = await sb.rpc("get_member_by_auth");

      if (!member) {
        return context.redirect("/workspace?unauthorized=true");
      }

      const hasAdminAccess =
        member.is_superadmin === true ||
        ADMIN_ROLES.has(member.operational_role);

      if (!hasAdminAccess) {
        return context.redirect("/workspace?unauthorized=true");
      }
    }

    return next();
  } catch {
    // On any unexpected error (network, Supabase down), fail-closed for admin, fail-open for others
    if (isAdminRoute(pathname)) {
      return context.redirect(`/?auth=error`);
    }
    return next();
  }
});

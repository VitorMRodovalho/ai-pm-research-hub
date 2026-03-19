import { defineMiddleware } from "astro:middleware";
import { createClient } from "@supabase/supabase-js";

// GC-089 / B4: SSR auth middleware for protected routes
// Primary security is Supabase RLS — this is defense-in-depth to avoid
// serving admin HTML shell to unauthenticated visitors.

const SUPABASE_URL = import.meta.env.PUBLIC_SUPABASE_URL || "https://ldrfrvwhxsmgaabwmaik.supabase.co";
const SUPABASE_ANON_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkcmZydndoeHNtZ2FhYndtYWlrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjU5NDQsImV4cCI6MjA4ODMwMTk0NH0.gzibKd7Jyck3Ya61vzrloX1YZt-0pNReTuefdi4mAmw";

const ADMIN_ROLES = new Set(["manager", "deputy_manager", "stakeholder", "tribe_leader", "curator"]);

// Strip locale prefix to get the canonical path
function stripLocale(path: string): string {
  return path.replace(/^\/(en|es)(?=\/|$)/, "") || "/";
}

// Extract locale prefix for redirect preservation
function getLocalePrefix(path: string): string {
  const match = path.match(/^\/(en|es)(?=\/|$)/);
  return match ? `/${match[1]}` : "";
}

// Routes that require authentication (checked against locale-stripped path)
function isProtectedRoute(canonicalPath: string): boolean {
  return canonicalPath.startsWith("/admin") || canonicalPath.startsWith("/workspace") || canonicalPath.startsWith("/profile");
}

// Routes that require admin-level access
function isAdminRoute(canonicalPath: string): boolean {
  return canonicalPath.startsWith("/admin");
}

// Security headers applied to ALL responses
function addSecurityHeaders(response: Response, canonicalPath: string): Response {
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  if (canonicalPath.startsWith("/admin")) {
    response.headers.set("X-Robots-Tag", "noindex, nofollow");
  }
  return response;
}

export const onRequest = defineMiddleware(async (context, next) => {
  const { pathname } = context.url;
  const canonicalPath = stripLocale(pathname);
  const localePrefix = getLocalePrefix(pathname);

  // Public routes: pass through with security headers
  if (!isProtectedRoute(canonicalPath)) {
    const response = await next();
    return addSecurityHeaders(response, canonicalPath);
  }

  // Bypass for test/CI environments with mock Supabase
  if (SUPABASE_URL.includes("//mock") || SUPABASE_URL.includes("//localhost")) {
    return next();
  }

  // Read access token from cookie (synced by Nav.astro client-side)
  const token = context.cookies.get("sb-access-token")?.value;

  if (!token) {
    return context.redirect(`${localePrefix}/?auth=required`);
  }

  try {
    // Verify token with Supabase Auth API
    const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: { user }, error: authError } = await sb.auth.getUser(token);

    if (authError || !user) {
      context.cookies.delete("sb-access-token", { path: "/" });
      return context.redirect(`${localePrefix}/?auth=expired`);
    }

    // For admin routes, verify the user has an appropriate role
    if (isAdminRoute(canonicalPath)) {
      const { data: member } = await sb.rpc("get_member_by_auth");

      if (!member) {
        return context.redirect(`${localePrefix}/workspace?unauthorized=true`);
      }

      const hasAdminAccess =
        member.is_superadmin === true ||
        ADMIN_ROLES.has(member.operational_role);

      if (!hasAdminAccess) {
        return context.redirect(`${localePrefix}/workspace?unauthorized=true`);
      }
    }

    const response = await next();
    return addSecurityHeaders(response, canonicalPath);
  } catch {
    // On any unexpected error, fail-closed for admin, fail-open for others
    if (isAdminRoute(canonicalPath)) {
      return context.redirect(`${localePrefix}/?auth=error`);
    }
    const response = await next();
    return addSecurityHeaders(response, canonicalPath);
  }
});

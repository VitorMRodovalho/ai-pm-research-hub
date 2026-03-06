import { defineMiddleware } from 'astro:middleware';
import { createClient } from '@supabase/supabase-js';

const SB_URL = import.meta.env.PUBLIC_SUPABASE_URL;
const SB_KEY = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

export const onRequest = defineMiddleware(async (context, next) => {
  const { url, redirect, cookies } = context;
  const path = url.pathname;

  // Only guard /admin routes
  if (!path.startsWith('/admin')) return next();

  // Read session from cookie (Supabase stores it as sb-{ref}-auth-token)
  const authCookie = cookies.get('sb-ldrfrvwhxsmgaabwmaik-auth-token');
  if (!authCookie?.value) {
    return redirect('/?auth=required');
  }

  try {
    const sb = createClient(SB_URL, SB_KEY);
    const session = JSON.parse(decodeURIComponent(authCookie.value));
    await sb.auth.setSession(session);

    const { data: member } = await sb.rpc('get_member_by_auth');
    if (!member || member.role === 'guest') {
      return redirect('/?auth=unauthorized');
    }

    // Attach member to locals for use in pages
    context.locals.member = member;
  } catch {
    return redirect('/?auth=required');
  }

  return next();
});

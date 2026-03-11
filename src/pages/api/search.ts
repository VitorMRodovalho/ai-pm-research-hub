/**
 * W90: Global Search API — Command Palette
 * GET /api/search?q=termo
 * Valida sessão via Authorization Bearer, chama search_knowledge RPC
 */
import type { APIRoute } from 'astro';
import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.PUBLIC_SUPABASE_URL || '';
const anonKey = import.meta.env.PUBLIC_SUPABASE_ANON_KEY || '';

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export const GET: APIRoute = async ({ request }) => {
  if (!url || !anonKey) {
    return jsonResponse({ error: 'Search service unavailable' }, 503);
  }

  const authHeader = request.headers.get('Authorization');
  const token = authHeader?.replace(/^Bearer\s+/i, '').trim();
  if (!token) {
    return jsonResponse({ error: 'Unauthorized', results: [] }, 401);
  }

  const searchParams = new URL(request.url).searchParams;
  const q = searchParams.get('q')?.trim() || '';
  if (q.length < 2) {
    return jsonResponse({ results: [], query: q });
  }

  try {
    const sb = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: session } = await sb.auth.getSession();
    if (!session?.session) {
      return jsonResponse({ error: 'Session invalid', results: [] }, 401);
    }

    const { data, error } = await sb.rpc('search_knowledge', { search_term: q });
    if (error) {
      return jsonResponse({ error: error.message, results: [] }, 500);
    }

    const results = Array.isArray(data) ? data : [];
    return jsonResponse({ results, query: q });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Search failed';
    return jsonResponse({ error: msg, results: [] }, 500);
  }
};

import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';

export const GET: APIRoute = async () => {
  try {
    const kv = (env as any).SESSION;
    if (!kv) return new Response('KV unavailable', { status: 500 });

    const list = await kv.list({ prefix: 'debug:' });
    const logs: any[] = [];
    for (const key of list.keys) {
      const val = await kv.get(key.name);
      if (val) {
        try { logs.push(JSON.parse(val)); } catch { logs.push({ raw: val, key: key.name }); }
      }
    }
    logs.sort((a: any, b: any) => (a.timestamp || '').localeCompare(b.timestamp || ''));

    return new Response(JSON.stringify(logs, null, 2), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500 });
  }
};

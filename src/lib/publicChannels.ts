import { createClient } from '@supabase/supabase-js';

/**
 * #2553 PR 2: os canais oficiais do Núcleo (LinkedIn, Instagram, YouTube, Spotify), de uma fonte só.
 *
 * Os links moravam escritos no rodapé do BaseLayout, enquanto o comentário dele já dizia que a fonte era
 * comms_channel_config. Agora o rodapé e a home leem get_public_channels, que devolve só canal e URL pública e
 * nunca uma coluna de credencial.
 *
 * O rodapé sai em toda página, então a leitura fica em cache no módulo e tem prazo curto: um banco lento (#2758)
 * não pode segurar a renderização. Se a leitura falhar, vale o último resultado bom; sem nenhum, o rodapé não mostra
 * canal. Uma URL escrita aqui como reserva seria o defeito que esta fonte existe para eliminar.
 */
export type ChannelKey = 'linkedin' | 'instagram' | 'youtube' | 'spotify';

export interface PublicChannel {
  channel: ChannelKey;
  url: string;
}

const KNOWN: readonly ChannelKey[] = ['linkedin', 'instagram', 'youtube', 'spotify'];
const TTL_MS = 10 * 60 * 1000;
const TIMEOUT_MS = 1500;

let cache: { at: number; rows: PublicChannel[] } | null = null;

function isPublicChannel(row: unknown): row is PublicChannel {
  const r = row as Record<string, unknown> | null;
  return !!r
    && KNOWN.includes(r.channel as ChannelKey)
    && typeof r.url === 'string'
    && /^https:\/\/\S+$/.test(r.url);
}

export async function loadPublicChannels(): Promise<PublicChannel[]> {
  if (cache && Date.now() - cache.at < TTL_MS) return cache.rows;
  try {
    const sb = createClient(import.meta.env.PUBLIC_SUPABASE_URL, import.meta.env.PUBLIC_SUPABASE_ANON_KEY, {
      auth: { persistSession: false },
    });
    const { data, error } = await sb.rpc('get_public_channels').abortSignal(AbortSignal.timeout(TIMEOUT_MS));
    if (error || !Array.isArray(data)) return cache?.rows ?? [];
    const rows = data.filter(isPublicChannel);
    cache = { at: Date.now(), rows };
    return rows;
  } catch {
    return cache?.rows ?? [];
  }
}

/** Só para testes: esquece o último resultado. */
export function resetPublicChannelsCache(): void {
  cache = null;
}

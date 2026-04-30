import rss from '@astrojs/rss';
import { createClient } from '@supabase/supabase-js';
import type { APIRoute } from 'astro';

export const GET: APIRoute = async (context) => {
  const sb = createClient(
    import.meta.env.PUBLIC_SUPABASE_URL,
    import.meta.env.PUBLIC_SUPABASE_ANON_KEY,
  );

  const { data: pubs } = await sb.from('public_publications')
    .select('id, title, abstract, authors, publication_date, publication_type, external_url, doi')
    .eq('is_published', true)
    .order('publication_date', { ascending: false })
    .limit(50);

  const items = (pubs || []).map((p: any) => {
    const authorList = Array.isArray(p.authors) ? p.authors.join(', ') : (p.authors || '');
    const authorPrefix = authorList ? `${authorList} — ` : '';
    return {
      title: p.title || 'Untitled',
      description: `${authorPrefix}${p.abstract || ''}`.slice(0, 600),
      pubDate: p.publication_date ? new Date(p.publication_date) : new Date(),
      link: p.external_url || (p.doi ? `https://doi.org/${p.doi}` : `/publications#${p.id}`),
      categories: p.publication_type ? [p.publication_type] : undefined,
    };
  });

  return rss({
    title: 'Núcleo IA & GP — Publications',
    description: 'Peer-reviewed publications, articles, and research output from PMI Brasil chapters volunteer researchers on AI applied to Project Management.',
    site: context.site ?? 'https://nucleoia.vitormr.dev',
    items,
    customData: '<language>pt-BR</language>',
  });
};

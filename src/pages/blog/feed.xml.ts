import rss from '@astrojs/rss';
import { createClient } from '@supabase/supabase-js';
import type { APIRoute } from 'astro';

export const GET: APIRoute = async (context) => {
  const sb = createClient(
    import.meta.env.PUBLIC_SUPABASE_URL,
    import.meta.env.PUBLIC_SUPABASE_ANON_KEY,
  );

  const { data: posts } = await sb.from('blog_posts')
    .select('slug, title, excerpt, published_at')
    .eq('status', 'published')
    .neq('category', 'announcement')
    .order('published_at', { ascending: false })
    .limit(50);

  const items = (posts || []).map((p: any) => {
    const titleObj = typeof p.title === 'string' ? { 'pt-BR': p.title } : (p.title || {});
    const excerptObj = typeof p.excerpt === 'string' ? { 'pt-BR': p.excerpt } : (p.excerpt || {});
    const title = titleObj['pt-BR'] || titleObj['en-US'] || titleObj['es-LATAM'] || p.slug;
    const description = excerptObj['pt-BR'] || excerptObj['en-US'] || excerptObj['es-LATAM'] || '';
    return {
      title,
      description,
      pubDate: p.published_at ? new Date(p.published_at) : new Date(),
      link: `/blog/${p.slug}`,
    };
  });

  return rss({
    title: 'Núcleo IA & GP — Blog',
    description: 'AI & Project Management research from a collaborative network of PMI Brasil chapters.',
    site: context.site ?? 'https://nucleoia.vitormr.dev',
    items,
    customData: '<language>pt-BR</language>',
  });
};

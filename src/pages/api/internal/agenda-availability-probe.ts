// #2188 — sonda de disponibilidade das agendas de agendamento de entrevista.
//
// POR QUE UM NAVEGADOR. A disponibilidade de um Google appointment schedule so existe depois que a
// pagina monta em JS. `fetch` no link curto devolve 200 com 3.501 bytes de casca (medido em
// 04/09/2026), e ler esse 200 como "a agenda respondeu" foi exatamente o erro que manteve a #2188
// invisivel: o despacho tinha sucesso em todas as superficies enquanto o candidato via porta
// fechada. A API do Calendar tampouco serve sem OAuth de CADA avaliador sobre a agenda dele.
// Renderizar o link publico e a unica leitura que responde a pergunta do candidato.
//
// Auth: Bearer shared secret AGENDA_PROBE_INTERNAL_SECRET (wrangler secret), casado com o GUC de
// banco `app.agenda_probe_internal_secret` que o cron `interview-agenda-probe` usa.
// CSRF: /api/internal/ esta na allowlist de bypass (src/middleware.ts).
//
// Cross-ref: migration 20260908170500, src/pages/api/internal/cert-pdf-render/[id].ts (mesmo
// binding BROWSER e mesmo desenho de segredo compartilhado).

import type { APIRoute } from 'astro';
import { env as cfEnv } from 'cloudflare:workers';
import { createClient } from '@supabase/supabase-js';
import puppeteer from '@cloudflare/puppeteer';
import { timingSafeEqual } from '../../../lib/timing-safe-equal';

export const prerender = false;

/**
 * Marcador que o Google usa no aria-label de cada dia SEM horario. E a leitura mais estavel da
 * pagina: sai da grade do mes numa unica renderizacao, sem clicar em dia nenhum.
 */
const SEM_HORARIO = 'no available times';

/** Dia da semana em ingles: o controle de que a pagina veio no idioma que o parser espera. */
const DIA_EN = /(sunday|monday|tuesday|wednesday|thursday|friday|saturday)/i;

/** Botao de horario na faixa de dias visivel ("17:00", "9:30"). */
const HORARIO = /^\d{1,2}:\d{2}$/;

const MESES_EN = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

interface LeituraDaPagina {
  monthLabel: string | null;
  cells: string[];
  slots: number;
  semDisponibilidade: boolean;
}

interface Sondagem {
  booking_url: string;
  ok: boolean;
  days_open: number | null;
  slots_visible: number | null;
  window_start: string | null;
  window_end: string | null;
  error: string | null;
}

/**
 * Converte os aria-labels da grade em datas. Cada celula vem como "9, Wednesday" ou
 * "August 30, Sunday, no available times": o nome do mes so aparece quando a celula pertence a um
 * mes diferente do exibido no cabecalho.
 */
function janelaDaGrade(monthLabel: string | null, cells: string[]): { inicio: string | null; fim: string | null } {
  if (!monthLabel) return { inicio: null, fim: null };
  const m = monthLabel.trim().match(/^([A-Za-z]+)\s+(\d{4})$/);
  if (!m) return { inicio: null, fim: null };
  const mesBase = MESES_EN.indexOf(m[1].toLowerCase());
  const anoBase = Number(m[2]);
  if (mesBase < 0 || !Number.isFinite(anoBase)) return { inicio: null, fim: null };

  const datas: number[] = [];
  for (const label of cells) {
    const comMes = label.match(/^([A-Za-z]+)\s+(\d{1,2}),/);
    const soDia = label.match(/^(\d{1,2}),/);
    let mes = mesBase;
    let dia: number;
    if (comMes) {
      const idx = MESES_EN.indexOf(comMes[1].toLowerCase());
      if (idx < 0) continue;
      mes = idx;
      dia = Number(comMes[2]);
    } else if (soDia) {
      dia = Number(soDia[1]);
    } else {
      continue;
    }
    // A grade cobre no maximo um mes antes e um depois do exibido: o ano vira junto.
    let ano = anoBase;
    if (mes === 11 && mesBase === 0) ano = anoBase - 1;
    if (mes === 0 && mesBase === 11) ano = anoBase + 1;
    datas.push(Date.UTC(ano, mes, dia));
  }
  if (datas.length === 0) return { inicio: null, fim: null };
  const iso = (t: number) => new Date(t).toISOString().slice(0, 10);
  return { inicio: iso(Math.min(...datas)), fim: iso(Math.max(...datas)) };
}

async function sondar(browser: any, url: string): Promise<Sondagem> {
  const base: Sondagem = {
    booking_url: url,
    ok: false,
    days_open: null,
    slots_visible: null,
    window_start: null,
    window_end: null,
    error: null,
  };

  let page: any = null;
  try {
    page = await browser.newPage();
    // O parser casa strings em ingles. Pedir o idioma e metade do controle; a outra metade e a
    // verificacao abaixo, que reprova a leitura se a pagina vier em outro idioma.
    await page.setExtraHTTPHeaders({ 'Accept-Language': 'en-US,en;q=0.9' });
    await page.goto(url, { waitUntil: 'networkidle0', timeout: 45000 });
    await page.waitForSelector('[role="grid"]', { timeout: 20000 });

    const leitura: LeituraDaPagina = await page.evaluate(() => {
      const grid = document.querySelector('[role="grid"]');

      // ⚠️ NÃO use `[role="gridcell"]`. A grade é uma `<table role="grid">` cujas células são `<td>`
      // SEM role explícito: o papel gridcell é IMPLÍCITO, existe na árvore de acessibilidade e não
      // no DOM. A primeira versão desta sonda casou esse seletor e voltou 0 células nas quatro
      // agendas — porque foi escrita a partir do snapshot de acessibilidade, que é uma projeção do
      // DOM e não o DOM. Quem carrega o aria-label do dia é o `<button data-grid-cell>` dentro do
      // `<td>`. O fallback para qualquer `button` do grid tolera o Google largar o dataset.
      const botoesDoDia = grid
        ? (() => {
            const comDataset = Array.from(grid.querySelectorAll('button[data-grid-cell]'));
            return comDataset.length > 0 ? comDataset : Array.from(grid.querySelectorAll('button'));
          })()
        : [];

      const cells = botoesDoDia
        .map((b) => (b.getAttribute('aria-label') ?? '').trim())
        .filter((s) => s.length > 0);

      const slots = Array.from(document.querySelectorAll('button'))
        .map((b) => (b.textContent ?? '').trim())
        .filter((t) => /^\d{1,2}:\d{2}$/.test(t)).length;

      // O mês exibido vem do aria-label da própria `<table role="grid">` ("September 2026").
      const monthLabel = grid?.getAttribute('aria-label')?.trim() ?? null;

      const semDisponibilidade = (document.body.innerText ?? '')
        .toLowerCase()
        .includes('no availability during these days');

      return { monthLabel, cells, slots, semDisponibilidade };
    });

    if (leitura.cells.length === 0) {
      return { ...base, error: 'grade_vazia: nenhuma celula de dia com aria-label' };
    }

    // O CONTROLE QUE PODE FALHAR. Sem ele, uma pagina em pt-BR nao casaria `no available times` e
    // TODA agenda seria contada como aberta — o pior formato de defeito, porque e silencioso e
    // otimista. Nesse caso a sonda declara que nao sabe ler, e o despacho fica com as colunas
    // nulas em vez de com um numero errado.
    if (!leitura.cells.some((c) => DIA_EN.test(c))) {
      return {
        ...base,
        error: `idioma_inesperado: a grade nao veio em ingles, o marcador "${SEM_HORARIO}" nao e confiavel aqui`,
      };
    }

    const diasAbertos = leitura.cells.filter((c) => !c.toLowerCase().includes(SEM_HORARIO)).length;
    const { inicio, fim } = janelaDaGrade(leitura.monthLabel, leitura.cells);

    // Coerencia entre os dois sinais: a faixa de dias diz "sem disponibilidade" mas a grade
    // aponta dia aberto, ou o contrario. Nao invalida a leitura (a faixa cobre so 6 dias e a
    // grade cobre 6 semanas), mas fica registrado.
    const divergencia = leitura.semDisponibilidade && diasAbertos > 0
      ? `faixa_diz_vazio_mas_grade_tem_${diasAbertos}_dias`
      : null;

    return {
      booking_url: url,
      ok: true,
      days_open: diasAbertos,
      slots_visible: leitura.slots,
      window_start: inicio,
      window_end: fim,
      error: divergencia,
    };
  } catch (e: any) {
    return { ...base, error: `render_failed: ${e?.message ?? String(e)}` };
  } finally {
    if (page) {
      try { await page.close(); } catch { /* ignore */ }
    }
  }
}

export const POST: APIRoute = async ({ request }) => {
  // 1. Auth: Bearer shared secret
  const expectedSecret = (cfEnv as any)?.AGENDA_PROBE_INTERNAL_SECRET as string | undefined;
  if (!expectedSecret) {
    return new Response(
      JSON.stringify({ error: 'server_misconfig', detail: 'AGENDA_PROBE_INTERNAL_SECRET not set' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
  const auth = request.headers.get('Authorization') ?? '';
  // #1050 — comparacao em tempo constante, para o segredo nao vazar byte a byte por timing.
  if (!(await timingSafeEqual(auth, `Bearer ${expectedSecret}`))) {
    return new Response(
      JSON.stringify({ error: 'unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 2. Cliente service-role
  const supabaseUrl = (cfEnv as any)?.SUPABASE_URL || import.meta.env.PUBLIC_SUPABASE_URL;
  const serviceRoleKey = (cfEnv as any)?.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: 'server_misconfig', detail: 'SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
  const sb = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

  // 3. As agendas a sondar: override do comite em ciclo aberto, agenda global de membro do comite,
  // e o fallback do ciclo. E o mesmo conjunto que `resolve_interview_booking_url` pode eleger.
  const [ciclos, comite, membros] = await Promise.all([
    sb.from('selection_cycles').select('id, interview_booking_url').eq('status', 'open'),
    sb.from('selection_committee').select('member_id, cycle_id, interview_booking_url'),
    sb.from('members').select('id, interview_booking_url').not('interview_booking_url', 'is', null),
  ]);
  if (ciclos.error || comite.error || membros.error) {
    return new Response(
      JSON.stringify({
        error: 'query_failed',
        detail: ciclos.error?.message ?? comite.error?.message ?? membros.error?.message,
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const abertos = new Set((ciclos.data ?? []).map((c: any) => c.id));
  const noComite = new Set(
    (comite.data ?? []).filter((s: any) => abertos.has(s.cycle_id)).map((s: any) => s.member_id),
  );

  const urls = new Set<string>();
  for (const c of ciclos.data ?? []) {
    if (c.interview_booking_url) urls.add(String(c.interview_booking_url));
  }
  for (const s of comite.data ?? []) {
    if (abertos.has(s.cycle_id) && s.interview_booking_url) urls.add(String(s.interview_booking_url));
  }
  for (const m of membros.data ?? []) {
    if (noComite.has(m.id) && m.interview_booking_url) urls.add(String(m.interview_booking_url));
  }

  if (urls.size === 0) {
    return new Response(
      JSON.stringify({ ok: true, probed: 0, detail: 'nenhuma agenda configurada em ciclo aberto' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 4. Renderiza
  const browserBinding = (cfEnv as any)?.BROWSER;
  if (!browserBinding) {
    return new Response(
      JSON.stringify({ error: 'server_misconfig', detail: 'BROWSER binding not available' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const sondagens: Sondagem[] = [];
  let browser: any = null;
  try {
    browser = await puppeteer.launch(browserBinding);
    // Em serie: sao poucas agendas (4 configuradas, medido em 08/09/2026) e uma aba por vez mantem
    // o consumo do binding previsivel.
    for (const url of urls) {
      sondagens.push(await sondar(browser, url));
    }
  } catch (e: any) {
    return new Response(
      JSON.stringify({ error: 'browser_failed', detail: e?.message ?? String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  } finally {
    if (browser) {
      try { await browser.close(); } catch { /* ignore */ }
    }
  }

  // 5. Grava. A sondagem que falhou tambem vira linha: "a sonda nao conseguiu ler" e um fato sobre
  // o dia, e apaga-lo faria a serie parecer continua quando nao foi.
  const gravadas: any[] = [];
  for (const s of sondagens) {
    const { data, error } = await sb.rpc('record_interview_agenda_probe', {
      p_booking_url: s.booking_url,
      p_days_open: s.days_open,
      p_slots_visible: s.slots_visible,
      p_window_start: s.window_start,
      p_window_end: s.window_end,
      p_ok: s.ok,
      p_error: s.error,
    });
    gravadas.push(error ? { booking_url: s.booking_url, write_error: error.message } : data);
  }

  return new Response(
    JSON.stringify({
      ok: true,
      probed: sondagens.length,
      fechadas: sondagens.filter((s) => s.ok && s.days_open === 0).length,
      cegas: sondagens.filter((s) => !s.ok).length,
      sondagens,
      gravadas,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
};

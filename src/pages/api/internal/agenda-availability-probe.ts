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

/**
 * Botao de horario. #2404 — o padrao anterior era `/^\d{1,2}:\d{2}$/`, e a pagina servida em
 * ingles escreve `5:30pm`: ele nao casava NENHUM horario. Medido em 21/09/2026: `slots_visible`
 * saiu 0 em 212 de 212 sondagens desde 08/09, sendo que 212 delas tinham `days_open > 0`.
 */
const HORARIO = /^\d{1,2}:\d{2}\s*([ap]\.?m\.?)?$/i;

const MESES_EN = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

interface LeituraDaPagina {
  monthLabel: string | null;
  cells: string[];
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

      // O mês exibido vem do aria-label da própria `<table role="grid">` ("September 2026").
      const monthLabel = grid?.getAttribute('aria-label')?.trim() ?? null;

      const semDisponibilidade = (document.body.innerText ?? '')
        .toLowerCase()
        .includes('no availability during these days');

      return { monthLabel, cells, semDisponibilidade };
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

    // #2404 — CONTAR HORARIO EXIGE INTERAGIR. A pagina so renderiza a lista de horarios depois que
    // um dia e selecionado: na chegada existem apenas os botoes da grade do mes. Medido em
    // 21/09/2026 nas duas agendas do ciclo, ja com o padrao corrigido, contando na chegada: 0 e 0.
    // Ou seja, consertar o regex sozinho teria deixado a coluna em zero do mesmo jeito.
    //
    // O que passamos a medir e "quantos horarios existem no PRIMEIRO dia disponivel", que e a
    // pergunta do candidato e o sinal que teria pego o caso que originou a #2188: havia dias
    // abertos, mas todos na semana seguinte, e `days_open > 0` nao distinguia isso.
    let slotsNoPrimeiroDia: number | null = null;
    let primeiroDiaAberto: string | null = null;
    if (diasAbertos > 0) {
      primeiroDiaAberto =
        leitura.cells.find((c) => !c.toLowerCase().includes(SEM_HORARIO)) ?? null;
      if (primeiroDiaAberto) {
        // O clique vai por `evaluate` e nao por seletor CSS: o `aria-label` do dia carrega virgula
        // e espaco ("October 1, Thursday"), e montar seletor com ele e convite a erro de escape.
        await page.evaluate((label: string) => {
          const grid = document.querySelector('[role="grid"]');
          if (!grid) return;
          const alvo = Array.from(grid.querySelectorAll('button[data-grid-cell]')).find(
            (b) => (b.getAttribute('aria-label') ?? '').trim() === label,
          );
          if (alvo) (alvo as HTMLElement).click();
        }, primeiroDiaAberto);

        // Sem `waitForTimeout`: ele saiu do puppeteer moderno. A lista de horarios chega por
        // fetch, entao esperar por tempo e o que resta, e 4s cobriu as medicoes de 21/09.
        await new Promise((r) => setTimeout(r, 4000));

        // UM regex so. `page.evaluate` roda no contexto da pagina e nao enxerga o escopo do
        // modulo, entao o padrao viaja como STRING e e remontado la dentro. A versao anterior
        // mantinha uma copia inline ao lado da constante `HORARIO`, e nada obrigava as duas a
        // concordarem: a constante nomeada documentava a intencao enquanto a copia decidia. Era
        // codigo morto que parecia fonte da verdade.
        slotsNoPrimeiroDia = await page.evaluate(
          (padrao: string) =>
            Array.from(document.querySelectorAll('button'))
              .map((b) => (b.textContent ?? '').trim())
              .filter((t) => new RegExp(padrao, 'i').test(t)).length,
          HORARIO.source,
        );
      }
    }

    // Coerencia entre os dois sinais: a faixa de dias diz "sem disponibilidade" mas a grade
    // aponta dia aberto, ou o contrario. Nao invalida a leitura (a faixa cobre so 6 dias e a
    // grade cobre 6 semanas), mas fica registrado.
    const divergencia = leitura.semDisponibilidade && diasAbertos > 0
      ? `faixa_diz_vazio_mas_grade_tem_${diasAbertos}_dias`
      : null;

    // #2404 — `slots_visible` passa a ser o do primeiro dia aberto. Quando nao ha dia aberto, a
    // pergunta nao se aplica e o valor honesto e ZERO (a grade inteira diz "no available times").
    // Quando ha dia aberto e mesmo assim nao veio horario, o valor honesto e NULO, porque ai nao
    // sabemos se a agenda esvaziou entre a leitura e o clique ou se a pagina mudou de forma.
    const slotsFinal = diasAbertos === 0 ? 0 : slotsNoPrimeiroDia;
    const contadorCego =
      diasAbertos > 0 && (slotsNoPrimeiroDia === null || slotsNoPrimeiroDia === 0)
        ? `contador_cego: ${diasAbertos} dia(s) aberto(s) e nenhum horario em "${primeiroDiaAberto}"`
        : null;

    return {
      booking_url: url,
      ok: true,
      days_open: diasAbertos,
      slots_visible: slotsFinal,
      window_start: inicio,
      window_end: fim,
      error: divergencia ?? contadorCego,
    };
  } catch (e: any) {
    // O texto da exceção vai para o LOG do Worker e para a tabela (RLS deny-all, só service_role
    // lê), nunca para a resposta HTTP: `js/stack-trace-exposure`. Ver a montagem da Response.
    console.error('[agenda-probe] render falhou', { url, erro: e?.message ?? String(e) });
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
    // Erro do Postgres nomeia tabela, coluna e constraint: fica no log, não na resposta.
    console.error('[agenda-probe] leitura das agendas falhou', {
      ciclos: ciclos.error?.message,
      comite: comite.error?.message,
      membros: membros.error?.message,
    });
    return new Response(
      JSON.stringify({ error: 'query_failed' }),
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
    // `js/stack-trace-exposure`: a mensagem de uma exceção pode carregar caminho de arquivo, versão
    // de dependência e forma interna. Ela vai para o log do Worker, onde o dono a lê; a resposta
    // HTTP recebe só a classe do erro.
    console.error('[agenda-probe] falha ao abrir o browser', e?.message ?? String(e));
    return new Response(
      JSON.stringify({ error: 'browser_failed' }),
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
    if (error) {
      // Mensagem de erro do Postgres nomeia tabela, coluna e constraint. Fica no log.
      console.error('[agenda-probe] gravação falhou', { url: s.booking_url, erro: error.message });
      gravadas.push({ booking_url: s.booking_url, escrita: 'falhou' });
    } else {
      gravadas.push(data);
    }
  }

  // A resposta HTTP leva a CLASSE do erro, nunca o texto da exceção (`js/stack-trace-exposure`).
  // O texto completo continua em dois lugares onde é útil e não é público: o log do Worker e a
  // coluna `error` de `interview_agenda_probes`, que tem RLS deny-all e só o service_role lê.
  // Foi esse texto que apontou `grade_vazia` na primeira execução real, então ele não se perde —
  // só deixa de sair pela porta da frente.
  const classeDoErro = (e: string | null) => (e ? e.split(':')[0] : null);

  return new Response(
    JSON.stringify({
      ok: true,
      probed: sondagens.length,
      fechadas: sondagens.filter((s) => s.ok && s.days_open === 0).length,
      cegas: sondagens.filter((s) => !s.ok).length,
      sondagens: sondagens.map((s) => ({
        booking_url: s.booking_url,
        ok: s.ok,
        days_open: s.days_open,
        slots_visible: s.slots_visible,
        window_start: s.window_start,
        window_end: s.window_end,
        error_class: classeDoErro(s.error),
      })),
      gravadas,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
};

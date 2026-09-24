// tests/contracts/2447-guia-de-artefatos-alcancavel.test.mjs
// Registrar em "test:behavioural" + "test:contracts" (#1109). NAO em test:structural: le o banco,
// e o guard #1908 exige DB-gated na faixa SERIALIZADA (#1509).
/**
 * O guia de artefatos, revisao e curadoria existe e e alcancavel pelos quatro caminhos combinados:
 * jornadas da Ajuda, botao flutuante, secao do card e a propria URL nas 3 linguas.
 *
 * O CASO (#2447): as jornadas da Ajuda eram de 14/03, anteriores ao fluxo de revisao, e os passos
 * de "submeter para curadoria" de lider e pesquisador apontavam para /publications, o caminho
 * paralelo que nao passa pelo card. O botao de ajuda nao tinha pergunta sobre artefato.
 *
 * E o guia NAO pode prometer o que o banco nao faz: a lista de tipos que passam por curadoria no
 * texto e conferida contra tags.requires_curation.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SERVICE_ROLE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

const GUIDE = '/guia-artefatos';

/** Os caminhos de entrada no guia, lidos do codigo sem comentarios. */
export function entradas({ help, card, pages }) {
  const h = maskJsComments(help);
  const c = maskJsComments(card);
  return {
    paginaNas3Linguas: pages.pt && pages.en && pages.es,
    botaoLinka: /href=\{`\$\{lp\}\/guia-artefatos`\}/.test(h),
    botaoTemPerguntas: ['what_is_artifact', 'review_flow', 'not_artifact_in_flow'].every((id) => new RegExp(`id: '${id}', section: 'leaders'`).test(h)),
    cardLinka: /const guideHref = \(\) => `\$\{pageLang\(\) === 'pt' \? '' : '\/' \+ pageLang\(\)\}\/guia-artefatos`;/.test(c)
      && (c.match(/href=\{guideHref\(\)\}/g) || []).length >= 2,
  };
}

/** Passos de jornada que ensinam a submeter para curadoria pelo caminho paralelo. */
export function passosPeloCaminhoParalelo(journeys) {
  const out = [];
  for (const j of journeys) {
    for (const s of j.steps || []) {
      const txt = `${s.title?.pt ?? ''} ${s.description?.pt ?? ''}`.toLowerCase();
      if (/curadoria/.test(txt) && s.action_url === '/publications') out.push(`${j.persona_key}.${s.key}`);
    }
  }
  return out.sort();
}

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const FONTES = {
  help: read('src/components/help/HelpFloatingButton.tsx'),
  card: read('src/components/board/CardDetail.tsx'),
  pages: {
    pt: existsSync('src/pages/guia-artefatos.astro'),
    en: /url=\/guia-artefatos\?lang=en-US/.test(read('src/pages/en/guia-artefatos.astro')),
    es: /url=\/guia-artefatos\?lang=es-LATAM/.test(read('src/pages/es/guia-artefatos.astro')),
  },
};

test('#2447: o guia e alcancavel pela URL, pelo botao de ajuda e pelo card', () => {
  const e = entradas(FONTES);
  assert.deepEqual(e, Object.fromEntries(Object.keys(e).map((k) => [k, true])));
});

test(dbGated ? '#2447: as jornadas da Ajuda levam ao guia, e nenhuma ensina a curadoria pelo caminho paralelo' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data, error } = await sb().from('help_journeys').select('persona_key, steps');
    assert.equal(error, null);
    assert.ok(Array.isArray(data) && data.length >= 3, `jornadas vieram com ${data?.length}`);
    assert.deepEqual(passosPeloCaminhoParalelo(data), [], 'passo de jornada ensina curadoria por /publications');
    for (const persona of ['tribe_leader', 'researcher']) {
      const j = data.find((r) => r.persona_key === persona);
      assert.ok(j && j.steps.some((s) => s.action_url === GUIDE), `a jornada ${persona} nao leva ao guia`);
    }
  });

test(dbGated ? '#2447: o guia descreve exatamente os tipos que o banco manda para a curadoria' : `SKIP: ${skipMsg}`,
  { skip: !dbGated }, async () => {
    const { data, error } = await sb().from('tags').select('label_pt').eq('domain', 'board_item').eq('requires_curation', true);
    assert.equal(error, null);
    const guia = read('src/data/artifact-curation-guide.ts');
    const linhaPublicacao = (guia.match(/\{ type: 'Publicação', examples: '([^']*)', flow: 'Peer review, revisão do líder e curadoria' \}/) || [])[1];
    assert.ok(linhaPublicacao, 'a linha de publicacao sumiu do guia, ou deixou de dizer que passa por curadoria');
    // controle: o banco tem de vir cheio, senao "todos citados" passaria por vacuidade
    assert.ok(data.length >= 5, `requires_curation veio com ${data.length} tipos`);
    const ausentes = data.map((r) => r.label_pt).filter((l) => l && l !== 'Publicação'
      && !linhaPublicacao.toLowerCase().includes(l.toLowerCase().split(' ')[0]));
    assert.deepEqual(ausentes, [], 'tipo de curadoria no banco que o guia nao cita');
  });

test('#2447 mutacao: cada detector reprova a forma do defeito, pela MESMA funcao', () => {
  const m = (src, a, b) => { const out = src.replace(a, b); assert.notEqual(out, src, `mutacao nao aplicou: ${a}`); return out; };
  // 1: link do guia sai do botao
  assert.equal(entradas({ ...FONTES, help: m(FONTES.help, '${lp}/guia-artefatos', '${lp}/help') }).botaoLinka, false);
  // 2: uma pergunta some
  assert.equal(entradas({ ...FONTES, help: m(FONTES.help, "id: 'review_flow', section: 'leaders'", "id: 'review_flow', section: 'admin'") }).botaoTemPerguntas, false);
  // 3: o card perde um dos links
  assert.equal(entradas({ ...FONTES, card: m(FONTES.card, 'href={guideHref()}', 'href="#"') }).cardLinka, false);
  // 4: pagina em uma lingua some
  assert.equal(entradas({ ...FONTES, pages: { ...FONTES.pages, es: false } }).paginaNas3Linguas, false);
  // 5: passo de curadoria apontando para /publications e acusado
  const J = [{ persona_key: 'tribe_leader', steps: [{ key: 'x', title: { pt: 'Submeta para curadoria' }, description: { pt: '' }, action_url: '/publications' }] }];
  assert.deepEqual(passosPeloCaminhoParalelo(J), ['tribe_leader.x']);
  // controle: o mesmo passo apontando para o guia nao e acusado
  assert.deepEqual(passosPeloCaminhoParalelo([{ ...J[0], steps: [{ ...J[0].steps[0], action_url: GUIDE }] }]), []);
});

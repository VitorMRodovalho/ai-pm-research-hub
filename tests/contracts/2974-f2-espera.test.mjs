/**
 * #2974 (F2): telas que esperavam o membro em laço próprio (`if (!member) { setTimeout(check, n); return; }`) passam
 * a esperar pelo gateAdminPage, sem mexer no portão.
 *
 * - O allow de cada tela é o predicado de antes, preso aqui como texto (main em 25fb90b7, só com as anotações de tipo
 *   do script de módulo). Mudar o predicado é mudar quem vê a tela, e isso não é desta fatia.
 * - Sem sessão, a tela pede para entrar; quando as capacidades falham, mostra o texto de falha; negada, o texto de
 *   antes. Nos três casos o aviso aparece e o conteúdo some.
 * - Liberada, o conteúdo aparece e o aviso some, para o caso de o Nav resolver de novo depois de uma recusa.
 * - A tela não espera mais por conta própria: nada de setTimeout nem de leitura do membro ou das capacidades fora do
 *   portão. A agenda-viva decide só pelas capacidades, e lê-las dentro do allow é o portão decidindo.
 * - F6: a comparação de tribos entra na mesma tabela. O portão dela esperava window.navMember, que nada define.
 * - O texto de falha de carga só existe onde a recusa pode ser falsa: a tela tem onLoadFailed se e só se o predicado
 *   lê capacidade. Um predicado que só lê o membro decide igual com ou sem get_caller_capabilities.
 * - O span admin-signin-to-view, que o adminSignInText lê, aparece uma vez só no que monta a tela (página e layouts).
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const norm = (s) => s.replace(/\s+/g, ' ').trim();

const TIER_B = "const hasAdminCapability = (window as any).__nucleoCanForAdminEntry?.() === true; " +
  "const v3HardTier = ['manager', 'deputy_manager'].includes(member.operational_role); " +
  "const hasAdminDesignation = (member.designations || []).some(function(d: string) { return d === 'deputy_manager' || d === 'curator'; }); " +
  'return member.is_superadmin || hasAdminCapability || v3HardTier || hasAdminDesignation;';
const TELAS = [
  {
    arq: 'src/pages/admin/agenda-recorrente.astro', id: 'recurring-agenda', nome: 'RecurringAgenda', texto: "t('admin.deniedAdmin', lang)",
    ilha: 'RecurringAgendaIsland',
    predicado: "return member.is_superadmin || member.operational_role === 'manager' || " +
      "(member.designations || []).some(function (d: string) { return d === 'deputy_manager'; });",
  },
  { arq: 'src/pages/admin/data-health.astro', id: 'data-health', nome: 'DataHealth', texto: "t('admin.deniedAdmin', lang)", ilha: 'DataHealthIsland', predicado: TIER_B },
  { arq: 'src/pages/admin/knowledge.astro', id: 'knowledge', nome: 'Knowledge', texto: 'deniedMsg', ilha: 'KnowledgeIsland', predicado: TIER_B },
  { arq: 'src/pages/admin/tags.astro', id: 'tags', nome: 'Tags', texto: "t('admin.deniedAdmin', lang)", ilha: 'TagManagementIsland', predicado: TIER_B },
  {
    arq: 'src/pages/admin/index.astro', id: 'admin-dashboard', nome: 'AdminDashboard', texto: "t('admin.deniedAdmin', lang)",
    ilha: 'AdminDashboardIsland', predicado: TIER_B.replace("d === 'curator'; });", "d === 'curator' || d === 'chapter_board'; });"),
  },
  {
    arq: 'src/pages/admin/vep-reconciliation.astro', id: 'vep-reconciliation', nome: 'VepReconciliation', texto: "t('admin.deniedAdmin', lang)",
    ilha: 'VepReconciliationIsland', predicado: TIER_B,
  },
  // F6: o portão antigo da comparação de tribos esperava window.navMember, que nada define, e nunca decidia. O allow
  // é o predicado que a página já tinha (aprovado pelo GP com a matriz de antes e depois).
  {
    arq: 'src/pages/admin/tribes.astro', id: 'tribes', nome: 'Tribes', texto: "t('admin.tribes.denied', lang)",
    ilha: 'CrossTribeIsland', predicado: TIER_B,
  },
  // A agenda-viva decide só pelas capacidades. Antes, `if (!caps) { setTimeout(check, 300); return; }` esperava por
  // elas sem fim; aqui o Nav já as leu quando o portão chama o allow, e sem elas a resposta é falso. O resto é o de antes.
  {
    arq: 'src/pages/admin/agenda-viva.astro', id: 'agenda-viva', nome: 'AgendaViva', texto: "t('admin.deniedAdmin', lang)",
    ilha: 'AdminAgendaVivaPanel',
    predicado: 'const caps = (window as any).__nucleoCapabilities; if (!caps) return false; ' +
      "const has = (arr: any) => Array.isArray(arr) && arr.includes('manage_event'); " +
      'return caps.is_superadmin || has(caps.org_actions) || Object.values(caps.initiative_actions || {}).some(has) || ' +
      'Object.values(caps.tribe_actions || {}).some(has);',
  },
];
// A stakeholder usa o BaseLayout e tem o próprio aviso (cadeado e parágrafo), então tem bloco próprio abaixo.
const STAKEHOLDER = {
  arq: 'src/pages/stakeholder.astro', nome: 'Stakeholder', assinatura: 'function hasStakeholderAccess(m: any): boolean {',
  predicado: "return m.is_superadmin === true || ['manager', 'deputy_manager'].includes(m.operational_role || '') || " +
    "m.operational_role === 'chapter_liaison' || " +
    "(m.designations || []).some((d: string) => ['sponsor', 'chapter_liaison', 'chapter_board'].includes(d));",
};
// Ler capacidade é o que torna a recusa possivelmente falsa quando get_caller_capabilities falha.
const LE_CAPACIDADE = /__nucleoCanFor|\bcanFor(?:AdminEntry)?\(|__nucleoCapabilities/;

const ler = (arq) => readFileSync(resolve(ROOT, arq), 'utf8');

// O que o `<div id="...">` envolve, contando as aberturas e os fechamentos de div até o que fecha o dele.
function divConteudo(src, id) {
  const a = src.indexOf(`<div id="${id}"`);
  if (a < 0) return null;
  let nivel = 0;
  for (const m of src.slice(a).matchAll(/<div\b|<\/div>/g)) {
    nivel += m[0] === '</div>' ? -1 : 1;
    if (nivel === 0) return src.slice(a, a + m.index);
  }
  return null;
}
// O corpo de `function nome(...) {` até o `}` que fecha na mesma indentação do script (dois espaços).
function corpo(src, assinatura) {
  const a = src.indexOf(assinatura);
  if (a < 0) return null;
  const b = src.indexOf('\n  }\n', a);
  return b < 0 ? null : src.slice(a + assinatura.length, b);
}

for (const t of TELAS) {
  const CONST = `${t.id.toUpperCase().replace(/-/g, '_')}_DENIED_TEXT`;

  test(`${t.arq}: o allow é o predicado de antes`, () => {
    const c = corpo(maskJsComments(ler(t.arq)), `function has${t.nome}Access(member: any): boolean {`);
    assert.ok(c !== null, `has${t.nome}Access não encontrada`);
    assert.equal(norm(c), norm(t.predicado), 'o predicado do allow mudou');
  });

  test(`${t.arq}: decide pelo gateAdminPage; sem sessão pede para entrar, falha de carga tem texto próprio`, () => {
    const s = norm(maskJsComments(ler(t.arq)));
    // A falha de carga só entra quando o predicado lê capacidade (o teste "se e só se" abaixo amarra as duas coisas).
    const leCapacidade = LE_CAPACIDADE.test(norm(t.predicado));
    assert.match(s, new RegExp(
      `gateAdminPage\\(\\{ allow: has${t.nome}Access, onAllowed: \\(\\) => show${t.nome}Page\\(\\), ` +
      `onDenied: \\(\\) => show${t.nome}Notice\\(${CONST}\\), ` +
      `onNoSession: \\(\\) => show${t.nome}Notice\\(adminSignInText\\(\\)\\), ` +
      (leCapacidade ? `onLoadFailed: \\(\\) => show${t.nome}Notice\\(adminLoadFailedText\\(\\)\\), ` : '') + '\\}\\);',
    ), 'o portão não liga cada caso ao seu aviso');
    assert.match(s, leCapacidade
      ? /import \{ adminLoadFailedText, adminSignInText, gateAdminPage \} from '\.\.\/\.\.\/lib\/member-ready';/
      : /import \{ adminSignInText, gateAdminPage \} from '\.\.\/\.\.\/lib\/member-ready';/);
  });

  test(`${t.arq}: o aviso esconde o conteúdo, e liberar mostra o conteúdo e esconde o aviso`, () => {
    const src = ler(t.arq);
    const s = norm(maskJsComments(src));
    assert.match(src, new RegExp(`<div id="${t.id}-notice" class="hidden [^"]*">\\{${esc(t.texto)}\\}</div>`),
      'o aviso não nasce escondido com o texto de negado');
    assert.match(divConteudo(src, `${t.id}-content`) || '', new RegExp(`<${t.ilha} client:load\\b`),
      'o conteúdo não envolve a ilha da tela');
    assert.match(s, new RegExp(`const ${CONST} = document\\.getElementById\\('${t.id}-notice'\\)\\?\\.textContent\\?\\.trim\\(\\) \\|\\| '';`),
      'o texto de negado não vem do aviso');
    assert.match(s, new RegExp(
      `function show${t.nome}Notice\\(text: string\\) \\{ const notice = document\\.getElementById\\('${t.id}-notice'\\); ` +
      "if \\(notice\\) \\{ notice\\.textContent = text; notice\\.classList\\.remove\\('hidden'\\); \\} " +
      `document\\.getElementById\\('${t.id}-content'\\)\\?\\.classList\\.add\\('hidden'\\); \\}`,
    ), 'o aviso não aparece no lugar do conteúdo');
    assert.match(s, new RegExp(
      `function show${t.nome}Page\\(\\) \\{ document\\.getElementById\\('${t.id}-notice'\\)\\?\\.classList\\.add\\('hidden'\\); ` +
      `document\\.getElementById\\('${t.id}-content'\\)\\?\\.classList\\.remove\\('hidden'\\); \\}`,
    ), 'liberar não mostra o conteúdo nem esconde o aviso');
    if (t.texto === 'deniedMsg') {
      assert.match(src, /const deniedMsg = t\('admin\.knowledge\.denied', lang\);/, 'o texto de negado da tela mudou');
    }
  });

  test(`${t.arq}: não espera mais por conta própria`, () => {
    const s = maskJsComments(ler(t.arq));
    assert.doesNotMatch(s, /setTimeout/, 'a tela voltou a se reagendar');
    // Dentro do allow, ler as capacidades é o portão decidindo; o predicado está preso pelo teste acima.
    const c = corpo(s, `function has${t.nome}Access(member: any): boolean {`);
    assert.ok(c !== null, `has${t.nome}Access não encontrada`);
    assert.doesNotMatch(s.replace(c, ''), /navGetMember|navMember|nav:member|getSession|__nucleoCapabilities/,
      'a tela lê o membro ou as capacidades fora do portão');
  });
}

// O que monta a tela: a página e a cadeia de layouts (o AdminLayout embrulha o BaseLayout, que traz o Nav).
function montagem(arq) {
  const src = ler(arq);
  const arqs = [arq];
  if (/import AdminLayout from '[^']*layouts\/AdminLayout\.astro';/.test(src)) arqs.push('src/layouts/AdminLayout.astro');
  if (/import (?:Admin|Base)Layout from '[^']*layouts\/(?:Admin|Base)Layout\.astro';/.test(src)) {
    arqs.push('src/layouts/BaseLayout.astro', 'src/components/nav/Nav.astro');
  }
  return arqs;
}

const PORTOES = [
  ...TELAS.map((t) => ({ arq: t.arq, assinatura: `function has${t.nome}Access(member: any): boolean {` })),
  { arq: STAKEHOLDER.arq, assinatura: STAKEHOLDER.assinatura },
];
for (const t of PORTOES) {
  test(`${t.arq}: tem onLoadFailed se e só se o predicado lê capacidade`, () => {
    const s = maskJsComments(ler(t.arq));
    const c = corpo(s, t.assinatura);
    assert.ok(c !== null, 'o predicado não foi encontrado');
    const le = LE_CAPACIDADE.test(c);
    assert.equal(/\bonLoadFailed\s*:/.test(s), le, le
      ? 'o predicado lê capacidade e a tela não tem o texto de falha de carga'
      : 'o predicado só lê o membro e a tela mostra falha de carga numa recusa certa');
  });

  test(`${t.arq}: o texto de entrar aparece uma vez só no que monta a tela`, () => {
    const arqs = montagem(t.arq);
    assert.ok(arqs.length > 1, 'a tela não usa o AdminLayout nem o BaseLayout');
    const n = arqs.reduce((soma, a) => soma + ler(a).split('id="admin-signin-to-view"').length - 1, 0);
    assert.equal(n, 1, `admin-signin-to-view aparece ${n} vezes em ${arqs.join(', ')}`);
  });
}

// ── A stakeholder: mesmo portão, no BaseLayout. O aviso é o cadeado com o parágrafo, e só o texto do parágrafo muda.
test(`${STAKEHOLDER.arq}: o allow é o predicado de antes`, () => {
  const c = corpo(maskJsComments(ler(STAKEHOLDER.arq)), STAKEHOLDER.assinatura);
  assert.ok(c !== null, 'hasStakeholderAccess não encontrada');
  assert.equal(norm(c), norm(STAKEHOLDER.predicado), 'o predicado do allow mudou');
});

test(`${STAKEHOLDER.arq}: decide pelo gateAdminPage; sem sessão pede para entrar`, () => {
  const s = norm(maskJsComments(ler(STAKEHOLDER.arq)));
  assert.match(s, /gateAdminPage\(\{ allow: hasStakeholderAccess, onAllowed: \(m\) => showStakeholderPage\(m\), onDenied: \(\) => showStakeholderNotice\(STAKEHOLDER_DENIED_TEXT\), onNoSession: \(\) => showStakeholderNotice\(adminSignInText\(\)\), \}\);/,
    'o portão não liga cada caso ao seu aviso');
  assert.match(s, /import \{ adminSignInText, gateAdminPage \} from '\.\.\/lib\/member-ready';/);
});

test(`${STAKEHOLDER.arq}: o aviso esconde o carregando e o app, e liberar mostra o app e esconde os dois`, () => {
  const src = ler(STAKEHOLDER.arq);
  const s = norm(maskJsComments(src));
  assert.match(src, /<span id="admin-signin-to-view" class="hidden">\{t\('admin\.signInToView', lang\)\}<\/span>/,
    'falta o texto de entrar, que o BaseLayout não traz');
  assert.match(src, /<div id="stakeholder-denied" class="hidden /, 'o aviso não nasce escondido');
  assert.match(divConteudo(src, 'stakeholder-denied') || '',
    /<p id="stakeholder-denied-text" class="[^"]*">\{t\('stakeholder\.accessDenied', lang\) \|\| '[^']*'\}<\/p>/,
    'o parágrafo do aviso não tem o texto de negado');
  assert.match(src, /<div id="stakeholder-app" class="hidden /, 'o app não nasce escondido');
  assert.match(divConteudo(src, 'stakeholder-app') || '', /<ChapterDashboard client:load\b/, 'o app não envolve o painel do capítulo');
  assert.match(s, /const STAKEHOLDER_DENIED_TEXT = document\.getElementById\('stakeholder-denied-text'\)\?\.textContent\?\.trim\(\) \|\| '';/,
    'o texto de negado não vem do aviso');
  assert.match(s, /function showStakeholderNotice\(text: string\) \{ document\.getElementById\('stakeholder-loading'\)\?\.classList\.add\('hidden'\); const p = document\.getElementById\('stakeholder-denied-text'\); if \(p\) p\.textContent = text; document\.getElementById\('stakeholder-denied'\)\?\.classList\.remove\('hidden'\); document\.getElementById\('stakeholder-app'\)\?\.classList\.add\('hidden'\); \}/,
    'o aviso não aparece no lugar do carregando e do app');
  const pagina = corpo(maskJsComments(src), 'function showStakeholderPage(m: any) {');
  assert.ok(pagina !== null, 'showStakeholderPage não encontrada');
  assert.match(norm(pagina), /^document\.getElementById\('stakeholder-loading'\)\?\.classList\.add\('hidden'\); document\.getElementById\('stakeholder-denied'\)\?\.classList\.add\('hidden'\); document\.getElementById\('stakeholder-app'\)\?\.classList\.remove\('hidden'\);/,
    'liberar não mostra o app nem esconde o carregando e o aviso');
  assert.ok(norm(pagina).includes("const isBoard = (m.designations || []).includes('chapter_board'); const dismissed = localStorage.getItem('chapter_board_welcome_dismissed'); if (isBoard && !dismissed) { document.getElementById('chapter-board-welcome')?.classList.remove('hidden'); }"),
    'a faixa de boas-vindas da diretoria mudou');
});

test(`${STAKEHOLDER.arq}: não espera mais por conta própria`, () => {
  const s = maskJsComments(ler(STAKEHOLDER.arq));
  assert.doesNotMatch(s, /setTimeout/, 'a tela voltou a se reagendar');
  assert.doesNotMatch(s, /navGetMember|navGetSb|navMember|nav:member|getSession|__nucleoCapabilities/, 'a tela lê o membro fora do portão');
});

// ── Ilhas do painel do admin, dos certificados, da vep-reconciliation e do workspace: a primeira chamada espera o
// useResolvedMember, sem prazo, e se repete quando o membro muda; sem membro, a ilha não mostra nada. Onde há
// predicado, quem vê é o de antes, ligado ao setAuthorized.
const PRED_VOLUNTARIADO = "if (!(m.is_superadmin || ['manager', 'deputy_manager'].includes(m.operational_role) || " +
  "(m.designations || []).includes('chapter_board'))) return; setAuthorized(true);";
const ILHAS = [
  { arq: 'src/components/admin/CrossTribeWidget.tsx', retorno: 'if (!memberId || !data) return null;', predicado: null },
  {
    arq: 'src/components/admin/VepReconciliationWidget.tsx', retorno: 'if (!memberId || !authorized || !data) return null;',
    predicado: "const isAdmin = m.is_superadmin || canForAdminEntry() || ['manager', 'deputy_manager'].includes(m.operational_role) || " +
      "(m.designations || []).some((d: string) => d === 'deputy_manager' || d === 'curator' || d === 'chapter_board'); " +
      'if (!isAdmin) return; setAuthorized(true);',
  },
  { arq: 'src/components/admin/VolunteerComplianceWidget.tsx', retorno: 'if (!memberId || !authorized || !data?.summary) return null;', predicado: PRED_VOLUNTARIADO },
  { arq: 'src/components/admin/VolunteerAgreementPanel.tsx', retorno: 'if (!memberId || !authorized || !summary) return null;', predicado: PRED_VOLUNTARIADO },
  {
    arq: 'src/components/admin/VepReconciliationIsland.tsx', retorno: 'if (!memberId) return null;',
    predicado: "const isAdmin = m.is_superadmin || canForAdminEntry() || ['manager', 'deputy_manager'].includes(m.operational_role) || " +
      "(m.designations || []).some((d: string) => d === 'deputy_manager' || d === 'curator' || d === 'chapter_board'); " +
      'if (!isAdmin) { setAuthorized(false); return; } setAuthorized(true);',
  },
  { arq: 'src/components/workspace/MyCardsWidget.tsx', retorno: 'if (!memberId || cards === null) return null;', predicado: null },
  { arq: 'src/components/workspace/MyActionItemsWidget.tsx', retorno: 'if (!memberId || items === null) return null;', predicado: null },
  // O painel da agenda-viva não tem predicado: quem decide é a página, e as RPCs (manage_event) são a fronteira.
  { arq: 'src/components/admin/AdminAgendaVivaPanel.tsx', retorno: 'if (!memberId) return null; if (loading) {', predicado: null },
];

// ── A ilha da comparação de tribos (F6) carrega dentro do próprio useEffect, que depende do filtro de tipo: a espera
// pelo membro fica no começo do efeito, e o membro entra nas dependências.
const CROSS_TRIBE = 'src/components/islands/CrossTribeIsland.tsx';
test(`${CROSS_TRIBE}: a primeira chamada espera o membro resolvido, sem laço próprio`, () => {
  const s = norm(maskJsComments(ler(CROSS_TRIBE)));
  assert.match(s, /import \{ useResolvedMember \} from '\.\.\/\.\.\/hooks\/useResolvedMember';/);
  assert.match(s, /const \{ memberId \} = useResolvedMember\(\);/, 'a ilha não lê o membro resolvido');
  assert.match(s, /useEffect\(\(\) => \{ if \(!memberId\) return; let cancelled = false; const load = async \(\) => \{ const sb = \(window as any\)\.navGetSb\?\.\(\); if \(!sb\) return; /,
    'o efeito não espera o membro antes de carregar');
  assert.match(s, /load\(\); return \(\) => \{ cancelled = true; \}; \}, \[selectedKind, memberId\]\);/, 'o efeito não se repete quando o membro muda');
  assert.doesNotMatch(s, /setTimeout/, 'a ilha voltou a se reagendar');
});

test(`${CROSS_TRIBE}: sem membro, não mostra nada`, () => {
  assert.ok(norm(maskJsComments(ler(CROSS_TRIBE))).includes('if (!memberId) return null; if (loading) return'), 'a ilha mostra conteúdo sem membro');
});

// O load vai até o fechamento do useCallback, com a lista de dependências que ele tiver (o painel da agenda-viva
// depende de getSb).
function corpoDoLoad(s) {
  const a = s.indexOf('const load = useCallback(async () => {');
  if (a < 0) return null;
  const m = /\}, \[[\w, ]*\]\);/.exec(s.slice(a));
  return m ? s.slice(a, a + m.index) : null;
}

for (const i of ILHAS) {
  test(`${i.arq}: a primeira chamada espera o membro resolvido, sem laço próprio`, () => {
    const s = norm(maskJsComments(ler(i.arq)));
    assert.match(s, /import \{ useResolvedMember \} from '\.\.\/\.\.\/hooks\/useResolvedMember';/);
    assert.match(s, /const \{ memberId \} = useResolvedMember\(\);/, 'a ilha não lê o membro resolvido');
    assert.match(s, /useEffect\(\(\) => \{ if \(memberId\) load\(\); \}, \[load, memberId\]\);/, 'a primeira chamada não espera o membro');
    assert.doesNotMatch(s, /useEffect\(\(\) => \{ load\(\); \}, \[load\]\);/, 'a ilha voltou a chamar na montagem');
    assert.doesNotMatch(s, /setTimeout/, 'a ilha voltou a se reagendar');
    const load = corpoDoLoad(s);
    assert.ok(load, 'load não encontrado');
    assert.match(load, /if \(!sb\) return;/, 'sem cliente, o load não para');
  });

  test(`${i.arq}: sem membro, não mostra nada`, () => {
    assert.ok(norm(maskJsComments(ler(i.arq))).includes(i.retorno), 'a ilha mostra conteúdo sem membro');
  });

  if (i.predicado) {
    test(`${i.arq}: quem vê é o predicado de antes`, () => {
      const load = corpoDoLoad(norm(maskJsComments(ler(i.arq)))) || '';
      const p = norm(i.predicado);
      assert.ok(load.includes(p), 'o predicado mudou');
      // o único setAuthorized(true) do load é o que vem logo depois do predicado
      assert.equal(load.split('setAuthorized(true)').length - 1, 1, 'o load autoriza em mais de um lugar');
      assert.equal(load.indexOf('setAuthorized(true)'), load.indexOf(p) + p.length - 'setAuthorized(true);'.length,
        'o load autoriza antes de o predicado decidir');
    });
  }
}

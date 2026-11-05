/**
 * #2974 (F2): telas que esperavam o membro em laço próprio (`if (!member) { setTimeout(check, n); return; }`) passam
 * a esperar pelo gateAdminPage, sem mexer no portão.
 *
 * - O allow de cada tela é o predicado de antes, preso aqui como texto (main em 25fb90b7, só com as anotações de tipo
 *   do script de módulo). Mudar o predicado é mudar quem vê a tela, e isso não é desta fatia.
 * - Sem sessão, a tela pede para entrar; quando as capacidades falham, mostra o texto de falha; negada, o texto de
 *   antes. Nos três casos o aviso aparece e o conteúdo some.
 * - Liberada, o conteúdo aparece e o aviso some, para o caso de o Nav resolver de novo depois de uma recusa.
 * - A tela não espera mais por conta própria: nada de setTimeout nem de leitura do membro fora do portão.
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
];

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
    assert.match(s, new RegExp(
      `gateAdminPage\\(\\{ allow: has${t.nome}Access, onAllowed: \\(\\) => show${t.nome}Page\\(\\), ` +
      `onDenied: \\(\\) => show${t.nome}Notice\\(${CONST}\\), ` +
      `onNoSession: \\(\\) => show${t.nome}Notice\\(adminSignInText\\(\\)\\), ` +
      `onLoadFailed: \\(\\) => show${t.nome}Notice\\(adminLoadFailedText\\(\\)\\), \\}\\);`,
    ), 'o portão não liga cada caso ao seu aviso');
    assert.match(s, /import \{ adminLoadFailedText, adminSignInText, gateAdminPage \} from '\.\.\/\.\.\/lib\/member-ready';/);
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
    assert.doesNotMatch(s, /navGetMember|navMember|nav:member|getSession|__nucleoCapabilities/, 'a tela lê o membro fora do portão');
  });
}

// ── Ilhas do painel do admin e dos certificados: a primeira chamada espera o useResolvedMember, sem prazo, e se repete
// quando o membro muda; sem membro, a ilha não mostra nada. Quem vê é o predicado de antes, ligado ao setAuthorized.
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
];

function corpoDoLoad(s) {
  const a = s.indexOf('const load = useCallback(async () => {');
  if (a < 0) return null;
  const b = s.indexOf('}, []);', a);
  return b < 0 ? null : s.slice(a, b);
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

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
    predicado: "return member.is_superadmin || member.operational_role === 'manager' || " +
      "(member.designations || []).some(function (d: string) { return d === 'deputy_manager'; });",
  },
  { arq: 'src/pages/admin/data-health.astro', id: 'data-health', nome: 'DataHealth', texto: "t('admin.deniedAdmin', lang)", predicado: TIER_B },
  { arq: 'src/pages/admin/knowledge.astro', id: 'knowledge', nome: 'Knowledge', texto: 'deniedMsg', predicado: TIER_B },
  { arq: 'src/pages/admin/tags.astro', id: 'tags', nome: 'Tags', texto: "t('admin.deniedAdmin', lang)", predicado: TIER_B },
];

const ler = (arq) => readFileSync(resolve(ROOT, arq), 'utf8');
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
    assert.match(src, new RegExp(`<div id="${t.id}-content" [^>]*>\\s*<\\w+Island client:load />\\s*</div>`),
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
    assert.doesNotMatch(s, /navGetMember|navMember|nav:member|getSession|is:inline/, 'a tela lê o membro fora do portão');
  });
}

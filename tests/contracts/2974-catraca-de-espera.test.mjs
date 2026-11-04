/**
 * #2974 (E1): catraca das formas de espera que decidem acesso fora do primitivo.
 *
 * A regra da emenda à ADR-0083: uma página ou ilha que decide um portão de tela, ou que faz uma chamada que depende de
 * quem é a pessoa, faz isso só dentro do primitivo de `src/lib/member-ready.ts` (`gateAdminPage`, `onMemberResolved`)
 * ou do hook `useResolvedMember`. As formas abaixo são as que a regra tira, e hoje ainda existem. A catraca não
 * corrige nada: ela impede que a dívida cresça e obriga a registrar cada correção.
 *
 * Os dados estão em `2974-catraca-de-espera.json`:
 *   - `base`: os arquivos que tinham a forma quando a catraca entrou. Cada base é selada por md5 aqui embaixo, então
 *     acrescentar um nome a ela reprova;
 *   - `corrigidas`: quem saiu da forma. Corrigir um arquivo é mover o nome de `base` para `corrigidas`, na mesma PR;
 *   - `isentos`: exceção como dado, com o motivo.
 *
 * O censo reprova:
 *   - arquivo com a forma que não está na dívida nem nos isentos (arquivo novo, ou corrigido que voltou);
 *   - arquivo da dívida que não tem mais a forma (corrigido sem registro);
 *   - isento que perdeu a forma.
 *
 * Formas: contador de tentativas esperando o membro ou o cliente; laço sem limite até o membro; laço sem limite até as
 * capacidades; escuta de `nav:member` sem `nav:no-session`; leitura de `navGetMember()` sem evento; ilha que chama RPC
 * depois de esperar só o cliente. Comentários são mascarados antes de medir.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '../..');
const DADOS = JSON.parse(readFileSync(resolve(HERE, '2974-catraca-de-espera.json'), 'utf8'));

// O selo de cada base. Mudar um selo é mudar a dívida aceita, e isso pede decisão registrada na PR.
const SELOS = {
  contador: '84d8b0278149a8f0bd192faef033768d',
  sem_limite_membro: '55283caa6bd82e0d7322f1d5c76a385e',
  sem_limite_capacidades: 'aeddc353d9e309ecedf9faec04da6107',
  so_nav_member: '0631f3fc3a96335ed0355685ff085bab',
  le_navgetmember_sem_evento: 'f9f9826bb8ba4d3a207ab69e9cb6ba56',
  ilha_sem_membro: '815e35a8dcde856e242d1cf69b4e57e0',
};

const CONTADOR = /\+\+\s*\w*(?:[Rr]etries|tries)\b|\b\w*(?:[Rr]etries|tries)\s*(?:\+\+|\+=\s*1)/;
const LACO = /if\s*\(\s*!\s*([\w.?()\[\]'"]+?)\s*\)\s*\{?\s*(?:[^;{}]{0,60};\s*)?setTimeout\(\s*(\w+)\s*,\s*(\d+)\s*\)/g;
const PRIMITIVO = /\bgateAdminPage\b|\bonMemberResolved\b|\buseResolvedMember\b/;
const ESPERA_MEMBRO = /navGetMember|nav:member|onMemberResolved|useResolvedMember|getSession|onAuthStateChange/;
const varsDoLaco = (c) => [...c.matchAll(LACO)].map((m) => m[1]);

/** Cada forma: (caminho, fonte sem comentários) => tem a forma. */
const FORMAS = {
  contador: (p, c) => CONTADOR.test(c) && (c.includes('navGetMember') || c.includes('navGetSb')),
  sem_limite_membro: (p, c) => varsDoLaco(c).some((v) => v === 'member' || v === 'm'),
  sem_limite_capacidades: (p, c) => varsDoLaco(c).includes('caps'),
  so_nav_member: (p, c) => /addEventListener\(\s*['"]nav:member['"]/.test(c)
    && !/addEventListener\(\s*['"]nav:no-session['"]/.test(c) && !PRIMITIVO.test(c),
  le_navgetmember_sem_evento: (p, c) => /navGetMember\?*\.?\(/.test(c)
    && !/['"]nav:member['"]|['"]nav:no-session['"]/.test(c) && !PRIMITIVO.test(c),
  ilha_sem_membro: (p, c) => /\.(tsx?|jsx?)$/.test(p) && !p.startsWith('src/pages/')
    && c.includes('navGetSb') && /\.rpc\(/.test(c) && !ESPERA_MEMBRO.test(c),
};

// Controles: cada detector diz sim para a forma e não para a mesma tela escrita com o primitivo.
const CONTROLES = {
  contador: [
    "let tries = 0; const t = setInterval(() => { tries++; const m = window.navGetMember(); }, 200);",
    "gateAdminPage({ allow, onAllowed, onDenied, onNoSession });",
  ],
  sem_limite_membro: [
    "function check() { const member = window.navGetMember?.(); if (!member) { setTimeout(check, 300); return; } }",
    "onMemberResolved((r) => { if (r.kind === 'member') boot(r.member); });",
  ],
  sem_limite_capacidades: [
    "function wait() { const caps = window.__nucleoCapabilities; if (!caps) { setTimeout(wait, 300); return; } }",
    "gateAdminPage({ allow: () => window.__nucleoCanFor('manage_event'), onAllowed, onDenied, onNoSession });",
  ],
  so_nav_member: [
    "window.addEventListener('nav:member', (e) => render(e.detail));",
    "window.addEventListener('nav:member', render); window.addEventListener('nav:no-session', render);",
  ],
  le_navgetmember_sem_evento: [
    "const member = (window as any).navGetMember?.(); if (!member) showDenied();",
    "onMemberResolved((r) => { const member = (window as any).navGetMember?.(); });",
  ],
  ilha_sem_membro: [
    "useEffect(() => { const sb = (window as any).navGetSb?.(); sb.rpc('get_x'); }, []);",
    "const { memberId } = useResolvedMember(); useEffect(() => { const sb = (window as any).navGetSb?.(); if (memberId) sb.rpc('get_x'); }, [memberId]);",
  ],
};

function arquivos(dir, out = []) {
  for (const e of readdirSync(join(ROOT, dir))) {
    const p = join(dir, e);
    if (statSync(join(ROOT, p)).isDirectory()) arquivos(p, out);
    else if (/\.(astro|tsx?|jsx?)$/.test(e)) out.push(p);
  }
  return out;
}

const selo = (lista) => createHash('md5').update([...lista].sort().join('\n')).digest('hex');

test('catraca: os detectores dizem sim para a forma e não para o primitivo', () => {
  assert.deepEqual(Object.keys(CONTROLES).sort(), Object.keys(FORMAS).sort());
  for (const [k, [sim, nao]] of Object.entries(CONTROLES)) {
    const p = k === 'ilha_sem_membro' ? 'src/components/x/Controle.tsx' : 'src/pages/controle.astro';
    assert.equal(FORMAS[k](p, sim), true, `${k}: o detector não reconhece a forma`);
    assert.equal(FORMAS[k](p, nao), false, `${k}: o detector acusa a tela escrita com o primitivo`);
  }
});

test('catraca: cada base está selada, e corrigidas e isentos não se misturam com ela', () => {
  assert.deepEqual(Object.keys(DADOS.formas).sort(), Object.keys(FORMAS).sort(), 'forma sem dados ou dados sem forma');
  assert.deepEqual(Object.keys(SELOS).sort(), Object.keys(FORMAS).sort(), 'forma sem selo');
  for (const [k, { base, corrigidas }] of Object.entries(DADOS.formas)) {
    assert.equal(new Set(base).size, base.length, `${k}: nome repetido na base`);
    assert.equal(selo(base), SELOS[k], `${k}: a base mudou. Ela não cresce; para registrar uma correção, mova o nome para corrigidas`);
    const fora = corrigidas.filter((p) => !base.includes(p));
    assert.deepEqual(fora, [], `${k}: corrigidas tem nome que não estava na base`);
    assert.equal(new Set(corrigidas).size, corrigidas.length, `${k}: nome repetido em corrigidas`);
    const isentos = Object.keys(DADOS.isentos[k] || {});
    assert.deepEqual(isentos.filter((p) => base.includes(p)), [], `${k}: isento também está na base`);
    for (const p of isentos) assert.ok(String(DADOS.isentos[k][p]).trim().length > 20, `${k}: isenção sem motivo: ${p}`);
  }
});

test('catraca: o código tem exatamente a dívida registrada, sem forma nova e sem correção sem registro', () => {
  const todos = [...arquivos('src/pages'), ...arquivos('src/components'), ...arquivos('src/hooks')];
  const fontes = new Map(todos.map((p) => [p, maskJsComments(readFileSync(join(ROOT, p), 'utf8'))]));
  const problemas = [];
  for (const [k, fn] of Object.entries(FORMAS)) {
    const { base, corrigidas } = DADOS.formas[k];
    const devidas = new Set(base.filter((p) => !corrigidas.includes(p)));
    const isentos = new Set(Object.keys(DADOS.isentos[k] || {}));
    const achadas = new Set(todos.filter((p) => fn(p, fontes.get(p))));
    const novas = [...achadas].filter((p) => !devidas.has(p) && !isentos.has(p)).sort();
    const semRegistro = [...devidas].filter((p) => !achadas.has(p)).sort();
    const isentoVencido = [...isentos].filter((p) => !achadas.has(p)).sort();
    if (novas.length) problemas.push(`${k}: forma nova ou que voltou (use o primitivo de member-ready):\n  ${novas.join('\n  ')}`);
    if (semRegistro.length) problemas.push(`${k}: não têm mais a forma; mova de base para corrigidas:\n  ${semRegistro.join('\n  ')}`);
    if (isentoVencido.length) problemas.push(`${k}: isento sem a forma; tire dos isentos:\n  ${isentoVencido.join('\n  ')}`);
  }
  assert.deepEqual(problemas, [], problemas.join('\n'));
});

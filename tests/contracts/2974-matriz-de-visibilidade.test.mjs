/**
 * #2974 (F0b): matriz de visibilidade do menu e da sidebar, exercida no Node sobre formas sintéticas de membro.
 *
 * As decisões vêm das FUNÇÕES do front, importadas de src:
 *   - gaveta e menu: `getItemAccessibility` de `src/lib/navigation.config.ts`, com o tier de `resolveTierFromMember`;
 *   - sidebar do admin: `isAdminSidebarItemVisible` sobre `ADMIN_SIDEBAR_SECTIONS`, o mesmo predicado que
 *     `AdminSidebar.tsx` usa.
 * As formas são sintéticas: cada papel sozinho, cada designação sozinha sobre `researcher`, superadmin, os dois papéis
 * de comitê e "sem membro". Nenhuma combinação real de pessoa entra aqui.
 *
 * #2974 (F1): cada forma leva também as capacidades simuladas (`setCapabilities`), porque as rotas de
 * `ADMIN_ROUTE_ACCESS` decidem pela ação V4. As formas de papel e designação vêm sem ações; superadmin vem com a marca;
 * e entram uma forma por ação de organização sozinha, mais as de escopo de tribo e de iniciativa.
 *
 * O snapshot (`2974-matriz-de-visibilidade.snapshot.json`) é o comportamento aprovado. Uma fatia que muda quem vê o
 * quê regrava o snapshot com `ATUALIZAR_MATRIZ=1 node --test <este arquivo>`, e a diferença aparece na revisão da PR.
 *
 * Também afirma que a gêmea do cliente em `Nav.astro` delega o "habilitado" a `getItemAccessibility`, em vez de
 * recalcular os eixos, para que menu do servidor e do cliente não divirjam por um eixo novo em só um lado.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';
import { NAV_ITEMS, getItemAccessibility, ADMIN_SIDEBAR_SECTIONS, isAdminSidebarItemVisible, ADMIN_ROUTE_ACCESS } from '../../src/lib/navigation.config.ts';
import { resolveTierFromMember } from '../../src/lib/admin/route-access.ts';
import { setCapabilities, clearCapabilities, ADMIN_TIER_ACTIONS } from '../../src/lib/permissions.ts';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '../..');
const SNAPSHOT = resolve(HERE, '2974-matriz-de-visibilidade.snapshot.json');

const PAPEIS = ['manager', 'deputy_manager', 'tribe_leader', 'researcher', 'chapter_liaison', 'sponsor', 'observer', 'guest',
  'alumni', 'none', 'institutional_auditor', 'facilitator', 'communicator', 'project_collaborator', 'cop_participant',
  'cop_observer', 'candidate', 'visitor'];
const DESIGNACOES = ['sponsor', 'chapter_liaison', 'ambassador', 'founder', 'curator', 'comms_team', 'comms_leader',
  'comms_member', 'co_gp', 'deputy_manager', 'chapter_board', 'certificacao_director', 'filiacao_director',
  'voluntariado_director', 'ip_committee', 'legal_signer', 'external_reviewer', 'chapter_vice_president', 'pmo_liaison',
  'chapter_witness', 'alumni'];
const SEM_ACOES = { is_superadmin: false, org_actions: [], initiative_actions: {}, tribe_actions: {} };
const PESQUISADOR = { operational_role: 'researcher', designations: [], is_superadmin: false };
const ACOES = [...new Set([...ADMIN_TIER_ACTIONS, ...Object.values(ADMIN_ROUTE_ACCESS).flatMap((a) => a.actions)])].sort();
// [id, membro, capacidades]
const FORMAS = [
  ...PAPEIS.map((p) => [`papel:${p}`, { operational_role: p, designations: [], is_superadmin: false }, SEM_ACOES]),
  ...DESIGNACOES.map((d) => [`designacao:${d}`, { operational_role: 'researcher', designations: [d], is_superadmin: false }, SEM_ACOES]),
  ['superadmin', { operational_role: 'researcher', designations: [], is_superadmin: true }, { ...SEM_ACOES, is_superadmin: true }],
  ['comite:evaluator', { operational_role: 'researcher', designations: [], is_superadmin: false, selection_committee_role: 'evaluator' }, SEM_ACOES],
  ['comite:observer', { operational_role: 'researcher', designations: [], is_superadmin: false, selection_committee_role: 'observer' }, SEM_ACOES],
  ...ACOES.map((a) => [`acao:${a}`, PESQUISADOR, { ...SEM_ACOES, org_actions: [a] }]),
  ...ACOES.map((a) => [`tribo:${a}`, PESQUISADOR, { ...SEM_ACOES, tribe_actions: { 1: [a] } }]),
  ...ACOES.map((a) => [`iniciativa:${a}`, PESQUISADOR, { ...SEM_ACOES, initiative_actions: { 'iniciativa-sintetica': [a] } }]),
  ['sem-membro', null, null],
];

function matriz() {
  const out = {};
  for (const [id, m, caps] of FORMAS) {
    if (caps) setCapabilities(caps); else clearCapabilities();
    const tier = resolveTierFromMember(m);
    const menu = NAV_ITEMS.filter((item) =>
      getItemAccessibility(item, tier, m?.designations || [], !!m, m?.operational_role, m?.selection_committee_role ?? null).enabled,
    ).map((item) => item.key);
    const sidebar = ADMIN_SIDEBAR_SECTIONS.flatMap((s) => s.items).filter((i) => isAdminSidebarItemVisible(m, i)).map((i) => i.href);
    out[id] = { menu, sidebar };
  }
  clearCapabilities();
  return out;
}

test('a matriz de visibilidade é a aprovada no snapshot', () => {
  const agora = matriz();
  if (process.env.ATUALIZAR_MATRIZ === '1') {
    writeFileSync(SNAPSHOT, JSON.stringify(agora, null, 1) + '\n');
  }
  const aprovada = JSON.parse(readFileSync(SNAPSHOT, 'utf8'));
  // controle: a matriz distingue formas (o instrumento consegue dizer não)
  assert.notDeepEqual(agora['papel:manager'], agora['papel:researcher'], 'controle: manager e researcher deram o mesmo');
  assert.equal(Object.keys(agora).length, FORMAS.length);
  for (const [id] of FORMAS) {
    assert.deepEqual(agora[id], aprovada[id], `a visibilidade mudou para ${id}; se foi de propósito, regrave o snapshot`);
  }
});

test('Nav.astro: a gêmea do cliente delega o habilitado a getItemAccessibility', () => {
  const nav = maskJsComments(readFileSync(resolve(ROOT, 'src/components/nav/Nav.astro'), 'utf8'));
  assert.match(nav, /import\s*\{[^}]*\bgetItemAccessibility\b[^}]*\}\s*from\s*'\.\.\/\.\.\/lib\/navigation\.config'/);
  const at = nav.indexOf('function getItemAccessClient(');
  assert.ok(at >= 0, 'getItemAccessClient não encontrada');
  const corpo = nav.slice(at, nav.indexOf('function isItemVisibleClient(', at));
  assert.match(corpo, /const \{ enabled \} = getItemAccessibility\(/);
  assert.doesNotMatch(corpo, /meetsMinTier|hasDesig|hasOpRole|hasCommittee|TIER_RANK/,
    'a gêmea voltou a recalcular os eixos por conta própria');
});

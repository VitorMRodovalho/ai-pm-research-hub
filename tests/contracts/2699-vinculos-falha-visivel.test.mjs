/**
 * #2699 (parte 3) — telas de membro e vínculo que diziam "ok" sem ter feito.
 *
 * Caso de 15/10/2026: a primeira tentativa de tirar um membro da tribo foi pelo campo Tribo de
 * /admin/members/[id]. A RPC gravou `members.tribe_id = null`, o gatilho de ponte devolveu o valor
 * a partir da iniciativa, o engajamento seguiu ativo, e a tela disse "Membro atualizado". Decisão
 * do GP: o campo vira somente leitura com link para a página da tribo, onde o vínculo muda de fato.
 *
 * Mesma auditoria, mesma classe: a ficha antiga /admin/member/[id] (tribo, salvar, inativar,
 * reativar), o painel de membros de board (remover, trocar papel) e a lista de membros (salvar,
 * superadmin).
 *
 * Os guards amarram CONDIÇÃO a RESULTADO dentro do bloco que decide (CLAUDE.md, 17/09).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const read = (p) => maskJsComments(readFileSync(join(ROOT, p), 'utf8'));
const DET = read('src/components/admin/members/MemberDetailIsland.tsx');
const OLD = read('src/pages/admin/member/[id].astro');
const LIST = read('src/components/admin/members/MemberListIsland.tsx');
const BOARD = read('src/components/admin/BoardMembersPanel.tsx');

function fnBody(src, header) {
  const i = src.indexOf(header);
  if (i < 0) return '';
  const j = src.indexOf('\n  };', i);
  return src.slice(i, j < 0 ? undefined : j);
}

test('#2699 /admin/members/[id]: Tribo é leitura com link, e o salvar não grava tribe_id', () => {
  assert.doesNotMatch(DET, /changes\.tribe_id\s*=/, 'o salvar voltou a gravar members.tribe_id');
  assert.doesNotMatch(DET, /setEditTribe/, 'o campo editável de tribo voltou');
  assert.match(DET,
    /data-tribe-readonly[^>]*>\s*\{m\.tribe_id != null\s+\? <a href=\{`\$\{lp\}\/tribe\/\$\{m\.tribe_id\}`\}/,
    'o campo tem de levar à página da tribo');
});

test('#2699 /admin/member/[id]: tribo leitura, salvar/inativar/reativar leem o erro', () => {
  assert.doesNotMatch(OLD, /<select id="f-tribe"/, 'o seletor de tribo voltou');
  assert.match(OLD, /p_tribe_id: null, /, 'o salvar não pode mandar tribo do formulário');
  assert.match(OLD, /id="f-tribe-readonly"[\s\S]{0,200}href="\$\{\(window as any\)\.__LANG_PREFIX \|\| ''\}\/tribe\/\$\{m\.tribe_id\}"/,
    'a tribo tem de levar à página da tribo');
  assert.match(OLD,
    /result = compat\.error \? \{ error: compat\.error\.message \|\| T\.error\.actionFailed \} : compat\.data;/,
    'o erro de rede do salvar era descartado');
  const inact = fnBody(OLD, 'const inactivateMember = async');
  assert.match(inact,
    /if \(inactErr \|\| inact\?\.error\) \{[^}]*'error'\); return; \}\s+\(window as any\)\.toast\?\.\(T\.toast\.inactivated/,
    'inativar tem de parar no erro antes do toast');
  const react = fnBody(OLD, 'const reactivateMember = async');
  assert.match(react, /sb\.rpc\('admin_reactivate_member', \{ p_member_id: id, p_tribe_id: null \}\)/,
    'p_tribe_id é obrigatório na assinatura; sem ele a chamada não acha a função');
  assert.match(react,
    /if \(reactErr \|\| react\?\.error\) \{[^}]*'error'\); return; \}\s+\(window as any\)\.toast\?\.\(T\.toast\.reactivated/,
    'reativar tem de parar no erro antes do toast');
});

test('#2699 lista de membros: salvar lê {error} do corpo e confere a linha do superadmin', () => {
  const save = fnBody(LIST, 'const saveEdit = async');
  assert.match(save, /const error = rpcErr \|\| \(upd\?\.error \? \{ message: upd\.error \} : null\);\s+if \(!error\)/,
    'admin_update_member devolve {success:false,error} com HTTP 200');
  assert.match(save,
    /\.update\(\{ is_superadmin: editSuperadmin \}\)\.eq\('id', editMember\.id\)\.select\('id'\);\s+if \(suErr \|\| !suRows\?\.length\) \{[\s\S]*?'error'\);[\s\S]*?return;/,
    'UPDATE barrado pela RLS volta sem erro e com 0 linhas');
});

test('#2699 membros de board: remover e trocar papel avisam a recusa', () => {
  const rem = fnBody(BOARD, 'const handleRemove = async');
  assert.match(rem, /if \(error \|\| data\?\.error\) \{\s+\(window as any\)\.toast\?\.\([^;]*'error'\);\s+\} else \{\s+\(window as any\)\.toast\?\.\(t\('boardMembers\.removed'/,
    'remover dizia "removido" com a recusa no corpo');
  const role = fnBody(BOARD, 'const handleChangeRole = async');
  assert.match(role, /const \{ data, error \} = await sb\.rpc\('admin_manage_board_member'[\s\S]*?if \(error \|\| data\?\.error\) \{\s+\(window as any\)\.toast\?\.\([^;]*'error'\);/,
    'trocar papel ignorava o resultado');
});

/**
 * resolve_whatsapp_link: tribo nula conta como tribo diferente nas duas checagens de acesso.
 *
 * Antes desta mudanca, o portao de acesso era `if not (A or B or C or (v_caller.tribe_id is not null and
 * v_caller.tribe_id = v_target.tribe_id)) then <recusa>`. Com o alvo sem tribo, a ultima comparacao da NULL; se A, B
 * e C forem falsos, a disjuncao inteira da NULL, `not NULL` da NULL e o IF nao entra na recusa: o link sai. O escopo
 * por capitulo tinha a mesma forma (`and not (...)`). Exercido em 27/10/2026 com a credencial de um membro comum:
 * alvo sem tribo devolveu o link, alvo de outra tribo devolveu 'Not authorized'.
 *
 * O QUE ESTE GUARD AFIRMA, no corpo da captura mais nova, com comentarios mascarados:
 *   G1. o portao de acesso fica dentro de COALESCE(..., false) e e ele que leva a 'Not authorized';
 *   G2. no escopo por capitulo, "mesma tribo" e COALESCE(caller = alvo, false) e leva a 'Not authorized';
 *   G3. a forma antiga `and not (v_caller.tribe_id is not null and ...)` nao volta;
 *   G4. as duas recusas vem antes do retorno com o link.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const body = maskLineComments(latestFunctionCapture(ROOT, 'resolve_whatsapp_link').body);

const DENY = String.raw`\s+return jsonb_build_object\('success', false, 'error', 'Not authorized'\);`;
const GATE = new RegExp(
  String.raw`if not coalesce\(\(\s*v_caller\.is_superadmin = true\s+or v_caller\.operational_role in \('manager', 'deputy_manager'\)\s+or public\.can_by_member\(v_caller\.id, 'view_pii'\)\s+or \(v_caller\.tribe_id is not null and v_caller\.tribe_id = v_target\.tribe_id\)\s*\), false\) then` + DENY,
);
const SCOPE = new RegExp(
  String.raw`if v_scope is not null\s+and v_target\.chapter is distinct from v_scope\s+and not coalesce\(v_caller\.tribe_id = v_target\.tribe_id, false\)\s+then` + DENY,
);

test('G1. o portao de acesso trata NULL como falso e recusa', () => {
  assert.match(body, GATE, 'a disjuncao do portao esta em COALESCE(..., false) e leva a Not authorized');
});

test('G2. no escopo por capitulo, tribo nula nao e a mesma tribo', () => {
  assert.match(body, SCOPE, 'mesma tribo e COALESCE(caller = alvo, false) e leva a Not authorized');
});

test('G3. a forma que falhava aberta nao volta ao escopo por capitulo', () => {
  assert.doesNotMatch(body, /and not \(\s*v_caller\.tribe_id is not null and v_caller\.tribe_id = v_target\.tribe_id\s*\)/);
});

test('G4. as duas recusas vem antes do retorno com o link', () => {
  const gate = body.search(GATE);
  const scope = body.search(SCOPE);
  const link = body.search(/'success', true,\s+'url', 'https:\/\/wa\.me\/'/);
  assert.ok(gate !== -1 && scope !== -1 && link !== -1, 'portao, escopo e retorno do link existem');
  assert.ok(gate < scope && scope < link, 'portao, depois escopo, depois o link');
});

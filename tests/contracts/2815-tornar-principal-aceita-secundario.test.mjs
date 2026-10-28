/**
 * #2815: "Tornar principal" do perfil aceita o e-mail secundário verificado pela tela, e troca os dois de lugar.
 *
 * O card "E-mails cadastrados" lista members.secondary_emails (gravado por confirm_secondary_email), e o botão
 * chamava member_set_primary_email, que procurava o endereço só em member_emails. Medido em 28/10/2026: 65 dos 67
 * secundários sem linha em member_emails, então o botão respondia "Email not found" para quase todos. Exercido no
 * banco, numa transação desfeita, com a função antiga: endereço só em secondary_emails deu esse erro.
 *
 * O QUE ESTE GUARD AFIRMA, no corpo da captura mais nova, com comentários mascarados:
 *   G1. a âncora do membro lê secondary_emails para v_secondary, com trava da linha;
 *   G2. "não encontrado" só sai quando o endereço não está em member_emails NEM em v_secondary;
 *   G3. a nova lista de secundários inclui o principal antigo e exclui o novo;
 *   G4. um único UPDATE grava o novo principal e a nova lista de secundários;
 *   G5. a liberação da trava de secondary_emails vem logo antes desse UPDATE;
 *   G6. endereço de outra conta é recusado com mensagem genérica, antes do UPDATE;
 *   G7. o portão #684 continua: discriminador por papel e "o próprio membro ou manage_member";
 *   G8. a tela manda para a função um endereço tirado de currentMember.secondary_emails.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const body = maskLineComments(latestFunctionCapture(ROOT, 'member_set_primary_email').body);

const UPDATE_RE = /UPDATE public\.members\s+SET email = COALESCE\(v_canonical::text, v_norm\),\s+secondary_emails = v_new_secondary,/;

test('G1. a âncora do membro lê secondary_emails, com trava da linha', () => {
  assert.match(
    body,
    /SELECT organization_id, email, COALESCE\(secondary_emails, '\{\}'::text\[\]\)\s+INTO v_target_org_id, v_current_email, v_secondary\s+FROM public\.members WHERE id = p_member_id\s+FOR UPDATE;/,
  );
});

test('G2. "não encontrado" só quando o endereço não está em nenhuma das duas listas', () => {
  assert.match(body, /v_in_secondary := v_norm = ANY \(SELECT lower\(e\) FROM unnest\(v_secondary\) AS e\);/);
  assert.match(
    body,
    /IF v_norm = '' OR \(v_row_id IS NULL AND NOT v_in_secondary\) THEN\s+RAISE EXCEPTION 'Email not found for this member; ensure it was previously added\.';/,
  );
});

test('G3. a nova lista de secundários ganha o principal antigo e perde o novo', () => {
  assert.match(
    body,
    /SELECT lower\(x\) AS e FROM unnest\(v_secondary\) AS x\s+UNION\s+SELECT lower\(v_current_email\)\s+\) s\s+WHERE e IS NOT NULL AND length\(e\) > 0 AND e <> v_norm;/,
  );
});

test('G4. um único UPDATE grava o novo principal e a nova lista', () => {
  assert.match(body, UPDATE_RE);
  assert.equal((body.match(/UPDATE public\.members\b/g) || []).length, 1, 'só um UPDATE em members');
});

test('G5. a trava de secondary_emails é liberada logo antes do UPDATE', () => {
  assert.match(
    body,
    /PERFORM set_config\('app\.bypass_secondary_emails_lock', 'true', true\);\s+UPDATE public\.members\s+SET email =/,
  );
});

test('G6. endereço de outra conta é recusado com mensagem genérica, antes do UPDATE', () => {
  const COLLISION =
    /IF EXISTS \(SELECT 1 FROM public\.member_emails WHERE email = v_norm::citext AND member_id <> p_member_id\)\s+OR EXISTS \(SELECT 1 FROM public\.members WHERE lower\(email\) = v_norm AND id <> p_member_id\) THEN\s+RAISE EXCEPTION 'This email already belongs to another account; contact the platform team\.';/;
  const c = body.search(COLLISION);
  assert.ok(c >= 0, 'recusa por colisão presente');
  const u = body.search(/UPDATE public\.members\s+SET email =/);
  assert.ok(u > c, 'a recusa vem antes do UPDATE');
});

test('G7. o portão #684 continua', () => {
  assert.match(body, /v_is_service_role := NOT public\._request_is_rest_caller\(\);/);
  assert.match(
    body,
    /IF v_caller\.id = p_member_id OR public\.can_by_member\(v_caller\.id, 'manage_member'\) THEN\s+v_allowed := true;/,
  );
  assert.match(body, /IF NOT v_allowed THEN\s+RAISE EXCEPTION 'Unauthorized to set primary email';/);
});

test('G8. a tela manda um endereço tirado de currentMember.secondary_emails', () => {
  const src = maskJsComments(readFileSync(join(ROOT, 'src/pages/profile.astro'), 'utf8'));
  const start = src.indexOf('async function makePrimaryEmail(');
  assert.ok(start >= 0, 'makePrimaryEmail presente');
  const fn = src.slice(start, src.indexOf('\n  }\n', start));
  assert.match(
    fn,
    /const existing: string\[\] = currentMember\.secondary_emails \|\| \[\];\s+const promoted = existing\[idx\];[\s\S]*sb\.rpc\('member_set_primary_email', \{\s+p_member_id: currentMember\.id, p_email: promoted,/,
  );
});

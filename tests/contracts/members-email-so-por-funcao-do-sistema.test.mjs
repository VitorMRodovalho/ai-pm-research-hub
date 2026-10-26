/**
 * members.email só muda por função do sistema (item interno, 26/10/2026).
 *
 * O caminho de objetos no Storage foi derivado do e-mail com @ e . trocados por _, e dois e-mails diferentes podem
 * dar o mesmo caminho. Como members_update_own deixa o membro gravar qualquer coluna da própria linha, a trava
 * recusa a troca de e-mail feita direto por authenticated ou anon. A troca legítima passa por
 * member_set_primary_email (SECURITY DEFINER) e o backend usa service_role.
 *
 * O guard afirma a condição junto do resultado, no corpo da captura vigente:
 *   A. o gatilho recusa quando o e-mail muda E quem executa é authenticated ou anon, com 42501;
 *   B. a função do gatilho não é SECURITY DEFINER (senão current_user seria o dono e a trava não pegaria ninguém);
 *   C. o gatilho é BEFORE UPDATE OF email em public.members, por linha, chamando essa função;
 *   D. a pós-condição exige os dois braços: authenticated recusado E o dono aceito (controle).
 */
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = new URL('../..', import.meta.url).pathname;
const norm = (s) => s.replace(/\s+/g, ' ').trim();

const CAP = latestFunctionCapture(ROOT, '_tg_lock_members_email');
const BODY = norm(maskLineComments(CAP.body));
const HEADER = norm(maskLineComments(CAP.block.slice(0, CAP.block.indexOf(CAP.body))));
const FILE = norm(maskLineComments(readFileSync(join(ROOT, 'supabase/migrations', CAP.file), 'utf8')));

describe('members.email só muda por função do sistema', () => {
  it('A: e-mail mudou E quem executa é authenticated ou anon => recusa com 42501', () => {
    assert.match(
      BODY,
      /IF OLD\.email IS DISTINCT FROM NEW\.email AND current_user IN \('authenticated', 'anon'\) THEN RAISE EXCEPTION '[^']*' USING ERRCODE = 'insufficient_privilege'; END IF; RETURN NEW;/,
    );
  });

  it('B: a função do gatilho não é SECURITY DEFINER', () => {
    assert.match(HEADER, /FUNCTION public\._tg_lock_members_email\(\) RETURNS trigger LANGUAGE plpgsql/);
    assert.doesNotMatch(HEADER, /SECURITY DEFINER/i);
  });

  it('C: BEFORE UPDATE OF email em public.members, por linha, com esta função', () => {
    assert.match(
      FILE,
      /CREATE TRIGGER trg_lock_members_email BEFORE UPDATE OF email ON public\.members FOR EACH ROW EXECUTE FUNCTION public\._tg_lock_members_email\(\);/,
    );
  });

  it('D: a pós-condição exige authenticated recusado E o dono aceito', () => {
    assert.match(
      FILE,
      /IF v_outcome IS DISTINCT FROM 'denied' OR v_control IS DISTINCT FROM 'allowed' THEN RAISE EXCEPTION/,
    );
    assert.match(FILE, /EXECUTE 'SET LOCAL ROLE authenticated'; BEGIN UPDATE public\.members SET email = /);
  });
});

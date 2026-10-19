/**
 * #2732 — members mantém a ponte com persons: o nome do perfil e o vínculo de volta.
 *
 * Decisão do GP (18/10/2026): o nome do PERFIL (members.name) é a fonte; persons segue members. O gatilho
 * copia o nome quando diverge e preenche persons.legacy_member_id quando está vazio, sem roubar vínculo.
 *
 * O corpo da função é lido pela captura MAIS NOVA (#1932), sem comentários; o gatilho, pelo arquivo da
 * migration. A última asserção lê o banco vivo com a chave de serviço (pula sem credenciais).
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';
import { dbFetch } from '../helpers/db-fetch.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const MIG_DIR = resolve(ROOT, 'supabase/migrations');
const MIG = readdirSync(MIG_DIR).filter((x) => x.endsWith('_2732_ponte_members_persons.sql'));
const SQL = MIG.length === 1 ? maskLineComments(readFileSync(resolve(MIG_DIR, MIG[0]), 'utf8')) : '';
const FN = maskLineComments(latestFunctionCapture(ROOT, '_trg_sync_person_bridge_from_member').body);

const BASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(BASE_URL && SERVICE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

test('#2732 a migration tem arquivo com a versão registrada', () => {
  assert.equal(MIG.length, 1);
  assert.doesNotMatch(MIG[0], /^20261018999999_/, 'arquivo ainda com o placeholder: renomeie para a versão registrada');
});

test('#2732 o gatilho dispara na criação e na troca de nome ou de pessoa', () => {
  assert.match(
    SQL,
    /CREATE TRIGGER trg_sync_person_bridge_from_member\s+AFTER INSERT OR UPDATE OF name, person_id ON public\.members\s+FOR EACH ROW EXECUTE FUNCTION public\._trg_sync_person_bridge_from_member\(\);/,
  );
  assert.match(SQL, /REVOKE ALL ON FUNCTION public\._trg_sync_person_bridge_from_member\(\) FROM PUBLIC, anon, authenticated;/);
});

test('#2732 persons.name segue o nome do perfil', () => {
  assert.match(
    FN,
    /UPDATE public\.persons p\s+SET name = NEW\.name,\s+updated_at = now\(\)\s+WHERE p\.id = NEW\.person_id\s+AND p\.name IS DISTINCT FROM NEW\.name;/,
  );
});

test('#2732 o vínculo de volta é preenchido só quando vazio e sem roubar', () => {
  assert.match(
    FN,
    /SET legacy_member_id = NEW\.id,\s+updated_at = now\(\)\s+WHERE p\.id = NEW\.person_id\s+AND p\.legacy_member_id IS NULL\s+AND NOT EXISTS \(SELECT 1 FROM public\.persons p2 WHERE p2\.legacy_member_id = NEW\.id\);/,
  );
});

test('#2732 banco vivo: nenhum membro com nome ou vínculo divergente da sua persons', { skip: dbGated ? false : skipMsg }, async () => {
  const headers = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` };
  const [rm, rp] = await Promise.all([
    dbFetch(`${BASE_URL}/rest/v1/members?select=id,name,person_id&person_id=not.is.null`, { headers }),
    dbFetch(`${BASE_URL}/rest/v1/persons?select=id,name,legacy_member_id`, { headers }),
  ]);
  assert.equal(rm.status, 200, `members voltou ${rm.status}`);
  assert.equal(rp.status, 200, `persons voltou ${rp.status}`);
  const members = await rm.json();
  const persons = new Map((await rp.json()).map((p) => [p.id, p]));
  assert.ok(members.length > 0, 'controle: nenhum membro com person_id veio do banco');
  const nomes = members.filter((m) => persons.get(m.person_id)?.name !== m.name).length;
  const vinculos = members.filter((m) => persons.get(m.person_id)?.legacy_member_id !== m.id).length;
  assert.equal(nomes, 0, `${nomes} membro(s) com nome diferente da persons`);
  assert.equal(vinculos, 0, `${vinculos} membro(s) com vínculo de volta inconsistente`);
});

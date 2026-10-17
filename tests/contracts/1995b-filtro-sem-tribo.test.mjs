/**
 * #1995, fatia 1b — a tribo de cada pessoa na fila de /admin/filiacao, para o filtro "sem tribo".
 *
 * Último critério de aceite da #1995 que a fatia 1 não atendeu: "Filtro 'sem tribo' combinável com o filtro de
 * termo já existente". A tribo vem de members.tribe_id, a coluna que o sinal tribe_blocked_no_tribe da fatia 1 já
 * usa; a coerência dela com o engajamento volunteer em research_tribe é vigiada pelas invariantes AG, AH e AO de
 * check_schema_invariants (medida sem divergência em 17/10/2026).
 *
 * O corpo SQL é lido pela captura MAIS NOVA (#1932). Cada asserção amarra a condição ao resultado.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { latestFunctionCapture, maskLineComments, maskJsComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(import.meta.dirname, '../..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const Q = maskLineComments(latestFunctionCapture(ROOT, 'get_affiliation_verification_queue').body);
const migName = readdirSync(resolve(ROOT, 'supabase/migrations')).filter((f) => f.endsWith('_1995b_filtro_sem_tribo.sql'));
const ISL = maskJsComments(read('src/components/admin/AffiliationQueueIsland.tsx'));

test('#1995 f1b há exatamente uma migration da fatia 1b', () => {
  assert.equal(migName.length, 1, `esperava 1 migration *_1995b_filtro_sem_tribo.sql, achei ${migName.length}`);
});

test('#1995 f1b a tribo sai de members.tribe_id e vira null quando a pessoa não tem tribo', () => {
  assert.match(Q, /m\.tribe_id,\s+tr\.name AS tribe_name\s+FROM public\.members m\s+LEFT JOIN public\.tribes tr ON tr\.id = m\.tribe_id\s/,
    'a tribo é a da coluna da pessoa, por LEFT JOIN, para quem não tem tribo continuar na fila');
  assert.match(Q, /'tribe', CASE WHEN c\.tribe_id IS NULL THEN NULL ELSE jsonb_build_object\('id', c\.tribe_id, 'name', c\.tribe_name\) END,/);
});

test('#1995 f1b a tela: filtro de tribo no mesmo recorte do filtro de termo', () => {
  const start = ISL.indexOf('let list = tab ===');
  const end = ISL.indexOf('}, [rows, allRows', start);
  assert.ok(start > 0 && end > start, 'recorte do useMemo da lista');
  const memo = ISL.slice(start, end + 200);
  assert.match(memo, /if \(termFilter !== 'all'\) list = list\.filter\(r => r\.term_status === termFilter\);/);
  assert.match(memo, /if \(tribeFilter === 'without'\) list = list\.filter\(r => !r\.tribe\);(?:[ \t]*\/\/[^\n]*)?\s+else if \(tribeFilter === 'with'\) list = list\.filter\(r => !!r\.tribe\);/,
    'sem tribo = tribe null; com tribo = tribe presente');
  assert.match(memo, /\}, \[rows, allRows, tab, statusFilter, cohortFilter, termFilter, obFilter, tribeFilter, /,
    'sem o filtro nas dependências a lista não se recalcula ao trocar a opção');
  assert.match(ISL, /<option value="without">\{t\('comp\.affiliationQueue\.tribeNone', 'Sem tribo'\)\}<\/option>/);
  assert.match(ISL, /<option value="with">\{t\('comp\.affiliationQueue\.tribeWith', 'Com tribo'\)\}<\/option>/);
  assert.match(ISL, /\{r\.tribe \? r\.tribe\.name : t\('comp\.affiliationQueue\.tribeNone', 'Sem tribo'\)\}/);
  for (const loc of ['pt-BR', 'en-US', 'es-LATAM']) {
    const dict = read(`src/i18n/${loc}.ts`);
    for (const k of ['tribeLabel', 'filterTribeAll', 'tribeWith', 'tribeNone']) {
      assert.ok(dict.includes(`'comp.affiliationQueue.${k}':`), `${loc} sem comp.affiliationQueue.${k}`);
    }
  }
});

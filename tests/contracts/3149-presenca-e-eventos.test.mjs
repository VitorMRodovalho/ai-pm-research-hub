/**
 * #3149: check-in, grade de presença e edição de evento dizem sucesso em recusa ou com número inventado.
 *
 * - check-in: o "+10 XP" era fixo no cliente; quem já estava presente via "+horas" de novo;
 * - grades: mark_member_present delega a register_own_presence, que recusa no corpo, e as grades
 *   liam só o `error`;
 * - editar evento: a recusa de update_event no ramo da série e a de link_event_to_initiative nos dois
 *   ramos não chegavam à pessoa.
 *
 * Comentários JS saem antes do assert. O helper throwIfRefused é importado e exercido.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { maskJsComments as mask } from '../helpers/guard-pin-staleness.mjs';
import { throwIfRefused } from '../../src/lib/rpc-checked.ts';

const ROOT = process.cwd();
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const ATT = mask(read('src/pages/attendance.astro'));
const TRIBE = mask(read('src/components/tribes/TribeAttendanceTab.tsx'));
const GRID = mask(read('src/components/attendance/AttendanceGridTab.tsx'));

function slice(src, from, to) {
  const a = src.indexOf(from);
  assert.ok(a >= 0, `achou ${from}`);
  const b = src.indexOf(to, a + from.length);
  assert.ok(b > a, `achou o fim depois de ${from}`);
  return src.slice(a, b);
}

test('#3149 S4: o check-in não inventa XP e só soma horas quando a presença é nova', () => {
  const fn = slice(ATT, 'async function checkIn(eventId: string) {', 'toast(feedbackMsg, \'success\');');
  assert.doesNotMatch(fn, /XP/, 'check-in: nenhum XP no toast');
  assert.match(fn, /if \(evHours && data\.already_present !== true\) feedbackMsg \+= `\\n\+\$\{evHours\}h`;/,
    'check-in: as horas entram só fora do already_present');
});

test('#3149 S5: throwIfRefused lança na recusa do corpo e prefere a mensagem legível', () => {
  assert.doesNotThrow(() => throwIfRefused({ success: true }));
  assert.doesNotThrow(() => throwIfRefused(null));
  assert.doesNotThrow(() => throwIfRefused([]));
  assert.throws(() => throwIfRefused({ success: false, error: 'attendance_already_recorded', message: 'Peça ao gestor.' }), (e) => e.message === 'Peça ao gestor.');
  assert.throws(() => throwIfRefused({ success: false, error: 'checkin_window_expired' }), (e) => e.message === 'checkin_window_expired');
  assert.throws(() => throwIfRefused({ success: false }), (e) => e.message === 'action_failed');
});

test('#3149 S5: as cinco chamadas de mark_member_present nas grades leem a recusa do corpo', () => {
  const calls = [
    [TRIBE, /const \{ data: presData, error: presErr \} = await sb\.rpc\('mark_member_present', \{ p_event_id: eventId, p_member_id: memberId, p_present: newPresent \}\);\s+if \(presErr\) throw presErr;\s+throwIfRefused\(presData\);/, 'tribo: ciclo'],
    [TRIBE, /const \{ data: undoData, error: undoErr \} = await sb\.rpc\('mark_member_present', \{[^}]*p_present: !newPresent \}\);\s+if \(undoErr\) throw undoErr;\s+throwIfRefused\(undoData\);/, 'tribo: desfazer'],
    [TRIBE, /const \{ data: presData, error: presErr \} = await sb\.rpc\('mark_member_present', \{\s+p_event_id: eventId, p_member_id: memberId, p_present: state === 'present',\s+\}\);\s+if \(presErr\) throw presErr;\s+throwIfRefused\(presData\);/, 'tribo: modal'],
    [GRID, /const \{ data: rpcData, error: rpcErr \} = await sb\.rpc\('mark_member_present', \{\s+p_event_id: eventId, p_member_id: memberId, p_present: nextState === 'present',\s+\}\);\s+if \(rpcErr\) throw rpcErr;\s+throwIfRefused\(rpcData\);/, 'grade geral: ciclo'],
    [GRID, /const \{ data: d1, error: e1 \} = await sb\.rpc\('mark_member_present', \{\s+p_event_id: eventId, p_member_id: memberId, p_present: state === 'present',\s+\}\);\s+if \(e1\) throw e1;\s+throwIfRefused\(d1\);/, 'grade geral: modal'],
  ];
  for (const [src, re, label] of calls) assert.match(src, re, label);
  for (const [src, label] of [[TRIBE, 'tribo'], [GRID, 'grade geral']]) {
    assert.equal((src.match(/sb\.rpc\('mark_member_present'/g) || []).length, (src.match(/throwIfRefused\(/g) || []).length,
      `${label}: toda chamada de mark_member_present lê o corpo`);
    assert.match(src, /import \{ throwIfRefused \} from '\.\.\/\.\.\/lib\/rpc-checked';/, `${label}: importa o helper`);
  }
});

test('#3149 S6: editar evento não diz sucesso com update_event ou o vínculo recusados', () => {
  assert.match(ATT,
    /p_audience_level: audience\s+\}\);\s+if \(error\) throw error;\s+if \(!data\?\.success\) throw new Error\(data\?\.error \|\| I18N\.msgEventSaveError\);\s+const updateFields/,
    'série: a recusa de update_event no corpo vira erro');
  const links = [...ATT.matchAll(/if \(linkErr \|\| !linkData\?\.success\) \{\s+console\.warn\('initiative link failed:', linkErr \|\| linkData\?\.error\);\s+linkRefused = String\(linkErr\?\.message \|\| linkData\?\.error \|\| I18N\.msgEventSaveError\);\s+\}/g)];
  assert.equal(links.length, 2, 'os dois ramos guardam a recusa do vínculo');
  assert.match(ATT, /if \(linkRefused\) toast\(I18N\.msgEventLinkRefused\.replace\('\{reason\}', linkRefused\), 'error'\);\s+else toast\(`\$\{count\} \$\{I18N\.recurrenceFutureUpdated\}`, 'success'\);/,
    'série: com vínculo recusado, não sai o sucesso');
  assert.match(ATT, /if \(linkRefused\) toast\(I18N\.msgEventLinkRefused\.replace\('\{reason\}', linkRefused\), 'error'\);\s+else toast\(I18N\.msgEventUpdated, 'success'\);/,
    'evento único: com vínculo recusado, não sai o sucesso');
  assert.match(ATT, /msgEventLinkRefused: t\('attendance\.msg\.eventLinkRefused', lang\),/, 'o texto vai ao script');
  for (const l of ['pt-BR', 'en-US', 'es-LATAM']) {
    assert.match(read(`src/i18n/${l}.ts`), /'attendance\.msg\.eventLinkRefused': '[^']*\{reason\}[^']*',/, `${l}: eventLinkRefused com o motivo`);
  }
});

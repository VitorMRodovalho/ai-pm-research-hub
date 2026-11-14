// #3056: get_public_impact_data.total_events (o "eventos" do /about) conta encontros da comunidade realizados
// (decisão do GP, 13/11/2026): data até hoje, sem cancelados e sem entrevista de seleção. Antes contava toda linha
// de events desde 2026-03-01, inclusive futuros, cancelados e entrevistas.
//
// Cada asserção recorta o subselect de 'total_events' da última migration que declara a função, sem comentários,
// e casa a condição DENTRO dele: a mesma string em outro campo (total_attendance_hours usa o mesmo filtro de data)
// não deixa o guard verde.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, join } from 'node:path';

const MIG_DIR = resolve(process.cwd(), 'supabase/migrations');
const stripComments = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

function totalEventsBlock() {
  const files = readdirSync(MIG_DIR).filter((f) => f.endsWith('.sql')).sort();
  const decl = 'CREATE OR REPLACE FUNCTION public.get_public_impact_data()';
  const decls = files.filter((f) => readFileSync(join(MIG_DIR, f), 'utf8').includes(decl));
  assert.ok(decls.length >= 1, 'get_public_impact_data: ao menos uma migration declara a função');
  const file = decls[decls.length - 1];
  const fn = stripComments(readFileSync(join(MIG_DIR, file), 'utf8')).split(decl)[1].split('$function$;')[0];
  const start = fn.indexOf("'total_events'");
  const end = fn.indexOf("'total_attendance_hours'");
  assert.ok(start >= 0 && end > start, `${file}: total_events vem antes de total_attendance_hours`);
  return { file, block: fn.slice(start, end) };
}

test('#3056: total_events só conta evento com data até hoje', () => {
  const { file, block } = totalEventsBlock();
  assert.match(block, /FROM events e\s+WHERE e\.date >= '2026-03-01' AND e\.date <= CURRENT_DATE/,
    `${file}: total_events precisa cortar eventos futuros`);
});

test('#3056: total_events tira os cancelados pelas duas marcas', () => {
  const { file, block } = totalEventsBlock();
  assert.match(block, /AND e\.status IS DISTINCT FROM 'cancelled' AND e\.cancelled_at IS NULL/,
    `${file}: total_events precisa tirar status cancelled e cancelled_at preenchido`);
});

test('#3056: total_events tira as entrevistas de seleção', () => {
  const { file, block } = totalEventsBlock();
  assert.match(block, /AND e\.type IS DISTINCT FROM 'entrevista'/,
    `${file}: total_events não conta entrevista de seleção`);
});

test('#3056: total_events mantém o corte de iniciativa confidencial e não exige presença', () => {
  const { file, block } = totalEventsBlock();
  assert.match(block, /AND NOT EXISTS \(SELECT 1 FROM initiatives ci WHERE ci\.id = e\.initiative_id AND ci\.visibility = 'confidential'\)/,
    `${file}: total_events mantém o gate de confidencial (ADR-0105)`);
  assert.doesNotMatch(block, /attendance/,
    `${file}: reunião sem chamada de presença continua contando (decisão do GP)`);
});

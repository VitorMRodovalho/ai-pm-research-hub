// tests/contracts/2690-aviso-de-entrevista-diz-a-hora-de-brasilia.test.mjs
/**
 * #2690 — o aviso de entrevista agendada diz a hora de Brasília, e diz que é de Brasília.
 *
 * SINTOMA (13/10/2026): uma entrevista às 19:30 de Brasília (`scheduled_at` = 22:30+00) gerou o
 * aviso "agendada para 16/10/2026 22:30", entregue ao entrevistador por e-mail. `to_char` formata
 * no fuso da SESSÃO, que é UTC, e o texto não dizia o fuso: quem lê entende a própria hora local,
 * três horas depois da real. Na mesma linha, `' (' || COALESCE(chapter, '') || ')'` imprimia "()".
 *
 * O que este arquivo prova:
 *   (A) cada `create_notification` de `schedule_interview` formata `p_scheduled_at` com
 *       `AT TIME ZONE 'America/Sao_Paulo'` e escreve "(horário de Brasília)" na MESMA expressão;
 *   (B) nenhum `to_char(p_scheduled_at, ...)` cru sobra no corpo;
 *   (C) o capítulo nulo ou vazio não imprime "()";
 *   (D) as asserções mordem: cada defeito reinjetado reprova;
 *   (E) o corpo VIVO é o capturado e carrega o desenho.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';
const sb = () => createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });

const capturaVigente = () => latestFunctionCapture(ROOT, 'schedule_interview');

/** Os blocos `PERFORM public.create_notification( ... );` do corpo, sem comentários de linha. */
function chamadasDeAviso(corpo) {
  const sql = maskLineComments(corpo);
  const blocos = [];
  const re = /PERFORM public\.create_notification\(/g;
  let m;
  while ((m = re.exec(sql))) {
    const fim = sql.indexOf(');', m.index);
    blocos.push(sql.slice(m.index, fim + 2));
  }
  return blocos;
}

function violacoes(corpo) {
  const v = [];
  const sql = maskLineComments(corpo);
  const avisos = chamadasDeAviso(corpo);
  const comHora = avisos.filter((b) => /to_char\(\s*p_scheduled_at\b/.test(b));
  if (comHora.length !== 2) {
    v.push(`esperava 2 avisos que formatam p_scheduled_at, achei ${comHora.length}`);
  }
  for (const b of comHora) {
    // (A) a conversão e o rótulo moram na mesma expressão que vai para o texto.
    if (!/to_char\(\s*p_scheduled_at\s+AT TIME ZONE 'America\/Sao_Paulo'\s*,\s*'DD\/MM\/YYYY HH24:MI'\s*\)\s*\|\|\s*' \(horário de Brasília\)/.test(b)) {
      v.push('um aviso formata a hora sem AT TIME ZONE America/Sao_Paulo seguido do rótulo de fuso');
    }
  }
  // (B) nenhum to_char cru sobre o horário da entrevista.
  if (/to_char\(\s*p_scheduled_at\s*,/.test(sql)) {
    v.push('sobrou to_char(p_scheduled_at, ...) sem conversão de fuso');
  }
  // (C) capítulo nulo ou vazio some inteiro, parênteses incluídos.
  if (/' \(' \|\| COALESCE\(v_app\.chapter, ''\) \|\| '\)/.test(sql)) {
    v.push('o capítulo nulo volta a imprimir "()"');
  }
  if (!/COALESCE\(' \(' \|\| NULLIF\(btrim\(v_app\.chapter\), ''\) \|\| '\)', ''\)/.test(sql)) {
    v.push('o capítulo não está protegido por NULLIF(btrim(...)) dentro do COALESCE');
  }
  return v;
}

test('#2690 static: o corpo capturado formata em Brasília, rotula o fuso e não imprime "()"', () => {
  const cap = capturaVigente();
  assert.ok(cap?.body, 'alguma migration captura schedule_interview');
  assert.deepEqual(violacoes(cap.body), []);
});

test('#2690 static: reprova o aviso que volta a formatar em UTC', () => {
  const { body } = capturaVigente();
  const adulterado = body.replace("p_scheduled_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')\n        || ' (horário de Brasília)'",
    "p_scheduled_at, 'DD/MM/YYYY HH24:MI')\n        || ' (horário de Brasília)'");
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('sobrou to_char')), JSON.stringify(v));
  assert.ok(v.some((m) => m.includes('sem AT TIME ZONE')), JSON.stringify(v));
});

test('#2690 static: reprova o aviso ao candidato que perde o rótulo de fuso', () => {
  const { body } = capturaVigente();
  const adulterado = body.replace("|| ' (horário de Brasília). Prepare-se!'", "|| '. Prepare-se!'");
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('rótulo de fuso')), JSON.stringify(v));
});

test('#2690 static: reprova o capítulo que volta a imprimir "()"', () => {
  const { body } = capturaVigente();
  const adulterado = body.replace(
    "COALESCE(' (' || NULLIF(btrim(v_app.chapter), '') || ')', '')",
    "' (' || COALESCE(v_app.chapter, '') || ')'",
  );
  assert.notEqual(adulterado, body, 'a injeção precisa mesmo alterar o corpo');
  const v = violacoes(adulterado);
  assert.ok(v.some((m) => m.includes('"()"')), JSON.stringify(v));
});

test('#2690 static: o comentário que cita o defeito não conta como código', () => {
  // A asserção (B) lê o corpo mascarado; um comentário com o padrão antigo não pode reprovar.
  const { body } = capturaVigente();
  const comComentario = body.replace('BEGIN', "BEGIN\n  -- antes: to_char(p_scheduled_at, 'DD/MM/YYYY HH24:MI')");
  assert.notEqual(comComentario, body);
  assert.deepEqual(violacoes(comComentario), []);
});

test('#2690 db: o corpo VIVO é o capturado e carrega o desenho',
  { skip: dbGated ? false : skipMsg }, async () => {
    const cap = capturaVigente();
    const md5Arquivo = createHash('md5').update(cap.body.replace(/\s+/g, ' ')).digest('hex');
    const { data, error } = await sb().rpc('_audit_list_public_function_bodies');
    assert.ifError(error);
    const vivas = (data ?? []).filter((f) => f.proname === 'schedule_interview');
    assert.equal(vivas.length, 1, `esperava UMA schedule_interview viva, achei ${vivas.length}`);
    assert.equal(vivas[0].body_md5, md5Arquivo, `o corpo vivo divergiu da captura (${cap.file})`);
    const src = await sb().rpc('_audit_function_source', { p_proname: 'schedule_interview' });
    assert.ifError(src.error);
    for (const row of src.data ?? []) assert.deepEqual(violacoes(row.prosrc), []);
  });

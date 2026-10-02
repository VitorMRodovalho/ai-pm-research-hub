/**
 * #2542 (etapa 0 da ADR-0134, item 2): quem lanca a nota da entrevista fica registrado como
 * entrevistador quando a lista esta vazia, inclusive quem tem manage_platform.
 *
 * O defeito, medido em 02/10/2026: 20 das 72 entrevistas concluidas do cycle4-2026 estavam sem
 * `interviewer_ids`. 19 vieram da agenda (`sync_calendar_booking_to_interview` grava ARRAY[]), e
 * as 20 foram avaliadas por quem tem manage_platform. O ramo do #1972 so registra quem e BARRADO
 * pelo portao; quem tem manage_platform passava direto e nunca era registrado.
 *
 * O conserto e um passo DEPOIS do portao (o portao continua sendo a primeira pergunta, como o
 * #1972 exige): se a lista ainda esta vazia ali, registra o chamador. Este guard amarra a
 * CONDICAO (lista vazia, depois do portao) ao RESULTADO (chamador gravado), e no banco afirma que
 * nenhuma entrevista concluida com nota segue sem entrevistador.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const ROOT = process.cwd();
const corpo = () => maskLineComments(latestFunctionCapture(ROOT, 'submit_interview_scores').body);

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.PUBLIC_SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = !!(SUPABASE_URL && SUPABASE_KEY);
const skipMsg = 'Skipped: SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY required';

const PORTAO_FIM = /RAISE EXCEPTION 'Unauthorized: not an assigned interviewer';\s+END IF;\s+END IF;/;
const PASSO_3B =
  /IF cardinality\(coalesce\(v_interview\.interviewer_ids, ARRAY\[\]::uuid\[\]\)\) = 0 THEN\s+UPDATE public\.selection_interviews\s+SET interviewer_ids = ARRAY\[v_caller\.id\]\s+WHERE id = p_interview_id;\s+v_interview\.interviewer_ids := ARRAY\[v_caller\.id\];/;

test('#2542 static: logo depois do portao, a lista vazia grava o chamador como entrevistador', () => {
  const b = corpo();
  const fim = b.search(PORTAO_FIM);
  assert.ok(fim > 0, 'o fim do portao de autorizacao existe');
  const depois = b.slice(fim).replace(PORTAO_FIM, '');
  // o PRIMEIRO comando depois do portao e o passo 3b; nada roda entre os dois
  assert.match(depois, new RegExp('^\\s+' + PASSO_3B.source),
    'o passo 3b tem de vir logo depois do portao, ligando a lista vazia ao chamador gravado');
});

test('#2542 static: o registro deixa rastro com a issue e o caminho', () => {
  const b = corpo();
  const ini = b.search(PASSO_3B);
  assert.ok(ini > 0, 'o passo 3b existe');
  const bloco = b.slice(ini, b.indexOf('END IF;', ini));
  assert.match(bloco, /INSERT INTO public\.admin_audit_log[\s\S]*'selection\.interview_self_assigned'[\s\S]*'issue', 2542, 'via', 'manage_platform'/);
});

test('#2542 static: o registro vem ANTES da nota ser gravada', () => {
  const b = corpo();
  const ini = b.search(PASSO_3B);
  const nota = b.indexOf('INSERT INTO public.selection_evaluations');
  assert.ok(ini > 0 && nota > ini, 'o entrevistador e gravado antes da avaliacao, e o passo 8 ja o enxerga');
});

test('#2542 db: nenhuma entrevista concluida com nota de entrevista segue sem entrevistador',
  { skip: dbGated ? false : skipMsg }, async () => {
    const sb = createClient(SUPABASE_URL, SUPABASE_KEY, { auth: { persistSession: false } });
    // controle positivo: a consulta enxerga entrevistas concluidas (senao o zero abaixo nao vale)
    const { count: concluidas, error: e0 } = await sb.from('selection_interviews')
      .select('id', { count: 'exact', head: true }).eq('status', 'completed');
    assert.ifError(e0);
    assert.ok(concluidas > 0, 'ha entrevistas concluidas para medir');

    const { data: vazias, error: e1 } = await sb.from('selection_interviews')
      .select('id, application_id').eq('status', 'completed').eq('interviewer_ids', '{}');
    assert.ifError(e1);
    const apps = [...new Set((vazias ?? []).map((v) => v.application_id))];
    let comNota = [];
    if (apps.length) {
      const { data, error: e2 } = await sb.from('selection_evaluations')
        .select('application_id').in('application_id', apps)
        .eq('evaluation_type', 'interview').not('submitted_at', 'is', null);
      assert.ifError(e2);
      comNota = [...new Set((data ?? []).map((r) => r.application_id))];
    }
    assert.equal(comNota.length, 0,
      `${comNota.length} candidatura(s) com entrevista concluida e nota de entrevista, mas sem entrevistador registrado`);
  });

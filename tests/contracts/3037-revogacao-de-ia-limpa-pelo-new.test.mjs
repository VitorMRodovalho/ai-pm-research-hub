// tests/contracts/3037-revogacao-de-ia-limpa-pelo-new.test.mjs
//
// #3037 — a revogação do consentimento de IA falhava SEMPRE com 27000 ("tuple to be updated was
// already modified by an operation triggered by the current command").
//
// O gatilho é BEFORE UPDATE OF consent_ai_analysis_revoked_at. O corpo vindo de 20260516970000
// (mantido por 20260517150000) limpava os campos de IA com UPDATE public.selection_applications
// ... WHERE id = NEW.id, na linha que o comando já estava atualizando. O Postgres recusa e desfaz
// tudo: nem a data da revogação, nem o fechamento da linha em consent_records, nem a limpeza.
// Num BEFORE, limpar é atribuir em NEW, como faziam 20260514300000 e 20260516940000.
//
// Nenhum guard pegou porque nenhum EXERCIA a revogação: o #1666 afirma que o corpo de
// revoke_consent_via_token fecha a linha do ledger, e fecha, mas a transação nunca chegava lá.
//
// ⚠️ RESÍDUO DECLARADO: este arquivo não revoga nada. Revogar o consentimento de uma candidatura
// real para testar seria tirar dela algo que ela deu. A prova no vivo foi feita uma vez, na
// candidatura de teste da #3017, e está no corpo da PR.
//
// Camada A (estática): a captura MAIS NOVA da função nas migrations, para que uma migration
//   futura que traga o UPDATE de volta reprove aqui.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): o corpo vivo, com a mesma
//   asserção. Um SKIP silencioso lê como verde: conferir o número de skips, não só `fail 0`.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const FN = '_trg_purge_ai_analysis_on_consent_revocation';

// As 12 colunas que a revogação limpa: as mesmas do corpo vivo antes da correção.
const COLUNAS = [
  'linkedin_relevant_posts',
  'cv_extracted_text',
  'ai_pm_focus_tags',
  'ai_analysis',
  'ai_triage_score',
  'ai_triage_reasoning',
  'ai_triage_confidence',
  'ai_triage_at',
  'ai_triage_model',
  'last_briefing_jsonb',
  'last_briefing_at',
  'last_briefing_model',
];

const normaliza = (s) => maskLineComments(s).replace(/\s+/g, ' ');

function afirmaCorpo(corpo, origem) {
  assert.doesNotMatch(corpo, /\bUPDATE\s+(?:public\s*\.\s*)?selection_applications\b/i,
    `${origem}: UPDATE na própria tabela dentro do BEFORE UPDATE é o 27000 da #3037`);

  // A condição e o que ela produz, no mesmo bloco: a limpeza só vale DENTRO do IF da revogação.
  const bloco = corpo.match(
    /IF NEW\.consent_ai_analysis_revoked_at IS NOT NULL AND OLD\.consent_ai_analysis_revoked_at IS NULL THEN (.*?) END IF;/,
  )?.[1];
  assert.ok(bloco, `${origem}: o IF da revogação (NEW preenchido, OLD vazio) não foi encontrado`);
  for (const col of COLUNAS) {
    assert.match(bloco, new RegExp(`\\bNEW\\.${col} := NULL;`),
      `${origem}: a revogação não limpa ${col} pelo NEW`);
  }

  // Num BEFORE, devolver outra coisa que não NEW descarta a atualização em silêncio.
  assert.match(corpo, /END IF; RETURN NEW; END;/, `${origem}: o gatilho tem de devolver NEW depois do IF`);
}

describe('#3037 A — a captura mais nova limpa pelo NEW', () => {
  it('a captura mais nova da função', () => {
    const cap = latestFunctionCapture(process.cwd(), FN);
    assert.ok(cap, `${FN}: nenhuma migration cria esta função`);
    afirmaCorpo(normaliza(cap.block), cap.file);
  });
});

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SUPABASE_SRK);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } }) : null;

describe('#3037 B — o corpo VIVO limpa pelo NEW', () => {
  it('em produção, não só no arquivo', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: FN });
    assert.ifError(error);
    assert.equal(data?.length, 1, `${FN}: esperada exatamente 1 função viva`);
    afirmaCorpo(normaliza(data[0].prosrc), 'corpo vivo');
  });
});

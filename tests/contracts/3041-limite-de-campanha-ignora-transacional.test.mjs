// tests/contracts/3041-limite-de-campanha-ignora-transacional.test.mjs
//
// #3041 — o limite de envio de admin_send_campaign (1 por hora, 3 por dia, por remetente) contava
// também os envios transacionais.
//
// campaign_send_one_off grava cada envio transacional em campaign_sends com sent_by igual a um
// membro que tem manage_platform e com audience_filter.type = 'transactional'. As duas contagens
// liam só sent_by, created_at e status, então uma rajada de boas-vindas automáticas bloqueava a
// campanha manual desse membro por até 24 horas.
//
// A asserção recorta cada bloco que decide (a contagem e o RAISE que ela dispara) e afirma a
// exclusão DENTRO da contagem. O COALESCE é parte do contrato: campanha manual não tem
// audience_filter.type, e `NULL <> 'transactional'` é NULL, o que tiraria da contagem justamente
// as campanhas que o limite existe para contar.
//
// Camada A (estática): a captura MAIS NOVA da função nas migrations.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): o corpo vivo, com a mesma
//   asserção. Um SKIP silencioso lê como verde: conferir o número de skips, não só `fail 0`.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture, maskLineComments } from '../helpers/guard-pin-staleness.mjs';

const FN = 'admin_send_campaign';

const LIMITES = [
  { janela: '1 hour', variavel: 'v_sends_last_hour', teto: 1, mensagem: 'Rate limit: max 1 campaign per hour' },
  { janela: '1 day', variavel: 'v_sends_last_day', teto: 3, mensagem: 'Rate limit: max 3 campaigns per day' },
];

const normaliza = (s) => maskLineComments(s).replace(/\s+/g, ' ');
const escapa = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function afirmaCorpo(corpo, origem) {
  for (const { janela, variavel, teto, mensagem } of LIMITES) {
    // A contagem e o RAISE que ela decide, no mesmo recorte.
    const bloco = corpo.match(new RegExp(
      `SELECT COUNT\\(\\*\\) INTO ${variavel} FROM public\\.campaign_sends WHERE (.*?); `
      + `IF ${variavel} >= ${teto} THEN RAISE EXCEPTION '${escapa(mensagem)}'; END IF;`,
    ))?.[1];
    assert.ok(bloco, `${origem}: a contagem de ${variavel} seguida do RAISE '${mensagem}' não foi encontrada`);
    assert.match(bloco, /\bsent_by = v_caller_id\b/, `${origem}: ${variavel} deixou de contar por remetente`);
    assert.match(bloco, new RegExp(`created_at > now\\(\\) - interval '${janela}'`),
      `${origem}: ${variavel} deixou de olhar a janela de ${janela}`);
    assert.match(bloco, /status NOT IN \('draft','failed'\)/, `${origem}: ${variavel} passou a contar rascunho ou falha`);
    assert.match(bloco, /\bAND COALESCE\(audience_filter->>'type', ''\) <> 'transactional'/,
      `${origem}: ${variavel} conta envio transacional (#3041), ou perdeu o COALESCE e deixou de contar a campanha manual`);
  }
}

describe('#3041 A — a captura mais nova não conta envio transacional no limite', () => {
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

describe('#3041 B — o corpo VIVO não conta envio transacional no limite', () => {
  it('em produção, não só no arquivo', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: FN });
    assert.ifError(error);
    assert.equal(data?.length, 1, `${FN}: esperada exatamente 1 função viva`);
    afirmaCorpo(normaliza(data[0].prosrc), 'corpo vivo');
  });
});

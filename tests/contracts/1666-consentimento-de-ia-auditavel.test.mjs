// tests/contracts/1666-consentimento-de-ia-auditavel.test.mjs
//
// #1666 — o consentimento de IA era gravado como carimbo, sem dizer COM O QUE a pessoa concordou.
//
// O contraste que tornou o defeito impossível de atribuir a limitação técnica estava DENTRO da
// mesma função: o ramo `voice_biometric` exige `version + lang + label_text_hash` sob `RAISE` e
// tinha 32 de 32 com evidência; o ramo `ai_analysis` gravava só o timestamp, 0 de 56.
//
// Ficou concreto porque o #1642 REESCREVEU o texto nos 3 idiomas: os 56 concordaram com uma
// redação que não existe mais, e não há registro de qual era (art. 8º, §2º — o ônus da prova de
// consentimento válido é do controlador).
//
// ⚠️ RESÍDUO DECLARADO — a concessão NÃO é exercida por chamada. `give_consent_via_token` faz
// `consent_ai_analysis_revoked_at = NULL`, então chamá-la sobre uma candidatura real poderia
// DES-REVOGAR quem revogou. Procurei alvo seguro (ciclo fechado + consentimento ativo + token
// vivo, onde a chamada seria no-op): existem **zero**. Um teste que precisa escolher entre não
// rodar e causar dano não roda. O que este arquivo afirma no lugar é o EFEITO observável: a
// consistência entre as duas representações do consentimento. Se a escrita no ledger quebrar,
// ou se a revogação deixar de fechar a linha, as asserções da camada B caem.
//
// Camada A (estática): a migration e o front.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): corpo vivo + estado do ledger.
//   ⚠️ um SKIP silencioso lê como verde. Conferir o número de skips, não só `fail 0`.

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIGRATION = 'supabase/migrations/20260807000600_1666_consentimento_de_ia_vira_registro_auditavel.sql';
const PORTAL = 'src/components/pmi-onboarding/PMIOnboardingPortal.tsx';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
const stripSql = (s) => s.replace(/^\s*--.*$/gm, '');
const stripTs = (s) => s.replace(/^\s*\/\/.*$/gm, '');

const MIG = stripSql(read(MIGRATION));
const TSX = stripTs(read(PORTAL));

describe('#1666 A — a migration liga o ledger que já existia', () => {
  it('a migration existe', () => {
    assert.ok(read(MIGRATION), `migration esperada em ${MIGRATION}`);
  });

  it('a coluna de evidência foi criada', () => {
    assert.match(MIG, /ADD COLUMN IF NOT EXISTS evidence jsonb/);
  });

  it('conceder ESCREVE no ledger e preenche a ponte de volta', () => {
    // `\b` não basta: `consent_records_XX` casaria como substring e a asserção passaria com a
    // tabela ERRADA — foi o que a primeira mutação deste arquivo revelou. O `(` obriga o nome a
    // terminar ali.
    assert.match(MIG, /INSERT INTO public\.consent_records\s*\(/);
    assert.match(MIG, /SET consent_record_id = v_consent_record_id/,
      'sem a ponte, o ledger existe e ninguém o alcança a partir da candidatura');
  });

  it('revogar FECHA a linha do ledger', () => {
    // Um ledger que afirma consentimento ATIVO para quem revogou é pior que não ter ledger.
    assert.match(MIG, /SET revoked_at = v_revoked_at/);
  });

  it('a ausência de evidência é REGISTRADA, não silenciada', () => {
    // Um default silencioso ('v2') transformaria ausência de prova em afirmação falsa sobre qual
    // texto a pessoa viu. É o contrário do que o registro existe para fazer.
    assert.match(MIG, /'unversioned'/);
    assert.doesNotMatch(
      MIG,
      /COALESCE\(NULLIF\(p_evidence ->> 'version', ''\), 'v[0-9]/,
      'defaultar para uma versão concreta inventa a prova que falta',
    );
  });

  it('o backfill NÃO fabrica evidência', () => {
    assert.match(MIG, /'v1-pre-1642'/, 'a versão anterior tem de ser nomeada como o que é');
    // O texto v1 não é reconstruível: hashear o texto de hoje e chamar de v1 seria falsificação.
    const bloco = MIG.match(/INSERT INTO public\.consent_records[\s\S]*?FROM public\.selection_applications/)?.[0] || '';
    assert.ok(bloco, 'bloco de backfill não encontrado');
    assert.doesNotMatch(bloco, /label_text_hash/, 'o backfill não pode inventar hash');
  });
});

describe('#1666 A — o front passa a enviar a prova', () => {
  it('existe versão do texto de consentimento de IA', () => {
    assert.match(TSX, /AI_CONSENT_VERSION\s*=\s*'v\d+'/);
  });

  it('a concessão envia version + lang + hash do texto EXIBIDO', () => {
    assert.match(TSX, /p_evidence\s*=\s*\{[\s\S]{0,220}label_text_hash:\s*await sha256Hex\(\s*T\('pmi\.onboarding\.consentBody'\)/,
      'o hash tem de ser do MESMO texto que a tela renderiza, não de uma constante paralela');
    assert.match(TSX, /version:\s*AI_CONSENT_VERSION/);
  });

  it('a revogação NÃO manda evidência (não há texto a provar no ato de revogar)', () => {
    assert.match(TSX, /if \(grant\) \{[\s\S]{0,400}args\.p_evidence/);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada B — DB-aware
// ─────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SUPABASE_SRK);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } }) : null;

describe('#1666 B — o corpo VIVO escreve no ledger', () => {
  for (const [fn, marca] of [
    ['give_consent_via_token', /INSERT INTO public\.consent_records/],
    ['revoke_consent_via_token', /SET revoked_at = v_revoked_at/],
  ]) {
    it(`${fn}: em produção, não só no arquivo`, { skip: dbGated ? false : skipMsg }, async () => {
      const { data, error } = await sb.rpc('_audit_function_source', { p_proname: fn });
      assert.ifError(error);
      assert.ok(data?.length > 0, `${fn} não existe no banco`);
      assert.match(stripSql(data[0].prosrc), marca, `${fn}: a escrita no ledger não está viva`);
    });
  }
});

describe('#1666 B — o EFEITO: as duas representações do consentimento concordam', () => {
  it('todo consentimento de IA tem linha no ledger', { skip: dbGated ? false : skipMsg }, async () => {
    const { data: apps, error } = await sb
      .from('selection_applications')
      .select('id, consent_ai_analysis_at, consent_ai_analysis_revoked_at, consent_record_id')
      .not('consent_ai_analysis_at', 'is', null);
    assert.ifError(error);
    assert.ok((apps?.length ?? 0) > 0, 'sem consentimento nenhum na base, a asserção não é exercida');

    const { data: ledger, error: e2 } = await sb
      .from('consent_records')
      .select('application_id, policy_version, revoked_at, evidence')
      .eq('policy_type', 'ai_analysis');
    assert.ifError(e2);

    const porApp = new Map();
    for (const r of ledger ?? []) porApp.set(r.application_id, r);

    const semLinha = (apps ?? []).filter((a) => !porApp.has(a.id)).map((a) => a.id);
    assert.deepEqual(semLinha, [], `consentimentos sem registro auditável: ${semLinha.length}`);

    const semPonte = (apps ?? []).filter((a) => !a.consent_record_id).map((a) => a.id);
    assert.deepEqual(semPonte, [], `consentimentos sem consent_record_id: ${semPonte.length}`);
  });

  it('quem revogou NÃO tem linha aberta no ledger', { skip: dbGated ? false : skipMsg }, async () => {
    // É a asserção que pega o defeito mais perigoso: um ledger que afirma consentimento ativo
    // para quem já retirou o consentimento.
    const { data: revogados, error } = await sb
      .from('selection_applications')
      .select('id')
      .not('consent_ai_analysis_revoked_at', 'is', null);
    assert.ifError(error);

    if (!revogados?.length) {
      console.log('[1666] ninguém revogou consentimento de IA — asserção não exercida');
      return;
    }
    const ids = revogados.map((r) => r.id);
    const { data: abertas, error: e2 } = await sb
      .from('consent_records')
      .select('application_id')
      .eq('policy_type', 'ai_analysis')
      .is('revoked_at', null)
      .in('application_id', ids);
    assert.ifError(e2);
    assert.deepEqual(abertas ?? [], [], 'o ledger afirma consentimento ATIVO para quem revogou');
  });

  it('nenhuma linha declara versão concreta SEM ter a evidência', { skip: dbGated ? false : skipMsg }, async () => {
    // O par (version, evidence) é o que dá valor probatório. Uma linha que diz "v2" sem hash
    // afirma que a pessoa viu o texto v2 sem poder prová-lo — a fabricação que este trabalho
    // existe para impedir. `v1-pre-1642` e `unversioned` são as duas formas honestas de dizer
    // "não temos a prova".
    const { data, error } = await sb
      .from('consent_records')
      .select('id, policy_version, evidence')
      .eq('policy_type', 'ai_analysis')
      .is('evidence', null);
    assert.ifError(error);
    const mentirosas = (data ?? []).filter(
      (r) => r.policy_version !== 'v1-pre-1642' && r.policy_version !== 'unversioned',
    );
    assert.deepEqual(
      mentirosas.map((r) => r.policy_version),
      [],
      'linha sem evidência declarando versão concreta do texto',
    );
  });
});

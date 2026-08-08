// tests/contracts/1682-ledger-de-consentimento-alcanca-o-titular.test.mjs
//
// #1682 — o ledger de consentimento era ESCRITO por `application_id` e LIDO por `member_id`.
//
// O #1666 criou o ledger e o preencheu com 56 linhas, todas com `application_id` e nenhuma com
// `member_id`. As duas superfícies de leitura do titular (`export_my_data`, art. 18 II, e
// `list_my_consents`) filtravam por `member_id`. Resultado medido em 08/08/2026: as duas
// devolviam `[]` para 100% dos titulares, com o ledger cheio — e 34 dessas linhas (33 pessoas)
// são de quem já é membro hoje.
//
// A ponte que resolvia isso já existia 20 linhas acima, no MESMO corpo do `export_my_data`: o
// bloco `selection_applications` resolve a candidatura por e-mail. O bloco do ledger não a usava.
//
// ⚠️ O que este arquivo NÃO afirma. A issue original dizia que `privacy_consent_accepted_at`,
// `consent_voice_biometric_at` e `persons.consent_status` também ficavam de fora da exportação.
// Os três JÁ SAÍAM: `profile`, `person` e `selection_applications` são montados com
// `row_to_json()`, que carrega a coluna sem que o corpo da função a mencione. A issue grepou o
// TEXTO; a medição observou o COMPORTAMENTO. Nenhuma asserção aqui trata esses três como defeito.
//
// Camada A (estática): as migrations.
// Camada B (DB-aware, PULA sem SUPABASE_URL + SERVICE_ROLE_KEY): corpo vivo + alcance real.
//   ⚠️ um SKIP silencioso lê como verde. Conferir o número de skips, não só `fail 0`.
//   ⚠️ Camada B é ESTRITAMENTE read-only: este arquivo nunca escreve em produção (#1636).

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MIG_EXPORT = 'supabase/migrations/20260808000100_1682_export_my_data_alcanca_o_ledger_por_candidatura.sql';
const MIG_LIST   = 'supabase/migrations/20260808000200_1682_list_my_consents_alcanca_o_ledger_por_candidatura.sql';
const MIG_WRITE  = 'supabase/migrations/20260808000300_1682_o_ledger_nasce_enderecado_ao_membro.sql';

const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : '');
// Tirar os comentários ANTES de assertar: um guard sobre a fonte crua casa o próprio comentário
// que descreve o que ele procura, e passa com o mecanismo ausente.
const stripSql = (s) => s.replace(/^\s*--.*$/gm, '');

const EXPORT = stripSql(read(MIG_EXPORT));
const LIST   = stripSql(read(MIG_LIST));
const WRITE  = stripSql(read(MIG_WRITE));

// A ponte: o ledger é alcançado pela candidatura cujo e-mail é do titular.
const PONTE = /cr\.application_id IN \(\s*SELECT sa\.id FROM public\.selection_applications sa\s*WHERE lower\(trim\(sa\.email\)\) = ANY \(v_emails\)/;

describe('#1682 A — as duas leituras alcançam o ledger pela candidatura', () => {
  for (const [nome, sql] of [['export_my_data', EXPORT], ['list_my_consents', LIST]]) {
    it(`${nome}: a migration existe`, () => {
      assert.ok(sql, `migration de ${nome} ausente`);
    });

    it(`${nome}: resolve os e-mails do titular UMA vez`, () => {
      assert.match(sql, /SELECT COALESCE\(array_agg\(DISTINCT s\.e\), ARRAY\[\]::text\[\]\) INTO v_emails/);
      // O UNION com member_emails é o motivo de a ponte existir: o e-mail da candidatura pode
      // não ser o do cadastro. Sem ele, a ponte alcança menos gente do que deveria.
      assert.match(sql, /FROM public\.member_emails me WHERE me\.member_id = v_member_id/);
    });

    it(`${nome}: o ledger NÃO é filtrado só por member_id`, () => {
      assert.match(sql, PONTE, `${nome}: sem a ponte, o ledger devolve [] com o ledger cheio`);
      assert.match(sql, /WHERE cr\.member_id = v_member_id\s*\n\s*OR cr\.application_id IN/);
    });

    it(`${nome}: o titular vê COMO foi alcançado`, () => {
      // Sem isso, quem lê a exportação não distingue "carimbado" de "resolvido por e-mail", e a
      // dívida do carimbo fica invisível justamente para quem poderia cobrá-la.
      assert.match(sql, /'linked_by', CASE WHEN cr\.member_id = v_member_id THEN 'member_id' ELSE 'application_email' END/);
    });
  }

  it('a resolução de e-mails fail-closes quando o titular não tem e-mail', () => {
    // `= ANY(NULL)` não casa nada, mas o COALESCE torna a intenção explícita em vez de acidental:
    // um titular sem e-mail deve alcançar ZERO candidaturas, nunca todas.
    for (const sql of [EXPORT, LIST]) {
      assert.match(sql, /COALESCE\(array_agg\(DISTINCT s\.e\), ARRAY\[\]::text\[\]\)/);
    }
  });
});

describe('#1682 A — a escrita passa a carimbar o vínculo', () => {
  it('a migration existe e o INSERT leva member_id', () => {
    assert.ok(WRITE, 'migration da escrita ausente');
    assert.match(
      WRITE,
      /INSERT INTO public\.consent_records \(\s*member_id, application_id, policy_type/,
      'sem member_id no INSERT, a ponte por e-mail permanece o ÚNICO caminho, para sempre',
    );
  });

  it('só carimba quando a resolução é INEQUÍVOCA', () => {
    // Dois membros com o mesmo endereço é defeito de identidade. Escolher um deles aqui gravaria
    // o consentimento de uma pessoa na conta de outra — e, diferente da leitura (onde a ponte
    // alcança ambos e nada se perde), a escrita PERSISTE o erro.
    assert.match(WRITE, /WHERE \(SELECT count\(\*\) FROM cand\) = 1/);
  });

  it('NÃO faz backfill das linhas já emitidas', () => {
    // O ledger é imutável por desenho (#1666). Reescrever consentimentos já registrados para
    // melhorar a ergonomia de leitura é o movimento que o próprio #1666 recusou.
    assert.doesNotMatch(WRITE, /UPDATE\s+public\.consent_records/i);
    assert.doesNotMatch(WRITE, /UPDATE\s+consent_records/i);
  });

  it('o vínculo vira observável no retorno', () => {
    assert.match(WRITE, /'member_linked', \(v_member_id IS NOT NULL\)/);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Camada B — DB-aware, READ-ONLY
// ─────────────────────────────────────────────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbGated = Boolean(SUPABASE_URL && SUPABASE_SRK);
const skipMsg = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';
const sb = dbGated ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } }) : null;

describe('#1682 B — a ponte está VIVA, não só no arquivo', () => {
  for (const fn of ['export_my_data', 'list_my_consents']) {
    it(`${fn}: o corpo em produção alcança o ledger pela candidatura`, { skip: dbGated ? false : skipMsg }, async () => {
      const { data, error } = await sb.rpc('_audit_function_source', { p_proname: fn });
      assert.ifError(error);
      assert.ok(data?.length > 0, `${fn} não existe no banco`);
      const src = stripSql(data[0].prosrc);
      assert.match(src, /OR cr\.application_id IN/, `${fn}: a ponte não está viva em produção`);
      assert.match(src, /v_emails/, `${fn}: a resolução de e-mails não está viva`);
    });
  }

  it('give_consent_via_token carimba member_id em produção', { skip: dbGated ? false : skipMsg }, async () => {
    const { data, error } = await sb.rpc('_audit_function_source', { p_proname: 'give_consent_via_token' });
    assert.ifError(error);
    assert.ok(data?.length > 0);
    assert.match(stripSql(data[0].prosrc), /member_id, application_id, policy_type/);
  });
});

describe('#1682 B — o EFEITO: o ledger alcança gente, e só a gente certa', () => {
  // Replica a condição de visibilidade fora do banco e responde às duas únicas perguntas que
  // importam: alguém enxerga o próprio consentimento, e ninguém enxerga o dos outros.
  async function alcance() {
    const pick = async (t, cols) => {
      const { data, error } = await sb.from(t).select(cols).limit(5000);
      assert.ifError(error);
      return data ?? [];
    };
    const [members, memberEmails, apps, ledger] = await Promise.all([
      pick('members', 'id, email'),
      pick('member_emails', 'member_id, email'),
      pick('selection_applications', 'id, email'),
      pick('consent_records', 'id, member_id, application_id'),
    ]);

    const norm = (e) => (e ?? '').trim().toLowerCase();
    // e-mail → titulares (plural de propósito: um endereço compartilhado é observável aqui)
    const donos = new Map();
    const add = (e, id) => {
      const k = norm(e);
      if (!k || !id) return;
      if (!donos.has(k)) donos.set(k, new Set());
      donos.get(k).add(id);
    };
    for (const m of members) add(m.email, m.id);
    for (const me of memberEmails) add(me.email, me.member_id);

    const appDonos = new Map();
    for (const a of apps) appDonos.set(a.id, donos.get(norm(a.email)) ?? new Set());

    const vistaPor = new Map();
    for (const cr of ledger) {
      const s = new Set();
      if (cr.member_id) s.add(cr.member_id);
      for (const d of appDonos.get(cr.application_id) ?? []) s.add(d);
      if (s.size) vistaPor.set(cr.id, s);
    }
    return { ledger, vistaPor };
  }

  it('o ledger não é invisível para todo mundo', { skip: dbGated ? false : skipMsg }, async () => {
    const { ledger, vistaPor } = await alcance();
    assert.ok(ledger.length > 0, 'ledger vazio — a asserção não é exercida');
    // ⚠️ O QUE ESTA ASSERÇÃO PEGA, E O QUE NÃO PEGA. Ela replica a condição de visibilidade em
    // JS; NÃO chama `export_my_data` (que exige `auth.uid()` e recusa o service_role). Portanto
    // ela NÃO cai se alguém remover a ponte do corpo da função — quem pega isso é o bloco
    // "a ponte está VIVA" acima, que lê `prosrc`. O que ESTA pega é a outra metade do defeito:
    // o ledger voltar a ser escrito de um jeito que nenhum titular alcança (foi assim que o
    // #1682 nasceu — 56 linhas endereçadas por uma chave que a leitura não usava). Declarado
    // porque um guard que promete mais do que observa é como o defeito volta.
    assert.ok(
      vistaPor.size > 0,
      `nenhuma das ${ledger.length} linhas do ledger é alcançável por titular algum — ` +
        'é exatamente o estado que o #1682 encontrou',
    );
  });

  it('nenhuma linha do ledger é visível para mais de um titular', { skip: dbGated ? false : skipMsg }, async () => {
    const { vistaPor } = await alcance();
    const vazando = [...vistaPor.entries()].filter(([, s]) => s.size > 1).map(([id]) => id);
    // Alargar a leitura para alcançar quem consentiu não pode alargá-la para o consentimento
    // alheio. Se dois membros compartilham um endereço, isto acusa antes de virar incidente.
    assert.deepEqual(vazando, [], `linhas do ledger visíveis por mais de um titular: ${vazando.length}`);
  });
});

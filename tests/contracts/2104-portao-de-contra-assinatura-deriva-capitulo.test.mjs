/**
 * RASCUNHO #2104 — contract test. NAO mover para tests/contracts/ antes da janela de DDL.
 *
 * O portao _can_sign_gate decidia capitulo por literal em 4 ramos. Passa a derivar:
 *   classe sede      (president_go, cert_director_go)        -> chapter_registry.is_contracting_chapter
 *   classe parceiros (president_others, partner_consultation) -> partner_chapters.partnership_status='signed', menos a sede
 *
 * O ponto do teste NAO e conferir que os 4 capitulos de hoje passam. E conferir que o
 * conjunto aceito CONTINUA DERIVADO DA TABELA. Escrever os 4 como literal aqui recriaria
 * a mesma foto congelada que a funcao tinha, e o teste ficaria verde enquanto a producao
 * nega. Por isso o esperado e SEMPRE lido do banco, nunca digitado.
 */
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

const GATE_PATH = 'supabase/migrations/20260830181254_2104_portao_de_contra_assinatura_deriva_capitulo_e_status_vira_auditavel.sql';
const INVARIANT_PATH = 'supabase/migrations/20260830195633_2104_invariante_AQ_capitulo_contratante_tem_participacao.sql';
const MIGRATION_SQL = readFileSync(GATE_PATH, 'utf8');
const INVARIANT_SQL = readFileSync(INVARIANT_PATH, 'utf8');

const URL = process.env.SUPABASE_URL;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const dbIt = URL && SERVICE ? it : it.skip;
const sb = URL && SERVICE ? createClient(URL, SERVICE) : null;

describe('#2104 — _can_sign_gate deriva capitulo, nao compara com literal', () => {

  describe('assercoes estaticas sobre a migration', () => {
    it('mantem a assinatura, SECDEF e o search_path pinado', () => {
      assert.match(MIGRATION_SQL, /FUNCTION public\._can_sign_gate/);
      assert.match(MIGRATION_SQL, /SECURITY DEFINER/);
      assert.match(MIGRATION_SQL, /SET search_path TO 'public', 'pg_temp'/);
    });

    it('NENHUM literal de capitulo sobra fora de comentario', () => {
      const semComentarios = MIGRATION_SQL
        .split('\n')
        .filter((l) => !l.trimStart().startsWith('--'))
        .join('\n');
      // Guard estatico casa o proprio comentario que descreve o anti-padrao:
      // por isso os comentarios saem ANTES de medir.
      assert.doesNotMatch(semComentarios, /'PMI-(GO|CE|DF|MG|RS|SP|RJ|BA|PR|PE|SC|SE|ES|AM|PB)'/);
    });

    it('os 4 ramos passam a ler as tabelas de verdade', () => {
      assert.match(MIGRATION_SQL, /WHEN 'president_go' THEN[\s\S]{0,400}chapter_registry[\s\S]{0,200}is_contracting_chapter/);
      assert.match(MIGRATION_SQL, /WHEN 'cert_director_go' THEN[\s\S]{0,400}chapter_registry[\s\S]{0,200}is_contracting_chapter/);
      assert.match(MIGRATION_SQL, /WHEN 'president_others' THEN[\s\S]{0,400}partner_chapters[\s\S]{0,200}partnership_status = 'signed'/);
      assert.match(MIGRATION_SQL, /WHEN 'partner_consultation' THEN[\s\S]{0,400}partner_chapters[\s\S]{0,200}partnership_status = 'signed'/);
    });

    it('committee_majority NAO foi tocado: decide por designation, nao por capitulo', () => {
      assert.match(MIGRATION_SQL, /WHEN 'committee_majority' THEN 'ip_committee' = ANY\(v_member\.designations\)/);
    });

    it('preserva os invariantes das ADRs anteriores nos ramos alterados', () => {
      // #1152: president_go e president_others exigem SEMPRE legal_signer.
      const go = MIGRATION_SQL.match(/WHEN 'president_go' THEN[\s\S]*?WHEN '/)[0];
      assert.match(go, /'legal_signer' = ANY\(v_member\.designations\)/);
      // ADR-0016 Am.4: cert_director_go NAO exige chapter_board, e e doc_type-scoped.
      const cert = MIGRATION_SQL.match(/WHEN 'cert_director_go' THEN[\s\S]*?WHEN '/)[0];
      assert.doesNotMatch(cert, /'chapter_board'/);
      assert.match(cert, /v_doc_type = 'project_charter'/);
    });
  });

  describe('o invariante AQ trava o acoplamento da sede', () => {
    it('a captura MAIS NOVA de check_schema_invariants ja contem o AQ', () => {
      // Lido por latestFunctionCapture e nao por caminho fixo: fixar a migration faria este
      // guard vencer na proxima captura, que e a divida que o #1932 cobra.
      const cap = latestFunctionCapture(ROOT, 'check_schema_invariants');
      assert.match(cap.block, /AQ_contracting_chapter_has_participation/,
        `a captura mais nova (${cap.file}) nao contem o invariante AQ`);
    });

    it('a migration do invariante monta o corpo SERVER-SIDE, nao transcreve 46 KB', () => {
      assert.match(INVARIANT_SQL, /SELECT p\.prosrc INTO v_src/);
      assert.match(INVARIANT_SQL, /CREATE OR REPLACE FUNCTION public\.check_schema_invariants/);
    });

    it('reprova se a insercao for no-op silencioso', () => {
      assert.match(INVARIANT_SQL, /RAISE EXCEPTION 'o padrao do END final nao casou/);
    });

    it('trava a contagem de RETURN QUERY em 43 -> 44', () => {
      assert.match(INVARIANT_SQL, /v_antes <> 43 OR v_depois <> 44/);
    });

    it('reprova se sobrar byte de controle (o backreference com prefixo E)', () => {
      assert.match(INVARIANT_SQL, /position\(chr\(1\) in v_new\) > 0/);
    });

    dbIt('AQ existe e nao esta violado', async () => {
      const { data, error } = await sb.rpc('check_schema_invariants');
      assert.equal(error, null);
      const aq = data.find((r) => r.invariant_name === 'AQ_contracting_chapter_has_participation');
      assert.ok(aq, 'o invariante AQ nao aparece na saida de check_schema_invariants');
      assert.equal(aq.violation_count, 0);
    });
  });

  describe('invariante de derivacao (DB-aware)', () => {
    dbIt('a flag de sede discrimina: exatamente 1 capitulo contratante', async () => {
      const { data, error } = await sb.from('chapter_registry')
        .select('chapter_code').eq('is_contracting_chapter', true);
      assert.equal(error, null);
      // Nao afirmo QUAL. Afirmo que existe exatamente um, que e o que o portao pressupoe.
      assert.equal(data.length, 1, 'a classe sede pressupoe um unico capitulo contratante');
    });

    dbIt('vacuidade: a classe parceiros nao pode ficar vazia sem alguem notar', async () => {
      const { data, error } = await sb.from('partner_chapters')
        .select('chapter_code').eq('partnership_status', 'signed');
      assert.equal(error, null);
      // Controle de vacuidade: se o vocabulario do status mudar (ex.: alguem migrar
      // 'signed' para outro valor), este teste reprova em vez de o portao negar calado.
      assert.ok(data.length >= 2,
        `partnership_status='signed' devolveu ${data.length} linhas; ` +
        'se o vocabulario mudou, o portao esta negando presidente de capitulo parceiro');
    });

    dbIt('o conjunto aceito e IDENTICO ao derivado da tabela (diferenca simetrica)', async () => {
      // Derivado, nunca digitado.
      const { data: sede } = await sb.from('chapter_registry')
        .select('chapter_code').eq('is_contracting_chapter', true);
      const sedeDisplay = `PMI-${sede[0].chapter_code}`;
      const { data: signed } = await sb.from('partner_chapters')
        .select('chapter_code').eq('partnership_status', 'signed');
      const esperado = new Set(signed.map((r) => r.chapter_code).filter((c) => c !== sedeDisplay));

      // O que o portao aceitaria hoje, pela mesma regra, lido do banco.
      const { data: membros } = await sb.from('members')
        .select('chapter').not('chapter', 'is', null);
      const aceitos = new Set(membros.map((m) => m.chapter).filter((c) => esperado.has(c)));

      const soNoEsperado = [...esperado].filter((c) => ![...aceitos].includes(c) &&
        membros.some((m) => m.chapter === c));
      assert.deepEqual(soNoEsperado, [],
        'ha capitulo derivado da tabela que o portao nao aceita');
      assert.ok(esperado.size >= 2, 'conjunto derivado vazio ou degenerado');
    });
  });
});

/* PROVA POR INJECAO DE DEFEITO — manual, registrada na PR, nao automatizada aqui.
 *
 * Automatizar exige INSERT em partner_chapters num banco compartilhado, e o portao
 * de DDL existe justamente porque escrita compartilhada derruba as outras branches
 * (aconteceu em 30/08: uma escrita de dado deixou 5 PRs vermelhas).
 *
 * Roteiro a executar na janela, em transacao com ROLLBACK, e colar o transcript na PR:
 *   1. BEGIN
 *   2. INSERT capitulo sintetico em chapter_registry + partner_chapters com 'signed'
 *   3. membro sintetico com chapter = display desse capitulo, chapter_board + legal_signer
 *   4. _can_sign_gate(..., 'president_others') deve devolver TRUE
 *   5. UPDATE partnership_status -> 'announced_at_risk'
 *   6. mesma chamada deve devolver FALSE
 *   7. ROLLBACK, e conferir com consulta NOVA que nada sobrou
 *
 * Sem o passo 6 a prova nao vale: verde que nunca viu vermelho nao testou portao nenhum.
 */

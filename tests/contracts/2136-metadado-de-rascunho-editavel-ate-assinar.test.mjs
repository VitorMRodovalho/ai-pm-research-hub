import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { latestFunctionCapture } from '../helpers/guard-pin-staleness.mjs';
import { normalizeBody, md5 } from '../helpers/rpc-body-drift-parser.mjs';

// #2136 — imutabilidade de metadado de documento de governanca segue o CICLO DE VIDA.
//
// O defeito: `governance_documents` nega insert/update/delete a `authenticated` via RLS
// (gd_deny_*, USING(false)) e NENHUMA das 18 funcoes *document* escrevia title/description.
// Resultado medido em 02/09/2026: um documento em `status='draft'`, com ZERO assinaturas e
// ZERO cadeias ativas, tinha o nome congelado como se ja tivesse sido assinado.
//
// A regra: enquanto rascunho nao assinado, metadado e editavel por manage_member, com audit
// log. A partir da primeira assinatura (ou cadeia ativa, ou ratificacao, ou saida de draft),
// congela. A imutabilidade existe para proteger o que alguem assinou; antes disso ela nao
// protege nada, so impede correcao.
//
// SCOPE LOCK verificado aqui: a regra mora na RPC. As policies de RLS NAO foram afrouxadas.

const MIGRATION = 'supabase/migrations/20260902014816_metadado_de_rascunho_e_editavel_ate_a_primeira_assinatura.sql';
const MIGRATION2 = 'supabase/migrations/20260902021856_rotulo_de_minuta_e_corrigivel_enquanto_o_documento_nao_foi_aprovado.sql';
const ROOT = process.cwd();
const SQL = existsSync(MIGRATION) ? readFileSync(MIGRATION, 'utf8') : '';

const URL = process.env.SUPABASE_URL;
const SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = URL && SRK ? createClient(URL, SRK, { auth: { persistSession: false } }) : null;
const skip = 'requer SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

describe('#2136 — metadado de rascunho e editavel ate a primeira assinatura', () => {
  describe('captura na migration (estatico)', () => {
    it('a migration existe e captura a funcao', () => {
      assert.ok(existsSync(MIGRATION), `migration ausente: ${MIGRATION}`);
      assert.match(SQL, /CREATE OR REPLACE FUNCTION public\.update_governance_document_meta/);
    });

    it('o gate e manage_member, nao um papel mais largo', () => {
      assert.match(SQL, /can_by_member\(v_caller_id, 'manage_member'\)/);
      assert.doesNotMatch(SQL, /can_by_member\(v_caller_id, 'manage_platform'\)/,
        'esta RPC nao deve exigir manage_platform: o gate ratificado e manage_member');
    });

    it('o congelamento cobre as QUATRO condicoes, nao so o status', () => {
      // injetar o defeito = remover qualquer uma destas fara este teste reprovar
      for (const cond of [
        /v_doc\.status <> 'draft'/,
        /v_assinaturas > 0/,
        /v_cadeias_ativas > 0/,
        /v_doc\.first_ratified_at IS NOT NULL/,
      ]) {
        assert.match(SQL, cond, `condicao de congelamento ausente: ${cond}`);
      }
    });

    it('fecha EXECUTE para PUBLIC/anon (CREATE FUNCTION nasce aberto)', () => {
      assert.match(SQL, /REVOKE ALL ON FUNCTION public\.update_governance_document_meta\(uuid, text, text\) FROM PUBLIC, anon/);
      assert.match(SQL, /GRANT EXECUTE ON FUNCTION public\.update_governance_document_meta\(uuid, text, text\) TO authenticated, service_role/);
    });

    it('escreve trilha de auditoria', () => {
      assert.match(SQL, /INSERT INTO public\.admin_audit_log/);
      assert.match(SQL, /'governance_document_meta_change'/);
    });

    it('NAO afrouxa RLS: nenhum DROP/ALTER de policy da tabela', () => {
      assert.doesNotMatch(SQL, /DROP\s+POLICY/i);
      assert.doesNotMatch(SQL, /ALTER\s+POLICY/i);
      assert.doesNotMatch(SQL, /gd_deny_update/i,
        'a policy de negacao deve permanecer intocada: a regra mora na RPC');
    });
  });

  describe('estado no banco', () => {
    it(sb ? 'o TAP nao carrega mais o termo vetado no titulo' : `SKIP: ${skip}`, async (t) => {
      if (!sb) return t.skip(skip);
      const { data, error } = await sb
        .from('governance_documents')
        .select('id, title')
        .ilike('title', '%Prep Course%');
      assert.equal(error, null, error?.message);
      assert.equal(data.length, 0,
        `documento(s) ainda com "Prep Course" no titulo: ${JSON.stringify(data)}`);
    });

    it(sb ? 'a RPC recusa chamador nao autenticado (service_role tem auth.uid() nulo)' : `SKIP: ${skip}`, async (t) => {
      if (!sb) return t.skip(skip);
      const { data, error } = await sb.rpc('update_governance_document_meta', {
        p_document_id: '00000000-0000-0000-0000-000000000000',
        p_title: 'nao deve gravar',
      });
      assert.equal(error, null, error?.message);
      assert.equal(data?.error, 'authentication_required',
        `esperava authentication_required, veio ${JSON.stringify(data)}`);
    });
  });
});

// ---------------------------------------------------------------------------
// Migration 2 — `version_label` nomeia a RODADA, nao o texto.
//
// O selo de `locked_at` existe para que um comentario ancorado numa clausula continue apontando
// para o MESMO TEXTO. Renomear o rotulo nao move uma virgula, entao congelar identidade junto com
// conteudo era escopo excessivo: impedia corrigir o rotulo de um rascunho que nunca vigorou.
//
// POR QUE O GUARD NAO FIXA ARQUIVO. O teste 571 afirma a mesma invariante do §9.2 (`change_class`
// congelado) lendo um `.sql` FIXO. Esta migration reescreve `trg_document_version_immutable`, e o
// 571 continuaria verde mesmo se a funcao viva perdesse a guarda: ele afirma sobre texto morto.
// `latestFunctionCapture` resolve pela captura MAIS RECENTE, e o hash vivo abaixo amarra a captura
// a producao — sem isso, tudo aqui seria afirmacao sobre um arquivo.
// ---------------------------------------------------------------------------
describe('#2136 — o rotulo de minuta e corrigivel enquanto o documento nao foi aprovado', () => {
  const TRG = latestFunctionCapture(ROOT, 'trg_document_version_immutable');
  const SQL2 = existsSync(MIGRATION2) ? readFileSync(MIGRATION2, 'utf8') : '';

  describe('a captura mais recente (estatico)', () => {
    it('a reescrita mais recente do trigger e a deste trabalho, nao a de 2026-05', () => {
      assert.equal(TRG.file, MIGRATION2.split('/').pop(),
        `a captura mais recente veio de ${TRG.file}: o guard estaria afirmando sobre outra versao`);
    });

    it('o conteudo segue congelado, change_class incluido (#571 PR-1 §9.2)', () => {
      for (const col of ['content_html', 'content_markdown', 'version_number',
                         'document_id', 'locked_at', 'change_class']) {
        assert.match(TRG.body, new RegExp(`NEW\\.${col} IS DISTINCT FROM OLD\\.${col}`),
          `a folga de rotulo nao pode descongelar ${col} de uma linha lacrada`);
      }
    });

    it('a folga de version_label e CONDICIONAL ao ciclo de vida, nao incondicional', () => {
      assert.match(TRG.body, /NEW\.version_label IS DISTINCT FROM OLD\.version_label/,
        'o ramo de version_label tem de existir');
      assert.match(TRG.body,
        /NOT COALESCE\(\s*public\.governance_document_is_unsigned_draft\(OLD\.document_id\)\s*,\s*false\s*\)/,
        'sem o gate, renomear rotulo de documento JA APROVADO passaria a ser permitido');
    });

    it('a regra vive em UM lugar: a RPC consome o mesmo helper', () => {
      const rpc = SQL2.match(
        /CREATE OR REPLACE FUNCTION public\.update_governance_document_meta[\s\S]*?\$function\$;/);
      assert.ok(rpc, 'a migration precisa recapturar a RPC que passou a usar o helper');
      assert.match(rpc[0], /public\.governance_document_is_unsigned_draft\(p_document_id\)/,
        'duas copias da regra divergem: foi assim que o congelamento virou escopo excessivo');
    });

    it('o helper fecha EXECUTE para PUBLIC/anon (CREATE FUNCTION nasce aberto)', () => {
      assert.match(SQL2,
        /REVOKE ALL ON FUNCTION public\.governance_document_is_unsigned_draft\(uuid\) FROM PUBLIC, anon;/,
        'sem o REVOKE, anon herda EXECUTE e enumera o estado de aprovacao de qualquer documento');
    });
  });

  describe('estado no banco', () => {
    it(sb ? 'a funcao VIVA e exatamente a que o guard acima leu (drift zero)' : `SKIP: ${skip}`,
      async (t) => {
      if (!sb) return t.skip(skip);
      const { data, error } = await sb.rpc('_audit_list_public_function_bodies');
      assert.equal(error, null, error?.message);
      const row = (data ?? []).find((r) => r.proname === 'trg_document_version_immutable');
      // CONTROLE POSITIVO: sem esta linha, `row === undefined` deixaria o hash nunca ser comparado
      // e as afirmacoes estaticas acima valeriam sobre um arquivo, nao sobre producao.
      assert.ok(row, `trigger ausente entre as ${data?.length ?? 0} funcoes vivas listadas`);
      assert.equal(row.body_md5, md5(normalizeBody(TRG.body)),
        'o corpo vivo divergiu da captura: as invariantes acima deixaram de valer em producao');
    });

    it(sb ? 'o helper separa rascunho de congelado nas DUAS direcoes' : `SKIP: ${skip}`,
      async (t) => {
      if (!sb) return t.skip(skip);
      const { data: docs, error: e1 } = await sb
        .from('governance_documents').select('id, status, signed_at, first_ratified_at');
      assert.equal(e1, null, e1?.message);
      assert.ok((docs ?? []).length > 0, 'nenhum documento lido — o guard nao mediria nada');

      const veredito = new Map();
      for (const d of docs) {
        const { data, error } = await sb.rpc('governance_document_is_unsigned_draft',
          { p_document_id: d.id });
        assert.equal(error, null, error?.message);
        veredito.set(d.id, data);
      }

      // CONTROLE NOS DOIS SENTIDOS: um helper que devolvesse sempre `true` (ou sempre `false`)
      // passaria em qualquer afirmacao de um lado so.
      const abertos = [...veredito.values()].filter((v) => v === true).length;
      const fechados = [...veredito.values()].filter((v) => v === false).length;
      assert.ok(abertos > 0, 'nenhum documento aberto: o lado permissivo nao foi exercido');
      assert.ok(fechados > 0, 'nenhum documento congelado: o lado restritivo nao foi exercido');

      // O helper nao pode ser MAIS FROUXO que o estado declarado na propria linha.
      const frouxos = docs.filter((d) =>
        veredito.get(d.id) === true &&
        (d.status !== 'draft' || d.signed_at !== null || d.first_ratified_at !== null));
      assert.deepEqual(frouxos.map((d) => d.id), [],
        'documento fora de rascunho (ou ja assinado/ratificado) classificado como editavel');
    });

    it(sb ? 'o TAP teve os rotulos de minuta corrigidos, e o espaco R** ficou livre' : `SKIP: ${skip}`,
      async (t) => {
      if (!sb) return t.skip(skip);
      const { data: ancora, error: e1 } = await sb
        .from('document_versions').select('document_id')
        .eq('id', '43f3bb5c-7e39-45a1-b548-800b6ad22ff5').maybeSingle();
      assert.equal(e1, null, e1?.message);
      assert.ok(ancora?.document_id, 'a versao ancora sumiu: o documento alvo mudou');

      const { data: vs, error: e2 } = await sb
        .from('document_versions').select('version_number, version_label, locked_at')
        .eq('document_id', ancora.document_id).order('version_number');
      assert.equal(e2, null, e2?.message);

      const porNumero = new Map(vs.map((v) => [v.version_number, v.version_label]));
      assert.equal(porNumero.get(1), 'M01', 'v1 deveria ter virado M01');
      assert.equal(porNumero.get(2), 'M02', 'v2 deveria ter virado M02');

      // CONTROLE DE QUE O RENAME ERA NECESSARIO: com R00 ocupado por uma minuta, publicar a versao
      // aprovada como R00 violaria UNIQUE (document_id, version_label) no dia da aprovacao.
      const aindaR = vs.filter((v) => /^R[0-9]/.test(v.version_label ?? ''));
      assert.deepEqual(aindaR.map((v) => v.version_label), [],
        'o espaco de rotulo aprovado continua ocupado por minuta');

      // v2 esta LACRADA e mesmo assim foi renomeada: e essa a folga que a migration abriu.
      const v2 = vs.find((v) => v.version_number === 2);
      assert.ok(v2?.locked_at, 'v2 deixou de estar lacrada: o teste perdeu o caso que importa');
    });
  });
});

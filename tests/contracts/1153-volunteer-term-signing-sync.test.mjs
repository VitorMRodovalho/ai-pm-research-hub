/**
 * Contract: #1153 — sincronizar o texto jurídico aprovado com o instrumento de Termo assinado.
 *
 * Direção 1 (ratificada PM Vitor 2026-07-06): o instrumento assinado renderiza a partir da
 * VERSÃO APROVADA DA CADEIA (governance_documents.current_version_id -> document_versions.
 * content_html), congelada imutavelmente no snapshot da assinatura (content_snapshot.html_body),
 * com {chapterName} resolvido (#1048). Aposenta o clauseN JSON como fonte para NOVOS certos,
 * mantendo o caminho de slots para os já assinados (imutabilidade #648 preservada verbatim).
 *
 * Trava:
 *   - Migração 352: índice único parcial (INV-1), activate_volunteer_term_version (gate
 *     manage_platform + flip atômico), sign_volunteer_agreement snapshota html_body/{chapterName}.
 *   - pdf.ts: caminho html_body (Direção 1) + caminho legado de slots; guard fail-loud mantido;
 *     nenhuma consulta viva a volunteer_term_template / status=active (reforça #648).
 *   - INV-1 (DB-aware): no máx. 1 volunteer_term_template active.
 *   - INV-2 (DB-aware): nenhum html_body snapshotado carrega {chapterName} cru.
 *
 * NOTA de scope de teste: pdf.ts NÃO é importável em runtime pelo runner (usa imports relativos
 * sem extensão — `../canonical` etc. — que `node --experimental-strip-types` não resolve). Como
 * TODO o repo, a lógica do renderer é travada por asserção estática; a fidelidade comportamental
 * (texto assinado ≡ versão aprovada, {chapterName} resolvido) é coberta pelo INV-2 DB-aware + QA
 * visual do PDF (SPEC §5.6).
 *
 * Scope: estático (sempre) + DB-aware (skip sem SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY).
 * Cross-ref: docs/reference/SPEC-1153-volunteer-term-signing-sync.md ·
 *            supabase/migrations/20260805000352_1153_volunteer_term_signing_sync.sql
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const PDF = readFileSync('src/lib/certificates/pdf.ts', 'utf8');
const MIG_PATH = 'supabase/migrations/20260805000352_1153_volunteer_term_signing_sync.sql';
const MIG = existsSync(MIG_PATH) ? readFileSync(MIG_PATH, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

describe('#1153 migração 352 — mecanismo Direção 1', () => {
  it('a migração existe', () => {
    assert.ok(existsSync(MIG_PATH), `${MIG_PATH} deve existir`);
  });
  it('INV-1: índice único parcial de linha-única-active', () => {
    assert.match(MIG, /CREATE UNIQUE INDEX[\s\S]*uq_one_active_volunteer_term/);
    assert.match(MIG, /WHERE status = 'active' AND doc_type = 'volunteer_term_template'/);
  });
  it('activate_volunteer_term_version: gate manage_platform + flip atômico', () => {
    assert.match(MIG, /FUNCTION public\.activate_volunteer_term_version\(p_doc_id uuid\)/);
    assert.match(MIG, /can_by_member\(v_actor_member, 'manage_platform'/,
      'ativação deve ser gated por manage_platform (GP-only)');
    assert.match(MIG, /SET status = 'superseded'[\s\S]*SET status = 'active'/,
      'flip deve superseder as demais e ativar a alvo (INV-1)');
    assert.match(MIG, /locked_at IS NOT NULL/,
      'só ativa uma versão TRAVADA na cadeia (não rascunho)');
  });
  it('sign_volunteer_agreement snapshota o content_html aprovado + resolve {chapterName}', () => {
    assert.match(MIG, /content_html, dv\.version_label INTO v_html_body/,
      'deve ler o corpo aprovado da versão da cadeia (current_version_id)');
    assert.match(MIG, /replace\(v_html_body, '\{chapterName\}', v_chapter_display\)/,
      'deve resolver {chapterName} para o nome do capítulo contratante (SSOT)');
    assert.match(MIG, /'html_body', v_html_body/,
      'deve gravar html_body no content_snapshot da assinatura');
    assert.match(MIG, /'clauses', v_template\.content/,
      'deve MANTER o snapshot de clauses (imutabilidade #648 + rollback)');
    assert.match(MIG, /'approved_body_unavailable'/,
      'deve errar explicitamente quando a versão ativa não tem corpo HTML aprovado');
  });
});

describe('#1153 pdf.ts — caminho Direção 1 + guarda #648 (estático)', () => {
  it('CertificateData carrega template_html_body e hydrate resolve pelo snapshot imutável', () => {
    assert.match(PDF, /template_html_body\?: string/, 'CertificateData deve declarar template_html_body');
    assert.match(PDF, /template_html_body = certData\.template_html_body \|\| snap\.html_body/,
      'hydrate deve resolver html_body do snapshot da assinatura');
  });
  it('não reintroduz consulta viva ao template (reforça #648)', () => {
    assert.doesNotMatch(PDF, /volunteer_term_template/,
      'pdf.ts não pode consultar o template volunteer_term_template ao vivo');
    assert.doesNotMatch(PDF, /\.eq\(\s*['"]status['"]\s*,\s*['"]active['"]\s*\)/,
      'pdf.ts não pode resolver por status=active');
  });
  it('caminho html_body renderiza o corpo aprovado e resolve {chapterName}', () => {
    assert.match(PDF, /const hasApprovedBody = approvedBody\.length > 0/);
    assert.match(PDF, /const legalSection = hasApprovedBody/,
      'a seção legal deve escolher o corpo aprovado quando presente');
    assert.ok(PDF.includes('approvedBody.replace(/\\{chapterName\\}/g, chapterInline)'),
      'o corpo aprovado deve ter {chapterName} defensivamente resolvido no render');
    assert.ok(PDF.includes('const chapterInline') && PDF.includes('cn.match(/\\(([^)]+)\\)\\s*$/)'),
      'chapterInline deve derivar a forma curta (parentético) do SSOT, sem hardcode');
  });
  it('caminho legado (slots) preservado + guard fail-loud (#648)', () => {
    assert.match(PDF, /Termos da Adesão do Programa de Voluntariado:/,
      'o caminho legado mantém o heading + <ol> verbatim (backward-compat)');
    assert.match(PDF, /volunteer_agreement_template_unavailable/,
      'guard deve recusar emitir instrumento em branco quando nem corpo nem clauses resolvem');
    assert.match(PDF, /if \(!hasApprovedBody && \(!c \|\| typeof c/,
      'o guard só dispara quando NÃO há corpo aprovado E não há clause1');
  });
});

describe('#1153 invariantes de dados (DB-aware)', () => {
  it('INV-1: no máximo 1 volunteer_term_template active', { skip: !sb && skipMsg }, async () => {
    const { data, error } = await sb
      .from('governance_documents')
      .select('id, version, status')
      .eq('doc_type', 'volunteer_term_template')
      .eq('status', 'active');
    assert.ok(!error, `query falhou: ${error?.message}`);
    assert.ok((data?.length ?? 0) <= 1,
      `INV-1 violado: ${data?.length} linhas active (${data?.map(d => d.version).join(', ')})`);
  });

  it('INV-2: nenhum html_body snapshotado carrega {chapterName} cru', { skip: !sb && skipMsg }, async () => {
    const { data, error } = await sb
      .from('certificates')
      .select('verification_code, content_snapshot')
      .eq('type', 'volunteer_agreement');
    assert.ok(!error, `query falhou: ${error?.message}`);
    const offenders = (data || []).filter(r => {
      const body = r?.content_snapshot?.html_body;
      return typeof body === 'string' && body.includes('{chapterName}');
    });
    assert.equal(offenders.length, 0,
      `certos com {chapterName} cru no html_body: ${offenders.map(o => o.verification_code).join(', ')}`);
  });

  it('activate_volunteer_term_version existe (não é PGRST202)', { skip: !sb && skipMsg }, async () => {
    // O gate real de manage_platform impede a execução por service_role sem membro; basta provar
    // que a função existe (não é PGRST202 "function not found").
    const { error } = await sb.rpc('activate_volunteer_term_version', {
      p_doc_id: '00000000-0000-0000-0000-000000000000',
    });
    if (error) {
      assert.notMatch(String(error.code || ''), /PGRST202/,
        `activate_volunteer_term_version deveria existir; erro: ${error.message}`);
    }
  });
});

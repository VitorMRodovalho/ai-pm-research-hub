/**
 * Contract: #648 — imutabilidade do Termo de Voluntário assinado.
 *
 * Causa raiz (confirmada, commit e766255a): o corpo das cláusulas nunca era snapshotado na
 * assinatura, e o render (src/lib/certificates/pdf.ts) resolvia as cláusulas pelo template
 * `status='active'` LIVE. Com o HOLD DO TERMO (#632/#633) movendo ambos os templates para
 * under_review, a query 'active' passou a retornar null → cláusulas EM BRANCO; e, mesmo com
 * template ativo, uma revisão reescreveria retroativamente termos já assinados.
 *
 * Este teste tranca as 6 camadas do fix:
 *   1 — render por snapshot/template_id pinado, NUNCA por 'active'; guard fail-loud; footer por versão.
 *   2 — sign_volunteer_agreement snapshota o corpo das cláusulas (content_snapshot.clauses).
 *   3 — política RLS de leitura do bucket privado `certificates` + download serve o PDF congelado.
 *   4 — backfill do corpo das cláusulas nos certs já assinados (todos pinam a78311fd).
 *   5 — ESTE teste (guard de imutabilidade).
 *   6 — gamification.astro roteia termos para /certificates (não renderiza cert genérico).
 *
 * Nota Option C: a RLS member-owned do bucket `certificates` — adiada na alpha p221 #267 para
 * "Studio UI" (ver certificates-bucket-and-backfill-script.test.mjs) — passa a ser implementada
 * via migração 20260805000150 (apply_migration rodou como role privilegiado; a policy está viva).
 *
 * Cross-ref: issue #648 · supabase/migrations/20260805000150_648_volunteer_term_pdf_immutability.sql
 * Scope: estático (sempre) + DB-aware (skip sem SUPABASE_URL + SERVICE_ROLE_KEY).
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const PDF = readFileSync('src/lib/certificates/pdf.ts', 'utf8');
const GAMI = readFileSync('src/pages/gamification.astro', 'utf8');
const MIG_PATH = 'supabase/migrations/20260805000150_648_volunteer_term_pdf_immutability.sql';
const MIG = existsSync(MIG_PATH) ? readFileSync(MIG_PATH, 'utf8') : '';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SRK = process.env.SUPABASE_SERVICE_ROLE_KEY;
const sb = SUPABASE_URL && SUPABASE_SRK
  ? createClient(SUPABASE_URL, SUPABASE_SRK, { auth: { persistSession: false } })
  : null;
const skipMsg = 'requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY';

describe('#648 Camada 1 — render imutável (pdf.ts)', () => {
  it('NÃO resolve cláusulas pelo template live (sem volunteer_term_template / status=active)', () => {
    assert.doesNotMatch(PDF, /volunteer_term_template/,
      'pdf.ts não pode mais consultar o template volunteer_term_template ao vivo — o corpo vem do snapshot/pinned template_id');
    assert.doesNotMatch(PDF, /\.eq\(\s*['"]status['"]\s*,\s*['"]active['"]\s*\)/,
      'pdf.ts não pode resolver cláusulas por status=active (null pós-HOLD → branco; viola imutabilidade)');
  });

  it('resolve por content_snapshot.clauses → cert.template_id pinado', () => {
    assert.match(PDF, /snap\.clauses/, 'deve preferir o snapshot de cláusulas da assinatura');
    assert.match(PDF, /\.eq\(\s*['"]id['"]\s*,\s*fullCert\.template_id\s*\)/,
      'fallback deve resolver o template pela VERSÃO PINADA (cert.template_id), independente do status atual');
  });

  it('buildVolunteerAgreementHTML falha LOUD em vez de renderizar cláusulas em branco', () => {
    assert.match(PDF, /volunteer_agreement_template_unavailable/,
      'render deve lançar erro explícito quando o corpo das cláusulas não resolve — nunca emitir instrumento em branco');
  });

  it('rodapé deriva a versão do template pinado (sem hardcode R3-C3)', () => {
    assert.match(PDF, /Template: \$\{certData\.template_version/,
      'o rótulo do template no rodapé deve vir de certData.template_version, não de um literal fixo');
  });
});

describe('#648 Camada 3 — serve o PDF congelado imutável', () => {
  it('downloadCertificatePDF serve o pdf_url congelado via signed URL antes de reconstruir', () => {
    assert.match(PDF, /createSignedUrl/,
      'o download de volunteer_agreement deve servir o artefato congelado via createSignedUrl');
    assert.match(PDF, /storage\.from\(\s*['"]certificates['"]\s*\)/,
      'deve usar o bucket privado certificates');
    // a serventia do frozen deve preceder o rebuild (hydrate) — o frozen é o artefato autoritativo.
    const frozenIdx = PDF.indexOf('createSignedUrl');
    const hydrateIdx = PDF.indexOf('if (sb) await hydrateCertData(certData, sb);');
    assert.ok(frozenIdx > -1 && hydrateIdx > -1 && frozenIdx < hydrateIdx,
      'a tentativa de servir o frozen PDF deve vir ANTES do rebuild live');
  });
});

describe('#648 Camada 2/3/4 — migração SQL', () => {
  it('a migração existe', () => {
    assert.ok(existsSync(MIG_PATH), `${MIG_PATH} deve existir`);
  });
  it('Camada 2 — sign_volunteer_agreement snapshota o corpo das cláusulas', () => {
    assert.match(MIG, /'clauses',\s*v_template\.content/,
      'a RPC deve gravar o corpo completo das cláusulas no content_snapshot na assinatura');
  });
  it('Camada 3 — cria a política RLS de leitura do bucket certificates (dono OU admin)', () => {
    assert.match(MIG, /certificates_read_owner_or_admin/);
    assert.match(MIG, /storage\.foldername\(name\)/,
      'a policy deve casar a pasta do objeto (member_id) com o membro autenticado');
    assert.match(MIG, /bucket_id\s*=\s*'certificates'/);
  });
  it('Camada 4 — backfill do corpo das cláusulas com marcador de proveniência', () => {
    assert.match(MIG, /clauses_source/,
      'o backfill deve carimbar a proveniência (pinned_template) para auditoria');
    assert.match(MIG, /clauses_backfilled_at/);
  });
});

describe('#648 Camada 6 — gamification.astro não renderiza termo como cert genérico', () => {
  it('roteia volunteer_agreement para /certificates antes do render inline', () => {
    assert.match(GAMI, /type === 'volunteer_agreement'[\s\S]{0,200}\/certificates/,
      'o downloadCertificatePDF inline do gamification deve rotear termos para /certificates (sem case próprio para o instrumento legal)');
  });
});

describe('#648 invariante de dados (DB-aware)', () => {
  it('todo volunteer_agreement tem content_snapshot.clauses em shape objeto com clause1', { skip: !sb && skipMsg }, async () => {
    const { data, error } = await sb
      .from('certificates')
      .select('verification_code, content_snapshot')
      .eq('type', 'volunteer_agreement');
    assert.ok(!error, `query falhou: ${error?.message}`);
    assert.ok(Array.isArray(data) && data.length > 0, 'deve haver certs volunteer_agreement');
    const offenders = data.filter(r => {
      const cl = r?.content_snapshot?.clauses;
      return !cl || typeof cl !== 'object' || Array.isArray(cl) || !cl.clause1;
    });
    assert.equal(offenders.length, 0,
      `certs sem corpo de cláusulas em objeto (clause1): ${offenders.map(o => o.verification_code).join(', ')}`);
  });
});

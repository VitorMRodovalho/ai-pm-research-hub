import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';

const ROOT = process.cwd();
const migrationPath = join(ROOT, 'supabase/migrations/20260805000162_646_governance_document_draft_preview.sql');
const readerPath = join(ROOT, 'src/pages/governance/document/[id].astro');
const adminDocsPath = join(ROOT, 'src/pages/admin/governance/documents.astro');
const ptPath = join(ROOT, 'src/i18n/pt-BR.ts');
const enPath = join(ROOT, 'src/i18n/en-US.ts');
const esPath = join(ROOT, 'src/i18n/es-LATAM.ts');

const migrationSql = readFileSync(migrationPath, 'utf8');
const readerSrc = readFileSync(readerPath, 'utf8');
const adminDocsSrc = readFileSync(adminDocsPath, 'utf8');
const ptSrc = readFileSync(ptPath, 'utf8');
const enSrc = readFileSync(enPath, 'utf8');
const esSrc = readFileSync(esPath, 'utf8');

describe('#646 governance draft preview', () => {
  it('adds a dedicated SECDEF draft preview RPC with explicit version id', () => {
    assert.match(
      migrationSql,
      /CREATE OR REPLACE FUNCTION public\.get_governance_document_draft_preview\(\s*p_document_id uuid,\s*p_version_id uuid\s*\)/s,
    );
    assert.match(migrationSql, /SECURITY DEFINER/);
    assert.match(migrationSql, /SET search_path TO 'public', 'pg_temp'/);
    assert.match(migrationSql, /dv\.document_id = p_document_id/);
    assert.match(migrationSql, /dv\.locked_at IS NULL/);
  });

  it('gates preview to active members plus narrow governance authority', () => {
    assert.match(migrationSql, /m\.auth_id = auth\.uid\(\)\s+AND m\.is_active = true/s);
    assert.match(migrationSql, /can_by_member\(v_caller_member_id, 'manage_member'\)/);
    assert.match(migrationSql, /can_by_member\(v_caller_member_id, 'participate_in_governance_review'\)/);
    assert.match(migrationSql, /can_by_member\(v_caller_member_id, 'curate_content'\)/);
    assert.match(migrationSql, /preview_gate_eligibles_cache/);
    assert.match(migrationSql, /_can_sign_gate\(v_caller_member_id, NULL, 'curator'/);
  });

  it('keeps legal scoped drafts tighter than generic active-member previews', () => {
    assert.match(migrationSql, /v_doc\.visibility_class = 'legal_scoped'/);
    assert.match(migrationSql, /member_document_signatures mds/);
    assert.match(migrationSql, /mds\.is_current = true/);
    assert.doesNotMatch(
      migrationSql,
      /v_doc\.visibility_class = 'legal_scoped'[\s\S]{0,180}participate_in_governance_review/,
    );
  });

  it('returns only reader-safe draft payload fields', () => {
    const returnBlock = migrationSql.slice(migrationSql.indexOf('RETURN jsonb_build_object('));
    assert.match(returnBlock, /'draft_version'/);
    assert.match(returnBlock, /'content_html'/);
    assert.doesNotMatch(returnBlock, /'content_markdown'|'drive_url'|'pdf_url'|'file_id'|'docusign_envelope_id'|'signatories'/);
  });

  it('revokes public execution and grants authenticated execution only', () => {
    assert.match(
      migrationSql,
      /REVOKE EXECUTE ON FUNCTION public\.get_governance_document_draft_preview\(uuid, uuid\) FROM PUBLIC/,
    );
    assert.match(
      migrationSql,
      /REVOKE EXECUTE ON FUNCTION public\.get_governance_document_draft_preview\(uuid, uuid\) FROM anon/,
    );
    assert.match(
      migrationSql,
      /GRANT\s+EXECUTE ON FUNCTION public\.get_governance_document_draft_preview\(uuid, uuid\) TO authenticated/,
    );
  });

  it('wires /governance/document/[id] preview mode without changing current reader path', () => {
    assert.match(readerSrc, /Astro\.url\.searchParams\.get\('version'\)/);
    assert.match(readerSrc, /PREVIEW_VERSION_ID/);
    assert.match(readerSrc, /get_governance_document_draft_preview/);
    assert.match(readerSrc, /get_governance_document_reader/);
    assert.match(readerSrc, /payload\.draft_version/);
    assert.match(readerSrc, /payload\.current_version/);
    assert.match(readerSrc, /doc-draft-preview-banner/);
    assert.match(readerSrc, /window\.print\(\)/);
    assert.match(readerSrc, /navigator\.clipboard\.writeText\(window\.location\.href\)/);
  });

  it('adds draft preview affordance to the admin drafts list', () => {
    assert.match(adminDocsSrc, /draftsPreviewBtn/);
    assert.match(adminDocsSrc, /\/governance\/document\//);
    assert.match(adminDocsSrc, /\?version=/);
    assert.match(adminDocsSrc, /\/versions\/new\?draft=/);
  });

  it('localizes draft preview strings in all supported locales', () => {
    for (const src of [ptSrc, enSrc, esSrc]) {
      assert.match(src, /'governance\.docs\.draftsPreviewBtn'/);
      assert.match(src, /'governance\.document\.draftPreviewTitle'/);
      assert.match(src, /'governance\.document\.draftPreviewBody'/);
      assert.match(src, /'governance\.document\.printPdfBtn'/);
      assert.match(src, /'governance\.document\.copyLinkBtn'/);
      assert.match(src, /'governance\.document\.copiedLink'/);
    }
  });
});

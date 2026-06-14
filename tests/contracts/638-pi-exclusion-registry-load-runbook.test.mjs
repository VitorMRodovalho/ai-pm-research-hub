import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';

const ROOT = process.cwd();
const runbookPath = join(ROOT, 'docs/legal/638_PI_EXCLUSION_REGISTRY_LOAD_RUNBOOK.md');
const runbook = readFileSync(runbookPath, 'utf8');

describe('#638 PI exclusion registry first-load runbook', () => {
  it('keeps the production load on hold until doc7, G12, and PM scope decisions clear', () => {
    assert.match(runbook, /Status:\*\* HOLD operacional/);
    assert.match(runbook, /nao autoriza executar mutacoes em producao/i);
    assert.match(runbook, /doc7\/termo publicado/);
    assert.match(runbook, /retorno G12\/legal/i);
    assert.match(runbook, /decisao PM sobre escopo de ativos/i);
    assert.match(runbook, /NAO EXECUTAR\*\* `create_exclusion_declaration` ou `register_exclusion_asset`/i);
    assert.match(runbook, /NAO EXECUTAR ANTES DOS GATES/);
  });

  it('records the live empty baseline measured for the registry', () => {
    assert.match(runbook, /Estado live medido em 2026-06-13/);
    assert.match(runbook, /0 declarations \/ 0 assets/);
    assert.match(runbook, /\|\s*0\s*\|\s*0\s*\|\s*0\s*\|\s*0\s*\|/);
  });

  it('uses the existing registry and OTS tool surface without inventing new APIs', () => {
    for (const tool of [
      'create_exclusion_declaration',
      'register_exclusion_asset',
      'get_exclusion_declaration',
      'export_anexo_i',
      'get_ots_pipeline_health',
      'revoke_exclusion_declaration',
    ]) {
      assert.match(runbook, new RegExp(tool));
    }
  });

  it('preserves the ADR-0101 digest-only and confirmed-not-pending rules', () => {
    assert.match(runbook, /digest-only/i);
    assert.match(runbook, /a obra nunca sai do Nucleo/i);
    assert.match(runbook, /sha256sum caminho\/para\/obra\.ext/);
    assert.match(runbook, /\^\[0-9a-f\]\{64\}\$/);
    assert.match(runbook, /pending != confirmed/);
    assert.match(runbook, /all_confirmed=true/);
    assert.match(runbook, /pg_cron.*nao prova HTTP 200/i);
    assert.match(runbook, /stamp_attempts >= 5/);
  });

  it('defines the per-asset metadata required for Anexo I reconciliation', () => {
    for (const field of [
      'title',
      'sha256',
      'nature',
      'author_label',
      'work_created_on',
      'source_ref',
      'reinforcement',
    ]) {
      assert.match(runbook, new RegExp(`\\\`${field}\\\``));
    }
  });

  it('keeps open PM decisions explicit, including platform code and reinforcements', () => {
    assert.match(runbook, /Codigo da plataforma entra como obra pre-existente/);
    assert.match(runbook, /Quais ativos precisam de reforco manual/);
    assert.match(runbook, /Quem e o declarant autorizado/);
    assert.match(runbook, /governance_document_id/);
  });

  it('links the canonical ADR and implementation artifacts', () => {
    assert.match(runbook, /ADR-0101-pi-exclusion-asset-registry-opentimestamps\.md/);
    assert.match(runbook, /20260805000135_p569_pi_exclusion_asset_registry\.sql/);
    assert.match(runbook, /supabase\/functions\/_shared\/ots\.ts/);
    assert.match(runbook, /supabase\/functions\/ots-stamp\/index\.ts/);
    assert.match(runbook, /supabase\/functions\/ots-upgrade\/index\.ts/);
  });
});

import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

const workflow = readFileSync('.github/workflows/release-tag.yml', 'utf8');
const scriptPath = 'scripts/register-release-provenance.mjs';
const script = existsSync(scriptPath) ? readFileSync(scriptPath, 'utf8') : '';
const migrationPath = 'supabase/migrations/20260805000163_639_release_provenance_registry_rpc.sql';
const migration = existsSync(migrationPath) ? readFileSync(migrationPath, 'utf8') : '';

describe('#639 release provenance stamping', () => {
  it('release-tag workflow creates release provenance before tagging/release publication', () => {
    assert.match(workflow, /node scripts\/register-release-provenance\.mjs prepare "\$\{\{ inputs\.version \}\}"/);
    assert.match(workflow, /MANIFEST\.sha256/);
    assert.match(workflow, /release-provenance\.json/);
    assert.match(workflow, /gh release create "v\$\{VERSION\}"/);
    assert.match(workflow, /release-provenance\/MANIFEST\.sha256/);
    assert.match(workflow, /release-provenance\/release-provenance\.json/);
  });

  it('workflow registers the manifest digest into the OTS-backed registry after release creation', () => {
    assert.match(workflow, /RELEASE_PROVENANCE_DECLARATION_ID: \$\{\{ secrets\.RELEASE_PROVENANCE_DECLARATION_ID \}\}/);
    assert.match(workflow, /SUPABASE_SERVICE_ROLE_KEY: \$\{\{ secrets\.SUPABASE_SERVICE_ROLE_KEY \}\}/);
    assert.match(workflow, /node scripts\/register-release-provenance\.mjs register "\$\{\{ inputs\.version \}\}"/);
    assert.match(workflow, /register_release_provenance_asset/);
  });

  it('script generates a git archive, hashes the archive, and hashes MANIFEST.sha256', () => {
    assert.ok(existsSync(scriptPath), 'release provenance script must exist');
    assert.match(script, /git', \['archive'/);
    assert.match(script, /MANIFEST\.sha256/);
    assert.match(script, /archive_sha256/);
    assert.match(script, /manifest_sha256/);
    assert.match(script, /createHash\('sha256'\)/);
  });

  it('script fails closed when registry secrets are missing', () => {
    assert.match(script, /SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for registry mode/);
    assert.match(script, /RELEASE_PROVENANCE_DECLARATION_ID is required for registry mode/);
  });

  it('service-role RPC writes only digest metadata into pi_exclusion_assets', () => {
    assert.ok(existsSync(migrationPath), 'release registry migration must exist');
    assert.match(migration, /CREATE OR REPLACE FUNCTION public\.register_release_provenance_asset/);
    assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.register_release_provenance_asset\(uuid,text,text,text,text,text\) TO service_role/);
    assert.match(migration, /REVOKE ALL ON FUNCTION public\.register_release_provenance_asset\(uuid,text,text,text,text,text\) FROM PUBLIC, anon, authenticated/);
    assert.match(migration, /INSERT INTO public\.pi_exclusion_assets/);
    assert.match(migration, /software-release-manifest/);
    assert.match(migration, /lower\(p_manifest_sha256\)/);
    assert.doesNotMatch(migration, /ots_proof\s*=/, 'workflow must not forge OTS proof bytes');
  });
});

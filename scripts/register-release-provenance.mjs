#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const ROOT = resolve(process.cwd());
const OUT_DIR = resolve(process.env.RELEASE_PROVENANCE_DIR || 'release-provenance');

function fail(message) {
  console.error(`[release-provenance] ${message}`);
  process.exit(1);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: ROOT,
    encoding: 'utf8',
    stdio: options.stdio || 'pipe',
  });
  if (result.status !== 0) {
    const stderr = result.stderr ? `\n${result.stderr.trim()}` : '';
    fail(`${command} ${args.join(' ')} failed${stderr}`);
  }
  return (result.stdout || '').trim();
}

function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function requireVersion(raw) {
  const version = String(raw || '').trim().replace(/^v/, '');
  if (!/^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9]+)?(?:\+[a-z0-9]+)?$/.test(version)) {
    fail(`invalid semver: ${raw || '(empty)'}`);
  }
  return version;
}

async function rpc(path, payload) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceKey) {
    fail('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for registry mode');
  }

  const url = `${supabaseUrl.replace(/\/$/, '')}/rest/v1/rpc/${path}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  if (!response.ok) {
    fail(`${path} RPC failed (${response.status}): ${text}`);
  }
  return text ? JSON.parse(text) : null;
}

function prepare(version) {
  mkdirSync(OUT_DIR, { recursive: true });

  const tag = `v${version}`;
  const commit = run('git', ['rev-parse', 'HEAD']);
  const shortCommit = commit.slice(0, 12);
  const archivePath = join(OUT_DIR, `ai-pm-research-hub-${tag}-${shortCommit}.tar.gz`);
  const manifestPath = join(OUT_DIR, 'MANIFEST.sha256');
  const metadataPath = join(OUT_DIR, 'release-provenance.json');

  run('git', ['archive', '--format=tar.gz', `--prefix=ai-pm-research-hub-${tag}/`, '-o', archivePath, 'HEAD']);

  const archiveSha = sha256File(archivePath);
  const manifest = [
    `# AI & PM Research Hub release provenance manifest`,
    `# version: ${tag}`,
    `# commit: ${commit}`,
    `# generated_by: scripts/register-release-provenance.mjs`,
    `${archiveSha}  ${basename(archivePath)}`,
    '',
  ].join('\n');
  writeFileSync(manifestPath, manifest);

  const manifestSha = sha256File(manifestPath);
  writeFileSync(metadataPath, JSON.stringify({
    version: tag,
    commit,
    archive: basename(archivePath),
    archive_sha256: archiveSha,
    manifest: basename(manifestPath),
    manifest_sha256: manifestSha,
  }, null, 2) + '\n');

  console.log(`[release-provenance] archive=${archivePath}`);
  console.log(`[release-provenance] archive_sha256=${archiveSha}`);
  console.log(`[release-provenance] manifest=${manifestPath}`);
  console.log(`[release-provenance] manifest_sha256=${manifestSha}`);
}

async function register(version) {
  const declarationId = process.env.RELEASE_PROVENANCE_DECLARATION_ID;
  if (!declarationId) {
    fail('RELEASE_PROVENANCE_DECLARATION_ID is required for registry mode');
  }

  const metadataPath = join(OUT_DIR, 'release-provenance.json');
  if (!existsSync(metadataPath)) {
    fail(`${metadataPath} not found; run prepare first`);
  }
  const metadata = JSON.parse(readFileSync(metadataPath, 'utf8'));
  const expectedTag = `v${version}`;
  if (metadata.version !== expectedTag) {
    fail(`metadata version ${metadata.version} does not match ${expectedTag}`);
  }

  const assetId = await rpc('register_release_provenance_asset', {
    p_declaration_id: declarationId,
    p_version: metadata.version,
    p_commit_sha: metadata.commit,
    p_manifest_sha256: metadata.manifest_sha256,
    p_archive_sha256: metadata.archive_sha256,
    p_source_ref: `${process.env.GITHUB_SERVER_URL || 'https://github.com'}/${process.env.GITHUB_REPOSITORY || 'VitorMRodovalho/ai-pm-research-hub'}/releases/tag/${metadata.version}`,
  });
  console.log(`[release-provenance] registry_asset_id=${assetId}`);
}

const [mode, rawVersion] = process.argv.slice(2);
const version = requireVersion(rawVersion || process.env.RELEASE_VERSION);

if (mode === 'prepare') {
  prepare(version);
} else if (mode === 'register') {
  await register(version);
} else {
  fail('usage: node scripts/register-release-provenance.mjs <prepare|register> <version>');
}

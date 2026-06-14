import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, it } from 'node:test';

const ROOT = process.cwd();
const licensePath = join(ROOT, 'LICENSE');
const docsLicensePath = join(ROOT, 'LICENSE-docs');
const readmePath = join(ROOT, 'README.md');

const license = existsSync(licensePath) ? readFileSync(licensePath, 'utf8') : '';
const docsLicense = existsSync(docsLicensePath) ? readFileSync(docsLicensePath, 'utf8') : '';
const readme = existsSync(readmePath) ? readFileSync(readmePath, 'utf8') : '';

describe('#640 repository dual-license contract', () => {
  it('ships the MIT code license at repository root', () => {
    assert.ok(existsSync(licensePath), 'LICENSE must exist');
    assert.match(license, /^MIT License/m);
    assert.match(license, /Copyright \(c\) 2026 Vitor Maia Rodovalho/);
    assert.match(license, /Permission is hereby granted, free of charge/);
    assert.match(license, /THE SOFTWARE IS PROVIDED "AS IS"/);
  });

  it('ships a CC BY-SA 4.0 docs license notice at repository root', () => {
    assert.ok(existsSync(docsLicensePath), 'LICENSE-docs must exist');
    assert.match(docsLicense, /Creative Commons Attribution-ShareAlike 4\.0 International/);
    assert.match(docsLicense, /SPDX-License-Identifier: CC-BY-SA-4\.0/);
    assert.match(docsLicense, /https:\/\/creativecommons\.org\/licenses\/by-sa\/4\.0\/legalcode/);
    assert.match(docsLicense, /documentation and other\s+non-code written materials/i);
  });

  it('keeps the README badges and License section aligned with the split', () => {
    assert.match(readme, /\[!\[License: MIT\][^\n]+\]\(LICENSE\)/);
    assert.match(readme, /\[!\[License: CC BY-SA 4\.0\][^\n]+\]\(LICENSE-docs\)/);
    assert.match(readme, /\*\*Source code\*\* is licensed under the \[MIT License\]\(LICENSE\)/);
    assert.match(readme, /\*\*Documentation and other non-code written materials\*\* are licensed under\s+\[Creative Commons Attribution-ShareAlike 4\.0 International\]\(LICENSE-docs\)/);
    assert.match(readme, /Third-party trademarks, logos, credentials, personal data, private operational records/);
  });

  it('does not claim PMI marks or private data are covered by the repository-level grants', () => {
    assert.match(docsLicense, /does not grant rights in third-party trademarks, logos/);
    assert.match(docsLicense, /personal data, credentials, private operational records/);
    assert.match(readme, /PMI.*registered marks of the Project Management Institute/);
  });
});

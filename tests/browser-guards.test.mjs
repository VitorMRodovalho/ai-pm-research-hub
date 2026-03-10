import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { chromium } from 'playwright';

const PORT = Number(process.env.BROWSER_TEST_PORT || (4700 + Math.floor(Math.random() * 200)));
const BASE = `http://127.0.0.1:${PORT}`;
const START_TIMEOUT_MS = 45_000;

let devServer;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForServer() {
  const startedAt = Date.now();
  while (Date.now() - startedAt < START_TIMEOUT_MS) {
    try {
      const res = await fetch(`${BASE}/`, { redirect: 'manual' });
      if (res.status >= 200 && res.status < 500) return;
    } catch {
      // retry until server becomes available
    }
    await sleep(500);
  }
  throw new Error(`Server did not start within ${START_TIMEOUT_MS}ms`);
}

async function run() {
  devServer = spawn(
    'npm',
    ['run', 'dev', '--', '--host', '127.0.0.1', '--port', String(PORT)],
    { stdio: 'inherit', shell: false }
  );
  await waitForServer();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(`${BASE}/admin/selection`, { waitUntil: 'networkidle' });
    const denied = page.locator('#sel-denied');
    await denied.waitFor({ state: 'visible' });
    assert.match(await denied.textContent() || '', /Acesso restrito a administradores/);
    assert.equal(await page.locator('#sel-panel').isVisible(), false);
    await page.close();
    console.log('Browser ACL guard test passed.');
  } finally {
    await browser.close();
    devServer?.kill('SIGTERM');
  }
}

run().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});

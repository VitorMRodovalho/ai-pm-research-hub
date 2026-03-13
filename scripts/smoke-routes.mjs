import { spawn } from 'node:child_process';

const PORT = Number(process.env.SMOKE_PORT || (4300 + Math.floor(Math.random() * 400)));
const BASE = `http://127.0.0.1:${PORT}`;
const START_TIMEOUT_MS = 45_000;

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
      // keep polling until timeout
    }
    await sleep(500);
  }
  throw new Error(`Server did not start within ${START_TIMEOUT_MS}ms`);
}

async function assertOk(path) {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) {
    throw new Error(`Expected ${path} to return 2xx, got ${res.status}`);
  }
}

async function assertRedirect(path, expectedLocation) {
  const res = await fetch(`${BASE}${path}`, { redirect: 'manual' });
  if (!(res.status >= 300 && res.status < 400)) {
    throw new Error(`Expected ${path} to redirect, got ${res.status}`);
  }
  const location = res.headers.get('location');
  if (location !== expectedLocation) {
    throw new Error(`Expected ${path} redirect to ${expectedLocation}, got ${location || '(none)'}`);
  }
}

async function assertContains(path, fragment) {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) {
    throw new Error(`Expected ${path} to return 2xx for content check, got ${res.status}`);
  }
  const body = await res.text();
  if (!body.includes(fragment)) {
    throw new Error(`Expected ${path} to contain "${fragment}"`);
  }
}

async function run() {
  const dev = spawn(
    'npm',
    ['run', 'dev', '--', '--host', '127.0.0.1', '--port', String(PORT)],
    { stdio: 'inherit', shell: false }
  );

  try {
    await waitForServer();

    await assertOk('/');
    await assertOk('/attendance');
    await assertOk('/gamification');
    await assertOk('/artifacts');
    await assertOk('/profile');
    await assertOk('/help');
    await assertOk('/admin');
    await assertOk('/admin/curatorship');
    await assertOk('/admin/analytics');
    await assertOk('/admin/portfolio');
    await assertOk('/admin/cycle-report');
    await assertOk('/admin/governance-v2');
    await assertOk('/admin/comms-ops');
    await assertOk('/admin/selection');
    await assertOk('/admin/comms');
    await assertOk('/admin/webinars');
    await assertOk('/admin/partnerships');
    await assertOk('/admin/sustainability');
    await assertOk('/publications');
    await assertOk('/projects');
    await assertOk('/en');
    await assertOk('/es');

    await assertOk('/teams');
    await assertOk('/workspace');
    await assertOk('/en/workspace');
    await assertOk('/es/workspace');
    await assertContains('/admin/selection', 'id="sel-denied"');
    await assertContains('/admin/analytics', 'id="analytics-denied"');
    await assertContains('/admin/curatorship', 'id="cur-denied"');
    await assertContains('/admin/comms', 'id="comms-denied"');
    await assertContains('/admin/portfolio', 'id="portfolio-denied"');
    await assertContains('/admin/governance-v2', 'id="boardgov-denied"');
    await assertContains('/admin/comms-ops', 'id="commsops-denied"');
    await assertContains('/admin/partnerships', 'id="partnerships-denied"');
    await assertContains('/admin/sustainability', 'id="sust-denied"');
    await assertContains('/webinars', 'id="webinars-denied"');
    await assertContains('/tribe/1', 'id="tribe-denied"');
    await assertRedirect('/rank', '/gamification');
    await assertRedirect('/ranks', '/gamification');

    console.log('Route smoke tests passed.');
  } finally {
    dev.kill('SIGTERM');
  }
}

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});

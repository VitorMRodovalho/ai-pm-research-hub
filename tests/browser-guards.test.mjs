import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { chromium } from 'playwright';

const START_TIMEOUT_MS = 45_000;

let devServer;
let port = Number(process.env.BROWSER_TEST_PORT || 0);
let base = '';

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function resolveAvailablePort(preferredPort) {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.unref();
    server.on('error', reject);
    server.listen(preferredPort, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close(() => reject(new Error('Could not resolve browser test port')));
        return;
      }
      const nextPort = address.port;
      server.close((error) => {
        if (error) reject(error);
        else resolve(nextPort);
      });
    });
  });
}

async function waitForServer() {
  const startedAt = Date.now();
  while (Date.now() - startedAt < START_TIMEOUT_MS) {
    try {
      const res = await fetch(`${base}/`, { redirect: 'manual' });
      if (res.status >= 200 && res.status < 500) return;
    } catch {
      // retry until server becomes available
    }
    await sleep(500);
  }
  throw new Error(`Server did not start within ${START_TIMEOUT_MS}ms`);
}

async function run() {
  port = await resolveAvailablePort(port || 0);
  base = `http://127.0.0.1:${port}`;
  devServer = spawn(
    'npm',
    ['run', 'dev', '--', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
    { stdio: 'inherit', shell: false }
  );
  await waitForServer();
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(`${base}/admin/selection`, { waitUntil: 'networkidle' });
    const denied = page.locator('#sel-denied');
    await denied.waitFor({ state: 'visible' });
    assert.match(await denied.textContent() || '', /Acesso restrito a administradores/);
    assert.equal(await page.locator('#sel-panel').isVisible(), false);

    await page.goto(`${base}/`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1800);
    assert.equal(await page.locator('#hero-cycle-status').isVisible(), true);
    assert.equal(await page.locator('#hero-countdown-area').isVisible(), false);
    assert.match(await page.locator('#hero-event-area').textContent() || '', /Kick-off|Gravação|Recording|Google Meet|Meet/);
    const tribesState = page.locator('#tribes-selection-state');
    const tribesDeadline = page.locator('#tribes-deadline-badge');
    const tribesNotice = page.locator('#tribes-selection-notice');
    await tribesState.waitFor({ state: 'visible' });
    await tribesDeadline.waitFor({ state: 'visible' });
    await tribesNotice.waitFor({ state: 'visible' });
    assert.match(await tribesState.textContent() || '', /SELEÇÃO ABERTA|SELEÇÃO ENCERRADA|CRONOGRAMA PENDENTE/);
    assert.equal(((await tribesDeadline.textContent()) || '').trim().length > 0, true);
    assert.equal(((await tribesNotice.textContent()) || '').trim().length > 0, true);
    assert.equal(((await tribesDeadline.textContent()) || '').includes('Encerra Sáb 08/Mar 12h BRT'), false);
    assert.equal(await page.locator('#loginPrompt').isVisible(), true);

    await page.goto(`${base}/admin/webinars`, { waitUntil: 'networkidle' });
    const webinarsDenied = page.locator('#webinars-denied');
    await webinarsDenied.waitFor({ state: 'visible' });
    assert.match(await webinarsDenied.textContent() || '', /Acesso restrito a administradores/);
    assert.equal(await page.locator('#webinars-content').isVisible(), false);

    await page.goto(`${base}/admin/webinars`, { waitUntil: 'networkidle' });
    await page.evaluate(() => {
      const fakeMember = {
        auth_id: 'admin-browser-test',
        operational_role: 'manager',
        designations: [],
        is_superadmin: false,
        name: 'Admin Browser',
      };
      const fakeEvents = [
        {
          id: 'webinar-past-1',
          type: 'webinar',
          title: 'AI Delivery Review',
          date: '2026-03-01',
          duration_minutes: 90,
          attendee_count: 12,
          is_recorded: true,
          youtube_url: 'https://youtube.com/watch?v=webinar1',
          meeting_link: null,
          audience_level: 'leadership',
        },
        {
          id: 'webinar-future-1',
          type: 'webinar',
          title: 'Autonomous Agents Deep Dive',
          date: '2099-04-20',
          duration_minutes: 60,
          attendee_count: 0,
          is_recorded: false,
          youtube_url: null,
          meeting_link: 'https://meet.google.com/future-webinar',
          audience_level: 'all',
        },
        {
          id: 'webinar-past-2',
          type: 'webinar',
          title: 'Research Ops Retrospective',
          date: '2026-02-20',
          duration_minutes: 75,
          attendee_count: 8,
          is_recorded: true,
          youtube_url: 'https://youtube.com/watch?v=webinar2',
          meeting_link: null,
          audience_level: 'tribe',
        },
      ];
      const fakeArtifacts = [
        {
          id: 'artifact-1',
          event_id: 'webinar-past-1',
          title: 'AI Delivery Review',
          meeting_date: '2026-03-01',
          recording_url: 'https://youtube.com/watch?v=webinar1',
          tribe_id: null,
        },
      ];
      const fakeResources = [
        {
          id: 'resource-1',
          asset_type: 'webinar',
          title: 'AI Delivery Review',
          tribe_id: null,
          url: 'https://youtube.com/watch?v=webinar1',
          is_active: true,
        },
      ];
      const fakeSb = {
        rpc(name) {
          if (name === 'get_events_with_attendance') return Promise.resolve({ data: fakeEvents, error: null });
          if (name === 'list_meeting_artifacts') return Promise.resolve({ data: fakeArtifacts, error: null });
          return Promise.resolve({ data: [], error: null });
        },
        from(table) {
          if (table === 'hub_resources') {
            return {
              select() { return this; },
              eq() { return this; },
              order() { return Promise.resolve({ data: fakeResources, error: null }); },
            };
          }
          return {
            select() { return this; },
            eq() { return this; },
            order() { return Promise.resolve({ data: [], error: null }); },
          };
        },
      };
      window.navGetMember = () => fakeMember;
      window.navGetSb = () => fakeSb;
      window.dispatchEvent(new CustomEvent('nav:member', { detail: fakeMember }));
    });
    await page.locator('#webinars-content').waitFor({ state: 'visible' });
    assert.equal(await page.locator('#webinars-denied').isVisible(), false);
    assert.match(await page.locator('#webinars-publication').textContent() || '', /Presentations: publicado/);
    assert.match(await page.locator('#webinars-publication').textContent() || '', /Workspace: publicado/);
    assert.match(await page.locator('#webinars-publication').textContent() || '', /Workspace: pendente/);
    assert.match(await page.locator('#webinars-upcoming').textContent() || '', /Autonomous Agents Deep Dive/);
    assert.match(await page.locator('#webinars-followup').textContent() || '', /AI Delivery Review|Research Ops Retrospective/);

    await page.close();
    console.log('Browser guard, home runtime, and webinars admin test passed.');
  } finally {
    await browser.close();
    devServer?.kill('SIGTERM');
  }
}

run().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});

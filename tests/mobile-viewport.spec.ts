/**
 * W128 Mobile Viewport Tests
 * Verifies critical pages render without horizontal overflow on mobile (375px)
 * and admin pages render without overflow on tablet (768px).
 *
 * These are Playwright tests — run with: npx playwright test tests/mobile-viewport.spec.ts
 * They require a running dev server or deployed environment.
 */
import { test, expect } from '@playwright/test';

const MOBILE_VIEWPORT = { width: 375, height: 812 };
const TABLET_VIEWPORT = { width: 768, height: 1024 };

const BASE = process.env.TEST_BASE_URL || 'http://localhost:4321';

const CRITICAL_PAGES = [
  '/',
  '/about',
  '/privacy',
  '/workspace',
  '/attendance',
  '/profile',
  '/tribes',
  '/help',
];

const ADMIN_PAGES = [
  '/admin/tribes',
  '/admin/partnerships',
  '/admin/cycle-report',
];

for (const page of CRITICAL_PAGES) {
  test(`Mobile (375px): ${page} renders without horizontal overflow`, async ({ browser }) => {
    const context = await browser.newContext({ viewport: MOBILE_VIEWPORT });
    const p = await context.newPage();
    await p.goto(`${BASE}${page}`, { waitUntil: 'domcontentloaded', timeout: 15000 });

    const scrollWidth = await p.evaluate(() => document.documentElement.scrollWidth);
    const clientWidth = await p.evaluate(() => document.documentElement.clientWidth);
    expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 5);

    await context.close();
  });
}

for (const page of ADMIN_PAGES) {
  test(`Tablet (768px): ${page} renders without horizontal overflow`, async ({ browser }) => {
    const context = await browser.newContext({ viewport: TABLET_VIEWPORT });
    const p = await context.newPage();
    await p.goto(`${BASE}${page}`, { waitUntil: 'domcontentloaded', timeout: 15000 });

    const scrollWidth = await p.evaluate(() => document.documentElement.scrollWidth);
    const clientWidth = await p.evaluate(() => document.documentElement.clientWidth);
    expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 5);

    await context.close();
  });
}

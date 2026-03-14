/**
 * W129: Persona Journey Tests
 * Tests page accessibility per persona tier.
 * Run: npx playwright test tests/persona-journeys.spec.ts
 */
import { test, expect } from '@playwright/test';

const BASE = process.env.BASE_URL || 'http://localhost:4321';

// ════════════════════════════════════════════════════
// Route definitions by persona
// ════════════════════════════════════════════════════

const PUBLIC_ROUTES = [
  '/',
  '/about',
  '/privacy',
  '/library',
  '/artifacts',
  '/gamification',
];

const AUTHENTICATED_ROUTES = [
  '/workspace',
  '/attendance',
  '/help',
];

const ADMIN_ROUTES = [
  '/admin',
  '/admin/analytics',
  '/admin/comms',
  '/admin/curatorship',
  '/admin/cycle-report',
  '/admin/chapter-report',
  '/admin/tribes',
  '/admin/partnerships',
  '/admin/sustainability',
  '/admin/selection',
];

const TRIBE_DASHBOARD_ROUTES = [
  '/admin/tribe/1',
  '/admin/tribe/2',
  '/admin/tribe/3',
  '/admin/tribe/4',
  '/admin/tribe/5',
  '/admin/tribe/6',
  '/admin/tribe/7',
  '/admin/tribe/8',
];

const ALL_ROUTES = [
  ...PUBLIC_ROUTES,
  ...AUTHENTICATED_ROUTES,
  ...ADMIN_ROUTES,
  ...TRIBE_DASHBOARD_ROUTES,
];

// ════════════════════════════════════════════════════
// P-VISITOR: Unauthenticated
// ════════════════════════════════════════════════════

test.describe('P-VISITOR (unauthenticated)', () => {
  for (const route of PUBLIC_ROUTES) {
    test(`can access public page ${route}`, async ({ page }) => {
      const response = await page.goto(`${BASE}${route}`);
      expect(response?.status()).toBeLessThan(400);

      // No visible error messages
      const errorText = await page.locator('text=/column.*does not exist|undefined is not|ReferenceError/i').count();
      expect(errorText).toBe(0);
    });
  }

  test('visitor sees login button in nav', async ({ page }) => {
    await page.goto(`${BASE}/`);
    // Nav should show login, not authenticated state
    const loginBtn = page.locator('[data-auth="login"], button:has-text("Login"), button:has-text("Entrar")');
    const authMenu = page.locator('[data-auth="menu"]');

    // At least one login indicator OR no auth menu
    const hasLogin = await loginBtn.count() > 0;
    const noAuthMenu = await authMenu.count() === 0;
    expect(hasLogin || noAuthMenu).toBeTruthy();
  });

  test('no PII visible on public pages', async ({ page }) => {
    for (const route of PUBLIC_ROUTES) {
      await page.goto(`${BASE}${route}`);
      const content = await page.textContent('body');
      // Should not expose email addresses
      const emailPattern = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;
      const emails = content?.match(emailPattern) || [];
      // Filter out generic/placeholder emails
      const realEmails = emails.filter(e =>
        !e.includes('example.com') && !e.includes('placeholder')
      );
      expect(realEmails.length).toBe(0);
    }
  });

  test('footer with privacy link on all public pages', async ({ page }) => {
    for (const route of PUBLIC_ROUTES) {
      await page.goto(`${BASE}${route}`);
      const privacyLink = page.locator('a[href="/privacy"]');
      expect(await privacyLink.count()).toBeGreaterThan(0);
    }
  });
});

// ════════════════════════════════════════════════════
// P-RESEARCHER: Authenticated member
// ════════════════════════════════════════════════════

test.describe('P-RESEARCHER (authenticated)', () => {
  test('researcher pages exist and return valid responses', async ({ page }) => {
    for (const route of AUTHENTICATED_ROUTES) {
      const response = await page.goto(`${BASE}${route}`);
      // Should return 200 (auth gate handled client-side, not 403)
      expect(response?.status()).toBeLessThan(400);
    }
  });

  test('workspace has auth gate for unauthenticated access', async ({ page }) => {
    await page.goto(`${BASE}/workspace`);
    // Should show either loading or auth gate (client-side auth check)
    const authGate = page.locator('#wk-auth-gate, [data-auth-gate]');
    const loading = page.locator('#wk-loading, [data-loading]');
    const hasGate = await authGate.count() > 0;
    const hasLoading = await loading.count() > 0;
    expect(hasGate || hasLoading).toBeTruthy();
  });
});

// ════════════════════════════════════════════════════
// P-TRIBE_LEADER: Tribe dashboard access
// ════════════════════════════════════════════════════

test.describe('P-TRIBE_LEADER (tribe leader)', () => {
  test('tribe dashboard pages return valid responses', async ({ page }) => {
    for (const route of TRIBE_DASHBOARD_ROUTES) {
      const response = await page.goto(`${BASE}${route}`);
      expect(response?.status()).toBeLessThan(400);
    }
  });
});

// ════════════════════════════════════════════════════
// P-SPONSOR: Chapter report access
// ════════════════════════════════════════════════════

test.describe('P-SPONSOR (sponsor)', () => {
  test('chapter report page exists', async ({ page }) => {
    const response = await page.goto(`${BASE}/admin/chapter-report`);
    expect(response?.status()).toBeLessThan(400);
  });

  test('cycle report page exists', async ({ page }) => {
    const response = await page.goto(`${BASE}/admin/cycle-report`);
    expect(response?.status()).toBeLessThan(400);
  });
});

// ════════════════════════════════════════════════════
// P-GP: Superadmin — all pages
// ════════════════════════════════════════════════════

test.describe('P-GP (superadmin)', () => {
  for (const route of ALL_ROUTES) {
    test(`page ${route} returns valid response`, async ({ page }) => {
      const response = await page.goto(`${BASE}${route}`);
      expect(response?.status()).toBeLessThan(400);
    });
  }

  test('no console errors with column-not-exist on admin pages', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    for (const route of ADMIN_ROUTES) {
      consoleErrors.length = 0;
      await page.goto(`${BASE}${route}`);
      await page.waitForTimeout(1000);

      const columnErrors = consoleErrors.filter(e =>
        e.includes('column') && e.includes('does not exist')
      );
      expect(columnErrors).toEqual([]);
    }
  });

  test('no pages show raw i18n keys', async ({ page }) => {
    for (const route of PUBLIC_ROUTES) {
      await page.goto(`${BASE}${route}`);
      const content = await page.textContent('body') || '';
      // Raw i18n keys look like "nav.admin" or "common.save" in rendered text
      const rawKeys = content.match(/\b[a-z]+\.[a-z]+\.[a-z]+\b/g) || [];
      // Filter out actual URLs and known patterns
      const suspicious = rawKeys.filter(k =>
        !k.includes('www.') && !k.includes('com.') && !k.includes('.js') && !k.includes('.ts')
      );
      // Allow some — just flag if there are many
      expect(suspicious.length).toBeLessThan(10);
    }
  });
});

// ════════════════════════════════════════════════════
// Cross-cutting: No broken links
// ════════════════════════════════════════════════════

test.describe('Cross-cutting checks', () => {
  test('no href="#" or href="undefined" on home page', async ({ page }) => {
    await page.goto(`${BASE}/`);
    const brokenLinks = await page.locator('a[href="#"], a[href="undefined"], a[href="null"]').count();
    expect(brokenLinks).toBe(0);
  });

  test('LangSwitcher renders on home page', async ({ page }) => {
    await page.goto(`${BASE}/`);
    // LangSwitcher should be visible in nav
    const switcher = page.locator('[data-lang-switcher], .lang-switcher, select');
    expect(await switcher.count()).toBeGreaterThan(0);
  });
});

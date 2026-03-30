import { test, expect } from '@playwright/test';

test('teams page loads', async ({ page }) => {
  const resp = await page.goto('/teams');
  expect(resp?.status()).toBeLessThan(400);
  await expect(page.locator('h1')).toContainText(/Projetos|Teams/i);
});

test('teams page has section structure', async ({ page }) => {
  await page.goto('/teams');
  // Should have loading state or shell with sections
  const hasLoading = await page.locator('#teams-loading').isVisible().catch(() => false);
  const hasShell = await page.locator('#teams-shell').isVisible().catch(() => false);
  const hasDenied = await page.locator('#teams-denied').isVisible().catch(() => false);
  expect(hasLoading || hasShell || hasDenied).toBeTruthy();
});

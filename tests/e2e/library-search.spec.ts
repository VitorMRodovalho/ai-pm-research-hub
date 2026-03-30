import { test, expect } from '@playwright/test';

test('library page loads and has search input', async ({ page }) => {
  await page.goto('/library');
  await page.waitForTimeout(1000);
  const searchInput = page.locator('#ws-search');
  await expect(searchInput).toBeVisible();
});

test('library page has type filter buttons', async ({ page }) => {
  await page.goto('/library');
  await page.waitForTimeout(1000);
  const filterBtns = page.locator('.ws-type-filter');
  expect(await filterBtns.count()).toBeGreaterThanOrEqual(4);
});

test('library page has tribe filter select', async ({ page }) => {
  await page.goto('/library');
  const tribeFilter = page.locator('#ws-tribe-filter');
  await expect(tribeFilter).toBeVisible();
});

import { test, expect } from '@playwright/test';

test('homepage loads without auth', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/Núcleo|Hub/);
  await expect(page.locator('text=/Ciclo|Cycle/')).toBeVisible();
  expect(await page.locator('.error, [data-error]').count()).toBe(0);
});

test('homepage has navigation', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('nav')).toBeVisible();
});

test('homepage KPI section renders', async ({ page }) => {
  await page.goto('/');
  await page.waitForTimeout(2000);
  expect(await page.locator('text=/[0-9]+/').count()).toBeGreaterThan(3);
});

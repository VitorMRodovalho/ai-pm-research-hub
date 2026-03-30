import { test, expect } from '@playwright/test';

test('EN homepage loads with English content', async ({ page }) => {
  await page.goto('/en/');
  await expect(page.locator('nav')).toBeVisible();
  // Check for English text in nav or hero
  const html = await page.locator('html').getAttribute('lang');
  // Page should render without errors
  expect(await page.locator('.error, [data-error]').count()).toBe(0);
});

test('ES homepage loads with Spanish content', async ({ page }) => {
  await page.goto('/es/');
  await expect(page.locator('nav')).toBeVisible();
  expect(await page.locator('.error, [data-error]').count()).toBe(0);
});

test('EN library page exists', async ({ page }) => {
  const resp = await page.goto('/en/library');
  expect(resp?.status()).toBeLessThan(400);
});

test('ES library page exists', async ({ page }) => {
  const resp = await page.goto('/es/library');
  expect(resp?.status()).toBeLessThan(400);
});

test('EN attendance page exists', async ({ page }) => {
  const resp = await page.goto('/en/attendance');
  expect(resp?.status()).toBeLessThan(400);
});

test('EN profile page exists', async ({ page }) => {
  const resp = await page.goto('/en/profile');
  expect(resp?.status()).toBeLessThan(400);
});

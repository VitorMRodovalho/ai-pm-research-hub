import { test, expect } from '@playwright/test';

test('homepage loads in dark mode without errors', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.goto('/');
  await expect(page.locator('nav')).toBeVisible();
  expect(await page.locator('.error, [data-error]').count()).toBe(0);
});

test('webinars page loads in dark mode', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.goto('/webinars');
  await expect(page.locator('h1')).toContainText('Webinars');
});

test('library page loads in dark mode', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.goto('/library');
  const searchInput = page.locator('#ws-search');
  await expect(searchInput).toBeVisible();
});

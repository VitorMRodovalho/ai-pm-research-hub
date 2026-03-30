import { test, expect, devices } from '@playwright/test';

test.use({ ...devices['iPhone 13'] });

test('homepage loads on mobile', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('nav')).toBeVisible();
  // Stats section should use 2-column grid on mobile
  const statsSection = page.locator('#platform-stats');
  await expect(statsSection).toBeVisible();
});

test('webinars page loads on mobile', async ({ page }) => {
  await page.goto('/webinars');
  await expect(page.locator('h1')).toContainText('Webinars');
});

test('library page loads on mobile', async ({ page }) => {
  await page.goto('/library');
  const searchInput = page.locator('#ws-search');
  await expect(searchInput).toBeVisible();
});

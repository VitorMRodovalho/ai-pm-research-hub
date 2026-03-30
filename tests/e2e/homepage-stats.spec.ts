import { test, expect } from '@playwright/test';

test('homepage stats section renders with placeholders', async ({ page }) => {
  await page.goto('/');
  const statsSection = page.locator('#platform-stats');
  await expect(statsSection).toBeVisible();
  // Should have 6 stat cards
  const cards = statsSection.locator('.stat-card');
  await expect(cards).toHaveCount(6);
});

test('homepage stats section has correct IDs', async ({ page }) => {
  await page.goto('/');
  for (const id of ['stat-members', 'stat-tribes', 'stat-chapters', 'stat-events', 'stat-resources', 'stat-retention']) {
    await expect(page.locator(`#${id}`)).toBeVisible();
  }
});

test('EN homepage has stats section with English title', async ({ page }) => {
  await page.goto('/en/');
  const statsSection = page.locator('#platform-stats');
  await expect(statsSection).toBeVisible();
  await expect(statsSection).toContainText(/platform in numbers/i);
});

test('ES homepage has stats section with Spanish title', async ({ page }) => {
  await page.goto('/es/');
  const statsSection = page.locator('#platform-stats');
  await expect(statsSection).toBeVisible();
  await expect(statsSection).toContainText(/plataforma en números/i);
});

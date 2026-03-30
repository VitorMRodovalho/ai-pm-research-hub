import { test, expect } from '@playwright/test';

test('public webinars page loads without auth', async ({ page }) => {
  await page.goto('/webinars');
  await expect(page).toHaveTitle(/Webinar/i);
  await expect(page.locator('h1')).toContainText('Webinars');
});

test('webinars page has upcoming and replay sections', async ({ page }) => {
  await page.goto('/webinars');
  // Page should have either upcoming section, replay section, or empty state
  await page.waitForTimeout(3000);
  const hasUpcoming = await page.locator('#webinars-upcoming-section').isVisible().catch(() => false);
  const hasPast = await page.locator('#webinars-past-section').isVisible().catch(() => false);
  const hasEmpty = await page.locator('#webinars-empty').isVisible().catch(() => false);
  expect(hasUpcoming || hasPast || hasEmpty).toBeTruthy();
});

test('webinars page has no console errors', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
  await page.goto('/webinars');
  await page.waitForTimeout(3000);
  // Filter out known non-critical errors (favicon, etc)
  const critical = errors.filter(e => !e.includes('favicon') && !e.includes('404'));
  expect(critical.length).toBe(0);
});

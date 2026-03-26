import { test, expect } from '@playwright/test';

test('governance page loads publicly', async ({ page }) => {
  await page.goto('/governance');
  await expect(page.locator('body')).toBeVisible();
  await page.waitForTimeout(3000);
  const hasContent = await page.locator('text=/manual|governança|governance|change request/i').count();
  expect(hasContent).toBeGreaterThan(0);
});

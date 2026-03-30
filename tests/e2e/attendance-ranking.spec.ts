import { test, expect } from '@playwright/test';

test('attendance page has ranking role filter', async ({ page }) => {
  await page.goto('/attendance');
  await page.waitForTimeout(1000);
  const roleFilter = page.locator('#ranking-role-filter');
  await expect(roleFilter).toBeVisible();
  // Should have at least 6 options (all + 5 roles)
  const options = roleFilter.locator('option');
  expect(await options.count()).toBeGreaterThanOrEqual(6);
});

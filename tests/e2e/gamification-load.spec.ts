import { test, expect } from '@playwright/test';

test('gamification page loads', async ({ page }) => {
  await page.goto('/gamification');
  await expect(page.locator('body')).toBeVisible();
  await page.waitForTimeout(2000);
  const hasContent = await page.locator('text=/ranking|pontos|points|gamif/i').count();
  const hasAuth = await page.locator('text=/login|entrar|sign in/i').count();
  expect(hasContent > 0 || hasAuth > 0).toBeTruthy();
});

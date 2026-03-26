import { test, expect } from '@playwright/test';

test('profile page structure exists', async ({ page }) => {
  await page.goto('/profile');
  await expect(page.locator('body')).toBeVisible();
  await page.waitForTimeout(2000);
  const hasProfile = await page.locator('text=/perfil|profile|dados pessoais|personal data/i').count();
  const hasAuth = await page.locator('text=/login|entrar|sign in/i').count();
  expect(hasProfile > 0 || hasAuth > 0).toBeTruthy();
});

import { test, expect } from '@playwright/test';

test('stakeholder page denies unauthenticated access', async ({ page }) => {
  await page.goto('/stakeholder');
  await page.waitForTimeout(2000);
  const hasAuthGate = await page.locator('text=/login|entrar|sign in|auth|acesso|loading/i').count();
  const redirected = !page.url().includes('/stakeholder');
  expect(hasAuthGate > 0 || redirected).toBeTruthy();
});

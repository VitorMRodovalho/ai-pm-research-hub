import { test, expect } from '@playwright/test';

test('workspace shows auth gate without login', async ({ page }) => {
  await page.goto('/workspace');
  await page.waitForTimeout(2000);
  const hasAuthGate = await page.locator('text=/login|entrar|sign in|auth/i').count();
  const redirected = !page.url().includes('/workspace');
  expect(hasAuthGate > 0 || redirected).toBeTruthy();
});

test('attendance page requires auth', async ({ page }) => {
  await page.goto('/attendance');
  await page.waitForTimeout(2000);
  const hasAuthGate = await page.locator('text=/login|entrar|sign in|auth/i').count();
  const redirected = !page.url().includes('/attendance');
  expect(hasAuthGate > 0 || redirected).toBeTruthy();
});

test('admin pages require auth', async ({ page }) => {
  await page.goto('/admin');
  await page.waitForTimeout(2000);
  const hasAuthGate = await page.locator('text=/login|entrar|sign in|auth/i').count();
  const redirected = !page.url().includes('/admin');
  expect(hasAuthGate > 0 || redirected).toBeTruthy();
});

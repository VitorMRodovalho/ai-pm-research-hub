import { test, expect } from '@playwright/test';

test('attendance page structure exists', async ({ page }) => {
  const errors: string[] = [];
  page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
  await page.goto('/attendance');
  await expect(page.locator('body')).toBeVisible();
  await page.waitForTimeout(3000);
  const criticalErrors = errors.filter(e => !e.includes('401') && !e.includes('auth') && !e.includes('supabase'));
  expect(criticalErrors.length).toBe(0);
});

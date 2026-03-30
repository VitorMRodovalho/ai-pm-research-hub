import { test, expect } from '@playwright/test';

test('OAuth consent page loads', async ({ page }) => {
  const resp = await page.goto('/oauth/consent');
  // Should load (even if it shows "invalid request" since no params)
  expect(resp?.status()).toBeLessThan(500);
});

test('well-known OAuth discovery endpoints exist', async ({ request }) => {
  const resp = await request.get('/.well-known/oauth-authorization-server');
  expect(resp.status()).toBe(200);
  const body = await resp.json();
  expect(body.issuer).toBeTruthy();
});

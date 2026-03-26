import { test, expect } from '@playwright/test';

test('blog listing page loads publicly', async ({ page }) => {
  await page.goto('/blog');
  await expect(page).toHaveTitle(/blog|Blog/i);
  await page.waitForTimeout(3000);
  const posts = await page.locator('article, [data-post], a[href*="/blog/"]').count();
  expect(posts).toBeGreaterThan(0);
});

test('blog post page loads', async ({ page }) => {
  await page.goto('/blog/zero-cost-research-platform-ai-lessons');
  await page.waitForTimeout(2000);
  await expect(page.locator('text=/Zero-Cost|zero-cost|Custo Zero/i')).toBeVisible();
});

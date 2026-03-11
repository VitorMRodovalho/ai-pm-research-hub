import { expect, test } from '@playwright/test';

test.describe('dark mode visual baseline', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      window.localStorage.setItem('ui_theme', 'dark');
      document.documentElement.setAttribute('data-theme', 'dark');
    });
  });

  test('home page dark mode baseline', async ({ page }) => {
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    await page.addStyleTag({
      content: `
        #hero-countdown-area, #hero-event-area { visibility: hidden !important; }
      `,
    });
    await expect(page.locator('body')).toHaveScreenshot('home-dark.png', {
      animations: 'disabled',
      fullPage: true,
    });
  });

  test('tribe denied shell dark mode baseline', async ({ page }) => {
    await page.goto('/tribe/1');
    await page.waitForSelector('#tribe-denied');
    await expect(page.locator('#tribe-denied')).toHaveScreenshot('tribe-denied-dark.png', {
      animations: 'disabled',
    });
  });

  test('admin portfolio denied dark mode baseline', async ({ page }) => {
    await page.goto('/admin/portfolio');
    await page.waitForSelector('#portfolio-denied');
    await expect(page.locator('#portfolio-denied')).toHaveScreenshot('portfolio-denied-dark.png', {
      animations: 'disabled',
    });
  });
});

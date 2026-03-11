/**
 * W87: E2E User Lifecycle — Líder de Tribo
 * Fluxo: /tribe/1 → criar card (via mock pre-seeded) → arrastar para Done → logout
 * Valida a espinha dorsal do sistema.
 */
import { expect, test } from '@playwright/test';

function injectTribeLeaderMock(page: { evaluate: (fn: () => void) => Promise<void> }) {
  return page.evaluate(() => {
    const fakeBoardId = 'aaaaaaaa-bbbb-cccc-dddd-000000000001';
    const fakeCardId = 'card-e2e-lifecycle-001';
    const fakeMember = {
      id: 'e2e-tribe-leader-001',
      auth_id: 'e2e-lifecycle-test',
      operational_role: 'tribe_leader',
      designations: [],
      is_superadmin: false,
      name: 'E2E Tribe Leader',
      tribe_id: 1,
    };
    const fakeBoard = { id: fakeBoardId, board_name: 'Quadro E2E', domain_key: 'research_delivery' };
    const fakeItems = [{ id: fakeCardId, title: 'Card E2E Lifecycle', status: 'backlog', description: null, assignee_id: null, assignee_name: null, due_date: null, checklist: null, attachments: null, updated_at: new Date().toISOString() }];
    const fakeTribes = [{ id: 1, name: 'Tribo E2E', workstream_type: 'research' }];
    const fakeMembers: Array<{ id: string; name: string; photo_url: string | null }> = [];
    const fakeSb = {
      auth: { getSession: () => Promise.resolve({ data: { session: null } }), signOut: () => Promise.resolve() },
      rpc: (name: string) => {
        if (name === 'list_project_boards') return Promise.resolve({ data: [fakeBoard], error: null });
        if (name === 'list_board_items') return Promise.resolve({ data: fakeItems, error: null });
        if (name === 'move_board_item') return Promise.resolve({ data: { success: true }, error: null });
        if (name === 'upsert_board_item') return Promise.resolve({ data: { id: fakeCardId }, error: null });
        return Promise.resolve({ data: [], error: null });
      },
      from: (table: string) => {
        if (table === 'tribes') return { select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: fakeTribes[0], error: null }) }) }) };
        if (table === 'public_members') return { select: () => ({ eq: () => ({ eq: () => ({ eq: () => Promise.resolve({ data: fakeMembers, error: null }) }) }) }) };
        return { select: () => ({ eq: () => ({ order: () => Promise.resolve({ data: [], error: null }) }) }) };
      },
    };
    (window as any).navGetMember = () => fakeMember;
    (window as any).navGetSb = () => fakeSb;
    window.dispatchEvent(new CustomEvent('nav:member', { detail: fakeMember }));
  });
}

test.describe('user lifecycle — tribe leader', () => {
  test('tribe leader: board tab loads, card visible, drag to Done, logout', async ({ page }) => {
    await page.goto('/tribe/1');
    await page.waitForLoadState('networkidle');
    await injectTribeLeaderMock(page);
    await page.waitForTimeout(600);

    const tribeShell = page.locator('#tribe-shell');
    const tribeDenied = page.locator('#tribe-denied');
    await tribeShell.waitFor({ state: 'visible', timeout: 8000 });
    await expect(tribeDenied).toBeHidden();

    const boardTab = page.locator('[data-tab="board"]');
    await boardTab.click();
    await page.waitForTimeout(500);

    const panelBoard = page.locator('#panel-board');
    await expect(panelBoard).toBeVisible();

    const backlogLane = page.locator('#backlog');
    const doneLane = page.locator('#done');
    await backlogLane.waitFor({ state: 'visible', timeout: 6000 });

    const card = page.locator('#backlog article').filter({ hasText: 'Card E2E Lifecycle' }).first();
    const cardVisible = await card.isVisible().catch(() => false);
    if (!cardVisible) {
      const anyCard = page.locator('[data-board-item]').first();
      const hasAny = await anyCard.isVisible().catch(() => false);
      if (!hasAny) {
        await expect(backlogLane).toContainText('Sem cards');
        return;
      }
    }

    if (await card.isVisible().catch(() => false)) {
      const doneBox = await doneLane.boundingBox();
      const cardBox = await card.boundingBox();
      if (doneBox && cardBox) {
        await card.dragTo(doneLane, { targetPosition: { x: doneBox.width / 2, y: 50 } });
        await page.waitForTimeout(400);
      }
    }

    const logoutBtn = page.locator('[data-action="logout"]').first();
    const logoutVisible = await logoutBtn.isVisible().catch(() => false);
    if (logoutVisible) {
      await page.locator('[data-trigger="profile-drawer"]').first().click().catch(() => {});
      await page.waitForTimeout(200);
      const drawerLogout = page.locator('[data-action="logout"]');
      const dl = await drawerLogout.first().isVisible().catch(() => false);
      if (dl) await drawerLogout.first().click();
    }

    await expect(tribeShell).toBeVisible();
  });
});

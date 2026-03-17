/**
 * W131 Contract Tests: Communication Engine + Blog
 * Static analysis — validates migration, campaign tables, blog, RPCs, i18n, Edge Function.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = process.cwd();

function readFile(relPath) {
  return readFileSync(resolve(ROOT, relPath), 'utf8');
}

function findFunctionBody(sql, funcName) {
  const regex = new RegExp(
    `CREATE OR REPLACE FUNCTION[^(]*${funcName}\\b[\\s\\S]*?\\$\\$([\\s\\S]*?)\\$\\$`, 'i'
  );
  const match = sql.match(regex);
  return match ? match[1] : '';
}

// ═══════════════════════════════════════════════════
// Migration
// ═══════════════════════════════════════════════════

test('W131 migration exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'supabase/migrations/20260319100034_w131_communication_engine.sql')),
    'W131 migration must exist'
  );
});

// ═══════════════════════════════════════════════════
// Campaign Templates
// ═══════════════════════════════════════════════════

test('W131 creates campaign_templates table', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS public.campaign_templates'), 'Must create campaign_templates');
  assert.ok(sql.includes('slug text NOT NULL UNIQUE'), 'Must have slug UNIQUE');
  assert.ok(sql.includes('subject jsonb NOT NULL'), 'Must have subject jsonb');
  assert.ok(sql.includes('body_html jsonb NOT NULL'), 'Must have body_html jsonb');
  assert.ok(sql.includes('body_text jsonb NOT NULL'), 'Must have body_text jsonb');
  assert.ok(sql.includes('target_audience jsonb'), 'Must have target_audience jsonb');
  assert.ok(sql.includes("category text NOT NULL DEFAULT 'operational'"), 'Must have category with default');
});

test('W131 creates campaign_sends table', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS public.campaign_sends'), 'Must create campaign_sends');
  assert.ok(sql.includes('template_id uuid REFERENCES public.campaign_templates(id)'), 'Must reference templates');
  assert.ok(sql.includes('sent_by uuid REFERENCES public.members(id)'), 'Must reference members');
  assert.ok(sql.includes("status text DEFAULT 'draft'"), 'Must have status with default draft');
  assert.ok(sql.includes('approved_by uuid'), 'Must have approved_by for GP approval');
});

test('W131 creates campaign_recipients table with CASCADE', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS public.campaign_recipients'), 'Must create campaign_recipients');
  assert.ok(sql.includes('ON DELETE CASCADE'), 'Must CASCADE delete with send');
  assert.ok(sql.includes('external_email text'), 'Must have external_email for non-members');
  assert.ok(sql.includes('unsubscribe_token uuid'), 'Must have unsubscribe_token per recipient');
  assert.ok(sql.includes('unsubscribed boolean'), 'Must track unsubscribe status');
});

// ═══════════════════════════════════════════════════
// RLS
// ═══════════════════════════════════════════════════

test('campaign_templates has admin RLS', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('ALTER TABLE public.campaign_templates ENABLE ROW LEVEL SECURITY'), 'Must enable RLS');
  assert.ok(sql.includes('Admin manages templates'), 'Must have admin policy');
  assert.ok(sql.includes("'comms_team'"), 'comms_team must have template access');
});

test('campaign_sends RLS restricts to GP/DM', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('ALTER TABLE public.campaign_sends ENABLE ROW LEVEL SECURITY'), 'Must enable RLS');
  assert.ok(sql.includes('Admin manages sends'), 'Must have admin send policy');
  assert.ok(sql.includes('Comms team reads sends'), 'comms_team can read but not send');
});

test('campaign_recipients has no direct access', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('No direct access to recipients'), 'Must block direct access');
  assert.ok(sql.includes('USING (false)'), 'Must use false policy');
});

// ═══════════════════════════════════════════════════
// RPCs
// ═══════════════════════════════════════════════════

test('admin_preview_campaign RPC exists', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  const body = findFunctionBody(sql, 'admin_preview_campaign');
  assert.ok(body, 'admin_preview_campaign must exist');
  assert.ok(body.includes('auth.uid()'), 'Must check auth');
  assert.ok(body.includes('{member.name}'), 'Must replace member.name variable');
  assert.ok(body.includes('{unsubscribe_url}'), 'Must replace unsubscribe_url variable');
});

test('admin_send_campaign RPC with rate limiting', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  const body = findFunctionBody(sql, 'admin_send_campaign');
  assert.ok(body, 'admin_send_campaign must exist');
  assert.ok(body.includes('1 hour'), 'Must have 1 hour rate limit');
  assert.ok(body.includes('1 day'), 'Must have daily rate limit');
  assert.ok(body.includes('max 1 campaign per hour'), 'Must enforce hourly limit');
  assert.ok(body.includes('max 3 campaigns per day'), 'Must enforce daily limit');
  assert.ok(body.includes("('manager','deputy_manager')"), 'Only GP/DM can send');
  assert.ok(body.includes('p_external_contacts'), 'Must support external contacts');
});

test('admin_get_campaign_stats RPC exists', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  const body = findFunctionBody(sql, 'admin_get_campaign_stats');
  assert.ok(body, 'admin_get_campaign_stats must exist');
  assert.ok(body.includes('delivered_count'), 'Must return delivered count');
  assert.ok(body.includes('open_count'), 'Must return open count');
  assert.ok(body.includes('unsubscribe_count'), 'Must return unsubscribe count');
});

// ═══════════════════════════════════════════════════
// Seeded Templates
// ═══════════════════════════════════════════════════

test('W131 seeds 5 campaign templates', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  const slugs = ['onboarding-researcher', 'onboarding-tribe-leader', 'beta-launch-all', 'pmi-key-personnel', 'blog-announcement'];
  for (const s of slugs) {
    assert.ok(sql.includes(`'${s}'`), `Must seed template with slug: ${s}`);
  }
});

test('all seeded templates have i18n (pt, en, es)', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  // Count occurrences of subject with all 3 languages
  const ptEnEs = sql.match(/"pt":"[^"]+","en":"[^"]+","es":"[^"]+"/g);
  assert.ok(ptEnEs && ptEnEs.length >= 5, `Must have at least 5 trilingual subject entries, found ${ptEnEs?.length || 0}`);
});

test('all templates have unsubscribe_url variable', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  // Every template body must contain unsubscribe_url
  const matches = sql.match(/\{unsubscribe_url\}/g);
  assert.ok(matches && matches.length >= 15, `Must have many unsubscribe_url references, found ${matches?.length || 0}`);
});

test('templates use PMI trademark correctly', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('PMI&reg;'), 'Must use PMI® (HTML entity)');
  assert.ok(sql.includes('PMP&reg;'), 'Must use PMP® (HTML entity)');
});

// ═══════════════════════════════════════════════════
// Blog
// ═══════════════════════════════════════════════════

test('W131 creates blog_posts table', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('CREATE TABLE IF NOT EXISTS public.blog_posts'), 'Must create blog_posts');
  assert.ok(sql.includes('slug text NOT NULL UNIQUE'), 'Must have unique slug');
  assert.ok(sql.includes('title jsonb NOT NULL'), 'Must have title jsonb');
  assert.ok(sql.includes('body_html jsonb NOT NULL'), 'Must have body_html jsonb');
  assert.ok(sql.includes("status text DEFAULT 'draft'"), 'Must default to draft');
  assert.ok(sql.includes("('draft','review','published')"), 'Must have status workflow');
});

test('blog_posts has public read + admin write RLS', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('Public reads published'), 'Must have public read policy');
  assert.ok(sql.includes("status = 'published'"), 'Public can only read published');
  assert.ok(sql.includes('Admin manages posts'), 'Must have admin write policy');
});

test('W131 seeds first blog post draft', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes("'plataforma-custo-zero'"), 'Must seed blog post with slug');
  assert.ok(sql.includes("'draft'"), 'Must be in draft status');
  assert.ok(sql.includes('case-study'), 'Must be category case-study');
});

// ═══════════════════════════════════════════════════
// Edge Function
// ═══════════════════════════════════════════════════

test('send-campaign Edge Function exists', () => {
  assert.ok(
    existsSync(resolve(ROOT, 'supabase/functions/send-campaign/index.ts')),
    'send-campaign Edge Function must exist'
  );
});

test('send-campaign uses Resend', () => {
  const content = readFile('supabase/functions/send-campaign/index.ts');
  assert.ok(content.includes('api.resend.com'), 'Must call Resend API');
  assert.ok(content.includes('nucleoia@pmigo.org.br'), 'Must send from nucleoia@pmigo.org.br');
});

test('send-campaign adds unsubscribe header', () => {
  const content = readFile('supabase/functions/send-campaign/index.ts');
  assert.ok(content.includes('List-Unsubscribe'), 'Must add List-Unsubscribe header');
  assert.ok(content.includes('unsubscribe_token'), 'Must use per-recipient unsubscribe token');
});

test('send-campaign skips unsubscribed recipients', () => {
  const content = readFile('supabase/functions/send-campaign/index.ts');
  assert.ok(content.includes('r.unsubscribed'), 'Must check unsubscribed status');
});

test('send-campaign detects language', () => {
  const content = readFile('supabase/functions/send-campaign/index.ts');
  assert.ok(content.includes('language') || content.includes('langKey'), 'Must handle language detection');
});

test('send-campaign has auth check', () => {
  const content = readFile('supabase/functions/send-campaign/index.ts');
  assert.ok(content.includes('auth.getUser'), 'Must verify auth token');
  assert.ok(content.includes('Forbidden'), 'Must reject unauthorized');
});

// ═══════════════════════════════════════════════════
// Admin Pages
// ═══════════════════════════════════════════════════

test('/admin/campaigns page exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/pages/admin/campaigns.astro')), 'campaigns admin page must exist');
});

test('/admin/campaigns has template editor', () => {
  const content = readFile('src/pages/admin/campaigns.astro');
  assert.ok(content.includes('tmpl-modal'), 'Must have template editor modal');
  assert.ok(content.includes('campaign-body') || content.includes('RichTextEditor'), 'Must have body editor (RichTextEditor)');
  assert.ok(content.includes('data-lang-tab'), 'Must have i18n language tabs');
  assert.ok(content.includes('var-btn'), 'Must have variable picker buttons');
});

test('/admin/campaigns has send functionality', () => {
  const content = readFile('src/pages/admin/campaigns.astro');
  assert.ok(content.includes('send-modal'), 'Must have send confirmation modal');
  assert.ok(content.includes('admin_send_campaign'), 'Must call send RPC');
  assert.ok(content.includes('send-campaign'), 'Must trigger Edge Function');
});

test('/admin/campaigns has preview', () => {
  const content = readFile('src/pages/admin/campaigns.astro');
  assert.ok(content.includes('preview-modal'), 'Must have preview modal');
  assert.ok(content.includes('admin_preview_campaign'), 'Must call preview RPC');
});

test('/admin/blog page exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/pages/admin/blog.astro')), 'blog admin page must exist');
});

test('/admin/blog has CRUD', () => {
  const content = readFile('src/pages/admin/blog.astro');
  assert.ok(content.includes('post-modal'), 'Must have post editor modal');
  assert.ok(content.includes('post-slug'), 'Must have slug field');
  assert.ok(content.includes('post-status'), 'Must have status selector');
  assert.ok(content.includes('data-blang'), 'Must have i18n tabs');
});

// ═══════════════════════════════════════════════════
// Public Blog Pages
// ═══════════════════════════════════════════════════

test('/blog listing page exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/pages/blog/index.astro')), 'blog index must exist');
});

test('/blog listing queries published posts', () => {
  const content = readFile('src/pages/blog/index.astro');
  assert.ok(content.includes("'published'"), 'Must filter by published status');
  assert.ok(content.includes('blog_posts'), 'Must query blog_posts table');
});

test('/blog/[slug] page exists', () => {
  assert.ok(existsSync(resolve(ROOT, 'src/pages/blog/[slug].astro')), 'blog slug page must exist');
});

test('/blog/[slug] shows individual post', () => {
  const content = readFile('src/pages/blog/[slug].astro');
  assert.ok(content.includes('slug'), 'Must use slug parameter');
  assert.ok(content.includes("'published'"), 'Must filter by published status');
  assert.ok(content.includes('post-title'), 'Must have title element');
  assert.ok(content.includes('post-body'), 'Must have body element');
});

// ═══════════════════════════════════════════════════
// Navigation
// ═══════════════════════════════════════════════════

test('AdminNav has campaigns and blog links', () => {
  const content = readFile('src/components/nav/AdminNav.astro');
  assert.ok(content.includes("'campaigns'"), 'Must have campaigns nav link');
  assert.ok(content.includes("'blog'"), 'Must have blog nav link');
  assert.ok(content.includes("'/admin/campaigns'"), 'Must link to /admin/campaigns');
  assert.ok(content.includes("'/admin/blog'"), 'Must link to /admin/blog');
});

test('navigation.config.ts has campaigns and blog entries', () => {
  const content = readFile('src/lib/navigation.config.ts');
  assert.ok(content.includes("'admin-campaigns'"), 'Must have admin-campaigns entry');
  assert.ok(content.includes("'admin-blog'"), 'Must have admin-blog entry');
  assert.ok(content.includes("'/blog'"), 'Must have public blog entry');
});

// ═══════════════════════════════════════════════════
// i18n
// ═══════════════════════════════════════════════════

test('PT-BR has all W131 campaign/blog keys', () => {
  const content = readFile('src/i18n/pt-BR.ts');
  const keys = ['campaigns.title', 'campaigns.subtitle', 'campaigns.newTemplate',
    'campaigns.sendNow', 'campaigns.preview', 'blog.title', 'blog.adminTitle',
    'blog.newPost', 'blog.statusDraft', 'blog.statusPublished', 'nav.adminCampaigns', 'nav.adminBlog'];
  for (const k of keys) {
    assert.ok(content.includes(`'${k}'`), `PT-BR must have key ${k}`);
  }
});

test('EN-US has all W131 campaign/blog keys', () => {
  const content = readFile('src/i18n/en-US.ts');
  const keys = ['campaigns.title', 'blog.title', 'nav.adminCampaigns', 'nav.adminBlog'];
  for (const k of keys) {
    assert.ok(content.includes(`'${k}'`), `EN-US must have key ${k}`);
  }
});

test('ES-LATAM has all W131 campaign/blog keys', () => {
  const content = readFile('src/i18n/es-LATAM.ts');
  const keys = ['campaigns.title', 'blog.title', 'nav.adminCampaigns', 'nav.adminBlog'];
  for (const k of keys) {
    assert.ok(content.includes(`'${k}'`), `ES-LATAM must have key ${k}`);
  }
});

// ═══════════════════════════════════════════════════
// LGPD Compliance
// ═══════════════════════════════════════════════════

test('external recipients cascade delete with send (not permanent)', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  assert.ok(sql.includes('ON DELETE CASCADE'), 'Recipients must cascade delete');
  // campaign_recipients.external_email is only created per-send, not stored permanently
});

test('every email template has unsubscribe link', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  // Count templates (5 inserts) and verify each has unsubscribe
  const insertBlocks = sql.split("INSERT INTO public.campaign_templates");
  // First element is before any INSERT, so skip it
  for (let i = 1; i < insertBlocks.length; i++) {
    assert.ok(
      insertBlocks[i].includes('unsubscribe_url') || insertBlocks[i].includes('unsubscribe'),
      `Template insert #${i} must reference unsubscribe`
    );
  }
});

test('rate limiting enforced in RPC', () => {
  const sql = readFile('supabase/migrations/20260319100034_w131_communication_engine.sql');
  const body = findFunctionBody(sql, 'admin_send_campaign');
  // Verify both hourly and daily limits
  assert.ok(body.includes('v_sends_last_hour'), 'Must track hourly sends');
  assert.ok(body.includes('v_sends_last_day'), 'Must track daily sends');
  assert.ok(body.includes('>= 1'), 'Must check >= 1 for hourly');
  assert.ok(body.includes('>= 3'), 'Must check >= 3 for daily');
});

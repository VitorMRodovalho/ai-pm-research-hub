-- p84 — Fix anon read of published blog_posts + public_publications
--
-- Bug: ADR-0058 multi-org RESTRICTIVE policies blocked anon SELECT even on
-- status='published' content. Anon's auth_org() = NULL; org_id NOT NULL on
-- the published row → restrictive `(org_id = auth_org()) OR (org_id IS NULL)`
-- evaluated FALSE → access denied. Result: /blog/[slug].astro returned
-- "Artigo não encontrado" for all visitors not authenticated to the same org.
--
-- Fix: split the FOR ALL restrictive policy into write-only (INSERT/UPDATE/
-- DELETE). SELECT is then governed exclusively by the permissive
-- "Public reads published" policy which allows status='published' for any
-- role (anon + authenticated). Writes remain strictly org-scoped — no
-- cross-org INSERT/UPDATE/DELETE possible.

-- ── blog_posts ──
DROP POLICY IF EXISTS "blog_posts_v4_org_scope" ON public.blog_posts;

CREATE POLICY "blog_posts_v4_org_scope_insert" ON public.blog_posts
AS RESTRICTIVE
FOR INSERT
WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

CREATE POLICY "blog_posts_v4_org_scope_update" ON public.blog_posts
AS RESTRICTIVE
FOR UPDATE
USING ((organization_id = auth_org()) OR (organization_id IS NULL))
WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

CREATE POLICY "blog_posts_v4_org_scope_delete" ON public.blog_posts
AS RESTRICTIVE
FOR DELETE
USING ((organization_id = auth_org()) OR (organization_id IS NULL));

-- ── public_publications ──
DROP POLICY IF EXISTS "public_publications_v4_org_scope" ON public.public_publications;

CREATE POLICY "public_publications_v4_org_scope_insert" ON public.public_publications
AS RESTRICTIVE
FOR INSERT
WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

CREATE POLICY "public_publications_v4_org_scope_update" ON public.public_publications
AS RESTRICTIVE
FOR UPDATE
USING ((organization_id = auth_org()) OR (organization_id IS NULL))
WITH CHECK ((organization_id = auth_org()) OR (organization_id IS NULL));

CREATE POLICY "public_publications_v4_org_scope_delete" ON public.public_publications
AS RESTRICTIVE
FOR DELETE
USING ((organization_id = auth_org()) OR (organization_id IS NULL));

NOTIFY pgrst, 'reload schema';

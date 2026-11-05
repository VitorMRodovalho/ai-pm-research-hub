-- #2974: ler rascunho e gravar em blog_posts pela API pede superadmin ou manage_comms.
-- A leitura do que está publicado não muda ("Public reads published"), nem as policies RESTRICTIVE de organização.
-- A policy não tem WITH CHECK, então o USING vale também para a linha nova no INSERT e no UPDATE.
ALTER POLICY "blog_posts_manage_v4" ON public.blog_posts
  USING (public.rls_is_superadmin() OR public.rls_can('manage_comms'));

-- ============================================================
-- Domain Model V4 — Fase 1 — Migration 1/N
-- ADR-0004: Organizations as First-Class
-- ============================================================
--
-- Escopo deste commit:
--   1. Drop de 10 tabelas zumbi descobertas durante audit pre-Fase 1
--      (0 rows, 0 refs em codigo, nao vieram de nenhuma migration file,
--       provavel residuo do starter multi-tenant do Supabase).
--   2. CREATE organizations per ADR-0004.
--   3. CREATE chapters (FK → organizations).
--   4. Seed: "Nucleo IA & Gerenciamento de Projetos" + 5 chapters federados
--      (PMI-GO, PMI-CE, PMI-DF, PMI-MG, PMI-RS).
--   5. Helper SQL auth_org() — single-org mode (retorna UUID fixo do Nucleo IA).
--   6. RLS policies (authenticated read; superadmin-only write).
--
-- UUID fixo do Nucleo IA (referenciado em migrations futuras):
--   2b4f58ab-7c45-4170-8718-b77ee69ff906
--
-- NAO entra neste commit (fica para Migration 2 de Fase 1):
--   - organization_id NOT NULL nas tabelas de dominio existentes.
--   - Alteracao de RLS existente.
--   - Mudancas em MCP / frontend.
--   - auth_org() lendo JWT claim (fica para Fase 1 cutover, depois do
--     shadow window).
--
-- Rollback:
--   DROP FUNCTION IF EXISTS public.auth_org();
--   DROP TABLE IF EXISTS public.chapters;
--   DROP TABLE IF EXISTS public.organizations;
--   -- Observacao: as 10 tabelas zumbi nao sao recriadas no rollback.
--   -- Tinham 0 rows e 0 refs em codigo — nada para preservar.
--
-- Autorizacao PM: Vitor em 2026-04-11 (sessao de inicio da Fase 1).
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- STEP 1 — Drop zombie tables (starter multi-tenant residue)
-- ------------------------------------------------------------
-- Todas as 10 tabelas abaixo foram verificadas com 0 rows, zero
-- referencias em src/ ou supabase/functions/, nenhuma em
-- supabase_migrations.schema_migrations. DROP CASCADE e seguro.
--
-- Drop em ordem que respeita FKs (filhas primeiro), com CASCADE
-- como rede de seguranca.

DROP TABLE IF EXISTS public.project_shares CASCADE;
DROP TABLE IF EXISTS public.program_shares CASCADE;
DROP TABLE IF EXISTS public.projects CASCADE;
DROP TABLE IF EXISTS public.programs CASCADE;
DROP TABLE IF EXISTS public.memberships CASCADE;
DROP TABLE IF EXISTS public.audit_log CASCADE;
DROP TABLE IF EXISTS public.value_milestones CASCADE;
DROP TABLE IF EXISTS public.forensic_access_log CASCADE;
DROP TABLE IF EXISTS public.forensic_timelines CASCADE;
DROP TABLE IF EXISTS public.organizations CASCADE;

-- ------------------------------------------------------------
-- STEP 2 — Create organizations (ADR-0004 canonical schema)
-- ------------------------------------------------------------

CREATE TABLE public.organizations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  slug          text NOT NULL UNIQUE,
  description   text,
  website_url   text,
  logo_url      text,
  status        text NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active','archived')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.organizations IS
  'ADR-0004: Organizations as first-class. Toda tabela de dominio tera organization_id apontando aqui (Fase 1, Migration 2).';

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read all orgs (single-org era — Nucleo IA apenas).
-- Quando multi-org entrar, esta policy sera substituida por filtro via auth_org().
CREATE POLICY "organizations_read_authenticated"
  ON public.organizations
  FOR SELECT
  TO authenticated
  USING (true);

-- Only superadmins write. Nenhuma policy para anon.
CREATE POLICY "organizations_write_superadmin"
  ON public.organizations
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid() AND is_superadmin = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid() AND is_superadmin = true
    )
  );

-- ------------------------------------------------------------
-- STEP 3 — Create chapters (FK → organizations)
-- ------------------------------------------------------------

CREATE TABLE public.chapters (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  code              text NOT NULL,           -- 'GO','CE','DF','MG','RS'
  name              text NOT NULL,           -- 'PMI Goias','PMI Ceara',...
  pmi_chapter_code  text,                    -- codigo PMI se aplicavel
  region            text,                    -- 'Centro-Oeste','Nordeste','Sudeste','Sul'
  status            text NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active','archived')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chapters_org_code_unique UNIQUE (organization_id, code)
);

CREATE INDEX idx_chapters_organization_id ON public.chapters(organization_id);

COMMENT ON TABLE public.chapters IS
  'ADR-0004: Capitulo filho de uma organization. Nucleo IA tem 5 chapters federados (GO/CE/DF/MG/RS).';

ALTER TABLE public.chapters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chapters_read_authenticated"
  ON public.chapters
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "chapters_write_superadmin"
  ON public.chapters
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid() AND is_superadmin = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.members
      WHERE auth_id = auth.uid() AND is_superadmin = true
    )
  );

-- ------------------------------------------------------------
-- STEP 4 — Seed: Nucleo IA + 5 chapters federados
-- ------------------------------------------------------------

INSERT INTO public.organizations (id, name, slug, description, status)
VALUES (
  '2b4f58ab-7c45-4170-8718-b77ee69ff906',
  'Nucleo IA & Gerenciamento de Projetos',
  'nucleo-ia',
  'Iniciativa voluntaria federada dos capitulos PMI-GO, PMI-CE, PMI-DF, PMI-MG e PMI-RS dedicada a pesquisa e disseminacao de IA aplicada a Gerenciamento de Projetos.',
  'active'
);

INSERT INTO public.chapters (organization_id, code, name, region) VALUES
  ('2b4f58ab-7c45-4170-8718-b77ee69ff906', 'GO', 'PMI Goias',       'Centro-Oeste'),
  ('2b4f58ab-7c45-4170-8718-b77ee69ff906', 'CE', 'PMI Ceara',       'Nordeste'),
  ('2b4f58ab-7c45-4170-8718-b77ee69ff906', 'DF', 'PMI Distrito Federal', 'Centro-Oeste'),
  ('2b4f58ab-7c45-4170-8718-b77ee69ff906', 'MG', 'PMI Minas Gerais','Sudeste'),
  ('2b4f58ab-7c45-4170-8718-b77ee69ff906', 'RS', 'PMI Rio Grande do Sul','Sul');

-- ------------------------------------------------------------
-- STEP 5 — auth_org() helper
-- ------------------------------------------------------------
-- Single-org mode: retorna o UUID fixo do Nucleo IA.
-- Expansao futura (pos-Fase 1 cutover): ler claim 'org_id' do JWT.

CREATE OR REPLACE FUNCTION public.auth_org()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT '2b4f58ab-7c45-4170-8718-b77ee69ff906'::uuid;
$$;

COMMENT ON FUNCTION public.auth_org() IS
  'ADR-0004: retorna organization_id ativa do caller. Single-org mode ate o cutover multi-org — sempre Nucleo IA.';

GRANT EXECUTE ON FUNCTION public.auth_org() TO authenticated, anon;

-- ------------------------------------------------------------
-- STEP 6 — PostgREST schema reload
-- ------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;

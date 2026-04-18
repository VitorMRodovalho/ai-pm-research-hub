-- ============================================================================
-- Migration: Phase IP-1 core tables (document_versions, approval_chains,
--            approval_signoffs, document_comments, member_document_signatures)
-- ADR: docs/council/2026-04-19-ip-ratification-decisions.md
-- Parecer legal: docs/council/2026-04-19-legal-counsel-ip-review.md
-- Rollback: DROP TABLE <tables> CASCADE; DROP TRIGGER <triggers>;
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. document_versions — histórico imutável, uma versão = um estado fixo
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.document_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL REFERENCES public.governance_documents(id) ON DELETE RESTRICT,
  version_number int NOT NULL CHECK (version_number >= 1),
  version_label text NOT NULL,
  content_html text NOT NULL,
  content_markdown text,
  content_diff_json jsonb,
  authored_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  authored_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  published_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  locked_at timestamptz,
  locked_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_id, version_number),
  UNIQUE (document_id, version_label)
);

COMMENT ON TABLE public.document_versions IS
  'Historico imutavel de versoes de governance_documents. Uma version = um estado fixo do conteudo. locked_at flag = a partir dai a row e imutavel (trigger enforce). ADR: docs/council/2026-04-19-ip-ratification-decisions.md';

COMMENT ON COLUMN public.document_versions.content_html IS
  'Conteudo renderizado em HTML. Imutavel apos locked_at. Deve coincidir com content_markdown (se preenchido).';

COMMENT ON COLUMN public.document_versions.content_diff_json IS
  'Diff estruturado vs versao anterior (para UI diff view). Formato: {added:[], removed:[], modified:[]}.';

COMMENT ON COLUMN public.document_versions.locked_at IS
  'Timestamp que marca versao imutavel. Apos lock, trigger trg_document_version_immutable impede UPDATE em campos de conteudo.';

CREATE INDEX IF NOT EXISTS idx_document_versions_document ON public.document_versions(document_id, version_number DESC);
CREATE INDEX IF NOT EXISTS idx_document_versions_locked ON public.document_versions(document_id) WHERE locked_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. approval_chains — estado da cadeia de aprovacao
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.approval_chains (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id uuid NOT NULL REFERENCES public.governance_documents(id) ON DELETE RESTRICT,
  version_id uuid NOT NULL REFERENCES public.document_versions(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','review','approved','active','withdrawn','superseded')),
  gates jsonb NOT NULL DEFAULT '[]'::jsonb,
  opened_at timestamptz,
  approved_at timestamptz,
  activated_at timestamptz,
  closed_at timestamptz,
  opened_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  closed_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (document_id, version_id)
);

COMMENT ON TABLE public.approval_chains IS
  'Estado da cadeia de aprovacao de uma document_version. gates armazena CONFIG apenas (array de {kind, threshold, order}); status de cada gate e COMPUTED via query em approval_signoffs (ADR-0012 mandato).';

COMMENT ON COLUMN public.approval_chains.gates IS
  'CONFIG da cadeia (array jsonb). Ex: [{"kind":"curator","threshold":1,"order":1}, {"kind":"president_go","threshold":1,"order":2}, ...]. Status de cada gate e computed via query em approval_signoffs, NAO armazenado aqui.';

COMMENT ON COLUMN public.approval_chains.status IS
  'Estado do chain. draft=being built / review=awaiting signoffs / approved=all gates satisfied / active=vigente / withdrawn=cancelled / superseded=substituido por nova versao';

CREATE INDEX IF NOT EXISTS idx_approval_chains_document ON public.approval_chains(document_id);
CREATE INDEX IF NOT EXISTS idx_approval_chains_version ON public.approval_chains(version_id);
CREATE INDEX IF NOT EXISTS idx_approval_chains_status ON public.approval_chains(status) WHERE status IN ('review','approved','active');

-- ---------------------------------------------------------------------------
-- 3. approval_signoffs — audit trail imutavel (append-only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.approval_signoffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_chain_id uuid NOT NULL REFERENCES public.approval_chains(id) ON DELETE RESTRICT,
  gate_kind text NOT NULL,
  signer_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  signoff_type text NOT NULL CHECK (signoff_type IN ('approval','acknowledge','abstain','rejection')),
  signed_at timestamptz NOT NULL DEFAULT now(),
  signature_hash text NOT NULL,
  signed_ip inet,
  signed_user_agent text,
  content_snapshot jsonb NOT NULL,
  sections_verified jsonb,
  comment_body text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (approval_chain_id, gate_kind, signer_id)
);

COMMENT ON TABLE public.approval_signoffs IS
  'Registro imutavel de cada signoff (aprovacao/ciencia/abstencao/rejeicao). Append-only via trigger trg_approval_signoff_immutable. signature_hash = hash(content_snapshot || signed_at || signer_id) para integridade.';

COMMENT ON COLUMN public.approval_signoffs.content_snapshot IS
  'Snapshot imutavel do content_html do document_version + metadados do signer (name, role, chapter) no momento do signoff. Evidencia legal de que o signer viu aquele texto exato.';

COMMENT ON COLUMN public.approval_signoffs.sections_verified IS
  'Array jsonb de secoes marcadas como lidas pelo signer (UX.Q1 scroll tracking). Formato: [{"section_id":"sec-2.6","verified_at":"...","viewport_ms":N}].';

COMMENT ON COLUMN public.approval_signoffs.signature_hash IS
  'SHA-256 hex digest de (content_snapshot || signed_at || signer_id). Verificacao de integridade pos-insercao.';

CREATE INDEX IF NOT EXISTS idx_approval_signoffs_chain ON public.approval_signoffs(approval_chain_id);
CREATE INDEX IF NOT EXISTS idx_approval_signoffs_signer ON public.approval_signoffs(signer_id);
CREATE INDEX IF NOT EXISTS idx_approval_signoffs_gate ON public.approval_signoffs(approval_chain_id, gate_kind);

-- ---------------------------------------------------------------------------
-- 4. document_comments — threading + visibility
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.document_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_version_id uuid NOT NULL REFERENCES public.document_versions(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  clause_anchor text,
  body text NOT NULL,
  parent_id uuid REFERENCES public.document_comments(id) ON DELETE CASCADE,
  visibility text NOT NULL DEFAULT 'public' CHECK (visibility IN ('public','curator_only')),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES public.members(id) ON DELETE SET NULL,
  resolution_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.document_comments IS
  'Comentarios em threads por clausula. visibility=public visivel a todos autenticados (UX.Q2 Tier 1 pode comentar); curator_only visivel so a curadores/lideres. admin_only REMOVIDO per PM decision p29.';

COMMENT ON COLUMN public.document_comments.clause_anchor IS
  'Identificador semantico da clausula/secao ancorada. Ex: sec-2.6, clause-4, art-3. Permite deep-link no viewer.';

CREATE INDEX IF NOT EXISTS idx_document_comments_version ON public.document_comments(document_version_id, created_at);
CREATE INDEX IF NOT EXISTS idx_document_comments_parent ON public.document_comments(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_document_comments_unresolved ON public.document_comments(document_version_id) WHERE resolved_at IS NULL;

-- ---------------------------------------------------------------------------
-- 5. member_document_signatures — baseline por ciclo (UX.Q3)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_document_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid NOT NULL REFERENCES public.members(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL REFERENCES public.governance_documents(id) ON DELETE RESTRICT,
  signed_version_id uuid NOT NULL REFERENCES public.document_versions(id) ON DELETE RESTRICT,
  approval_chain_id uuid REFERENCES public.approval_chains(id) ON DELETE SET NULL,
  signoff_id uuid REFERENCES public.approval_signoffs(id) ON DELETE SET NULL,
  certificate_id uuid REFERENCES public.certificates(id) ON DELETE SET NULL,
  signed_at timestamptz NOT NULL DEFAULT now(),
  is_current boolean NOT NULL DEFAULT true,
  superseded_at timestamptz,
  superseded_by_version_id uuid REFERENCES public.document_versions(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (member_id, signed_version_id)
);

COMMENT ON TABLE public.member_document_signatures IS
  'Baseline por ciclo (UX.Q3): qual versao do documento X o membro M assinou. Multi-row por (member, document) — uma por versao ratificada. is_current=true na versao mais recente assinada; is_current=false em rows superseded.';

COMMENT ON COLUMN public.member_document_signatures.is_current IS
  'Marcado false quando nova versao e assinada pelo mesmo membro. Permite diff viewer identificar baseline (last signed) vs current_version_id.';

CREATE INDEX IF NOT EXISTS idx_member_doc_sigs_member ON public.member_document_signatures(member_id, document_id);
CREATE INDEX IF NOT EXISTS idx_member_doc_sigs_current ON public.member_document_signatures(member_id, document_id) WHERE is_current = true;
CREATE INDEX IF NOT EXISTS idx_member_doc_sigs_version ON public.member_document_signatures(signed_version_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_member_doc_sigs_current
  ON public.member_document_signatures(member_id, document_id)
  WHERE is_current = true;

-- ---------------------------------------------------------------------------
-- 6. Trigger: document_version immutable after lock
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_document_version_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  -- Bloquear updates em campos de conteudo apos lock
  IF OLD.locked_at IS NOT NULL THEN
    IF NEW.content_html IS DISTINCT FROM OLD.content_html
       OR NEW.content_markdown IS DISTINCT FROM OLD.content_markdown
       OR NEW.content_diff_json IS DISTINCT FROM OLD.content_diff_json
       OR NEW.version_number IS DISTINCT FROM OLD.version_number
       OR NEW.version_label IS DISTINCT FROM OLD.version_label
       OR NEW.document_id IS DISTINCT FROM OLD.document_id
       OR NEW.locked_at IS DISTINCT FROM OLD.locked_at
    THEN
      RAISE EXCEPTION 'document_versions row locked at % is immutable (id=%, document=%)', OLD.locked_at, OLD.id, OLD.document_id
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_document_version_immutable ON public.document_versions;
CREATE TRIGGER trg_document_version_immutable
  BEFORE UPDATE ON public.document_versions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_document_version_immutable();

-- ---------------------------------------------------------------------------
-- 7. Trigger: approval_signoffs append-only
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_approval_signoff_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  RAISE EXCEPTION 'approval_signoffs is append-only (id=%). UPDATE blocked. To revoke signoff, insert a new signoff_type=rejection row.', OLD.id
    USING ERRCODE = 'check_violation';
END;
$function$;

DROP TRIGGER IF EXISTS trg_approval_signoff_immutable ON public.approval_signoffs;
CREATE TRIGGER trg_approval_signoff_immutable
  BEFORE UPDATE ON public.approval_signoffs
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_approval_signoff_immutable();

-- ---------------------------------------------------------------------------
-- 8. Trigger: approval_chains updated_at
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_approval_chain_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_approval_chain_set_updated_at ON public.approval_chains;
CREATE TRIGGER trg_approval_chain_set_updated_at
  BEFORE UPDATE ON public.approval_chains
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_approval_chain_set_updated_at();

-- ---------------------------------------------------------------------------
-- 9. Trigger: document_comments updated_at
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_document_comments_set_updated_at ON public.document_comments;
CREATE TRIGGER trg_document_comments_set_updated_at
  BEFORE UPDATE ON public.document_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_approval_chain_set_updated_at();

-- ---------------------------------------------------------------------------
-- 10. Trigger: member_document_signatures — on new signature supersede previous
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_member_doc_sig_supersede_previous()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF NEW.is_current = true THEN
    UPDATE public.member_document_signatures
       SET is_current = false,
           superseded_at = now(),
           superseded_by_version_id = NEW.signed_version_id,
           updated_at = now()
     WHERE member_id = NEW.member_id
       AND document_id = NEW.document_id
       AND id <> NEW.id
       AND is_current = true;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_member_doc_sig_supersede_previous ON public.member_document_signatures;
CREATE TRIGGER trg_member_doc_sig_supersede_previous
  AFTER INSERT ON public.member_document_signatures
  FOR EACH ROW
  WHEN (NEW.is_current = true)
  EXECUTE FUNCTION public.trg_member_doc_sig_supersede_previous();

-- ---------------------------------------------------------------------------
-- Grants for authenticated (RLS policies vira na migration 20260429060000)
-- ---------------------------------------------------------------------------
GRANT SELECT, INSERT ON public.document_versions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.approval_chains TO authenticated;
GRANT SELECT, INSERT ON public.approval_signoffs TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.document_comments TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.member_document_signatures TO authenticated;

-- Anon: nenhum acesso (LGPD — tabelas envolvem PII via signer_id/author_id)
REVOKE ALL ON public.document_versions FROM anon;
REVOKE ALL ON public.approval_chains FROM anon;
REVOKE ALL ON public.approval_signoffs FROM anon;
REVOKE ALL ON public.document_comments FROM anon;
REVOKE ALL ON public.member_document_signatures FROM anon;

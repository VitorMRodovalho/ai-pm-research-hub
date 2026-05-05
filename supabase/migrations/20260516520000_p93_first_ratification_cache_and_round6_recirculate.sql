-- p93 (2026-05-05): Round 6 recirculation + first/current ratification cache
--
-- Background: p90/p90.b/p90.c shipped v4-v6 LOCKED versions in 5 governance docs
-- + created Anexo Tecnico v1 — but did NOT update approval_chains nor create new
-- chains. Curators were reviewing v3 (Round 5 ADR-0068 draft) text while M1-M5
-- material corrections were already locked in v6/v5.
--
-- Sections:
--   1. Schema: 6 cache columns (first_ratified_*, current_ratified_*) + trigger
--   2. New email template `governance_recirculation_batch` (multi-doc)
--   3. Supersede 5 stale chains + create 5 new chains pointing to v6/v5
--   4. Create chain v1 for Anexo Tecnico (4 reduced gates)
--   5. Enqueue 3 batched emails (1 per curator with 6 chain links)
--   6. NOTIFY pgrst

-- =========================================================================
-- Section 1: Schema — first/current ratified cache + trigger
-- =========================================================================

ALTER TABLE public.governance_documents
  ADD COLUMN IF NOT EXISTS first_ratified_at         timestamptz,
  ADD COLUMN IF NOT EXISTS first_ratified_chain_id   uuid,
  ADD COLUMN IF NOT EXISTS first_ratified_version_id uuid,
  ADD COLUMN IF NOT EXISTS current_ratified_at         timestamptz,
  ADD COLUMN IF NOT EXISTS current_ratified_chain_id   uuid,
  ADD COLUMN IF NOT EXISTS current_ratified_version_id uuid;

ALTER TABLE public.governance_documents
  DROP CONSTRAINT IF EXISTS governance_docs_first_ratified_chain_fk,
  DROP CONSTRAINT IF EXISTS governance_docs_first_ratified_version_fk,
  DROP CONSTRAINT IF EXISTS governance_docs_current_ratified_chain_fk,
  DROP CONSTRAINT IF EXISTS governance_docs_current_ratified_version_fk;

ALTER TABLE public.governance_documents
  ADD CONSTRAINT governance_docs_first_ratified_chain_fk
    FOREIGN KEY (first_ratified_chain_id) REFERENCES public.approval_chains(id) ON DELETE SET NULL,
  ADD CONSTRAINT governance_docs_first_ratified_version_fk
    FOREIGN KEY (first_ratified_version_id) REFERENCES public.document_versions(id) ON DELETE SET NULL,
  ADD CONSTRAINT governance_docs_current_ratified_chain_fk
    FOREIGN KEY (current_ratified_chain_id) REFERENCES public.approval_chains(id) ON DELETE SET NULL,
  ADD CONSTRAINT governance_docs_current_ratified_version_fk
    FOREIGN KEY (current_ratified_version_id) REFERENCES public.document_versions(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.governance_documents.first_ratified_at IS
  'Timestamp da primeira vez que uma approval_chain deste doc atingiu status=active. NULL = doc nunca foi oficialmente ratificado. Idempotente — nao sobrescrito por re-ratificacoes posteriores. Mantido por trg_sync_ratification_cache. Pattern espelha current_version_id (cache+trigger).';
COMMENT ON COLUMN public.governance_documents.current_ratified_at IS
  'Timestamp da chain oficial em vigor agora (ultima a ratificar). NULL = doc ainda em pre-ratificacao. Sobrescrito a cada nova ratificacao. Use para listar versao oficial atual sem JOIN; comparar com versao anterior via approval_chains historico (activated_at IS NOT NULL).';

CREATE INDEX IF NOT EXISTS idx_governance_documents_first_ratified
  ON public.governance_documents(first_ratified_at) WHERE first_ratified_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_governance_documents_current_ratified
  ON public.governance_documents(current_ratified_at) WHERE current_ratified_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.trg_sync_ratification_cache()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_activated_at timestamptz;
BEGIN
  IF NEW.status = 'active' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'active') THEN
    v_activated_at := COALESCE(NEW.activated_at, NEW.approved_at, now());

    -- Auto-supersede prior active chain for same doc (if any)
    UPDATE public.approval_chains
       SET status = 'superseded',
           closed_at = COALESCE(closed_at, v_activated_at),
           notes = COALESCE(notes, '') || E'\n[auto-superseded by chain ' || NEW.id::text || ' at ' || v_activated_at::text || ' — new ratification supersedes prior active chain]',
           updated_at = now()
     WHERE document_id = NEW.document_id
       AND id <> NEW.id
       AND status = 'active';

    -- Update governance_documents cache
    UPDATE public.governance_documents
       SET first_ratified_at         = COALESCE(first_ratified_at, v_activated_at),
           first_ratified_chain_id   = COALESCE(first_ratified_chain_id, NEW.id),
           first_ratified_version_id = COALESCE(first_ratified_version_id, NEW.version_id),
           current_ratified_at         = v_activated_at,
           current_ratified_chain_id   = NEW.id,
           current_ratified_version_id = NEW.version_id,
           status = CASE WHEN status = 'under_review' THEN 'active' ELSE status END,
           updated_at = now()
     WHERE id = NEW.document_id;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_ratification_cache ON public.approval_chains;
CREATE TRIGGER trg_sync_ratification_cache
  AFTER INSERT OR UPDATE OF status ON public.approval_chains
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_ratification_cache();

COMMENT ON FUNCTION public.trg_sync_ratification_cache() IS
  'p93: maintain governance_documents.first_ratified_* (idempotent) + current_ratified_* (overwrite) + auto-supersede prior active chain + auto-promote doc.status under_review->active. Fires on chain.status transitions to active.';

-- =========================================================================
-- Section 2: New batch email template
-- =========================================================================

INSERT INTO public.campaign_templates (
  id, name, slug, subject, body_html, body_text,
  target_audience, category, variables
) VALUES (
  gen_random_uuid(),
  'Re-circulacao batch — multiplos docs governance em 1 email',
  'governance_recirculation_batch',
  jsonb_build_object('pt', 'Re-circulacao Round 6 — 6 documentos de governanca aguardam sua revisao, {{first_name}}'),
  jsonb_build_object('pt', $body$<p>Ola {{first_name}},</p>
<div style="margin:12px 0;font-size:14px;line-height:1.5;">{{batch_intro}}</div>
<h3 style="margin-top:20px;color:#1e3a8a;">Documentos para revisao e re-assinatura</h3>
{{doc_links_html}}
<p style="margin-top:20px;font-size:12px;color:#6b7280;">
  Glossario canonico do Nucleo (espelho dinamico): <a href="{{platform_url}}/governance/glossario">{{platform_url}}/governance/glossario</a>
</p>
<p style="margin-top:14px;">
  Qualquer duvida ou nova ressalva, abra comentario diretamente nas chains ou responda este email.
</p>
<p style="margin-top:18px;">—<br>{{sender_name}}<br>Gerente de Projeto — Nucleo IA &amp; GP</p>$body$),
  jsonb_build_object('pt', 'Re-circulacao Round 6: 6 docs governance aguardam revisao. Acesse {{platform_url}}/admin/governance/documents'),
  jsonb_build_object('all', false, 'roles', '[]'::jsonb, 'chapters', '[]'::jsonb, 'designations', '[]'::jsonb),
  'operational',
  jsonb_build_object(
    'first_name',     jsonb_build_object('type','text', 'required',true),
    'batch_intro',    jsonb_build_object('type','html', 'required',true),
    'doc_links_html', jsonb_build_object('type','html', 'required',true),
    'platform_url',   jsonb_build_object('type','url',  'required',false),
    'sender_name',    jsonb_build_object('type','text', 'required',false)
  )
)
ON CONFLICT (slug) DO UPDATE SET
  subject = EXCLUDED.subject,
  body_html = EXCLUDED.body_html,
  body_text = EXCLUDED.body_text,
  variables = EXCLUDED.variables;

-- =========================================================================
-- Section 3: Supersede 5 stale chains + create 5 new chains v6/v5
-- =========================================================================

DO $do$
DECLARE
  v_pm_id uuid;
  v_old_chain RECORD;
  v_new_chain_id uuid;
  v_doc RECORD;
  v_doc_chain_map jsonb := '[
    {"doc_id":"cfb15185-2800-4441-9ff1-f36096e83aa8", "stale_chain_id":"955a4728-0f43-402b-8531-8b6f82db0627", "title":"Politica IP"},
    {"doc_id":"280c2c56-e0e3-4b10-be68-6c731d1b4520", "stale_chain_id":"d16d1241-460d-47e6-9437-ce153027394d", "title":"Termo de Adesao"},
    {"doc_id":"d2b7782c-dc1a-44d4-a5d5-16248117a895", "stale_chain_id":"2e76f367-bece-4d68-abcf-7df03bd6c80c", "title":"Adendo Retificativo"},
    {"doc_id":"41de16e2-4f2e-4eac-b63e-8f0b45b22629", "stale_chain_id":"d5291281-aadd-4759-9524-dbea06bb450f", "title":"Adendo PI Cooperacao"},
    {"doc_id":"cd170c37-3975-49c3-aae6-a918c07f157e", "stale_chain_id":"cec9e6b8-fcf1-435c-aa6b-9af5656ee6e1", "title":"Acordo Bilateral"}
  ]'::jsonb;
  v_entry jsonb;
BEGIN
  SELECT id INTO v_pm_id FROM public.members WHERE email = 'vitor.rodovalho@outlook.com';
  IF v_pm_id IS NULL THEN
    RAISE EXCEPTION 'GP member not found for vitor.rodovalho@outlook.com';
  END IF;

  FOR v_entry IN SELECT * FROM jsonb_array_elements(v_doc_chain_map)
  LOOP
    SELECT ac.id, ac.document_id, ac.version_id, ac.status, ac.gates
    INTO v_old_chain
    FROM public.approval_chains ac
    WHERE ac.id = (v_entry->>'stale_chain_id')::uuid
      AND ac.document_id = (v_entry->>'doc_id')::uuid;

    IF v_old_chain.id IS NULL THEN
      RAISE EXCEPTION 'Stale chain not found for doc %: %',
        v_entry->>'title', v_entry->>'stale_chain_id';
    END IF;
    IF v_old_chain.status <> 'review' THEN
      RAISE EXCEPTION 'Stale chain % is not in review (status=%)',
        v_old_chain.id, v_old_chain.status;
    END IF;

    SELECT gd.id, gd.title, gd.current_version_id, dv.version_label
    INTO v_doc
    FROM public.governance_documents gd
    JOIN public.document_versions dv ON dv.id = gd.current_version_id
    WHERE gd.id = (v_entry->>'doc_id')::uuid;

    IF v_doc.current_version_id = v_old_chain.version_id THEN
      RAISE EXCEPTION 'No-op: stale chain version_id matches current_version_id for doc %',
        v_doc.title;
    END IF;

    -- (a) Supersede stale chain
    UPDATE public.approval_chains
      SET status = 'superseded',
          closed_at = now(),
          closed_by = v_pm_id,
          notes = COALESCE(notes,'') || E'\n[p93 recirculate 2026-05-05] superseded — stale chain pointed to v3 (Round 5 ADR-0068) but Round 6 hotfixes (p90/p90.b/p90.c) introduced v4-v6 with material changes M1-M5. Replaced by new chain pointing to current_version_id (' || v_doc.version_label || ').',
          updated_at = now()
      WHERE id = v_old_chain.id;

    -- (b) New chain pointing to current_version_id (v6/v5), gates copied verbatim
    INSERT INTO public.approval_chains (
      document_id, version_id, status, gates, opened_at, opened_by, notes
    ) VALUES (
      v_doc.id,
      v_doc.current_version_id,
      'review',
      v_old_chain.gates,
      now(),
      v_pm_id,
      'p93 recirculate 2026-05-05: replaces superseded chain ' || v_old_chain.id::text ||
      ' (stale Round 5 v3) — current ' || v_doc.version_label ||
      ' (Round 6 hotfixes p90/p90.b/p90.c absorvendo M1-M5 material changes). Curators must re-sign because text changed materially.'
    ) RETURNING id INTO v_new_chain_id;

    -- (c) Audit
    INSERT INTO public.admin_audit_log (
      actor_id, action, target_type, target_id, changes, created_at
    ) VALUES (
      v_pm_id,
      'governance.recirculated_round6_p93',
      'approval_chain',
      v_new_chain_id,
      jsonb_build_object(
        'session', 'p93',
        'session_date', '2026-05-05',
        'document_id', v_doc.id,
        'document_title', v_doc.title,
        'old_chain_id', v_old_chain.id,
        'old_chain_version_id', v_old_chain.version_id,
        'new_chain_id', v_new_chain_id,
        'new_chain_version_id', v_doc.current_version_id,
        'new_version_label', v_doc.version_label,
        'reason', 'p90/p90.b/p90.c shipped v4-v6 LOCKED but never created chains; curators were reviewing stale v3 text'
      ),
      now()
    );
  END LOOP;
END $do$;

-- =========================================================================
-- Section 4: Create chain v1 for Anexo Tecnico (no chain existed)
-- =========================================================================

DO $do$
DECLARE
  v_pm_id uuid;
  v_anexo_id uuid := '980a71fd-6af7-492f-b784-bbe1e346e389';
  v_anexo_version_id uuid;
  v_new_chain_id uuid;
  v_anexo_gates jsonb := '[
    {"kind":"curator",              "order":1, "threshold":"all"},
    {"kind":"submitter_acceptance", "order":2, "threshold":1},
    {"kind":"president_go",         "order":3, "threshold":1},
    {"kind":"president_others",     "order":4, "threshold":4}
  ]'::jsonb;
BEGIN
  SELECT id INTO v_pm_id FROM public.members WHERE email = 'vitor.rodovalho@outlook.com';

  IF EXISTS (SELECT 1 FROM public.approval_chains WHERE document_id = v_anexo_id) THEN
    RAISE EXCEPTION 'Anexo Tecnico already has chain(s) — aborting to avoid duplicates';
  END IF;

  SELECT current_version_id INTO v_anexo_version_id
  FROM public.governance_documents WHERE id = v_anexo_id;

  IF v_anexo_version_id IS NULL THEN
    RAISE EXCEPTION 'Anexo Tecnico has no current_version_id';
  END IF;

  INSERT INTO public.approval_chains (
    document_id, version_id, status, gates, opened_at, opened_by, notes
  ) VALUES (
    v_anexo_id,
    v_anexo_version_id,
    'review',
    v_anexo_gates,
    now(),
    v_pm_id,
    'p93 recirculate 2026-05-05: chain inicial Anexo Tecnico v1 (criado em p90.c sem chain). Gates reduzidos (4): curator + submitter_acceptance + president_go + president_others. Sem leader_awareness/member_ratification — anexo subsidiario referenciado pela Politica IP, Adendo PI Coop e Acordo Bilateral.'
  ) RETURNING id INTO v_new_chain_id;

  INSERT INTO public.admin_audit_log (
    actor_id, action, target_type, target_id, changes, created_at
  ) VALUES (
    v_pm_id,
    'governance.first_chain_created_p93',
    'approval_chain',
    v_new_chain_id,
    jsonb_build_object(
      'session', 'p93',
      'session_date', '2026-05-05',
      'document_id', v_anexo_id,
      'document_title', 'Anexo Tecnico — Plataforma Operacional do Nucleo IA & GP',
      'new_chain_id', v_new_chain_id,
      'new_chain_version_id', v_anexo_version_id,
      'gates_count', 4,
      'reason', 'p90.c criou v1 LOCKED do Anexo Tecnico mas nao criou approval_chain'
    ),
    now()
  );
END $do$;

-- =========================================================================
-- Section 5: Send 3 batched emails to curators (1 per curator with 6 chain links)
-- =========================================================================

DO $do$
DECLARE
  v_pm_id uuid;
  v_pm_name text := 'Vitor Maia Rodovalho';
  v_curator RECORD;
  v_doc RECORD;
  v_doc_links_html text := '';
  v_batch_intro text;
  v_send_result jsonb;
BEGIN
  SELECT id INTO v_pm_id FROM public.members WHERE email = 'vitor.rodovalho@outlook.com';

  FOR v_doc IN
    SELECT
      ac.id AS new_chain_id,
      gd.title,
      dv.version_label,
      LEFT(COALESCE(dv.notes, '(sem changelog)'), 220) AS changelog_short,
      (SELECT id FROM public.approval_chains
        WHERE document_id = ac.document_id
          AND status = 'superseded'
          AND closed_at >= now() - interval '5 minutes'
        ORDER BY closed_at DESC LIMIT 1) AS prior_id
    FROM public.approval_chains ac
    JOIN public.governance_documents gd ON gd.id = ac.document_id
    JOIN public.document_versions dv ON dv.id = ac.version_id
    WHERE ac.status = 'review'
      AND ac.opened_at >= now() - interval '5 minutes'
      AND ac.document_id IN (
        'cfb15185-2800-4441-9ff1-f36096e83aa8',
        '280c2c56-e0e3-4b10-be68-6c731d1b4520',
        'd2b7782c-dc1a-44d4-a5d5-16248117a895',
        '41de16e2-4f2e-4eac-b63e-8f0b45b22629',
        'cd170c37-3975-49c3-aae6-a918c07f157e',
        '980a71fd-6af7-492f-b784-bbe1e346e389'
      )
    ORDER BY gd.title
  LOOP
    v_doc_links_html := v_doc_links_html ||
      '<div style="border:1px solid #e5e7eb;border-radius:8px;padding:14px;margin-bottom:10px;background:#f9fafb;">' ||
        '<strong style="font-size:15px;color:#1e3a8a;">📄 ' || v_doc.title || '</strong>' ||
        ' <span style="font-size:11px;background:#dbeafe;color:#1e40af;padding:2px 6px;border-radius:4px;margin-left:6px;font-family:monospace;">' || v_doc.version_label || '</span>' ||
        '<p style="margin:6px 0;font-size:12px;color:#6b7280;font-style:italic;">' || replace(replace(v_doc.changelog_short, '<', '&lt;'), '>', '&gt;') || '...</p>' ||
        '<p style="margin:6px 0;">' ||
          '<a href="https://nucleoia.vitormr.dev/admin/governance/documents/' || v_doc.new_chain_id::text || '" style="display:inline-block;background:#1e3a8a;color:#fff;padding:6px 12px;border-radius:6px;text-decoration:none;font-weight:bold;font-size:12px;">🔍 Revisar e assinar →</a>' ||
          CASE WHEN v_doc.prior_id IS NOT NULL THEN
            ' <a href="https://nucleoia.vitormr.dev/admin/governance/documents/' || v_doc.prior_id::text || '" style="margin-left:8px;font-size:11px;color:#6b7280;">💬 Comentários da chain anterior</a>'
          ELSE
            ' <span style="margin-left:8px;font-size:11px;color:#6b7280;font-style:italic;">(novo doc — sem chain anterior)</span>'
          END ||
        '</p>' ||
      '</div>';
  END LOOP;

  v_batch_intro :=
    '<p>Os 6 documentos de governança foram atualizados (Round 6 — sessões p90/p90.b/p90.c, 04-05/maio/2026) e precisam da sua revisão e re-assinatura nas novas chains.</p>' ||
    '<p><strong>5 mudanças materiais (M1-M5)</strong> absorvendo críticas Ricardo Santos:</p>' ||
    '<ul style="margin:6px 0;padding-left:22px;font-size:13px;">' ||
      '<li><strong>M1</strong> (Termo §15.4 + Adendo Retificativo §3º): aceite tácito refatorado distinguindo Editorial vs Material change (CC art. 111 + 423 favor aderente)</li>' ||
      '<li><strong>M2</strong> (Política IP §2.5.5): LGPD redraft 3 regimes (Brasil / UE-EEE / UK) + future-proof</li>' ||
      '<li><strong>M3</strong> (Adendo PI Cooperação Art. 8): simplificado para thin cross-ref ao Anexo Técnico</li>' ||
      '<li><strong>M4</strong> (Política IP nova Cláusula 16): disclaimer marca PMI® (uso por iniciativa voluntária inter-capítulos)</li>' ||
      '<li><strong>M5</strong> (Acordo Bilateral nova Cláusula 12): Cooperação com Entidades Externas + PMOGA framework</li>' ||
    '</ul>' ||
    '<p><strong>1 doc novo</strong>: Anexo Técnico — Plataforma Operacional (8 seções: titularidade, autoria, CoI, uso, continuidade, exploração comercial).</p>' ||
    '<p><strong>11 fixes editoriais</strong>: Termo de Compromisso → Termo de Adesão; Lei 14.063/2020 + MP 2.200-2/2001; Política de Publicação → Política de Governança; glossário expandido (12 termos novos); títulos canônicos; tributária simplificada.</p>' ||
    '<p style="background:#fef3c7;border-left:4px solid #f59e0b;padding:10px;margin:12px 0;font-size:13px;"><strong>⚠️ Importante:</strong> quem já assinou as versões anteriores precisa re-assinar nas novas chains, porque o texto mudou materialmente — o framework ADR-0068 exige aceite expresso para Material change. As chains anteriores (status: superseded) permanecem disponíveis para vocês marcarem comentários como resolvidos conforme verificarem nos novos textos — sem perder histórico.</p>';

  FOR v_curator IN
    SELECT id, email, name FROM public.members
    WHERE email IN ('boblmacedo@gmail.com','sarah.famr@gmail.com','fabriciorcc@gmail.com')
  LOOP
    v_send_result := public.campaign_send_one_off(
      p_template_slug := 'governance_recirculation_batch',
      p_to_email := v_curator.email,
      p_variables := jsonb_build_object(
        'first_name', split_part(v_curator.name, ' ', 1),
        'batch_intro', v_batch_intro,
        'doc_links_html', v_doc_links_html,
        'platform_url', 'https://nucleoia.vitormr.dev',
        'sender_name', v_pm_name
      ),
      p_metadata := jsonb_build_object(
        'source', 'p93_round6_recirculate',
        'recipient_name', v_curator.name,
        'language', 'pt'
      )
    );

    INSERT INTO public.admin_audit_log (
      actor_id, action, target_type, target_id, changes, created_at
    ) VALUES (
      v_pm_id,
      'governance.recirculation_batch_email_p93',
      'campaign_send',
      (v_send_result->>'send_id')::uuid,
      jsonb_build_object(
        'session', 'p93',
        'recipient_email', v_curator.email,
        'recipient_name', v_curator.name,
        'template_slug', 'governance_recirculation_batch',
        'doc_count', 6,
        'send_id', v_send_result->>'send_id'
      ),
      now()
    );
  END LOOP;
END $do$;

-- =========================================================================
-- Section 6: NOTIFY pgrst
-- =========================================================================

NOTIFY pgrst, 'reload schema';

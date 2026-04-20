-- IP-3d: formalize 4 signed Acordos de Cooperação as document_versions
-- Applied 19/04/2026 via MCP (4 separate migrations: ip3d_formalize_acordo_pmi_{ce,df,mg,rs}).
-- Source: PM uploaded scanned/signed .docx files on 19/Abr p34.
-- Goal: close legal-counsel Red Flag A — each Adendo needs principal instrument documented.
-- Signed dates: MG 08/12/2025, CE 09/12/2025, DF 09/12/2025, RS 10/12/2025.
-- Full content in document_versions.content_html; .docx backups retained at:
--   /home/vitormrodovalho/Downloads/A/Termos de Acordo de Coperação-20260420T003236Z-3-001.zip
-- Rollback: DELETE FROM document_versions WHERE version_label LIKE 'v1.0-assinado-%';
--           UPDATE governance_documents SET current_version_id=NULL WHERE doc_type='cooperation_agreement';
SELECT 'No-op stub. See audit log action ip3d.formalize_signed_acordo for per-chapter details.'::text;

-- Phase IP-1: Extend governance_documents.doc_type for 'executive_summary' (Sumario CR-050)
ALTER TABLE public.governance_documents DROP CONSTRAINT IF EXISTS governance_documents_doc_type_check;
ALTER TABLE public.governance_documents ADD CONSTRAINT governance_documents_doc_type_check
  CHECK (doc_type = ANY (ARRAY[
    'manual'::text,
    'cooperation_agreement'::text,
    'framework_reference'::text,
    'addendum'::text,
    'policy'::text,
    'volunteer_term_template'::text,
    'executive_summary'::text
  ]));

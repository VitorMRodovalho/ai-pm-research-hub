-- partner_chapters: the 10 chapters announced at the CBGPL (30/04/2026) take part in the Núcleo while
-- their agreement awaits signature. The old value 'announced_at_risk' (#1175 D2, PM 2026-07-08) read
-- as "at risk"; the GP decided on 11/11/2026 to label the state for what it is.
-- Only the non-signed value changes. Every reader compares against 'signed' (no function body cites
-- the old value, measured in pg_proc on 11/11/2026), so the countersignature gate and the selection
-- tags keep their behaviour.

ALTER TABLE public.partner_chapters
  DROP CONSTRAINT IF EXISTS partner_chapters_partnership_status_check;

UPDATE public.partner_chapters
   SET partnership_status = 'participating_pending_signature'
 WHERE partnership_status = 'announced_at_risk';

ALTER TABLE public.partner_chapters
  ADD CONSTRAINT partner_chapters_partnership_status_check
  CHECK (partnership_status IN ('signed', 'participating_pending_signature'));

COMMENT ON COLUMN public.partner_chapters.partnership_status IS
  'signed = cooperation agreement signed; participating_pending_signature = the chapter takes part '
  '(announced at the CBGPL on 30/04/2026) and its agreement has not been signed yet. Readers must '
  'compare against ''signed''; the second value is a label, never a gate.';

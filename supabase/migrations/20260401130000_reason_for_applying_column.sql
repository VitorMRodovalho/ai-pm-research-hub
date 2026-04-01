-- Add reason_for_applying as dedicated column (separate from essay questions)
-- "Reason for Applying" is a standard VEP field, not an essay question
ALTER TABLE selection_applications ADD COLUMN IF NOT EXISTS reason_for_applying text;

-- VEP Opportunities: admin write policies for frontend config UI
-- Also includes interview rubrics from 20260401100000

-- Write policies for vep_opportunities (admin only)
CREATE POLICY IF NOT EXISTS vep_opportunities_insert_admin ON vep_opportunities FOR INSERT
WITH CHECK (EXISTS (
  SELECT 1 FROM members WHERE auth_id = auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
));

CREATE POLICY IF NOT EXISTS vep_opportunities_update_admin ON vep_opportunities FOR UPDATE
USING (EXISTS (
  SELECT 1 FROM members WHERE auth_id = auth.uid()
  AND (is_superadmin = true OR operational_role IN ('manager', 'deputy_manager'))
));

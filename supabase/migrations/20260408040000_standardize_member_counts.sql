-- Standardize member counting across all RPCs
-- Canonical definition: "active member" = is_active = true AND current_cycle_active = true
-- Previously some RPCs used only is_active (53), others used both (52)
-- After fixing Daniel Bittencourt (observer, not cycle_active → is_active=false), both = 52

-- 1. Daniel Bittencourt: observer, not in current cycle
UPDATE members SET is_active = false WHERE name = 'Daniel Bittencourt' AND chapter = 'PMI-MG' AND operational_role = 'observer';

-- 2. KPI baseline: 53 → 52
UPDATE annual_kpi_targets SET baseline_value = 52 WHERE kpi_key = 'active_members' AND cycle = 4;

-- 3. RPCs fixed via session (surgical text replace):
-- get_annual_kpis: active_members_count now uses current_cycle_active
-- get_sustainability_dashboard: v_active_count now uses current_cycle_active
-- get_executive_kpis: v_total_active now uses is_active AND current_cycle_active
-- get_public_impact_data: active_members now uses current_cycle_active
-- platform_activity_summary: member count now uses current_cycle_active

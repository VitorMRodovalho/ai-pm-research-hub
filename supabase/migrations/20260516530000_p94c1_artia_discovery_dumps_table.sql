-- p94 Phase C.1: artia_discovery_dumps table for Artia structure discovery
-- Trigger: PMO Audit 2026 (Núcleo 17%) → expand sync-artia from 1 block (KPIs) to 7 blocks
-- Step 1: discover how other PMI-GO projects structure folders/activities in account 6345833
-- Persist results for offline analysis and Phase C.2 schema design

CREATE TABLE IF NOT EXISTS artia_discovery_dumps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dumped_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  account_id BIGINT NOT NULL,
  project_id BIGINT,
  project_name TEXT,
  dump_kind TEXT NOT NULL CHECK (dump_kind IN ('projects_list','folders_list','activities_sample','error')),
  payload JSONB NOT NULL,
  source_query TEXT,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_artia_dumps_dumped_at ON artia_discovery_dumps(dumped_at DESC);
CREATE INDEX IF NOT EXISTS idx_artia_dumps_kind_account ON artia_discovery_dumps(dump_kind, account_id);
CREATE INDEX IF NOT EXISTS idx_artia_dumps_project ON artia_discovery_dumps(project_id) WHERE project_id IS NOT NULL;

ALTER TABLE artia_discovery_dumps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v4_artia_dumps_admin_read" ON artia_discovery_dumps
  FOR SELECT USING (rls_can('manage_member') OR rls_can('view_internal_analytics'));

-- Service role bypass via SECDEF RPCs only (no direct INSERT from client)

COMMENT ON TABLE artia_discovery_dumps IS 'Phase C.1 discovery: dumps of Artia project/folder/activity structure for analysis. Used to design Phase C.2 schema migrations and Phase C.3 EF expansion.';
COMMENT ON COLUMN artia_discovery_dumps.dump_kind IS 'projects_list = top-level projects in account; folders_list = folders in a project; activities_sample = up to 20 activities per folder; error = GraphQL/HTTP errors';
COMMENT ON COLUMN artia_discovery_dumps.payload IS 'Raw GraphQL response data (jsonb). For projects_list: array of {id,title,customStatus}. For folders_list: array of {id,title}. For activities_sample: array of {id,title,description,completedPercent,customStatus}.';

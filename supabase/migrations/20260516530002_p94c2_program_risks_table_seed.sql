-- p94 Phase C.2 Step 2: program_risks table + 11-row seed from TAP §13
-- Trigger: PMO Audit Bloco 5c — Riscos identificados e registrados (currently 0/4)

CREATE TABLE IF NOT EXISTS program_risks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_year INT NOT NULL DEFAULT 2026,
  risk_code TEXT NOT NULL,
  risk_title TEXT NOT NULL,
  cause TEXT NOT NULL,
  consequence TEXT NOT NULL,
  treatment TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'aberto'
    CHECK (status IN ('aberto','em_tratamento','mitigado','encerrado')),
  probability TEXT
    CHECK (probability IS NULL OR probability IN ('baixa','media','alta')),
  impact TEXT
    CHECK (impact IS NULL OR impact IN ('baixo','medio','alto')),
  responsible_role TEXT,
  artia_activity_id BIGINT,
  artia_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(cycle_year, risk_code)
);

CREATE INDEX IF NOT EXISTS idx_program_risks_cycle_status
  ON program_risks(cycle_year, status);

CREATE INDEX IF NOT EXISTS idx_program_risks_artia_stale
  ON program_risks(artia_synced_at NULLS FIRST)
  WHERE artia_activity_id IS NOT NULL;

ALTER TABLE program_risks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "v4_program_risks_admin_read" ON program_risks
  FOR SELECT USING (rls_can('manage_member') OR rls_can('view_internal_analytics'));

CREATE OR REPLACE FUNCTION trg_program_risks_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_program_risks_updated_at
  BEFORE UPDATE ON program_risks
  FOR EACH ROW EXECUTE FUNCTION trg_program_risks_updated_at();

INSERT INTO program_risks (cycle_year, risk_code, risk_title, cause, consequence, treatment, status, probability, impact, responsible_role) VALUES
(2026, 'R-01', 'Não interação entre participantes do Núcleo', 'Desinteresse dos membros / falta de tempo', 'Falta de envolvimento e baixa entrega', 'Motivação constante via Hub de Comunicação · distribuição clara de tarefas via plataforma · valorização das entregas via Newsletter', 'em_tratamento', 'media', 'medio', 'GP'),
(2026, 'R-02', 'Single-point-of-failure no GP', 'Indisponibilidade do GP por questões pessoais/profissionais', 'Paralisação do programa', 'Vice-GP designado (Fabricio Costa) com responsabilidades documentadas', 'mitigado', 'baixa', 'alto', 'GP'),
(2026, 'R-03', 'Ausência total ou parcial de apoio das diretorias', 'Falta de disponibilidade ou interesse das diretorias parceiras', 'Baixa motivação dos voluntários · baixa visibilidade interna PMI-GO', 'Sponsor formal (Ivan Lourenço) · Acordos Cooperação Bilateral assinados · canalização via diretorias parceiras', 'em_tratamento', 'baixa', 'medio', 'GP'),
(2026, 'R-04', 'Dificuldade em encontrar voluntários filiados ao PMI', 'Falta de incentivos ou de reconhecimento de benefícios da filiação', 'Limitação da participação', 'Processo seletivo metrificado · benefícios de visibilidade (artigos, certificados Credly, palestras)', 'em_tratamento', 'media', 'medio', 'Comitê de Curadoria'),
(2026, 'R-05', 'Não conformidade com Política IP / LGPD', 'Produção de conteúdo sem revisão · uso indevido de dados pessoais', 'Risco legal · risco reputacional para PMI-GO', 'Comitê de Curadoria revisa todas entregas · Tribo Q4 Governança como guardiã · ciclo LGPD Art.18 implementado', 'em_tratamento', 'media', 'alto', 'Comitê de Curadoria'),
(2026, 'R-06', 'Uso indevido de marca PMI®', 'Comunicação externa sem disclaimer', 'Risco reputacional / contestação institucional', 'Disclaimer obrigatório em todas publicações · uso institucional autorizado via PMI-GO', 'em_tratamento', 'baixa', 'medio', 'Hub de Comunicação'),
(2026, 'R-07', 'Descontinuidade da plataforma', 'Plataforma open source sem garantia de manutenção', 'Perda de ferramenta operacional · perda de histórico operacional', 'Backup regular Drive · repositório GitHub público · documentação técnica em docs/ · ADRs registrando decisões · Manual de Governança documenta processo', 'em_tratamento', 'baixa', 'alto', 'GP'),
(2026, 'R-08', 'Riscos de IP em produções colaborativas', 'Disputa de autoria / atribuição', 'Conflito interno · perda de motivação', 'Política Institucional de IP em revisão · Tracks A/B/C definidos · revisão colaborativa Comitê de Curadoria', 'em_tratamento', 'media', 'medio', 'Comitê de Curadoria'),
(2026, 'R-09', 'Dificuldade em buscar parcerias externas', 'Falta de tempo / capacidade comercial', 'Limita expansão · não atinge meta 3 entidades', 'Apoio do Vice-GP · canal via PMI-GO sponsor · entidades acadêmicas via PMI Latam', 'aberto', 'alta', 'medio', 'Vice-GP'),
(2026, 'R-10', 'Conflito de agenda com calendário PMI-GO', 'Ações Núcleo competem com eventos PMI-GO', 'Frustração das diretorias · queda de prestígio', 'Calendário sincronizado · não realizar eventos do Núcleo em datas conflitantes (Restrição TAP §8)', 'mitigado', 'baixa', 'baixo', 'GP'),
(2026, 'R-11', 'Drift de evidência institucional vs Artia/Drive', 'Auditoria PMO marcou 0% em Kick-off / Templates / Lições / Uso do Artia', 'Score crítico em auditoria · perda de credibilidade institucional', 'Plano de ação 2026-05: migrar artefatos Drive pessoal → Drive institucional · expandir sync-artia (cron semanal) para 7 blocos · adotar template TAP institucional', 'em_tratamento', 'alta', 'alto', 'GP')
ON CONFLICT (cycle_year, risk_code) DO NOTHING;

COMMENT ON TABLE program_risks IS 'Phase C.2: structured risks (was markdown in TAP §13). One row per risk, synced to Artia activity in folder 04.06-Riscos. Cron mensal updates customStatus + completedPercent based on status field.';

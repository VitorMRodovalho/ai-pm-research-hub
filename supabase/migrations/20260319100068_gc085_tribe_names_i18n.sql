-- ============================================================
-- GC-085: Tribe names i18n — parallel jsonb columns
-- Zero impact on 44 RPCs that use tribes.name
-- ============================================================

BEGIN;

-- Step 1: Add parallel columns
ALTER TABLE tribes ADD COLUMN IF NOT EXISTS name_i18n jsonb;
ALTER TABLE tribes ADD COLUMN IF NOT EXISTS quadrant_name_i18n jsonb;

COMMENT ON COLUMN tribes.name_i18n IS 'Trilingual tribe name {pt, en, es}. Frontend reads this; RPCs still use name (PT-BR).';
COMMENT ON COLUMN tribes.quadrant_name_i18n IS 'Trilingual quadrant name {pt, en, es}. Frontend reads this; RPCs still use quadrant_name.';

-- Step 2: Populate i18n data
UPDATE tribes SET name_i18n = '{"pt": "Radar Tecnológico", "en": "Technology Radar", "es": "Radar Tecnológico"}'::jsonb,
  quadrant_name_i18n = '{"pt": "O Praticante Aumentado", "en": "The Augmented Practitioner", "es": "El Practicante Aumentado"}'::jsonb
WHERE id = 1;

UPDATE tribes SET name_i18n = '{"pt": "Agentes Autônomos", "en": "Autonomous Agents", "es": "Agentes Autónomos"}'::jsonb,
  quadrant_name_i18n = '{"pt": "O Praticante Aumentado", "en": "The Augmented Practitioner", "es": "El Practicante Aumentado"}'::jsonb
WHERE id = 2;

UPDATE tribes SET name_i18n = '{"pt": "TMO & PMO do Futuro", "en": "TMO & PMO of the Future", "es": "TMO & PMO del Futuro"}'::jsonb,
  quadrant_name_i18n = '{"pt": "Gestão de Projetos com IA", "en": "AI Project Management", "es": "Gestión de Proyectos con IA"}'::jsonb
WHERE id = 3;

UPDATE tribes SET name_i18n = '{"pt": "Cultura & Change", "en": "Culture & Change", "es": "Cultura & Cambio"}'::jsonb,
  quadrant_name_i18n = '{"pt": "Liderança Organizacional", "en": "Organizational Leadership", "es": "Liderazgo Organizacional"}'::jsonb
WHERE id = 4;

UPDATE tribes SET name_i18n = '{"pt": "Talentos & Upskilling", "en": "Talent & Upskilling", "es": "Talento & Upskilling"}'::jsonb,
  quadrant_name_i18n = '{"pt": "Liderança Organizacional", "en": "Organizational Leadership", "es": "Liderazgo Organizacional"}'::jsonb
WHERE id = 5;

UPDATE tribes SET name_i18n = '{"pt": "ROI & Portfólio", "en": "ROI & Portfolio", "es": "ROI & Portafolio"}'::jsonb,
  quadrant_name_i18n = '{"pt": "Liderança Organizacional", "en": "Organizational Leadership", "es": "Liderazgo Organizacional"}'::jsonb
WHERE id = 6;

UPDATE tribes SET name_i18n = '{"pt": "Governança & Trustworthy AI", "en": "Governance & Trustworthy AI", "es": "Gobernanza & IA Confiable"}'::jsonb,
  quadrant_name_i18n = '{"pt": "Futuro & Responsabilidade", "en": "Future & Responsibility", "es": "Futuro & Responsabilidad"}'::jsonb
WHERE id = 7;

UPDATE tribes SET name_i18n = '{"pt": "Inclusão & Colaboração & Comunicação", "en": "Inclusion & Collaboration & Communication", "es": "Inclusión & Colaboración & Comunicación"}'::jsonb,
  quadrant_name_i18n = '{"pt": "Futuro & Responsabilidade", "en": "Future & Responsibility", "es": "Futuro & Responsabilidad"}'::jsonb
WHERE id = 8;

COMMIT;

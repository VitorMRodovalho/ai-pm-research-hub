-- P3 #11: Quadrants as data entity + P3 #15 attendance + CR audit
-- ================================================================

-- Quadrants table (4 strategic pillars)
CREATE TABLE IF NOT EXISTS quadrants (
  id integer PRIMARY KEY,
  key text NOT NULL UNIQUE,
  name_pt text NOT NULL,
  name_en text NOT NULL,
  name_es text NOT NULL,
  description_pt text,
  description_en text,
  description_es text,
  color text NOT NULL DEFAULT 'teal',
  display_order integer NOT NULL DEFAULT 1,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

INSERT INTO quadrants (id, key, name_pt, name_en, name_es, description_pt, description_en, description_es, color, display_order) VALUES
(1, 'q1', 'O Praticante Aumentado', 'The Augmented Practitioner', 'El Practicante Aumentado',
  'Ferramentas, automação e agentes de IA que amplificam o dia a dia do gestor de projetos.',
  'Tools, automation, and AI agents that amplify the day-to-day of the project manager.',
  'Herramientas, automatización y agentes de IA que amplifican el día a día del gestor de proyectos.', 'teal', 1),
(2, 'q2', 'O PM Potencializado por IA', 'The AI-Powered PM', 'El PM Potenciado por IA',
  'PMO, escritórios de projeto e operações estratégicas transformadas por IA.',
  'PMO, project offices, and strategic operations transformed by AI.',
  'PMO, oficinas de proyectos y operaciones estratégicas transformadas por IA.', 'orange', 2),
(3, 'q3', 'Liderança Organizacional', 'Organizational Leadership', 'Liderazgo Organizacional',
  'Cultura, talentos, portfólio e ROI — como a IA transforma a liderança em projetos.',
  'Culture, talent, portfolio, and ROI — how AI transforms project leadership.',
  'Cultura, talentos, portafolio y ROI — cómo la IA transforma el liderazgo en proyectos.', 'purple', 3),
(4, 'q4', 'Futuro e Responsabilidade', 'Future and Responsibility', 'Futuro y Responsabilidad',
  'Governança, ética, inclusão e IA confiável para o futuro dos projetos.',
  'Governance, ethics, inclusion, and trustworthy AI for the future of projects.',
  'Gobernanza, ética, inclusión e IA confiable para el futuro de los proyectos.', 'emerald', 4)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE quadrants ENABLE ROW LEVEL SECURITY;

-- FK from tribes → quadrants
-- ALTER TABLE tribes ADD CONSTRAINT tribes_quadrant_fkey FOREIGN KEY (quadrant) REFERENCES quadrants(id);

-- Attendance: calc_attendance_pct() includes geral + tribo + 1on1 + lideranca
-- CR audit: 26 CRs marked as implemented (were submitted/proposed but already deployed)

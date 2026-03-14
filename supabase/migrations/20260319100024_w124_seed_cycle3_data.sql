-- W124 Phase 1: Seed Cycle 3 Selection Data (historical import)
-- ============================================================
-- Wraps all seed data in a DO block so we can capture the cycle_id
-- and reference it in subsequent INSERTs.
-- ============================================================

DO $$
DECLARE
  v_cycle_id uuid;
  v_fabricio_id uuid;
  v_vitor_id uuid;
BEGIN
  -- 1. Create the Cycle 3 selection cycle
  INSERT INTO selection_cycles (
    cycle_code, title, status,
    open_date, close_date,
    min_evaluators,
    objective_criteria,
    interview_criteria,
    leader_extra_criteria,
    objective_cutoff_formula,
    final_cutoff_formula,
    onboarding_steps
  ) VALUES (
    'cycle3-2026',
    'Seleção Ciclo 3 — 2026',
    'closed',
    '2025-12-01',
    '2026-01-31',
    2,
    '[
      {"key":"certification","label":"Certificações PMI","weight":2,"max":5},
      {"key":"research_exp","label":"Experiência em Pesquisa","weight":5,"max":5},
      {"key":"gp_knowledge","label":"Conhecimento em GP","weight":5,"max":5},
      {"key":"ai_knowledge","label":"Conhecimento em IA","weight":5,"max":5},
      {"key":"tech_skills","label":"Habilidades Técnicas","weight":5,"max":5},
      {"key":"availability","label":"Disponibilidade","weight":3,"max":5},
      {"key":"motivation","label":"Motivação / Carta","weight":5,"max":5}
    ]'::jsonb,
    '[
      {"key":"communication","label":"Comunicação","weight":4,"max":5},
      {"key":"proactivity","label":"Proatividade","weight":3,"max":5},
      {"key":"teamwork","label":"Trabalho em Equipe","weight":3,"max":5},
      {"key":"culture_alignment","label":"Alinhamento Cultural","weight":3,"max":5}
    ]'::jsonb,
    '[
      {"key":"research_and_gp_exp","label":"Exp. Pesquisa + GP","weight":5,"max":5},
      {"key":"leadership","label":"Liderança","weight":4,"max":5},
      {"key":"technical_knowledge","label":"Conhecimento Técnico","weight":3,"max":5},
      {"key":"pmi_involvement","label":"Envolvimento PMI","weight":3,"max":5},
      {"key":"language","label":"Idiomas","weight":3,"max":5}
    ]'::jsonb,
    '(2*min + 4*avg + 2*max) / 8',
    '(2*min + 4*avg + 2*max) / 8',
    '[
      {"key":"accept_terms","label":"Aceitar Termo de Compromisso","sla_days":7},
      {"key":"join_whatsapp","label":"Entrar no grupo WhatsApp","sla_days":3},
      {"key":"platform_access","label":"Acesso à plataforma Hub","sla_days":7},
      {"key":"kick_off","label":"Participar do Kick-off","sla_days":14},
      {"key":"profile_complete","label":"Completar perfil no Hub","sla_days":14}
    ]'::jsonb
  )
  RETURNING id INTO v_cycle_id;

  -- 2. Get committee member IDs
  SELECT id INTO v_fabricio_id FROM members WHERE email = 'fabriciorcc@gmail.com' LIMIT 1;
  SELECT id INTO v_vitor_id FROM members WHERE email = 'vitor.rodovalho@outlook.com' LIMIT 1;

  -- 3. Insert committee members
  IF v_fabricio_id IS NOT NULL THEN
    INSERT INTO selection_committee (cycle_id, member_id, role, can_interview)
    VALUES (v_cycle_id, v_fabricio_id, 'lead', true);
  END IF;

  IF v_vitor_id IS NOT NULL THEN
    INSERT INTO selection_committee (cycle_id, member_id, role, can_interview)
    VALUES (v_cycle_id, v_vitor_id, 'lead', true);
  END IF;

  -- ============================================================
  -- 4. Applications (62 records: 50 researchers + 12 leaders)
  -- ============================================================
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Alexandre Meirelles', 'alexacm60@gmail.com', '+5531999035034', '1460040', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/alexandremeirelles/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1460040.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A18Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=SkKACK28o3CjwmFkW9wx1vZCRD5QezMcNRxF8wlbGaE%3D', 'Student Membership,Minas Gerais, Brazil Chapter,Espírito Santo, Brazil Chapter', 'PMP,Pmi-Rmp,Pmo-Cp,Pmi-Pmocp', 'researcher', 'approved', '{}'::text[], NULL, NULL, 134, 11, 145, 1, 1, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Paulo Alves De Oliveira Junior', 'paulo-junior@outlook.com', '+14252491264', '1158211', 'PMI-GO', 'FL', 'United States', 'https://www.linkedin.com/in/pejota/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1158211.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A40Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=g36N8TF2CGbrQAxTeup%2FunewRlG6Ihds2qualGf3uFs%3D', NULL, 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 124, 13, 137, 1, 2, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Ana Carla Cavalcante', 'anagatcavalcante@gmail.com', '+5585986118454', '12227090', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/anacarlacavalcante/', NULL, NULL, NULL, 'researcher', 'converted', '{convert_to_leader}', 'researcher', 'leader', 118, 12, 130, 1, 3, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Gerson Albuquerque Neto', 'gersonvan@gmail.com', '+5585997666577', '1751501', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/gersonvalbuquerquen/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1751501.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A30Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=D9IUN89zFTL%2B3vIQ13OheJsup7l9gH8Dq18M%2F%2Bbl4lE%3D', 'Individual Membership,Ceará, Brazil Chapter', NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 110, 9, 119, 2, 4, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Hayala Curto', 'hayala.curto@gmail.com', '+553199535798', '367666', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/hayala/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/367666.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A38Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=cPGfO1fuK4DMT6jg1Ea5io35evY%2BqqTyOXXHaONva9s%3D', 'Student Membership,Minas Gerais, Brazil Chapter,Central Italy Chapter', 'PMP,Pmi-Sp,Pmi-Rmp', 'researcher', 'converted', '{convert_to_leader}', 'researcher', 'leader', 107, 12, 119, 2, 4, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Lídia Do Vale', 'lidiadovalle@gmail.com', '+5562998070112', '9978497', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/lidia-alcantara-do-vale/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/9978497.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A25Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=33aF8FnYvgBqkUUlxopxm99TUcDybtsdZ%2Fl9SmispFo%3D', 'Student Membership,Goiás, Brazil Chapter', NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 102, 13, 115, 2, 6, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Herlon Alves De Sousa', 'saguaho@gmail.com', '+558591260092', '5592639', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/herlon-sousa-b0b16660/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/5592639.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A29Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=bMis7hMuNsMIZq3RZ4IpALUCqRDrOMe8pAfh1OzHc9s%3D', NULL, 'PMP', 'researcher', 'withdrawn', '{}'::text[], NULL, NULL, 109, NULL, 109, 3, 7, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Ricardo Santos', 'r_frana@yahoo.com.br', '+5521999994756', '850146', 'PMI-MG', 'RJ', 'Brazil', 'https://www.linkedin.com/in/ricardofrancasantos/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/850146.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A14Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=5et0%2BOdGIAK%2FcCzgdqjK7PZ7AaIsCz9P6rITLY2Tspw%3D', 'Retiree Membership,Minas Gerais, Brazil Chapter', 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 95, 11, 106, 3, 8, 'tem problema de horario na quarta a noite', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Pedro Henrique Rodrigues Mendes', 'pedrojjp2@gmail.com', '+5561991614136', '11909310', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/pedro-henrique-rodrigues-mendes-69769072/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/11909310.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A22Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=T9m3rKHhF19dH8241xYppaAirp2%2Bvxn%2BW7EnKFy%2FalU%3D', 'Student Membership,Distrito Federal, Brazil Chapter', 'Cpmai,Pmi-Cpmai', 'researcher', 'approved', '{}'::text[], NULL, NULL, 98, 7, 105, 1, 9, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Wellinghton Pereira Barboza', 'wbarbozaeng@gmail.com', '+50496176336', '6301187', 'PMI-GO', 'MG', 'Brazil', 'https://www.linkedin.com/in/wellinghton-pereira-barboza-mba-pmp%C2%AE-prince2%C2%AE-psm-i%C2%AE-pspo-i%C2%AE-ckms-8833762a4/?locale=en_US', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/6301187.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A05Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=9hfqQLqULRHC9BqOHT3TKCSB3u%2BupnbLgBrznKXwKAQ%3D', 'Individual Membership,Goiás, Brazil Chapter,Honduras Chapter', 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 88, 13, 101, 3, 10, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Marcos Antunes Klemz', 'maklemz@gmail.com', '+148988055519', '5428333', 'PMI-MG', 'SC', 'United States', 'https://www.linkedin.com/in/maklemz/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/5428333.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A44Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=d0CYYeyoO6%2F%2FigKRe7c5xA9HKpAxkxDAFgXCCOskFEo%3D', 'Individual Membership,Minas Gerais, Brazil Chapter,Carolina Chapter', 'PMP', 'researcher', 'converted', '{convert_to_leader}', 'researcher', 'leader', 84, 11, 95, 4, 11, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Mayanna Duarte', 'mayanna.aires@gmail.com', '+5598992344014', '9597956', 'PMI-CE', 'MA', 'Brazil', 'https://www.linkedin.com/in/mayanna-duarte-547173121/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/9597956.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A47Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=rKFFG3ghuZ6GLaj%2Bsk9HRipBfrI4346uFwSZRxvQBKs%3D', 'Student Membership,Ceará, Brazil Chapter', NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 81, 12, 93, 4, 12, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Antonio Marcos Costa', 'marcosmouracosta@gmail.com', '+556592648171', '7381882', 'PMI-GO', 'MT', 'Brazil', 'https://www.linkedin.com/in/marcos-costa-eng-automa%C3%A7ao/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/7381882.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A11Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=VxfRRZXSEmfzvvbc2hmTKT1tLY92Ka7PvRWkOPurCHA%3D', 'Student Membership,Goiás, Brazil Chapter', 'PMP,Dasm', 'researcher', 'approved', '{}'::text[], NULL, NULL, 78, 11, 89, 4, 13, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Letícia Vieira', 'lrvieira@universo.univates.br', '+555181735636', NULL, 'PMI-RS', 'RS', 'Brazil', 'https://www.linkedin.com/in/letícia-rodrigues-vieira/', NULL, NULL, NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 75, 12.5, 87.5, 1, 14, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Thiago Freire', 'thiagorfreire@gmail.com', '+5521988006325', '12265640', 'PMI-GO', 'RJ', 'Brazil', 'https://www.linkedin.com/in/thiagorfreire/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12265640.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A54Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=LWvE0jcVQlf9b2y6qCRIyZso%2BmubzMsyzbeSTprCQKY%3D', NULL, NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 75, 12, 87, 5, 15, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Leonardo Chaves', 'leonardo.grandinetti@gmail.com', '+5531992421793', '1445614', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/grandi/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1445614.docx?sv=2024-08-04&se=2026-01-17T16%3A35%3A10Z&sr=b&sp=r&rscd=inline&sig=KIgNDeqpeLUUsmdfmio%2BcVCIXl%2B%2BaLu%2B3HgJe%2BDlPFQ%3D', 'Individual Membership,Minas Gerais, Brazil Chapter,São Paulo, Brazil Chapter', 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 74, 12, 86, 5, 16, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Fabricia Maciel', 'maciel.fabricia@gmail.com', '+5531993821515', '2831305', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/fabricia-maciel-b062aa38/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/2831305.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A11Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=fssptHwGzHOBY4A0H8%2By2bLLsyBOj%2B9IecsUSVwE29Y%3D', NULL, NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 74, 12, 86, 5, 16, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Guilhere Matricarde Matricarde', 'guilherme.mmat@gmail.com', '+5516981468986', '9116683', 'PMI-CE', 'SP', 'Brazil', 'https://www.linkedin.com/in/guilherme-matheus-matricarde/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/9116683.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A07Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=hUVyKdHbmFdF4mfi3IPsuyLoQsTuzPfg9IXTAxpQxuk%3D', 'Individual Membership,Ceará, Brazil Chapter', NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 73, 13, 86, 5, 16, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Rodolfo Santana', 'rodolfosiqueirasantana@gmail.com', '+5531998523288', '1084916', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/rodolfo-siqueira-santana-msc-pmp/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1084916.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A04Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=B6L%2FCTqWal31Q6Ittsd4q6T5Qhf%2F7Y%2FaDfEN4R4VWa8%3D', 'Individual Membership', 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 75, 10, 85, 7, 19, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Leandro Mota', 'leandro_mota@hotmail.com', '+5561982146613', '2410458', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/leandro-w-m-mota-pmp-41777b27/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/2410458.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A33Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=%2FiLu%2BOhLbkxew48lTKc292a8ZmRBtjh%2Bngb3wEq4FWg%3D', 'Individual Membership,Distrito Federal, Brazil Chapter', 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 69, 11, 80, 2, 20, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Daniel Bittencourt', 'dlbittencourt@hotmail.com', '+5531984781922', '8504849', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/daniel-leite-bittencourt/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/8504849.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A16Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=XGnPl6dhpG20yzMqWfL%2BTxSyLZ6GRpWFyzqiaIG6Oh0%3D', 'Individual Membership,Minas Gerais, Brazil Chapter', 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 72, 8, 80, 8, 20, 'So não pode as quartas (dia da guarda da filha)', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Gustavo Batista Ferreira', 'eng.gustavobatista@gmail.com', '+5585999917598', '5109519', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/gustavo-batista-38280490/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/5109519.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A05Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=qz6kUYV0eipnivYnUPsPWSn9%2FtDsJn9zqzwXq4uIFvU%3D', 'Student Membership,Ceará, Brazil Chapter', 'PMP,Dasm', 'researcher', 'approved', '{}'::text[], NULL, NULL, 67, 11, 78, 6, 22, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Italo Soares Nogueira', 'italo.sn@hotmail.com', '+5562992795103', '8704241', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/italo-soares-nogueira-44933a11b/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/8704241.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A48Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=OEFnXa4IUJ3RnAW8KAqrI4XR0WtOpHZT68Vlklw1OYk%3D', 'Individual Membership,Goiás, Brazil Chapter', NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 66, 11, 77, 6, 23, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Stephania Marta De Souza', 'stephaniamarta@gmail.com', '+5561981213216', '10083828', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/stephania-marta/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/10083828.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A52Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=FHnZlPHctkXiqd%2FNL4HHppVY3Ot%2FFX28HqptPa59HF4%3D', 'Individual Membership,Distrito Federal, Brazil Chapter', 'PMP', 'researcher', 'approved', '{}'::text[], NULL, NULL, 68, 8, 76, 3, 24, 'Não sei, fiquei com receio de alinhamento/espectativa', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Rodrigo Grilo Gomes', 'rodrigo_ggomes@hotmail.com', '+5562983106910', '3299447', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/rodrigo-grilo-gomes-pmp-64805396/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/3299447.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A08Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=w%2F5vpuxxVgddH42k8N0RwH6mD5qkFcrLzI8euegN9bY%3D', 'Individual Membership,Goiás, Brazil Chapter', 'PMP,Pmo-Cp,Pmi-Pmocp', 'researcher', 'approved', '{}'::text[], NULL, NULL, 66, 7, 73, 7, 25, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Ligia Costa', 'ligiacostaribeiro@gmail.com', '+5585994535863', '10060395', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/ligiacostaribeiro/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/10060395.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A10Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=5UI%2B1SrcT8CGmyA5OaoRfTXAql6FEHvSNriHyaXvfdo%3D', 'Student Membership,Ceará, Brazil Chapter', NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 63, 8, 71, 7, 26, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Edson Costa', 'eng.edsoncosta@hotmail.com', NULL, '12262677', 'PMI-CE', NULL, 'Brazil', 'https://www.linkedin.com/in/edson-costa-57a5a7137/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12262677.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A26Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=LBuuE%2B6uvWzh5igtuWbrF9vn2NQdHhAHiPqrl5e4U94%3D', NULL, NULL, 'researcher', 'cancelled', '{}'::text[], NULL, NULL, 66, NULL, 66, 8, 27, 'Não retornou contato via Linkedin e nem E-mail', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Erick Oliveira', 'erickoliveirarel@gmail.com', '+5561982820869', '12236986', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/erick-oliveira-ri/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12236986.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A15Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=pNNeq0lHUZiUt8jgwxecebwTazVSrkQLy31lIu8vRM4%3D', NULL, NULL, 'researcher', 'rejected', '{}'::text[], NULL, NULL, 56, 7, 63, 4, 28, 'Ainda não é o momento dele em maturidade para este projeto, Ainda não vinculado ao PMI, Estudante de Relações Internacionais', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Alessandra Dourado', 'ale1gold@hotmail.com', '+5561995953424', '7786524', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/alessandradouradoalves/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/7786524.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A36Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=VYfjv7Dw0aRGvbwl4tUA4pZYYXJ%2BydTOp9%2BiRSZWvvc%3D', 'Individual Membership,Distrito Federal, Brazil Chapter', 'Capm', 'researcher', 'cancelled', '{}'::text[], NULL, NULL, 60, NULL, 60, 5, 29, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Adalberto Neris', 'adalbertoneris@gmail.com', '+5543991496131', '12238778', NULL, 'PR', 'Brazil', 'https://www.linkedin.com/in/adalbertoneris/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12238778.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A03Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=UmAIgrK6%2FEwETX%2FjdDaHigwP2CP3TsjAk9keNwennSY%3D', NULL, NULL, 'researcher', 'withdrawn', '{}'::text[], NULL, NULL, 50, 9, 59, 1, 30, 'Informou que Não poderá se filiar neste semestre', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Kelly Penga', 'kellypenga@gmail.com', '+5561981639924', '12275895', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/kelly-penga-8baa2451/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12275895.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A57Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=YaMrQMVw9cvoSbNWgGZu5KrUo4i9OF1A%2BgrvwFjTQlw%3D', NULL, NULL, 'researcher', 'withdrawn', '{}'::text[], NULL, NULL, 48, 9, 57, 6, 31, 'Apesar de aprovada, solicitou withdraw', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Grazielle Santos', 'graziellessantos@gmail.com', '+5561984418343', '7370905', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/graziellessantos/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/7370905.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A34Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=VjXNhFSJduGQGa2CrOBnRb1crisf5Jj%2FlrM8XVETvHI%3D', 'Individual Membership,Distrito Federal, Brazil Chapter', NULL, 'researcher', 'cancelled', '{}'::text[], NULL, NULL, 57, NULL, 57, 6, 31, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Vinicyus Saraiva De Sousa', 'vinicyus-saraiva@hotmail.com', '+5562993079819', '11413480', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/vinicyus-saraiva-de-sousa/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/11413480.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A20Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=KqjHMxS8RdfUvRR4HLi1LiagalEP98OaAgDRyaqTE60%3D', 'Student Membership,Goiás, Brazil Chapter', NULL, 'researcher', 'approved', '{}'::text[], NULL, NULL, 46, 10, 56, 8, 33, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Natália Souza', 'nataliadesouzas19@gmail.com', '+5585986902909', '11456625', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/natalia-souzas/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/11456625.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A01Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=cuCDYgTDOONrPPlgazPpZtCAgo9sG3eMIHQMCwO0yks%3D', 'Student Membership,São Paulo, Brazil Chapter,Ceará, Brazil Chapter', NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 53, NULL, 53, 9, 34, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Deborah Pontes', 'deborahvpontes@gmail.com', '+5585998509219', '2071924', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/deborah-veloso-de-pontes-aa79aa23/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/2071924.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A13Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=TGnXjE8y3qQ6C%2Fb7DPWhbXoEr0LI%2FZNbc8mjbxnFYSQ%3D', 'Individual Membership,Ceará, Brazil Chapter', 'PMP', 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 48, NULL, 48, 10, 35, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Andressa Martins', 'catoze@gmail.com', '+556282663727', '7573695', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/catoze/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/7573695.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A13Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=rn0IFy7cMOv3mgwT%2B8OOrZi5Mu6NushidJWnqOzd89I%3D', 'Student Membership,Goiás, Brazil Chapter', NULL, 'researcher', 'waitlist', '{}'::text[], NULL, NULL, 43, 5, 48, 9, 35, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Robson Tavares', 'rtr.1979.10.7@gmail.com', '+5531994846128', '5809089', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/robson-tavares-b5050467/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/5809089.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A45Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=iJ3hgzbSXyA2JzGekVO0n26p2v3GQ7sOVbejAb8p9Yo%3D', NULL, NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 44, NULL, 44, 9, 37, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Patricia Mesquita', 'patriciamesquita@id.uff.br', '+5521985495008', '12268657', NULL, 'RJ', 'Brazil', 'https://www.linkedin.com/in/patricia-mesquita-2021/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12268657.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A32Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=VLIp1Amn%2FLK4ZF9bR3wq808rRpfu8oFZGtrikhYrZCA%3D', NULL, NULL, 'researcher', 'cancelled', '{}'::text[], NULL, NULL, 44, NULL, 44, 2, 37, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Marcio Vidal', 'mfvidal@gmail.com', NULL, '7772310', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/marciovidal/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/7772310.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A19Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=j5pQWr5%2FPnAo7nG36yKcYrbEui97F9CgJdLLqLQ8vBM%3D', 'Student Membership,Ceará, Brazil Chapter', NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 39, NULL, 39, 11, 39, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Fabiano Bressiani', 'fbressiani@unknown.com', NULL, NULL, 'PMI-RS', 'RS', 'Brazil', 'https://www.linkedin.com/in/fbressiani/', NULL, NULL, NULL, 'researcher', 'submitted', '{}'::text[], NULL, NULL, 30, 5, 35, 2, 40, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Gabriela Ferreira', 'couto.gabrielaf@gmail.com', '+553197343-2957', '11387109', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/gabrielamcferreira', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/11387109.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A59Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=8wvz27uFscnB2qNASy4MBf70tBowX03sFdLfKKZQ3ZM%3D', 'Student Membership,Minas Gerais, Brazil Chapter', NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 34, NULL, 34, 10, 41, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Vanessa Andrade', 'vanesafag@gmail.com', NULL, '9028174', 'PMI-DF', 'DF', 'Brazil', 'https://www.linkedin.com/in/vanessa-freitas-andrade-aa4845226/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/9028174.pdf?sv=2024-08-04&se=2026-01-17T16%3A36%3A08Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=wO4gskNPGuPQVyLmZDlTyuahtwZRYngWrbP4DsMpX2M%3D', 'Individual Membership,Distrito Federal, Brazil Chapter', 'Dasm', 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 33, NULL, 33, 8, 42, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Ana Paula Afonso Barbosa', 'anapaulaafonsobarbosa@gmail.com', '+5562993764437', '9951716', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/ana-paula-afonso-barbosa/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/9951716.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A42Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=Nz06MRu2gQfDFFdSeDqMxLEENLgAzkpxgv%2BDDgQDjYw%3D', NULL, NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 30, NULL, 30, 10, 43, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Jéssica Rodrigues Santa Rosa', 'jessica.r.santarosa@gmail.com', '+5562981214974', '12232738', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/jessicasantarosa/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12232738.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A43Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=qX%2FWJVlR%2B6nedfHhXZOei7z3OyduR1z1CePkpUa8dBc%3D', NULL, NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 30, NULL, 30, 10, 43, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Rayara Pinheiro', 'rayaraps93@gmail.com', '+5585991274488', '12290236', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/rayarapinheiro93/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12290236.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A56Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=qReReT7ZV4d7%2FaaB8BdBKzyhEFRGnWuZ0meQFfA94VA%3D', NULL, NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 23, NULL, 23, 12, 45, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Maurício Machado', 'mauricio.abe.machado@gmail.com', '+556192173113', '1081185', 'PMI-CE', 'DF', 'Brazil', 'https://www.linkedin.com/in/mauricioabe/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1081185.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A50Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=vVxwib5DvUXTMpI5Qr4XBaXvr38o0GgYsCV%2FVzc0dmA%3D', 'Individual Membership,Ceará, Brazil Chapter', 'PMP', 'researcher', 'submitted', '{}'::text[], NULL, NULL, 22, NULL, 22, 13, 46, 'Já é voluntário, pelo segundo ciclo', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Luciana Dutra Martins', 'lucianadutramartins@outlook.com', '+5562984018324', '3053549', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/luciana-dutra-martins-51b8b643/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/3053549.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A04Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=g%2F6sjlZgGoVnE5TYA3YdkrqiGVLWR4OQDraBSfdWGq0%3D', 'Individual Membership,Goiás, Brazil Chapter', 'PMP', 'researcher', 'submitted', '{}'::text[], NULL, NULL, 22, NULL, 22, 12, 46, 'Já é voluntário, pelo segundo ciclo', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Charanvenkatesh Gorle', 'charanvenkatesh2004@gmail.com', '+917780760730', '11895842', 'VOID', NULL, 'India', 'https://www.linkedin.com/in/charanvenkatesh-gorle-a16680232/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/11895842.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A39Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=i9n9WDWqj%2B4KsrNqjHa%2B%2FLkN3384QogZrVtrce2hBw8%3D', NULL, NULL, 'researcher', 'submitted', '{}'::text[], NULL, NULL, 22, NULL, 22, 1, 46, 'Desclassificado - barreira linguistica, projecto rodado em Pt-br', now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Ana Carla De Oliveira', 'anacarla.enge@gmail.com', '+556298310025', '9950860', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/ana-carla-oliveira-2b22b293/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12227090.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A28Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=39kHAaDhKBT28qUvqba2b38NVGJHv5Mzttpun4sS2rk%3D', NULL, NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 21, NULL, 21, 13, 49, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, objective_score_avg, interview_score, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Daniel Canuto', 'canutoaugusto123@gmail.com', '+5562994991967', '10569967', 'PMI-GO', 'GO', 'Brazil', 'https://www.linkedin.com/in/daniel-canuto-2491a9224/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/10569967.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A55Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=%2FhtMCEtVmRKa5guEJP37Lpa%2FJbD86k1dnpXnXwm7KYs%3D', NULL, NULL, 'researcher', 'objective_cutoff', '{}'::text[], NULL, NULL, 20, NULL, 20, 14, 50, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Hayala Curto', 'hayala.curto@gmail.com', '+553199535798', '367666', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/hayala/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/367666.pdf?sv=2024-08-04&se=2026-01-17T16%3A35%3A38Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=cPGfO1fuK4DMT6jg1Ea5io35evY%2BqqTyOXXHaONva9s%3D', 'Student Membership,Minas Gerais, Brazil Chapter,Central Italy Chapter', 'PMP,Pmi-Sp,Pmi-Rmp', 'leader', 'approved', '{}'::text[], NULL, NULL, 96, 1, 1, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Fabricio Costa', 'fabriciorcc@gmail.com', '+15035447898', '1971339', 'PMI-GO', 'VA', 'United States', 'https://www.linkedin.com/in/fabriciorcc/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1971339.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A09Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=Bb3aFztGDzP%2FOvhFbPRI7van%2BpSfB1D03Qt5KdaLHbw%3D', 'Individual Membership,Goiás, Brazil Chapter,Washington, Dc Chapter', 'PMP', 'leader', 'approved', '{}'::text[], NULL, NULL, 88, 1, 2, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Marcel Fleming', 'fleming.marcel@yahoo.com.br', '+5534998039899', '1218766', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/marcelfleming', 'Pasta Drive', 'Individual Membership,Minas Gerais, Brazil Chapter,Carolina Chapter', 'PMP', 'leader', 'approved', '{}'::text[], NULL, NULL, 83.5, 2, 3, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Fernando Maquiaveli', 'fernando@maquiaveli.com.br', '+5511981455963', '1057095', 'PMI-DF', 'SP', 'Brazil', 'https://www.linkedin.com/in/fernandomaquiaveli/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1057095.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A12Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=IRELVdsGfANX7A55carFtxZXDMXAUIq68Kkh2AoIzzo%3D', 'Individual Membership,Distrito Federal, Brazil Chapter,São Paulo, Brazil Chapter', 'PMP,DASSM', 'leader', 'approved', '{}'::text[], NULL, NULL, 81, 1, 4, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Jefferson Pinto', 'jefferson.pinheiro.pinto@gmail.com', '+351936041519', '2353763', 'PMI-DF', '11.0', 'Portugal', 'https://www.linkedin.com/in/jeffersonpp/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/2353763.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A11Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=T184gNahodosU1RjBcZ5WfUEOwkiK2Pk%2Fr9XZHbOpLQ%3D', 'Student Membership,Portugal Chapter, Distrito Federal, Brazil Chapter', 'PMP', 'leader', 'approved', '{}'::text[], NULL, NULL, 80, 2, 5, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Marcos Antunes Klemz', 'maklemz@gmail.com', '+5548988055519', '5428333', 'PMI-MG', 'SC', 'United States', 'https://www.linkedin.com/in/maklemz/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/5428333.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A05Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=DUbaPmnDJ9J5wjSV0Xt6MVO9XlsiurcWkCRT7HH1j8s%3D', 'Individual Membership,Minas Gerais, Brazil Chapter,Carolina Chapter', 'PMP', 'leader', 'approved', '{}'::text[], NULL, NULL, 71, 3, 6, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Ana Carla Cavalcante', 'anagatcavalcante@gmail.com', '+5585986118454', '12227090', 'PMI-CE', 'CE', 'Brazil', 'https://www.linkedin.com/in/anacarlacavalcante/', NULL, NULL, NULL, 'leader', 'approved', '{}'::text[], NULL, NULL, 68, 1, 7, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Rodolfo Santana', 'rodolfosiqueirasantana@gmail.com', '+5531998523288', '1084916', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/rodolfo-siqueira-santana-msc-pmp/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/1084916.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A08Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=iTzMsABLSzEwHx5RBisdz4GCGgulnNZiod2rCX1gv1M%3D', 'Individual Membership', 'PMP', 'leader', 'converted', '{convert_to_researcher}', 'leader', 'researcher', 67, 4, 8, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Telson Alves', 'telsonvieira@gmail.com', '+5521993979057', '6331409', 'PMI-MG', 'MG', 'Brazil', 'https://www.linkedin.com/in/telsonvieira/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/6331409.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A07Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=r8T5g9mQWAXdvh6YZP4h%2F2kgkUjay0djJjbH%2BvehnS4%3D', 'Individual Membership,Minas Gerais, Brazil Chapter', 'PMP', 'leader', 'converted', '{convert_to_researcher}', 'leader', 'researcher', 57, 5, 9, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Estela Boiani', 'estelaboiani.arq@gmail.com', '+5548999965429', '7844148', NULL, 'SC', 'Brazil', 'https://www.linkedin.com/in/estela-boiani-17737045/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/7844148.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A14Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=pPMmlVdgPscCY%2B7zUUdNDOCtd9BEiqYonvCaQY%2B3kk0%3D', NULL, NULL, 'leader', 'rejected', '{}'::text[], NULL, NULL, 54.5, 1, 10, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Adalberto Neris', 'adalbertoneris@gmail.com', '+5543991496131', '12238778', NULL, 'PR', 'Brazil', 'https://www.linkedin.com/in/adalbertoneris/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12238778.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A15Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=EjpMeg25txwcMeks0jomQygPjPdtIK6ETMr2kLhryLQ%3D', NULL, NULL, 'leader', 'converted', '{convert_to_researcher}', 'leader', 'researcher', 54, 2, 11, NULL, now());
INSERT INTO selection_applications (cycle_id, applicant_name, email, phone, pmi_id, chapter, state, country, linkedin_url, resume_url, membership_status, certifications, role_applied, status, tags, converted_from, converted_to, final_score, rank_chapter, rank_overall, feedback, imported_at)
VALUES (v_cycle_id, 'Fernanda Longato De Moura', 'contato@fernandalongato.com', '+5548988264356', '12268793', NULL, 'SC', 'Brazil', 'https://www.linkedin.com/in/fernandalongato/', 'https://cavprodeastusshared.blob.core.windows.net/vep-resume-storage/12268793.pdf?sv=2024-08-04&se=2026-01-17T15%3A50%3A03Z&sr=b&sp=r&rscd=inline&rsct=application%2Fpdf&sig=PohRZGtjpfrSH4SZ0%2BEz0UF6WmKorEvtlOFrwZCrdMM%3D', NULL, NULL, 'leader', 'withdrawn', '{}'::text[], NULL, NULL, 43.5, 3, 12, 'Canditada cancelou candidatura', now());
  -- ============================================================
  -- 5. Evaluations (159 records: objective + interview + leader_extra)
  -- ============================================================
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 5.0}'::jsonb, 67, now()
FROM selection_applications a, members m
WHERE a.email = 'alexacm60@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 5.0}'::jsonb, 67, now()
FROM selection_applications a, members m
WHERE a.email = 'alexacm60@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'alexacm60@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 63, now()
FROM selection_applications a, members m
WHERE a.email = 'paulo-junior@outlook.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 4.0}'::jsonb, 61, now()
FROM selection_applications a, members m
WHERE a.email = 'paulo-junior@outlook.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 13, now()
FROM selection_applications a, members m
WHERE a.email = 'paulo-junior@outlook.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 3.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 57, now()
FROM selection_applications a, members m
WHERE a.email = 'anagatcavalcante@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 61, now()
FROM selection_applications a, members m
WHERE a.email = 'anagatcavalcante@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 2.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'anagatcavalcante@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 3.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 55, now()
FROM selection_applications a, members m
WHERE a.email = 'gersonvan@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 5.0, "gp_knowledge": 3.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 55, now()
FROM selection_applications a, members m
WHERE a.email = 'gersonvan@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 2.0}'::jsonb, 9, now()
FROM selection_applications a, members m
WHERE a.email = 'gersonvan@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 57, now()
FROM selection_applications a, members m
WHERE a.email = 'hayala.curto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 4.0, "gp_knowledge": 4.0, "ai_knowledge": 3.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 50, now()
FROM selection_applications a, members m
WHERE a.email = 'hayala.curto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'hayala.curto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 5.0}'::jsonb, 59, now()
FROM selection_applications a, members m
WHERE a.email = 'lidiadovalle@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 2.0, "ai_knowledge": 4.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 4.0}'::jsonb, 43, now()
FROM selection_applications a, members m
WHERE a.email = 'lidiadovalle@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 13, now()
FROM selection_applications a, members m
WHERE a.email = 'lidiadovalle@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 5.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 59, now()
FROM selection_applications a, members m
WHERE a.email = 'saguaho@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 2.0, "gp_knowledge": 4.0, "ai_knowledge": 3.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 4.0}'::jsonb, 50, now()
FROM selection_applications a, members m
WHERE a.email = 'saguaho@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 5.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 41, now()
FROM selection_applications a, members m
WHERE a.email = 'r_frana@yahoo.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 3.0, "ai_knowledge": 4.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 54, now()
FROM selection_applications a, members m
WHERE a.email = 'r_frana@yahoo.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 2.0, "culture_alignment": 2.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'r_frana@yahoo.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 1.0, "ai_knowledge": 5.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 47, now()
FROM selection_applications a, members m
WHERE a.email = 'pedrojjp2@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 4.0, "gp_knowledge": 2.0, "ai_knowledge": 4.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 5.0}'::jsonb, 51, now()
FROM selection_applications a, members m
WHERE a.email = 'pedrojjp2@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 1.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 2.0}'::jsonb, 7, now()
FROM selection_applications a, members m
WHERE a.email = 'pedrojjp2@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 1.0, "gp_knowledge": 5.0, "ai_knowledge": 3.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 45, now()
FROM selection_applications a, members m
WHERE a.email = 'wbarbozaeng@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 2.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 4.0}'::jsonb, 43, now()
FROM selection_applications a, members m
WHERE a.email = 'wbarbozaeng@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 13, now()
FROM selection_applications a, members m
WHERE a.email = 'wbarbozaeng@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 5.0, "ai_knowledge": 1.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 41, now()
FROM selection_applications a, members m
WHERE a.email = 'maklemz@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 2.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 43, now()
FROM selection_applications a, members m
WHERE a.email = 'maklemz@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'maklemz@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 5.0}'::jsonb, 43, now()
FROM selection_applications a, members m
WHERE a.email = 'mayanna.aires@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 2.0, "ai_knowledge": 3.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 4.0}'::jsonb, 38, now()
FROM selection_applications a, members m
WHERE a.email = 'mayanna.aires@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'mayanna.aires@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 35, now()
FROM selection_applications a, members m
WHERE a.email = 'marcosmouracosta@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 43, now()
FROM selection_applications a, members m
WHERE a.email = 'marcosmouracosta@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 3.0, "teamwork": 2.0, "culture_alignment": 3.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'marcosmouracosta@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 39, now()
FROM selection_applications a, members m
WHERE a.email = 'thiagorfreire@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 2.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 36, now()
FROM selection_applications a, members m
WHERE a.email = 'thiagorfreire@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 2.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'thiagorfreire@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 5.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 41, now()
FROM selection_applications a, members m
WHERE a.email = 'leonardo.grandinetti@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 33, now()
FROM selection_applications a, members m
WHERE a.email = 'leonardo.grandinetti@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'leonardo.grandinetti@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 1.0, "gp_knowledge": 5.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 37, now()
FROM selection_applications a, members m
WHERE a.email = 'maciel.fabricia@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 1.0, "ai_knowledge": 3.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 37, now()
FROM selection_applications a, members m
WHERE a.email = 'maciel.fabricia@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'maciel.fabricia@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 0.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 31, now()
FROM selection_applications a, members m
WHERE a.email = 'guilherme.mmat@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 1.0, "gp_knowledge": 4.0, "ai_knowledge": 3.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 42, now()
FROM selection_applications a, members m
WHERE a.email = 'guilherme.mmat@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 13, now()
FROM selection_applications a, members m
WHERE a.email = 'guilherme.mmat@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 37, now()
FROM selection_applications a, members m
WHERE a.email = 'rodolfosiqueirasantana@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 2.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 2.0}'::jsonb, 38, now()
FROM selection_applications a, members m
WHERE a.email = 'rodolfosiqueirasantana@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 2.0}'::jsonb, 10, now()
FROM selection_applications a, members m
WHERE a.email = 'rodolfosiqueirasantana@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 5.0, "ai_knowledge": 0.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 34, now()
FROM selection_applications a, members m
WHERE a.email = 'leandro_mota@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 35, now()
FROM selection_applications a, members m
WHERE a.email = 'leandro_mota@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 2.0, "culture_alignment": 2.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'leandro_mota@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 1.0, "gp_knowledge": 5.0, "ai_knowledge": 1.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 39, now()
FROM selection_applications a, members m
WHERE a.email = 'dlbittencourt@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 33, now()
FROM selection_applications a, members m
WHERE a.email = 'dlbittencourt@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 2.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 2.0}'::jsonb, 8, now()
FROM selection_applications a, members m
WHERE a.email = 'dlbittencourt@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 27, now()
FROM selection_applications a, members m
WHERE a.email = 'eng.gustavobatista@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 2.0, "gp_knowledge": 3.0, "ai_knowledge": 2.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 4.0}'::jsonb, 40, now()
FROM selection_applications a, members m
WHERE a.email = 'eng.gustavobatista@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 2.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'eng.gustavobatista@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 35, now()
FROM selection_applications a, members m
WHERE a.email = 'italo.sn@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 2.0, "ai_knowledge": 2.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 31, now()
FROM selection_applications a, members m
WHERE a.email = 'italo.sn@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'italo.sn@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 31, now()
FROM selection_applications a, members m
WHERE a.email = 'stephaniamarta@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 2.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 37, now()
FROM selection_applications a, members m
WHERE a.email = 'stephaniamarta@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 1.0}'::jsonb, 8, now()
FROM selection_applications a, members m
WHERE a.email = 'stephaniamarta@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 27, now()
FROM selection_applications a, members m
WHERE a.email = 'rodrigo_ggomes@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 2.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 2.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 39, now()
FROM selection_applications a, members m
WHERE a.email = 'rodrigo_ggomes@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 2.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 1.0}'::jsonb, 7, now()
FROM selection_applications a, members m
WHERE a.email = 'rodrigo_ggomes@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 29, now()
FROM selection_applications a, members m
WHERE a.email = 'ligiacostaribeiro@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 2.0, "ai_knowledge": 1.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 4.0}'::jsonb, 34, now()
FROM selection_applications a, members m
WHERE a.email = 'ligiacostaribeiro@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 1.0}'::jsonb, 8, now()
FROM selection_applications a, members m
WHERE a.email = 'ligiacostaribeiro@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 35, now()
FROM selection_applications a, members m
WHERE a.email = 'eng.edsoncosta@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 3.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 31, now()
FROM selection_applications a, members m
WHERE a.email = 'eng.edsoncosta@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 1.0, "ai_knowledge": 3.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 29, now()
FROM selection_applications a, members m
WHERE a.email = 'erickoliveirarel@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 27, now()
FROM selection_applications a, members m
WHERE a.email = 'erickoliveirarel@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 2.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 1.0}'::jsonb, 7, now()
FROM selection_applications a, members m
WHERE a.email = 'erickoliveirarel@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 33, now()
FROM selection_applications a, members m
WHERE a.email = 'ale1gold@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 27, now()
FROM selection_applications a, members m
WHERE a.email = 'ale1gold@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 23, now()
FROM selection_applications a, members m
WHERE a.email = 'adalbertoneris@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 27, now()
FROM selection_applications a, members m
WHERE a.email = 'adalbertoneris@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 2.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 1.0}'::jsonb, 9, now()
FROM selection_applications a, members m
WHERE a.email = 'adalbertoneris@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 3.0, "ai_knowledge": 0.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 24, now()
FROM selection_applications a, members m
WHERE a.email = 'kellypenga@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 2.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 24, now()
FROM selection_applications a, members m
WHERE a.email = 'kellypenga@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 2.0}'::jsonb, 9, now()
FROM selection_applications a, members m
WHERE a.email = 'kellypenga@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 0.0, "gp_knowledge": 3.0, "ai_knowledge": 3.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 31, now()
FROM selection_applications a, members m
WHERE a.email = 'graziellessantos@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 26, now()
FROM selection_applications a, members m
WHERE a.email = 'graziellessantos@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 23, now()
FROM selection_applications a, members m
WHERE a.email = 'vinicyus-saraiva@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 1.0, "ai_knowledge": 3.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 2.0}'::jsonb, 23, now()
FROM selection_applications a, members m
WHERE a.email = 'vinicyus-saraiva@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 2.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 2.0}'::jsonb, 10, now()
FROM selection_applications a, members m
WHERE a.email = 'vinicyus-saraiva@hotmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 3.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 27, now()
FROM selection_applications a, members m
WHERE a.email = 'nataliadesouzas19@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 2.0, "ai_knowledge": 1.0, "tech_skills": 4.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 26, now()
FROM selection_applications a, members m
WHERE a.email = 'nataliadesouzas19@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 0.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 25, now()
FROM selection_applications a, members m
WHERE a.email = 'deborahvpontes@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 2.0, "research_exp": 0.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 23, now()
FROM selection_applications a, members m
WHERE a.email = 'deborahvpontes@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 3.0, "ai_knowledge": 1.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 21, now()
FROM selection_applications a, members m
WHERE a.email = 'catoze@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'catoze@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 1.0, "proactivity": 1.0, "teamwork": 1.0, "culture_alignment": 2.0}'::jsonb, 5, now()
FROM selection_applications a, members m
WHERE a.email = 'catoze@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 3.0, "ai_knowledge": 0.0, "tech_skills": 5.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'rtr.1979.10.7@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'rtr.1979.10.7@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": 1.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'patriciamesquita@id.uff.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'patriciamesquita@id.uff.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 3.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 17, now()
FROM selection_applications a, members m
WHERE a.email = 'mfvidal@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'mfvidal@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'couto.gabrielaf@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'couto.gabrielaf@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 1.0, "research_exp": null, "gp_knowledge": 3.0, "ai_knowledge": null, "tech_skills": null, "availability": null, "motivation": null}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'vanesafag@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'vanesafag@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 8, now()
FROM selection_applications a, members m
WHERE a.email = 'anapaulaafonsobarbosa@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'anapaulaafonsobarbosa@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 0.0}'::jsonb, 8, now()
FROM selection_applications a, members m
WHERE a.email = 'jessica.r.santarosa@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'jessica.r.santarosa@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'rayaraps93@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 0.0, "ai_knowledge": 0.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 2.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'rayaraps93@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": null, "research_exp": null, "gp_knowledge": null, "ai_knowledge": null, "tech_skills": null, "availability": null, "motivation": null}'::jsonb, NULL, now()
FROM selection_applications a, members m
WHERE a.email = 'mauricio.abe.machado@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'mauricio.abe.machado@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": null, "research_exp": null, "gp_knowledge": null, "ai_knowledge": null, "tech_skills": null, "availability": null, "motivation": null}'::jsonb, NULL, now()
FROM selection_applications a, members m
WHERE a.email = 'lucianadutramartins@outlook.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'lucianadutramartins@outlook.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": null, "research_exp": null, "gp_knowledge": null, "ai_knowledge": null, "tech_skills": null, "availability": null, "motivation": null}'::jsonb, NULL, now()
FROM selection_applications a, members m
WHERE a.email = 'charanvenkatesh2004@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 2.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 2.0, "availability": 2.0, "motivation": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'charanvenkatesh2004@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 0.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 1.0, "availability": 1.0, "motivation": 0.0}'::jsonb, 6, now()
FROM selection_applications a, members m
WHERE a.email = 'anacarla.enge@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 1.0, "ai_knowledge": 1.0, "tech_skills": 1.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 15, now()
FROM selection_applications a, members m
WHERE a.email = 'anacarla.enge@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 0.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 10, now()
FROM selection_applications a, members m
WHERE a.email = 'canutoaugusto123@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'objective', '{"certification": 0.0, "research_exp": 1.0, "gp_knowledge": 1.0, "ai_knowledge": 0.0, "tech_skills": 0.0, "availability": 3.0, "motivation": 1.0}'::jsonb, 10, now()
FROM selection_applications a, members m
WHERE a.email = 'canutoaugusto123@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'researcher'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 5.0, "leadership": 4.0, "technical_knowledge": 4.0, "pmi_involvement": 4.0, "language": 3.0}'::jsonb, 42, now()
FROM selection_applications a, members m
WHERE a.email = 'hayala.curto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 5.0, "leadership": 4.0, "technical_knowledge": 4.0, "pmi_involvement": 4.0, "language": 3.0}'::jsonb, 42, now()
FROM selection_applications a, members m
WHERE a.email = 'hayala.curto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'hayala.curto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 5.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 3.0, "language": 3.0}'::jsonb, 36, now()
FROM selection_applications a, members m
WHERE a.email = 'fabriciorcc@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 5.0, "technical_knowledge": 4.0, "pmi_involvement": 5.0, "language": 3.0}'::jsonb, 40, now()
FROM selection_applications a, members m
WHERE a.email = 'fabriciorcc@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'fabriciorcc@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 5.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 1.0, "language": 3.0}'::jsonb, 33, now()
FROM selection_applications a, members m
WHERE a.email = 'fleming.marcel@yahoo.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 4.0, "technical_knowledge": 4.0, "pmi_involvement": 5.0, "language": 3.0}'::jsonb, 37.5, now()
FROM selection_applications a, members m
WHERE a.email = 'fleming.marcel@yahoo.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 13, now()
FROM selection_applications a, members m
WHERE a.email = 'fleming.marcel@yahoo.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 5.0, "leadership": 5.0, "technical_knowledge": 3.0, "pmi_involvement": 0.0, "language": 3.0}'::jsonb, 36.5, now()
FROM selection_applications a, members m
WHERE a.email = 'fernando@maquiaveli.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 2.0, "leadership": 4.0, "technical_knowledge": 4.0, "pmi_involvement": 3.0, "language": 3.0}'::jsonb, 31.5, now()
FROM selection_applications a, members m
WHERE a.email = 'fernando@maquiaveli.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 13, now()
FROM selection_applications a, members m
WHERE a.email = 'fernando@maquiaveli.com.br' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 5.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 3.0, "language": 1.0}'::jsonb, 34, now()
FROM selection_applications a, members m
WHERE a.email = 'jefferson.pinheiro.pinto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 4.0, "leadership": 3.0, "technical_knowledge": 4.0, "pmi_involvement": 5.0, "language": 2.0}'::jsonb, 37, now()
FROM selection_applications a, members m
WHERE a.email = 'jefferson.pinheiro.pinto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 2.0, "proactivity": 2.0, "teamwork": 2.0, "culture_alignment": 3.0}'::jsonb, 9, now()
FROM selection_applications a, members m
WHERE a.email = 'jefferson.pinheiro.pinto@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 3.0, "language": 3.0}'::jsonb, 30, now()
FROM selection_applications a, members m
WHERE a.email = 'maklemz@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 2.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 5.0, "language": 3.0}'::jsonb, 30, now()
FROM selection_applications a, members m
WHERE a.email = 'maklemz@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 11, now()
FROM selection_applications a, members m
WHERE a.email = 'maklemz@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 1.0, "leadership": 5.0, "technical_knowledge": 4.0, "pmi_involvement": 1.0, "language": 3.0}'::jsonb, 28, now()
FROM selection_applications a, members m
WHERE a.email = 'anagatcavalcante@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 1.0, "leadership": 5.0, "technical_knowledge": 4.0, "pmi_involvement": 1.0, "language": 3.0}'::jsonb, 28, now()
FROM selection_applications a, members m
WHERE a.email = 'anagatcavalcante@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 4.0, "proactivity": 3.0, "teamwork": 2.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'anagatcavalcante@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 1.0, "language": 3.0}'::jsonb, 27, now()
FROM selection_applications a, members m
WHERE a.email = 'rodolfosiqueirasantana@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 3.0, "language": 3.0}'::jsonb, 30, now()
FROM selection_applications a, members m
WHERE a.email = 'rodolfosiqueirasantana@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 2.0, "teamwork": 3.0, "culture_alignment": 2.0}'::jsonb, 10, now()
FROM selection_applications a, members m
WHERE a.email = 'rodolfosiqueirasantana@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 0.0, "language": 1.0}'::jsonb, 23.5, now()
FROM selection_applications a, members m
WHERE a.email = 'telsonvieira@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 2.0, "leadership": 2.0, "technical_knowledge": 3.0, "pmi_involvement": 3.0, "language": 0.0}'::jsonb, 21.5, now()
FROM selection_applications a, members m
WHERE a.email = 'telsonvieira@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 3.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 3.0}'::jsonb, 12, now()
FROM selection_applications a, members m
WHERE a.email = 'telsonvieira@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 5.0, "leadership": 3.0, "technical_knowledge": 3.0, "pmi_involvement": 0.0, "language": 0.0}'::jsonb, 28.5, now()
FROM selection_applications a, members m
WHERE a.email = 'estelaboiani.arq@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 4.0, "leadership": 4.0, "technical_knowledge": 2.0, "pmi_involvement": 0.0, "language": 0.0}'::jsonb, 26, now()
FROM selection_applications a, members m
WHERE a.email = 'estelaboiani.arq@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 3.0, "technical_knowledge": 1.0, "pmi_involvement": 0.0, "language": 1.0}'::jsonb, 19.5, now()
FROM selection_applications a, members m
WHERE a.email = 'adalbertoneris@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 4.0, "leadership": 2.0, "technical_knowledge": 2.0, "pmi_involvement": 1.0, "language": 3.0}'::jsonb, 25.5, now()
FROM selection_applications a, members m
WHERE a.email = 'adalbertoneris@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'interview', '{"communication": 2.0, "proactivity": 3.0, "teamwork": 3.0, "culture_alignment": 1.0}'::jsonb, 9, now()
FROM selection_applications a, members m
WHERE a.email = 'adalbertoneris@gmail.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 3.0, "leadership": 3.0, "technical_knowledge": 1.0, "pmi_involvement": 0.0, "language": 3.0}'::jsonb, 21.5, now()
FROM selection_applications a, members m
WHERE a.email = 'contato@fernandalongato.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Fabricio Costa'
LIMIT 1;
INSERT INTO selection_evaluations (application_id, evaluator_id, evaluation_type, scores, weighted_subtotal, submitted_at)
SELECT a.id, m.id, 'leader_extra', '{"research_and_gp_exp": 2.0, "leadership": 3.0, "technical_knowledge": 2.0, "pmi_involvement": 1.0, "language": 3.0}'::jsonb, 22, now()
FROM selection_applications a, members m
WHERE a.email = 'contato@fernandalongato.com' AND a.cycle_id = v_cycle_id AND a.role_applied = 'leader'
AND m.name = 'Vitor Maia Rodovalho'
LIMIT 1;

  RAISE NOTICE 'W124 seed: cycle %, applications + evaluations inserted', v_cycle_id;
END $$;

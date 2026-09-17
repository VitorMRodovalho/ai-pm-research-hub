-- #2296 item 3, onda 2 — o dono decide os 22 badges que faltavam, e a fila zera.
--
-- CONTEXTO: a onda 1 (mig 20260917011621) criou credly_badge_decisions e semeou as 17 decisoes que
-- JA estavam afirmadas em guard. Sobraram 22, e o detector caiu de 39 para 22.
--
-- O QUE MUDOU AGORA: decisao do dono na sessao de 16/09, com o quadro completo na tela — o que a
-- camada G da #2296 exige e que faltou em 15/09. As tres apresentacoes foram:
--
--   Grupo A (10) — variacao anual ou de faixa de badge JA decidido. Nao e julgamento novo: e
--                  estender ao irmao a decisao que ja existe e esta registrada.
--   Grupo C (5)  — certificacao real de terceiro FORA do dominio IA+GP, mesma familia de irmaos ja
--                  decididos sob o limite do #1209.
--   Grupo B (7)  — o julgamento genuino, sem irmao exato.
--
-- ⚠️ CONTROLE MEDIDO ANTES DA DECISAO: o classificador vivo poe TODOS os 22 em badge/10 hoje. Logo,
-- "manter em 10" confirma o estado atual e nao mexe em uma linha de codigo nem reprecifica ninguem;
-- "subir" exigiria palavra-chave nova em classify-badge.ts + reprocessamento. A decisao do dono foi
-- manter os 22, entao gamification_points nao e tocado — e nem poderia ser por remocao, porque e
-- ledger append-only desde a onda 3 da #1087 (desfazer ali e linha compensatoria).
--
-- TRES CASOS TIVERAM NUANCE DECLARADA, e ficam registrados para quem reabrir:
--   * 'IPMA-UCL Megaproject CEO participant' — o tema (megaprojetos) ESTA no dominio de GP, e este
--     e o caso mais defensavel de subir algum dia. Fica em 10 porque o badge atesta PARTICIPACAO
--     ('participant'), nao credencial avaliada.
--   * 'Microsoft Global Hackathon 2026' — participacao em hackathon, nao entrega avaliada.
--   * 'Problem Solving' — nome genérico, e o emissor NAO e identificavel pelo nosso dado (so o nome
--     do badge chega do Credly). Decidido de todo modo porque a decisao e ROBUSTA AO EMISSOR: se for
--     skill badge genérica vale 10 por regra; se for certificacao de terceiro, vale 10 pelo limite
--     do #1209. As duas hipoteses convergem, entao a falta do emissor nao bloqueia a decisao.
--
-- decided_by fica NULL como nas 17 primeiras: a procedencia vive em decision_source, e o repo e
-- publico (nao se nomeia pessoa aqui).
--
-- Cross-ref: #2296, #1209, #1087, #1149.

INSERT INTO public.credly_badge_decisions
  (badge_name, decided_category, rationale, decision_source, decided_on)
VALUES
  -- ── Grupo A: herda decisao de irmao ja registrado ────────────────────────────
  ('Chapter Leader 2022', 'badge',
   'Variacao anual de "Chapter Leader 2023", ja decidido. Reconhecimento de atuacao em capitulo vale 10 por regra.',
   'decisao do dono 2026-09-16 (grupo A: herda de Chapter Leader 2023), issue #2296 item 3', '2026-09-16'),
  ('Lifelong Learning 2025', 'badge',
   'Variacao anual de "Lifelong Learning" / "Lifelong Learning 2026", ambos ja decididos. Fidelidade vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de Lifelong Learning), issue #2296 item 3', '2026-09-16'),
  ('Survey Contributor of The Agile Adoption Report 2022', 'badge',
   'Variacao anual de "...Report 2021", ja decidido. Contribuicao com pesquisa de terceiro vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de Survey Contributor 2021), issue #2296 item 3', '2026-09-16'),
  ('Worldwide Communities - Community Champion 2018', 'badge',
   'Variacao anual de "...Community Champion 2019", ja decidido. Reconhecimento de comunidade vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de Community Champion 2019), issue #2296 item 3', '2026-09-16'),
  ('Worldwide Communities - Community Champion 2020', 'badge',
   'Variacao anual de "...Community Champion 2019", ja decidido. Reconhecimento de comunidade vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de Community Champion 2019), issue #2296 item 3', '2026-09-16'),
  ('Instructor Recognition - 10 Students Reached', 'badge',
   'Outra faixa de "Instructor Recognition - First Class Delivered", ja decidido. Marco de instrutor vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de Instructor Recognition), issue #2296 item 3', '2026-09-16'),
  ('Instructor Recognition - Skillable Announcement', 'badge',
   'Outra faixa de "Instructor Recognition - First Class Delivered", ja decidido. Marco de instrutor vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de Instructor Recognition), issue #2296 item 3', '2026-09-16'),
  ('FY26 LevelUp Contributor', 'badge',
   'Outra faixa de "FY26 LevelUp Super Luminary", ja decidido. Reconhecimento interno de empregador vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de FY26 LevelUp Super Luminary), issue #2296 item 3', '2026-09-16'),
  ('FY26 LevelUp Luminary', 'badge',
   'Outra faixa de "FY26 LevelUp Super Luminary", ja decidido. Reconhecimento interno de empregador vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de FY26 LevelUp Super Luminary), issue #2296 item 3', '2026-09-16'),
  ('FY26 LevelUp Super Contributor', 'badge',
   'Outra faixa de "FY26 LevelUp Super Luminary", ja decidido. Reconhecimento interno de empregador vale 10.',
   'decisao do dono 2026-09-16 (grupo A: herda de FY26 LevelUp Super Luminary), issue #2296 item 3', '2026-09-16'),
  -- ── Grupo C: certificacao de terceiro fora do dominio (limite do #1209) ──────
  ('OneTrust Cookie Consent Expert', 'badge',
   'Certificacao real de privacidade, fora do dominio IA+GP. Mesma familia de "OneTrust Certified Privacy Professional", ja decidido pelo limite do #1209.',
   'decisao do dono 2026-09-16 (grupo C: limite #1209 fora-do-dominio), issue #2296 item 3', '2026-09-16'),
  ('OneTrust Data Mapping Automation Expert', 'badge',
   'Certificacao real de privacidade, fora do dominio IA+GP (limite do #1209).',
   'decisao do dono 2026-09-16 (grupo C: limite #1209 fora-do-dominio), issue #2296 item 3', '2026-09-16'),
  ('OneTrust OneTrust Data Discovery Expert', 'badge',
   'Certificacao real de privacidade, fora do dominio IA+GP (limite do #1209). O nome duplica "OneTrust" na origem; copiado verbatim porque e por ele que o detector casa.',
   'decisao do dono 2026-09-16 (grupo C: limite #1209 fora-do-dominio), issue #2296 item 3', '2026-09-16'),
  ('OneTrust Privacy Rights Automation Expert', 'badge',
   'Certificacao real de privacidade, fora do dominio IA+GP (limite do #1209).',
   'decisao do dono 2026-09-16 (grupo C: limite #1209 fora-do-dominio), issue #2296 item 3', '2026-09-16'),
  ('Oracle Database 10g Administrator Certified Professional - Version Retired', 'badge',
   'Certificacao real de DBA, fora do dominio IA+GP, e a propria versao esta aposentada. Mesma familia de "Oracle Certified Professional, Java SE 5 Programmer" (limite do #1209).',
   'decisao do dono 2026-09-16 (grupo C: limite #1209 fora-do-dominio), issue #2296 item 3', '2026-09-16'),
  -- ── Grupo B: o julgamento genuino ───────────────────────────────────────────
  ('Connected Communities - Engagement Lead 2021', 'badge',
   'Atuacao em comunidade do PMI. Participacao/reconhecimento vale 10 por regra.',
   'decisao do dono 2026-09-16 (grupo B), issue #2296 item 3', '2026-09-16'),
  ('Worldwide Communities - Community SME 2018', 'badge',
   'Reconhecimento de comunidade como especialista de referencia. Reconhecimento vale 10 por regra.',
   'decisao do dono 2026-09-16 (grupo B), issue #2296 item 3', '2026-09-16'),
  ('FY24 Value Based Delivery Platinum', 'badge',
   'Reconhecimento interno de empregador, sem avaliacao externa. Reconhecimento vale 10 por regra.',
   'decisao do dono 2026-09-16 (grupo B), issue #2296 item 3', '2026-09-16'),
  ('FY26 Value Acceleration IP Contributor - Platinum', 'badge',
   'Reconhecimento interno de empregador, sem avaliacao externa. Reconhecimento vale 10 por regra.',
   'decisao do dono 2026-09-16 (grupo B), issue #2296 item 3', '2026-09-16'),
  ('IPMA-UCL Megaproject CEO participant', 'badge',
   'NUANCE DECLARADA: o tema (megaprojetos) esta DENTRO do dominio de GP, e este e o caso mais defensavel de subir algum dia. Fica em 10 porque o badge atesta PARTICIPACAO ("participant"), nao credencial avaliada. Reabrir exige decisao nova e informada, nao inferencia.',
   'decisao do dono 2026-09-16 (grupo B, nuance registrada), issue #2296 item 3', '2026-09-16'),
  ('Microsoft Global Hackathon 2026', 'badge',
   'NUANCE DECLARADA: participacao em hackathon, nao entrega avaliada por banca. Participacao vale 10 por regra, mesmo quando o tema tangencia IA.',
   'decisao do dono 2026-09-16 (grupo B, nuance registrada), issue #2296 item 3', '2026-09-16'),
  ('Problem Solving', 'badge',
   'NUANCE DECLARADA: nome genérico e emissor NAO identificavel pelo nosso dado (do Credly chega so o nome do badge). Decidido porque a decisao e ROBUSTA AO EMISSOR: skill badge genérica vale 10 por regra, e certificacao de terceiro vale 10 pelo limite do #1209 — as duas hipoteses convergem. Se o emissor aparecer e contrariar as duas, reabrir.',
   'decisao do dono 2026-09-16 (grupo B, nuance registrada), issue #2296 item 3', '2026-09-16')
ON CONFLICT (badge_name) DO NOTHING;

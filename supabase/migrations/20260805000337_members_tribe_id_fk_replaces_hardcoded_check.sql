-- 337: members.tribe_id tinha CHECK hardcoded (tribe_id BETWEEN 1 AND 8), que pré-datava
-- a criação de tribos novas e bloqueou a alocação do líder da Tribo 9 (C4). Sem FK.
-- Fix semântico (Pattern 47 — sem hardcode; deriva do SSOT tribes): DROP CHECK + FK a tribes(id).
-- Pré-validado ao vivo: 0 órfãos (members.tribe_id NOT NULL sem row em tribes).
-- Aplicada em prod via apply_migration em 2026-07-04 (sessão kickoff C4).

ALTER TABLE public.members DROP CONSTRAINT members_tribe_id_check;

ALTER TABLE public.members
  ADD CONSTRAINT members_tribe_id_fkey
  FOREIGN KEY (tribe_id) REFERENCES public.tribes(id);

NOTIFY pgrst, 'reload schema';

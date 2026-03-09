-- Extend announcements with optional tribe_id for tribe-specific announcements
-- Null tribe_id = global announcement (current behavior)
-- Non-null tribe_id = visible only to that tribe's members

ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS tribe_id INT REFERENCES public.tribes(id);

COMMENT ON COLUMN public.announcements.tribe_id IS
  'Null = global announcement visible to all. Non-null = visible only to members of this tribe.';

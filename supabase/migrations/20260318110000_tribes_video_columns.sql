-- ═══════════════════════════════════════════════════════════════════════════
-- P3 Fix: Add video_url and video_duration columns to tribes table
-- Backfill from hardcoded src/data/tribes.ts
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Add columns (idempotent)
ALTER TABLE public.tribes ADD COLUMN IF NOT EXISTS video_url TEXT;
ALTER TABLE public.tribes ADD COLUMN IF NOT EXISTS video_duration TEXT;

-- Backfill video data per tribe
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=XJLAvcHFKT8', video_duration = '7min'  WHERE id = 1;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=HwgjMalJXQE', video_duration = '8min'  WHERE id = 2;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=vxQ4WLTyKpY', video_duration = '4min'  WHERE id = 3;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=LZSk96EsepA', video_duration = '3min'  WHERE id = 4;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=KbhnAJdSeDw', video_duration = '5min'  WHERE id = 5;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=R2fA7hVE1dc', video_duration = '11min' WHERE id = 6;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=3su8GgtFzVY', video_duration = '3min'  WHERE id = 7;
UPDATE public.tribes SET video_url = 'https://www.youtube.com/watch?v=ghrgJ3_nk4k', video_duration = '14min' WHERE id = 8;

COMMIT;

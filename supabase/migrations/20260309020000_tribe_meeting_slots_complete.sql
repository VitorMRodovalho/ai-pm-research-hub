-- Complete tribe_meeting_slots for tribes 3, 4, 6 (currently missing)
-- Tribes 1,2,5,7,8 already have slots configured

INSERT INTO public.tribe_meeting_slots (tribe_id, day_of_week, time_start, time_end, is_active) VALUES
  (3, 2, '19:30:00', '20:30:00', true),  -- Tribe 03 TMO & PMO: Tue 19:30
  (4, 3, '20:00:00', '21:00:00', true),  -- Tribe 04 Cultura & Change: Wed 20:00
  (6, 4, '19:00:00', '20:00:00', true)   -- Tribe 06 ROI & Portfólio: Thu 19:00
ON CONFLICT DO NOTHING;

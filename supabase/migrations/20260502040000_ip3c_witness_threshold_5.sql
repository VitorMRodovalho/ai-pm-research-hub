-- Phase IP-3c: bump chapter_witness threshold 4 → 5 now that PMI-GO has witness
-- via chapter_vice_president preposto fallback (Emanuela).

UPDATE public.approval_chains
SET gates = '[
  {"kind": "curator",              "order": 1, "threshold": 1},
  {"kind": "leader_awareness",     "order": 2, "threshold": 0},
  {"kind": "submitter_acceptance", "order": 3, "threshold": 1},
  {"kind": "chapter_witness",      "order": 4, "threshold": 5},
  {"kind": "president_go",         "order": 5, "threshold": 1},
  {"kind": "president_others",     "order": 6, "threshold": 4},
  {"kind": "member_ratification",  "order": 7, "threshold": "all"}
]'::jsonb,
updated_at = now()
WHERE id IN (
  '8b65de6c-b888-468c-892b-8249c8cf0482',
  '47f2d655-6ff2-4cb2-9fe0-97ebd8ba4532',
  '548fd268-0f08-4d90-9518-7bacdc907776'
);

UPDATE public.approval_chains
SET gates = '[
  {"kind": "curator",              "order": 1, "threshold": 1},
  {"kind": "leader_awareness",     "order": 2, "threshold": 0},
  {"kind": "submitter_acceptance", "order": 3, "threshold": 1},
  {"kind": "chapter_witness",      "order": 4, "threshold": 5},
  {"kind": "president_go",         "order": 5, "threshold": 1},
  {"kind": "president_others",     "order": 6, "threshold": 4}
]'::jsonb,
updated_at = now()
WHERE id = '8e7a70c6-f9dd-4c57-b5fa-b548ec965581';

NOTIFY pgrst, 'reload schema';

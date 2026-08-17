---
name: champion-metrics
description: Selects champions for a recorded meeting from measured participation instead of recall or call order. Parses the timestamped transcript, applies an eliminatory gate plus a three-axis score, and reports whether the winning set survives a change of weights. Use whenever champions are about to be awarded for a Reunião Geral or any recorded session, before calling champion_award.
---

# Champion selection from measured participation

## Why this exists

Champions were once awarded in the order the assistant happened to call the tool.
Measured afterwards, that order handed a slot to the candidate ranked **last of five**
on every axis and locked out the one ranked first, because the platform caps awards
per event. Recall is not a ranking. Measure first, award second.

## Platform constraints (verify, do not recite)

The caps live in the body of `award_champion`. Re-read them before using this skill,
because a migration can move them:

```sql
SELECT prosrc FROM pg_proc WHERE proname = 'award_champion';
```

At the time this skill was written the RPC enforced a per-event cap by surface
(`general` / `tribe` / `deliverable`) plus a separate per-grantor cap per event, both
labelled anti-inflation. Two consequences:

- **A cap of N means the selection is a ranking problem, not a list problem.** Anyone
  beyond N is excluded, so who is in the last slot has to be defensible.
- `champions_awarded` has **no comments column**. The columns are `criteria_met`,
  `justification`, `points_awarded`, `status` and the revocation fields. The metric
  annotation therefore goes inside `justification`, as a bracketed block.

Suggestion is not award: `events.suggested_champion_ids` has **no cap**, so everyone who
presented can be confirmed there even when only N can be awarded.

## The gate

**Eliminatory: the candidate occupied an agenda slot with their own deliverable.**
Someone who only debated does not qualify, however much they spoke. This keeps the
recognition attached to work delivered, consistent with merit immutability.

## The three axes

All measured from the transcript, normalized 0-100 against the highest in the candidate
group, then weighted:

| axis | what it measures | default weight |
|---|---|---|
| **A** words spoken inside their own block | substance of the delivery | 40% |
| **B** distinct other people who spoke during their block | whether it moved the room | 35% |
| **C** words spoken outside their own block | help given to other tribes | 25% |

## What is deliberately NOT an axis

**Span (minutes between first and last utterance).** Whoever presents last in the agenda
has a structurally short span, so the axis would measure **agenda position**, not
contribution. Including it silently penalizes the closing presenter. If you add an axis,
ask first whether it measures the person or the schedule.

## Robustness is part of the output

A ranking that only holds at one weighting is an artifact of the weighting. The script
re-scores across every weight combination and reports how many produce the same top-N
**set**. Report that number alongside the ranking. If the set is unstable, say so and
bring the tie to the PM rather than resolving it silently.

## Procedure

1. Locate the timestamped transcript. For Google Meet it is the `Notes by Gemini` doc in
   the recording folder. Native Google docs read as **0 bytes through the rclone mount**;
   pull them with `rclone cat`.
2. Run `scripts/metrica_participacao.py <transcript.md>` to produce per-speaker counts.
   It parses `**Name:** text` turns under `### **HH:MM:SS**` headers.
3. Define the agenda-block windows from the agenda announced in the meeting (usually
   posted in the chat log), not from your reading of who seemed important.
4. Run `scripts/score_champions.py` for the ranking plus the robustness sweep.
5. Award the top-N via `champion_award`, appending the bracketed metric block to each
   `justification`. Put **everyone who passed the gate** into `suggested_champion_ids`.
6. If a previous award has to be undone, use `champion_award action='revoke'` with the
   metric in the reason. Revocation works only inside the grantor window.

## Reporting rule

Name the axes and the weights whenever the ranking is shown. A score with no visible
formula is indistinguishable from an opinion, which is the failure this skill exists to
prevent.

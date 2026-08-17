#!/usr/bin/env python3
"""Rank champion candidates from measured participation, and test the ranking
against a change of weights.

Usage:
  score_champions.py metrics.json [--top 3] [--weights 0.40,0.35,0.25]

GATE (eliminatory): the candidate occupied an agenda slot with their own
deliverable (`bloco_pauta` true). Debating alone does not qualify.

AXES, each normalized 0-100 against the highest in the candidate group:
  A  words spoken inside their own block      substance of the delivery
  B  distinct other people who spoke in it     whether it moved the room
  C  words spoken outside their own block      help given to other tribes

SPAN IS NOT AN AXIS. Whoever presents last has a structurally short span, so it
would measure agenda position rather than contribution.

The robustness sweep re-scores over every weight combination on a coarse grid and
reports how many yield the same top-N SET. A set that only holds at one weighting
is an artifact of that weighting; report the number, and escalate an unstable set
to the PM instead of resolving it silently.
"""
import argparse, itertools, json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('metrics', help='metrics.json from metrica_participacao.py')
    ap.add_argument('--top', type=int, default=3, help='per-event cap for the surface')
    ap.add_argument('--weights', default='0.40,0.35,0.25', help='wA,wB,wC')
    a = ap.parse_args()

    w = tuple(float(x) for x in a.weights.split(','))
    if abs(sum(w) - 1.0) > 1e-9:
        raise SystemExit(f'ABORT: weights must sum to 1.0, got {sum(w)}')

    rows = json.load(open(a.metrics, encoding='utf-8'))
    cand = [r for r in rows if r['bloco_pauta']]
    if len(cand) <= a.top:
        print(f'NOTE: {len(cand)} candidate(s) for {a.top} slot(s). '
              'No ranking needed, but the metric still belongs in the justification.')

    for r in cand:
        r['A'] = r['palavras'] - r['palavras_fora_do_bloco']
        r['B'] = r['debate_no_bloco']
        r['C'] = r['palavras_fora_do_bloco']
    mx = {k: max(r[k] for r in cand) or 1 for k in 'ABC'}
    for r in cand:
        r['nA'], r['nB'], r['nC'] = (100 * r[k] / mx[k] for k in 'ABC')
        r['score'] = round(w[0] * r['nA'] + w[1] * r['nB'] + w[2] * r['nC'], 1)

    cand.sort(key=lambda r: -r['score'])
    print(f'CANDIDATES (gate = own agenda slot): {len(cand)} of {len(rows)} speakers')
    print(f'weights A={w[0]} B={w[1]} C={w[2]}\n')
    print(f"{'#':>2} {'speaker':24}{'A words':>9}{'B debate':>9}{'C outside':>10}{'score':>8}")
    for i, r in enumerate(cand, 1):
        mark = '*' if i <= a.top else ' '
        print(f"{i:2}{mark}{r['nome'][:24]:24}{r['A']:9}{r['B']:9}{r['C']:10}{r['score']:8}")

    grid = [c for c in itertools.product([0.2, 0.3, 0.4, 0.5], repeat=3)
            if abs(sum(c) - 1.0) < 1e-9]
    tops = {}
    for g in grid:
        s = sorted(cand, key=lambda r: -(g[0] * r['nA'] + g[1] * r['nB'] + g[2] * r['nC']))
        key = frozenset(x['nome'] for x in s[:a.top])
        tops[key] = tops.get(key, 0) + 1
    best, hits = max(tops.items(), key=lambda kv: kv[1])
    print(f'\nROBUSTNESS: same top-{a.top} SET in {hits}/{len(grid)} weight combinations')
    for k, v in sorted(tops.items(), key=lambda kv: -kv[1]):
        print(f'  {v:3}/{len(grid)}  {", ".join(sorted(k))}')
    if hits < len(grid):
        print('\nThe set is NOT weight-invariant. Report this and take the tie to the PM.')


if __name__ == '__main__':
    main()

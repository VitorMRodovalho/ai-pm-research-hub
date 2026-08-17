#!/usr/bin/env python3
"""Per-speaker participation metrics from a timestamped meeting transcript.

Every number comes from the transcript text. Nothing is estimated.

Usage:
  metrica_participacao.py <transcript.md> <blocks.json> [--out metrics.json]

blocks.json maps each presenter to the [start, end) of THEIR agenda slot, as
announced in the meeting (usually in the chat log), e.g.:

  {"Some Presenter": ["00:02:54", "00:25:36"],
   "Other Presenter": ["01:01:43", "01:26:29"]}

The transcript is expected in Google "Notes by Gemini" shape: blocks headed by
`### **HH:MM:SS**` and turns written as `**Speaker:** text`.
"""
import argparse, json, re, sys
from collections import defaultdict


def secs(t):
    h, m, s = (int(x) for x in t.split(':'))
    return h * 3600 + m * 60 + s


def parse_turns(text):
    """-> [(block_seconds, speaker, utterance)]"""
    marker = '# **📖 Transcrição**'
    if marker in text:  # drop the summary section, keep the transcript
        text = text.split(marker, 1)[1]
    turns, cur = [], None
    for line in text.splitlines():
        h = re.match(r'^### \*\*(\d{2}:\d{2}:\d{2})\*\*', line)
        if h:
            cur = h.group(1)
            continue
        t = re.match(r'^\*\*(.+?):\*\* (.*)$', line)
        if t and cur:
            turns.append((secs(cur), t.group(1).strip(), t.group(2).strip()))
    return turns


def compute(turns, blocks):
    stats = defaultdict(lambda: {'turnos': 0, 'palavras': 0, 'blocos': set(),
                                 'primeiro': None, 'ultimo': None})
    for t, n, x in turns:
        s = stats[n]
        s['turnos'] += 1
        s['palavras'] += len(x.split())
        s['blocos'].add(t)
        s['primeiro'] = t if s['primeiro'] is None else min(s['primeiro'], t)
        s['ultimo'] = max(s['ultimo'] or 0, t)

    rows = []
    for n, s in stats.items():
        jan = blocks.get(n)
        inside = (lambda t: jan and jan[0] <= t < jan[1])
        fora = [(t, x) for t, nn, x in turns if nn == n and not inside(t)]
        rows.append({
            'nome': n,
            'palavras': s['palavras'],
            'turnos': s['turnos'],
            'blocos': len(s['blocos']),
            'span_min': round((s['ultimo'] - s['primeiro']) / 60, 1),
            'bloco_pauta': bool(jan),
            # distinct OTHER people who spoke during this presenter's slot
            'debate_no_bloco': len({nn for t, nn, _ in turns
                                    if inside(t) and nn != n}) if jan else 0,
            'turnos_fora_do_bloco': len(fora),
            'palavras_fora_do_bloco': sum(len(x.split()) for _, x in fora),
        })
    rows.sort(key=lambda r: -r['palavras'])
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('transcript')
    ap.add_argument('blocks', help='JSON: {"Presenter": ["HH:MM:SS","HH:MM:SS"]}')
    ap.add_argument('--out', default='metrics.json')
    a = ap.parse_args()

    turns = parse_turns(open(a.transcript, encoding='utf-8').read())
    if not turns:
        sys.exit('ABORT: no turns parsed. Check the transcript shape '
                 '(### **HH:MM:SS** headers and **Speaker:** turns).')
    blocks = {k: (secs(v[0]), secs(v[1]))
              for k, v in json.load(open(a.blocks, encoding='utf-8')).items()}

    unknown = [k for k in blocks if k not in {n for _, n, _ in turns}]
    if unknown:
        sys.exit(f'ABORT: presenter(s) in blocks.json never speak in the '
                 f'transcript, so a name variant is wrong: {unknown}')

    rows = compute(turns, blocks)
    hdr = f"{'speaker':32}{'words':>8}{'turns':>7}{'blocks':>7}{'span':>7}{'slot':>6}{'debate':>8}{'outside':>8}"
    print(hdr)
    for r in rows:
        print(f"{r['nome'][:32]:32}{r['palavras']:8}{r['turnos']:7}{r['blocos']:7}"
              f"{r['span_min']:7}{('yes' if r['bloco_pauta'] else '-'):>6}"
              f"{r['debate_no_bloco']:8}{r['turnos_fora_do_bloco']:8}")
    print(f"\nspeakers: {len(rows)} | turns: {len(turns)} | "
          f"words: {sum(r['palavras'] for r in rows)}")
    json.dump(rows, open(a.out, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'wrote {a.out}')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Stop hook: números afirmados em PROSA precisam de lastro no turno.

Por que existe (#588, 18/09/2026): a regra de grounding da CLAUDE.md enumera seis
superfícies — user-decision prompt, AskUserQuestion, mensagem de commit, corpo de PR,
SPEC, arquivo de memória. PROSA DE CONVERSA não está entre elas, e é a única escrita
para ser lida por gente: é a que o dono ENCAMINHA. Num único dia, "~20 capítulos"
saiu daqui em prosa e chegou a um grupo com os parceiros; o valor real era 16.

O que faz: ao fim da resposta, extrai os números com cara de CONTAGEM da última
mensagem e confere se cada um aparece em algum resultado de ferramenta DESTE turno.
Os que não aparecem são listados.

Não é preventivo e não pode ser: prosa não tem pre-receive hook, igual a corpo de
issue. É detective por construção, e o valor está em avisar antes de o texto viajar.

Uso avulso (medição retroativa):
    ground-numbers.py --audit <transcript.jsonl>
"""
import json
import os
import re
import sys

# Ruído conhecido: formas que são identificador ou carimbo, nunca medição.
DESCARTA = re.compile(
    r"""(?x)
    \#\d+                      # referência de issue/PR
  | \b\d{1,2}[:/h]\d{2}\b      # hora ou data curta (10:35, 18/09)
  | \b\d{1,2}/\d{1,2}(/\d{2,4})?\b
  | \b\d{4}-\d{2}-\d{2}\b      # data ISO
  | \bv?\d+\.\d+(\.\d+)?\b     # versão
  | \b[0-9a-f]{7,}\b           # sha, uuid, hex
  | \b(19|20)\d{2}\b           # ano
    """
)

# Só conta número COLADO num substantivo ("16 capítulos", "6 pessoas"), que é a
# forma de uma AFIRMAÇÃO de contagem. Número solto é quase sempre citação ou
# aritmética, e medido em 18/09 fazia o detector disparar em 48% dos turnos.
CANDIDATO = re.compile(r"\b(\d{1,6})\s+(?:de\s+)?([a-zà-ÿ][a-zà-ÿ]{3,})", re.I)

MIN_INTEIRO = 3

# Lastro olha o turno atual E o anterior: em conversa, a medição costuma vir num
# turno e a frase que a usa no seguinte. Medido: 35% de disparo com um turno só,
# 16% com dois. Ver a auditoria em #588.
TURNOS_DE_LASTRO = 2


def _texto(bloco):
    if isinstance(bloco, str):
        return bloco
    if isinstance(bloco, list):
        return "\n".join(_texto(b) for b in bloco)
    if isinstance(bloco, dict):
        for k in ("text", "content", "output", "result"):
            if k in bloco:
                return _texto(bloco[k])
        return json.dumps(bloco, ensure_ascii=False)
    return "" if bloco is None else str(bloco)


def _sem_codigo(t):
    """Fora de bloco de código, de código inline e de URL: lá o número é citação."""
    t = re.sub(r"```.*?```", " ", t, flags=re.S)
    t = re.sub(r"`[^`]*`", " ", t)
    t = re.sub(r"https?://\S+", " ", t)
    t = re.sub(r"\]\([^)]*\)", " ", t)
    return t


def candidatos(prosa):
    prosa = _sem_codigo(prosa)
    prosa = DESCARTA.sub(" ", prosa)
    saida = []
    for m in CANDIDATO.finditer(prosa):
        bruto = m.group(1)
        try:
            if int(bruto) < MIN_INTEIRO:
                continue
        except ValueError:
            continue
        saida.append((bruto, f"{bruto} {m.group(2)}"))
    return saida


def turno(linhas, quantos=TURNOS_DE_LASTRO):
    """Os últimos `quantos` turnos de usuário até o fim."""
    cortes = [i for i, ev in enumerate(linhas)
              if ev.get("type") == "user" and not _eh_tool_result(ev)]
    if not cortes:
        return linhas
    return linhas[cortes[-quantos] if len(cortes) >= quantos else cortes[0]:]


def _eh_tool_result(ev):
    msg = ev.get("message") or {}
    cont = msg.get("content")
    if isinstance(cont, list):
        return any(isinstance(b, dict) and b.get("type") == "tool_result" for b in cont)
    return False


def lastro(eventos):
    """Todo texto que veio de ferramenta neste turno."""
    partes = []
    for ev in eventos:
        msg = ev.get("message") or {}
        cont = msg.get("content")
        if isinstance(cont, list):
            for b in cont:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    partes.append(_texto(b.get("content")))
        if "toolUseResult" in ev:
            partes.append(_texto(ev["toolUseResult"]))
    return "\n".join(partes)


def ultima_fala(eventos):
    for ev in reversed(eventos):
        if ev.get("type") != "assistant":
            continue
        cont = (ev.get("message") or {}).get("content")
        if isinstance(cont, list):
            t = "\n".join(
                b.get("text", "") for b in cont
                if isinstance(b, dict) and b.get("type") == "text"
            ).strip()
            if t:
                return t
    return ""


def analisa(eventos):
    prosa = ultima_fala(eventos)
    if not prosa:
        return []
    fonte = lastro(eventos)
    orfaos, vistos = [], set()
    for valor, ctx in candidatos(prosa):
        if valor in vistos:
            continue
        # Lastro = o literal aparece em algum resultado de ferramenta do turno.
        if re.search(r"(?<![\d.,])" + re.escape(valor) + r"(?![\d])", fonte):
            continue
        vistos.add(valor)
        orfaos.append((valor, ctx))
    return orfaos


def carrega(caminho):
    out = []
    with open(caminho, encoding="utf-8") as fh:
        for linha in fh:
            linha = linha.strip()
            if linha:
                try:
                    out.append(json.loads(linha))
                except json.JSONDecodeError:
                    pass
    return out


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--audit":
        linhas = carrega(sys.argv[2])
        turnos, disparos, total_orfaos = 0, 0, 0
        cortes = [i for i, ev in enumerate(linhas)
                  if ev.get("type") == "user" and not _eh_tool_result(ev)]
        for idx, (a, b) in enumerate(zip(cortes, cortes[1:] + [len(linhas)])):
            ini = cortes[idx - 1] if idx else a
            bloco = linhas[ini:b]
            if not ultima_fala(bloco):
                continue
            turnos += 1
            orf = analisa(bloco)
            if orf:
                disparos += 1
                total_orfaos += len(orf)
                print(f"  turno {turnos}: " + ", ".join(v for v, _ in orf[:8]))
        pct = (100.0 * disparos / turnos) if turnos else 0.0
        print(f"\nturnos com prosa: {turnos}")
        print(f"turnos que disparariam: {disparos}  ({pct:.0f}%)")
        print(f"numeros sem lastro: {total_orfaos}")
        return 0

    try:
        entrada = json.load(sys.stdin)
    except Exception:
        return 0
    if entrada.get("stop_hook_active"):
        return 0
    caminho = entrada.get("transcript_path")
    if not caminho or not os.path.exists(caminho):
        return 0
    orf = analisa(turno(carrega(caminho)))
    if not orf:
        return 0
    linhas = [f"  {v}  —  ...{c}..." for v, c in orf[:10]]
    print(
        "GROUNDING: numero(s) afirmado(s) em prosa sem aparecer em nenhum resultado "
        "de ferramenta deste turno:\n" + "\n".join(linhas) +
        "\n\nProsa e a superficie que o dono ENCAMINHA. Se algum destes for contagem, "
        "medida ou estimativa sua, RE-MEÇA agora ou rotule como estimativa. "
        "Se for numero citado pelo usuario, de documento lido, ou aritmetica obvia, "
        "ignore este aviso. Ver #588.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

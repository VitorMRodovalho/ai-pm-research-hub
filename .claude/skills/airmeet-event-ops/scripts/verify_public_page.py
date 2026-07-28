#!/usr/bin/env python3
"""Verifica a pagina publica de um evento no Airmeet.

O Airmeet e SPA: `curl` cru devolve casca vazia, entao a landing e renderizada em Chrome headless.
As meta tags og:*, porem, o Airmeet serve por user-agent, so para crawler. Os dois caminhos sao
checados aqui porque medem coisas diferentes: o que o visitante ve, e o que o preview do link mostra.

TZ e forcado para America/Sao_Paulo: o Airmeet renderiza o horario no fuso do VISITANTE, e sem TZ o
headless cai no default da maquina. Isso ja produziu um falso positivo de "horario errado" (EDT).

Uso: python3 verify_public_page.py <url> [--out DIR]
"""
import argparse, os, re, subprocess, sys, pathlib

CRAWLERS = {
    "WhatsApp": "WhatsApp/2.23",
    "LinkedIn": "LinkedInBot/1.0 (compatible; Mozilla/5.0)",
    "Facebook": "facebookexternalhit/1.1",
}
META = ("og:title", "og:description", "og:image", "og:type")


def og_tags(url, ua):
    p = subprocess.run(["curl", "-s", "-L", "-A", ua, url], capture_output=True, text=True)
    out = {}
    for key in META:
        m = re.search(r'<meta property="%s" content="([^"]*)"' % re.escape(key), p.stdout, re.I)
        out[key] = m.group(1) if m else None
    return out


def render(url, dst):
    env = dict(os.environ, TZ="America/Sao_Paulo")
    subprocess.run([
        "google-chrome-stable", "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--window-size=1280,1600",
        "--virtual-time-budget=15000", f"--screenshot={dst}", url,
    ], check=True, capture_output=True, env=env)
    return dst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("--out", default=".")
    a = ap.parse_args()
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)

    print(f"== {a.url}\n")

    print("-- meta tags que os crawlers recebem --")
    base = None
    for nome, ua in CRAWLERS.items():
        t = og_tags(a.url, ua)
        if base is None:
            base = t
        divergiu = " (DIVERGE dos outros)" if t != base else ""
        print(f"  {nome}{divergiu}")
        for k in META:
            print(f"     {k:16s} {t[k]!r}")

    print("\n-- avisos --")
    t = base or {}
    tit = t.get("og:title") or ""
    if not tit:
        print("  FALHA: sem og:title. O preview do link sai sem titulo.")
    else:
        if tit != tit.strip():
            print(f"  ATENCAO: og:title tem espaco sobrando nas pontas: {tit!r}")
        # heuristica de acento faltando em palavras comuns de PT
        for errado, certo in (("analise", "análise"), ("cenario", "cenário"), ("informacao", "informação"),
                              ("priorizacao", "priorização"), ("seguranca", "segurança"),
                              ("gestao", "gestão"), ("aplicacoes", "aplicações"), ("pratica", "prática")):
            if re.search(r"\b%s" % errado, tit, re.I):
                print(f'  ATENCAO: og:title parece sem acento: "{errado}" deveria ser "{certo}".')
    desc = t.get("og:description") or ""
    if desc.strip().lower().startswith("checkout this event"):
        print("  NOTA: og:description e string FIXA do Airmeet e nao muda com o Overview (medido 26/07).")
        print("        Nao ha o que corrigir aqui. Consequencia: o card do link nao tem legenda propria,")
        print("        entao a copy do post precisa carregar o contexto. Do preview so se controla")
        print("        titulo e imagem.")
    if not t.get("og:image"):
        print("  ATENCAO: sem og:image. O preview sai sem imagem.")

    print("\n-- landing renderizada (TZ=America/Sao_Paulo) --")
    shot = render(a.url, str(out / "airmeet-landing.png"))
    print(f"  screenshot: {shot}")
    print("  OLHAR a imagem. Conferir, na ordem:")
    print("   1. o H1 (e o titulo do evento, nao o subtitulo por acidente)")
    print("   2. o horario com rotulo UTC-03:00")
    print("   3. a capa (peca de divulgacao 16:9, NAO a tela de palco)")
    print("   4. a secao Overview preenchida")
    print("   5. o botao Register for this event")
    return 0


if __name__ == "__main__":
    sys.exit(main())

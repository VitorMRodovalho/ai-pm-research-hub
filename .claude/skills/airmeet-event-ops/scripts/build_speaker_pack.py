#!/usr/bin/env python3
"""Monta o pack de import de speakers do Airmeet: CSV de 14 colunas + fotos 400x400.

O ponto do script e o CRUZAMENTO: cada linha do CSV tem que ter uma foto cujo nome de arquivo seja a
string literal `{First Name}_{Last Name}.png`. O `_` substitui APENAS o espaco ENTRE os dois campos;
espaco dentro de nome composto continua espaco, e ACENTO tem que ser identico ao do CSV. Errar isso faz
o auto-map falhar em silencio e o evento vai ao ar com foto trocada ou sem foto.

Manifesto JSON esperado:
{
  "speakers": [
    {"first": "Denis", "last": "Vasconcelos", "email": "...", "job_title": "...",
     "organization": "...", "city": "...", "country": "Brasil", "bio": "...",
     "linkedin": "...", "website": "", "foto": "/caminho/para/origem.png"}
  ]
}
Campos ausentes viram string vazia (o Airmeet aceita). `foto` e opcional; sem ela, so nao gera imagem.

Uso: python3 build_speaker_pack.py manifesto.json dir-saida
"""
import csv, json, pathlib, sys
from PIL import Image, ImageOps

COLUNAS = ["First Name", "Last Name", "Email", "Job Title", "Organization", "Video Headline",
           "City", "Country", "Speaker Biography", "LinkedIn", "X (Twitter)", "Facebook",
           "Instagram", "Website"]
LADO = 400


def linha(s):
    return [s.get("first", ""), s.get("last", ""), s.get("email", ""), s.get("job_title", ""),
            s.get("organization", ""), s.get("video_headline", ""), s.get("city", ""),
            s.get("country", ""), s.get("bio", ""), s.get("linkedin", ""), s.get("x", ""),
            s.get("facebook", ""), s.get("instagram", ""), s.get("website", "")]


def main():
    if len(sys.argv) != 3:
        print(__doc__); return 2
    man = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = pathlib.Path(sys.argv[2]); (out / "fotos").mkdir(parents=True, exist_ok=True)
    speakers = man["speakers"]

    csv_path = out / "Speakers_Airmeet.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, quoting=csv.QUOTE_ALL)
        w.writerow(COLUNAS)
        w.writerows(linha(s) for s in speakers)
    print(f"CSV: {csv_path} ({len(speakers)} speakers)")

    ok = True
    print("\n-- fotos e auto-map --")
    for s in speakers:
        nome = f'{s.get("first","")}_{s.get("last","")}.png'
        src = s.get("foto")
        if not src:
            print(f'  SEM FOTO  "{nome}" (o speaker entra sem imagem)'); continue
        im = Image.open(src)
        orig = im.size
        im = ImageOps.exif_transpose(im).convert("RGB")
        im = ImageOps.fit(im, (LADO, LADO), Image.LANCZOS, centering=(0.5, 0.42))
        im.save(out / "fotos" / nome)
        upscale = min(orig) < LADO
        if upscale:
            ok = False
        print(f'  {"UPSCALE!" if upscale else "OK      "} "{nome}"  origem {orig[0]}x{orig[1]} -> {LADO}x{LADO}')

    print("\n-- cruzamento CSV x arquivos --")
    esperados = {f'{s.get("first","")}_{s.get("last","")}.png' for s in speakers if s.get("foto")}
    presentes = {p.name for p in (out / "fotos").iterdir() if p.suffix == ".png"}
    for n in sorted(esperados - presentes):
        print(f"  FALHA: CSV pede {n!r} e o arquivo nao existe"); ok = False
    for n in sorted(presentes - esperados):
        print(f"  FALHA: arquivo {n!r} nao corresponde a nenhuma linha do CSV"); ok = False
    if esperados == presentes:
        print(f"  OK: {len(esperados)} linhas e {len(presentes)} arquivos casam um a um")

    print("\n-- e-mail (o Airmeet usa p/ o convite de backstage) --")
    sem = [f'{s.get("first","")} {s.get("last","")}' for s in speakers if not s.get("email")]
    print("  faltando: " + (", ".join(sem) if sem else "nenhum"))
    if sem:
        print("  NAO inventar e-mail. Pedir a quem convidou o palestrante.")

    print("\n-- ordem de import no Airmeet --")
    print("  1o o CSV, 2o SO os arquivos de fotos/ (nao a pasta inteira: extra images present)")
    print("\nRESULTADO:", "PASSA" if ok else "FALHA")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

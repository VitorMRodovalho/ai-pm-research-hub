#!/usr/bin/env bash
# Monta o ZIP do webinar da Tribo 11 para quem vai trabalhar as pecas FORA deste repo.
#
# O ZIP NAO e versionado, e a razao e a mesma que mantem `fotos/` no .gitignore: ele leva
# os RETRATOS, e este repositorio e publico. O que se versiona e esta receita; o pacote se
# remonta em segundos a partir dela mais a pasta de retratos do evento.
#
#   NUCLEO_FOTOS=/caminho/dos/retratos ./empacotar.sh [destino]
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
DK="$(dirname "$AQUI")"
DEST="${1:-$PWD}"; mkdir -p "$DEST"; DEST="$(cd "$DEST" && pwd)"
NOME="webinar-t11-design"

: "${NUCLEO_FOTOS:?defina NUCLEO_FOTOS com a pasta dos retratos do evento}"
[ -d "$NUCLEO_FOTOS" ] || { echo "NUCLEO_FOTOS nao existe: $NUCLEO_FOTOS" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/$NOME"
mkdir -p "$P"/{kit,fotos,fontes,pecas}

# toolchain: so o que ESTE webinar usa
cp "$DK"/brand.py "$DK"/qa_measure.py "$DK"/_qa_contraste.py "$P/"
cp "$DK"/recortar.py "$DK"/fundir.py "$DK"/checar.py "$DK"/verificar.py "$P/"
cp "$DK"/build_t11_campanha.py "$DK"/build_t11_campanha_final.py "$P/"
[ -f "$DK/build_t11_airmeet.py" ] && cp "$DK/build_t11_airmeet.py" "$P/" \
  || echo "aviso: build_t11_airmeet.py ausente; o pacote sai sem as telas do Airmeet"
cp "$AQUI/LEIA-ME.md" "$AQUI/gerar.sh" "$P/"; chmod +x "$P/gerar.sh"

# os 2 assets de marca lidos em runtime
cp "$DK"/kit/faixa-institucional-fade-1920x300.png "$DK"/kit/logo-512.png "$P/kit/"

# retratos: originais e derivados. NAO versionados; vem de NUCLEO_FOTOS
cp "$NUCLEO_FOTOS"/*.png "$NUCLEO_FOTOS"/*.jpg "$NUCLEO_FOTOS"/*.jpeg "$P/fotos/" 2>/dev/null || true
n=$(find "$P/fotos" -type f | wc -l)
[ "$n" -gt 0 ] || { echo "nenhum retrato copiado de $NUCLEO_FOTOS" >&2; exit 1; }

# fontes: Inter, OFL-1.1, redistribuivel. Sem elas o Chrome substitui EM SILENCIO.
F=/usr/share/fonts/opentype/inter
for f in InterDisplay-Black.otf InterDisplay-Bold.otf Inter-Regular.otf Inter-Bold.otf; do
  [ -f "$F/$f" ] && cp "$F/$f" "$P/fontes/" || echo "aviso: fonte $f nao encontrada"
done
[ -f /usr/share/doc/fonts-inter/copyright ] && \
  cp /usr/share/doc/fonts-inter/copyright "$P/fontes/LICENCA-INTER.txt"

# pecas ja geradas, como referencia
cp "$DK"/out/t11-*.png "$P/pecas/" 2>/dev/null || echo "aviso: ./out vazio; rode os builders antes"

( cd "$TMP" && zip -qr "$DEST/$NOME.zip" "$NOME" )
echo "pacote: $DEST/$NOME.zip  ($(du -h "$DEST/$NOME.zip" | cut -f1), $n retratos)"

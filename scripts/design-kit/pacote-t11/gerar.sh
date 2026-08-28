#!/usr/bin/env bash
# Gera todas as pecas deste webinar. Rode a partir da pasta do pacote.
set -euo pipefail
cd "$(dirname "$0")"
python3 verificar.py
export NUCLEO_FOTOS="$PWD/fotos"
mkdir -p out
echo
echo "== campanha (3 tratamentos x 3 formatos) =="
python3 build_t11_campanha_final.py
echo
echo "== telas do Airmeet =="
python3 build_t11_airmeet.py
echo
echo "Saida em ./out"

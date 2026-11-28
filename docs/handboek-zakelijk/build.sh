#!/usr/bin/env bash
# Bouwt het Handboek Pasr Zakelijk opnieuw: schermafbeeldingen (echte webcode met demo-backend + app-scènes),
# JPEG's, PDF, en zet de PDF op de website. Nodig: Node met Playwright (Chromium), Python 3 met Pillow en pypdf.
#   bash docs/handboek-zakelijk/build.sh
set -euo pipefail
cd "$(dirname "$0")"
node shots/web.cjs
node shots/app.cjs
python3 images.py
node render.cjs
mkdir -p ../../website/zakelijk/handboek
cp Handboek-Pasr-Zakelijk.pdf ../../website/zakelijk/handboek/Handboek-Pasr-Zakelijk.pdf
echo "Klaar: docs/handboek-zakelijk/Handboek-Pasr-Zakelijk.pdf en website/zakelijk/handboek/"

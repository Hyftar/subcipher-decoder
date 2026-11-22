#!/usr/bin/env bash
# Generates test fixtures: pictures of a substitution-ciphered pangram.
# Run from the repo root inside nix-shell:  ./scripts/make_fixtures.sh
set -euo pipefail

FONT="$(nix-build '<nixpkgs>' -A dejavu_fonts --no-out-link)/share/fonts/truetype/DejaVuSans.ttf"
OUT=test/fixtures
mkdir -p "$OUT"

# Plain text (one line per row) and the cipher alphabet A..Z.
PLAIN=$'THE QUICK BROWN FOX\nJUMPS OVER THE LAZY DOG\nPACK MY BOX WITH FIVE\nDOZEN LIQUOR JUGS'
CIPHER="ΩΔΦΨΣΛΞΠΘΓ♠♣♥♦★☂☀☎✈⚓♪☯⚑✿☘⌘"
ALPHA="ABCDEFGHIJKLMNOPQRSTUVWXYZ"

encoded=""
while IFS= read -r -n1 ch; do
  if [[ -z "$ch" ]]; then encoded+=$'\n'; continue; fi
  idx=$(expr index "$ALPHA" "$ch" || true)
  if [[ "$idx" -gt 0 ]]; then encoded+="${CIPHER:$((idx - 1)):1}"; else encoded+="$ch"; fi
done <<< "$PLAIN"
encoded="${encoded%$'\n'}"

printf '%s' "$PLAIN" > "$OUT/pangram.txt"

# Clean scan.
magick -background white -fill black -font "$FONT" -pointsize 48 \
  -interline-spacing 18 \
  label:"$encoded" -bordercolor white -border 40 "$OUT/pangram_clean.png"

# "Phone photo": uneven lighting, slight blur, sensor noise, greyish ink.
read -r W H < <(magick identify -format '%w %h\n' "$OUT/pangram_clean.png")
magick "$OUT/pangram_clean.png" -fill '#333' -opaque black \
  \( -size "${W}x${H}" gradient:'#f4f0e6-#8a8478' \) -compose multiply -composite \
  -blur 0x0.8 -attenuate 0.6 +noise Gaussian "$OUT/pangram_photo.png"

for f in pangram_clean pangram_photo; do
  magick "$OUT/$f.png" -colorspace gray -depth 8 "gray:$OUT/$f.gray"
  magick identify -format '%w %h\n' "$OUT/$f.png" > "$OUT/$f.size"
done

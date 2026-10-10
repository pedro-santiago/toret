#!/bin/zsh
# Reproduces the generated artwork. Usage: tools/art/generate.sh <job> [seed ...]
# Model: FLUX.2 [klein] 4B, 4-bit MLX build (mlx-community/flux2-klein-4b-4bit),
# Apache-2.0, run locally with mflux. Output goes to $OUT (default build/art/raw);
# tools/art/quantise.py then prints it onto the poster inks. See PROMPTS.md.
set -e
OUT=${OUT:-build/art/raw}; mkdir -p "$OUT"
MODEL=mlx-community/flux2-klein-4b-4bit

STYLE="Flat vector gouache travel poster in the mid-century Bauhaus style. High contrast, bold saturated flat colours with hard crisp edges, big simple geometric shapes, a limited palette of cream paper, pure black, mustard yellow, brick red, deep river blue, grey-green and sand beige. No gradients, no shading, no texture, no soft edges, no text, no letters, no numbers, no watermark, no border, no frame."

TORET="A Turin cast-iron public drinking fountain: a slim pure black column topped by a bull's head spout, a thin bright blue stream of water falling into a small round basin, standing in the foreground on cobblestones in cream and grey-green. Behind it a long row of sand-beige arcaded buildings with bold brick-red roofs, sharply faceted grey-green mountains with pale snow facets, and one huge flat mustard-yellow sun disc behind everything. Strong black silhouette."

SKYLINE="The skyline of Turin: a tall slender spire on a green ribbed dome rising above a row of sand-beige arcaded palaces with red roofs, faceted grey-green Alps behind, one huge flat mustard-yellow sun disc, one small flat red circle, and a blue river with cream stripes in the foreground."

ICON="A bold flat app icon composition: a huge mustard-yellow sun disc on a cream ground, in front of it the black silhouette of a cast-iron fountain spout shaped like a bull's head pouring one thin stream and one blue water drop, and wide blue river stripes along the bottom. Very simple, centred, large shapes, readable when tiny."

run() { # name prompt width height seed
  mflux-generate-flux2 --model $MODEL --prompt "$2 $STYLE" --width $3 --height $4 \
    --steps 4 --seed $5 --no-metadata --output "$OUT/$1_$5.png" >/dev/null 2>&1
  echo "done $1_$5"
}

job=$1; shift
case $job in
  toret-portrait)  for s in "$@"; do run toret-portrait "$TORET Portrait composition, the fountain in the lower centre." 768 1024 $s; done ;;
  toret-wide)      for s in "$@"; do run toret-wide "$TORET Wide composition, the fountain on the right third." 1152 768 $s; done ;;
  toret-square)    for s in "$@"; do run toret-square "$TORET Square composition, the fountain centred." 1024 1024 $s; done ;;
  skyline-tall)    for s in "$@"; do run skyline-tall "$SKYLINE Very tall portrait composition." 576 1248 $s; done ;;
  skyline-wide)    for s in "$@"; do run skyline-wide "$SKYLINE Wide landscape composition." 1152 640 $s; done ;;
  icon)            for s in "$@"; do run icon "$ICON" 1024 1024 $s; done ;;
  *) echo "unknown job $job"; exit 1 ;;
esac

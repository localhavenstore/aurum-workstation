#!/usr/bin/env bash
# Build the release tarball + SHA256SUMS from THIS tree (review r2 B10: relative paths only; only ../dist is replaced).
# Signing happens where the release minisign key lives (owner decision before the first public release).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); TREE=$(dirname "$HERE"); SRC=$TREE/src; OUT=$TREE/dist
VER=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['aurum_ws'])" "$SRC/release.json")
[[ -f $SRC/assets/aurum-wallpaper.png ]] || { echo "missing $SRC/assets/aurum-wallpaper.png" >&2; exit 1; }
[[ $OUT == "$TREE/dist" ]] || exit 1
rm -rf -- "$OUT"; mkdir -p "$OUT/aurum-ws-$VER/assets"
install -m 0755 "$SRC/aurum-ws" "$OUT/aurum-ws-$VER/aurum-ws"
install -m 0644 "$SRC/release.json" "$OUT/aurum-ws-$VER/release.json"
install -m 0644 "$SRC/assets/aurum-wallpaper.png" "$OUT/aurum-ws-$VER/assets/"
install -m 0644 "$TREE/README.md" "$TREE/LICENSE" "$OUT/aurum-ws-$VER/"
(cd "$OUT" && tar --owner=0 --group=0 --numeric-owner --mode=go-w --sort=name --mtime='2026-10-04 00:00Z' -cf - "aurum-ws-$VER" | gzip -n -9 > "aurum-ws-$VER.tar.gz" && sha256sum "aurum-ws-$VER.tar.gz" > SHA256SUMS)
rm -rf -- "$OUT/aurum-ws-$VER"; ls -la "$OUT"

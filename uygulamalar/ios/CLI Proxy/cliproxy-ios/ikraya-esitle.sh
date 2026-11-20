#!/bin/zsh
# ProxyKit'in asıl kaynağını İkra'daki kopyasına aktarır (canlı testler ve derleme çıktıları hariç).
# Kullanım: ./ikraya-esitle.sh [İkra çalışma ağacı]   (varsayılan ~/Developer/.build/ikra-cliproxy/wt)
set -e
HEDEF=${1:-~/Developer/.build/ikra-cliproxy/wt}/DersPodcast/Packages/ProxyKit
rsync -a --delete --exclude .build --exclude .swiftpm --exclude KAYNAK.md --exclude 'Tests/ProxyKitTests/LiveTests.swift' \
  "$(dirname "$0")/ProxyKit/" "$HEDEF/"
echo "ProxyKit → $HEDEF"

# ProxyKit (kopya)

Asıl kaynak: `~/Developer/cliproxy-ios/ProxyKit` (iPhone "CLI Proxy" uygulaması). Bu klasör İkra'nın
kendi başına derlenebilmesi için kopyadır; değişiklik asıl kaynakta yapılıp
`~/Developer/cliproxy-ios/ikraya-esitle.sh` ile buraya aktarılır.

İkra bu paketi uygulama içinde çalıştırır: vekile (`/dersdas/claude/v1`) giden model istekleri ağa
çıkmadan `PhoneProxy` üzerinden telefondaki hesaplarla karşılanır (bkz. `Core/Engine/PhoneProxy.swift`).

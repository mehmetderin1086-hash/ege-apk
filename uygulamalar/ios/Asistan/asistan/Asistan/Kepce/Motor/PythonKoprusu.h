// Gömülü CPython'a ince C köprüsü. Swift Python başlıklarını görmez; yalnız bu üç işlevi çağırır.
#pragma once

/// Yorumlayıcıyı kurar. `home`: paketteki python/ dizini; `paths`: ':' ile ayrılmış ek arama yolları
/// (önce gelen önceliklidir); `pycache`: .pyc önbelleği. Başarıda NULL, hatada `free` edilecek ileti döner.
char *kp_baslat(const char *home, const char *paths, const char *pycache);

/// `module.function(*args)` çağırır (args: dizgi); sonucu dizgiye çevirip döndürür.
/// Başarısızlıkta NULL döner ve `*hata` `free` edilecek iletiyi tutar. GIL'i kendi alır ve bırakır.
char *kp_cagir(const char *module, const char *function, const char *const *args, int argc, char **hata);

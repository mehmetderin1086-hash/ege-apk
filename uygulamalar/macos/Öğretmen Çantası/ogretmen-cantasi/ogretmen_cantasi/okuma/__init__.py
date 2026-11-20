"""Dış dosyaların okunması: e-Okul listesi, ders programı, deneme sonuçları.

Ortak ilke: hiçbir ayrıştırıcı tek doğru biçim varsaymaz ve başarısızlıkta
akışı tıkamaz. Okunamayan her satır uyarı olarak döner, kullanıcı arayüzde
elle düzeltir. Okulların verdiği dosyalar birbirine benzemiyor; "anlayamadım"
demek, yanlış anlamaktan iyidir.
"""

from .tablo import Tablo, tabloyu_oku  # noqa: F401

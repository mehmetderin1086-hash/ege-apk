"""Ders referans kitapları katmanı.

Öğretmenin ders kaynağını (PDF/txt ders kitabı, konu notları) alır, pasajlara
böler ve gömme vektörlerini bir dizine yazar. Puanlama sırasında her soru için
en ilgili kitap pasajları bulunur; bu pasajlar:

1. TESPİT: gözden geçirme arayüzünde öğretmene "bu sorunun kitaptaki karşılığı"
   olarak kanıt gösterilir.
2. REFERANSLI PUANLAMA: rubrik kalemleri, ders kitabının kendi ifadeleriyle
   temellendirilerek anlamsal eşleştirme güçlendirilir; öğrenci cevabı kitapla
   güçlü örtüşüyor ama rubrikte yakalanmadıysa sonuç "incele"ye işaretlenir
   (haksız sıfır vermeyi engeller, insan onayında bırakır).
"""

from .kitap import KitapDeposu, KitapPasaji, metin_cikar, pasajlara_bol
from .yerel_rag import YerelRAGCevabi, YerelRAGDeposu

__all__ = [
    "KitapDeposu",
    "KitapPasaji",
    "YerelRAGCevabi",
    "YerelRAGDeposu",
    "metin_cikar",
    "pasajlara_bol",
]

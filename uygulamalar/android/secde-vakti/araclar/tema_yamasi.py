# Flutter AOT anlık görüntüsünde (libapp.so) varsayılan "Zümrüt" temasının renklerini ve adını değiştirir.
#
# ColorTheme sabitlerinin renk alanları snapshot'ta Dart'ın işaretli değişken uzunluklu tamsayı
# biçimiyle (7 bit/bayt, son bayt 192 + işaretli 6 bit) yazılıdır; her alanı 64 bitte üç, 32 bitte
# (armeabi-v7a) bir tane 0xc0 izler.
# 0x080000..0x3ffffff aralığındaki her renk 4 bayt tutar; yeni renkler de bu aralıkta seçildiği
# için dosyada hiçbir şey kaymaz. Ad da aynı uzunlukta (Latin-1, 6 karakter) değiştirilir.
#
# Kullanım: tema_yamasi.py girdi_libapp.so cikti_libapp.so
import sys

ESKI = [0x1f6e5c, 0x4fb89e, 0xb5893c, 0xd9b76a, 0xeaf2ee, 0x24322b, 0xf4f7f1, 0x121c17, 0x123f35, 0x255f4e]
# Yeni "Mihrap" paleti: gece mavisi-çivit + kehribar, sade nötr zeminler.
YENI = [
    0x3d4a9c,  # ana renk (açık tema)
    0x9aa6f5,  # ana renk (koyu tema)
    0xc07a1e,  # vurgu (kehribar)
    0xf0b35a,  # açık vurgu
    0xeef0f8,  # açık yüzey tonu
    0x1c2033,  # koyu yüzey
    0xf7f7fa,  # açık zemin
    0x12142a,  # koyu zemin
    0x1e2559,  # üst kart geçişi başlangıç
    0x3d4a9c,  # üst kart geçişi bitiş
]
ESKI_AD = 'Zümrüt'.encode('latin-1')
YENI_AD = 'Mihrap'.encode('latin-1')


def kodla(v):
    out = bytearray()
    while v < -64 or v > 63:
        out.append(v & 0x7f)
        v >>= 7
    out.append((v + 192) & 0xff)
    return bytes(out)


def dizi(degerler, ara):
    return b''.join(kodla(v) + ara for v in degerler)


assert len(ESKI) == len(YENI) == 10
for e, y in zip(ESKI, YENI):
    assert len(kodla(e)) == len(kodla(y)) == 4, (hex(e), hex(y))
assert len(ESKI_AD) == len(YENI_AD)

veri = bytearray(open(sys.argv[1], 'rb').read())
for ara in (b'\xc0\xc0\xc0', b'\xc0'):
    eski = dizi(ESKI, ara)
    yeni = dizi(YENI, ara)
    yer = [i for i in range(len(veri)) if veri.startswith(eski, i)]
    if yer:
        break
assert len(yer) == 1, 'Zümrüt renk dizisi tek değil: %r' % yer
veri[yer[0]:yer[0] + len(eski)] = yeni

ad = [i for i in range(len(veri)) if veri.startswith(ESKI_AD, i)]
assert len(ad) == 1, 'Zümrüt adı tek değil: %r' % ad
veri[ad[0]:ad[0] + len(ESKI_AD)] = YENI_AD

open(sys.argv[2], 'wb').write(veri)
print('renkler @%#x, ad @%#x yamalandı' % (yer[0], ad[0]))

"""Komut satırı arayüzü.

Sunucuyu başlatmak, müfredatı yeniden çıkarmak ve yedek almak için. Masaüstü
uygulaması da bu komutu çağırır.
"""

from __future__ import annotations

import argparse

from . import ayarlar, depo


def sunucuyu_durdur() -> bool:
    """Çalışan sunucuyu kapatır; kapatacak bir şey yoksa False döner.

    Masaüstü başlatıcısı, portta zaten bu program çalışıyorsa yeni sunucu
    açmaz — doğru davranış, ama program güncellendiğinde eski sürüm çalışmaya
    devam ediyor ve yeni şablonlarla eski kod karışabiliyor. Güncelleme
    sonrası bu komut çağrılır.
    """
    import os
    import signal

    pid_dosyasi = ayarlar.gunluk_dizini() / "server.pid"
    if not pid_dosyasi.is_file():
        print("Çalışan sunucu kaydı yok.")
        return False
    try:
        pid = int(pid_dosyasi.read_text().strip())
        os.kill(pid, signal.SIGTERM)
    except (ValueError, ProcessLookupError):
        pid_dosyasi.unlink(missing_ok=True)
        print("Kayıtlı süreç zaten kapalı.")
        return False
    except PermissionError:
        print(f"Süreç {pid} kapatılamadı (izin yok).")
        return False
    pid_dosyasi.unlink(missing_ok=True)
    print(f"Sunucu kapatıldı (süreç {pid}).")
    return True


def main() -> int:
    ayristirici = argparse.ArgumentParser(prog="ogretmen-cantasi", description=__doc__)
    altlar = ayristirici.add_subparsers(dest="komut", required=True)

    sunucu = altlar.add_parser("sunucu", help="yerel sunucuyu başlat")
    sunucu.add_argument("--adres", default="127.0.0.1")
    sunucu.add_argument("--port", type=int, default=ayarlar.PORT_BASLANGIC)

    altlar.add_parser("yedek", help="veritabanının tarih damgalı kopyasını al")
    altlar.add_parser("durum", help="veri yollarını ve kayıt sayılarını göster")
    altlar.add_parser("durdur", help="çalışan sunucuyu kapat")

    args = ayristirici.parse_args()

    if args.komut == "sunucu":
        from .web.sunucu import calistir

        print(f"{ayarlar.UYGULAMA_ADI}: http://{args.adres}:{args.port}")
        calistir(args.adres, args.port)
        return 0

    if args.komut == "durdur":
        return 0 if sunucuyu_durdur() else 1

    if args.komut == "yedek":
        hedef = depo.yedekle()
        print(f"Yedek: {hedef}" if hedef else "Yedeklenecek veritabanı yok.")
        return 0

    baglanti = depo.baglan()
    try:
        print(f"Veritabanı : {ayarlar.veritabani_yolu()}")
        print(f"Yedekler   : {ayarlar.yedek_dizini()}")
        for tablo in ("ogretim_yili", "sube", "ogrenci", "soru", "sinav", "deneme", "materyal"):
            adet = baglanti.execute(f"SELECT COUNT(*) AS n FROM {tablo}").fetchone()["n"]
            print(f"{tablo:<12}: {adet}")
    finally:
        baglanti.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

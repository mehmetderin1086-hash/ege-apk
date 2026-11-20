#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik okuyucu CLI — form üret, tara/oku, anahtar gir, puanla, analiz, dışa aktar.

Örnekler:
  python3 optik.py uret --on-ayar lgs-sozel -o form.pdf
  python3 optik.py uret --ad "6A Fen" --ders "Fen Bilimleri:20:4" \\
      --kitapcik 2 --yanlis-boler 0 -o fen.pdf
  python3 optik.py sinavlar
  python3 optik.py oku --sinav a1b2c3d4 taramalar/*.jpg toplu.pdf
  python3 optik.py anahtar --sinav a1b2c3d4 --kitapcik A \\
      --cevaplar "Fen Bilimleri=ABCDABCDABCDABCDABCD"
  python3 optik.py anahtar --sinav a1b2c3d4 --kitapcik A --tara anahtar.jpg
  python3 optik.py puanla --sinav a1b2c3d4
  python3 optik.py analiz --sinav a1b2c3d4 --kazanim-csv kazanimlar.csv
  python3 optik.py disa --sinav a1b2c3d4 --tur csv -o sonuclar.csv

Okuma motoru .venv-ml ister: python3 optik_kur.py
"""
import argparse
import os
import sys

import optik_analiz as oan
import optik_kayit as okt
import optik_sema as osm


def _sinav_yukle(conn, sinav_id):
    sinav = okt.sinav_al(conn, sinav_id)
    if sinav is None:
        print(f"HATA: sınav bulunamadı: {sinav_id} "
              "(liste: python3 optik.py sinavlar)")
        sys.exit(2)
    return sinav


def _sablon_dosyasi(sinav):
    """Şablonu işçiye vermek için geçici dosyaya yazar."""
    import tempfile
    fd, yol = tempfile.mkstemp(suffix=".sablon.json")
    os.close(fd)
    osm.sablon_yaz(sinav["sablon"], yol)
    return yol


def _ders_coz(metinler):
    dersler = []
    for metin in metinler or []:
        parcalar = metin.rsplit(":", 2)
        if len(parcalar) != 3:
            raise SystemExit(f"HATA: --ders biçimi 'Ad:soru:secenek' "
                             f"olmalı: {metin!r}")
        dersler.append({"ad": parcalar[0], "soru": int(parcalar[1]),
                        "secenek": int(parcalar[2])})
    return dersler


def cmd_uret(args):
    import optik_form as of
    tanim = {"ad": args.ad, "kurum": args.kurum,
             "kitapcik": args.kitapcik,
             "ogrenci_no_hane": args.ogrenci_no,
             "tc": args.tc == "acik",
             "ad_soyad": args.ad_soyad == "acik",
             "yanlis_boler": args.yanlis_boler,
             "dersler": _ders_coz(args.ders) or None}
    tanim = {k: v for k, v in tanim.items() if v is not None}
    sonuc = of.form_uret(tanim, yol=args.cikti, on_ayar=args.on_ayar)
    conn = okt.baglan()
    okt.sinav_ekle(conn, sonuc["sablon"],
                   {"yanlis_boler":
                    sonuc["sablon"].puan_kurali.get("yanlis_boler", 0)})
    conn.close()
    s = sonuc["sablon"]
    print(f"form üretildi: {sonuc['pdf']} ({sonuc['sayfa']} sayfa)")
    print(f"şablon: {sonuc['sablon_yolu']}")
    print(f"sınav kimliği: {sonuc['sinav_id']} — {s.soru_sayisi()} soru, "
          f"kitapçık: {'/'.join(s.kitapcik_turleri)}")
    print(f"okumak için: python3 optik.py oku --sinav {sonuc['sinav_id']} "
          "taramalar…")


def cmd_sinavlar(_args):
    conn = okt.baglan()
    liste = okt.sinav_listesi(conn)
    conn.close()
    if not liste:
        print("kayıtlı sınav yok — python3 optik.py uret ile başlayın")
        return
    print(f"{'kimlik':10s} {'ad':34s} {'kağıt':>6s} {'kuyruk':>7s} "
          f"{'anahtar':>8s}  oluşturma")
    for s in liste:
        print(f"{s['id']:10s} {s['ad'][:34]:34s} {s['kagit_sayisi']:6d} "
              f"{s['inceleme_sayisi']:7d} {s['anahtar_sayisi']:8d}  "
              f"{s['olusturma'][:16]}")


def cmd_oku(args):
    import optik_oku as ook
    conn = okt.baglan()
    sinav = _sinav_yukle(conn, args.sinav)
    sablon_yolu = _sablon_dosyasi(sinav)
    media = okt.media_dizin(args.sinav)

    def ilerleme(i, n, kaynak):
        if kaynak:
            print(f"  [{i + 1}/{n}] {os.path.basename(kaynak)}")
    try:
        kagitlar = ook.parti_oku(sinav["sablon"], sablon_yolu,
                                 args.girdiler, warp_dizin=media,
                                 ilerleme_cb=ilerleme)
    finally:
        os.unlink(sablon_yolu)
    okundu = kuyruk = hatali = 0
    for k in kagitlar:
        okt.kagit_ekle(conn, args.sinav, k)
        if k["durum"] == "okundu":
            okundu += 1
        elif k["durum"] == "incelenecek":
            kuyruk += 1
            print(f"  İNCELE: {os.path.basename(k['kaynak'])} "
                  f"s.{k['kaynak_sayfa']} — {'; '.join(k['sorunlar'])}")
        else:
            hatali += 1
            print(f"  HATA: {os.path.basename(k['kaynak'])} "
                  f"s.{k['kaynak_sayfa']} — {k.get('hata')}")
    conn.close()
    print(f"{len(kagitlar)} sayfa okundu: {okundu} temiz, "
          f"{kuyruk} incelemede, {hatali} hatalı")
    if kuyruk:
        print("inceleme: web arayüzü → Optik → İncele "
              "(python3 soru_kes_web.py)")


def _cevaplari_coz(metinler, sablon):
    """--cevaplar değerleri → {ders: {no: harfler}}.

    'Matematik=ABCD..' (ders bazlı) veya tek derste 'ABCD..'.
    Nokta/tire = iptal (anahtar boş). Çoklu doğru köşeli: A[BC]D → 2.
    soru 'BC'."""
    dersler = sablon.dersler() or [""]
    sonuc = {}
    for metin in metinler or []:
        if "=" in metin:
            ders, dizi = metin.split("=", 1)
            ders = ders.strip()
        else:
            if len(dersler) > 1:
                raise SystemExit("HATA: çok dersli sınavda --cevaplar "
                                 "'Ders=ABCD…' biçiminde olmalı")
            ders, dizi = dersler[0], metin
        harfler = {}
        no = 0
        i = 0
        dizi = dizi.strip().upper()
        while i < len(dizi):
            no += 1
            c = dizi[i]
            if c == "[":
                kapa = dizi.index("]", i)
                harfler[str(no)] = dizi[i + 1:kapa]
                i = kapa + 1
            else:
                harfler[str(no)] = "" if c in ".-" else c
                i += 1
        sonuc[ders] = harfler
    return sonuc


def cmd_anahtar(args):
    conn = okt.baglan()
    sinav = _sinav_yukle(conn, args.sinav)
    sablon = sinav["sablon"]
    kitapcik = args.kitapcik or sablon.kitapcik_turleri[0]
    if kitapcik not in sablon.kitapcik_turleri:
        raise SystemExit(f"HATA: kitapçık {kitapcik!r} bu formda yok "
                         f"({'/'.join(sablon.kitapcik_turleri)})")
    if args.tara:
        import optik_oku as ook
        sablon_yolu = _sablon_dosyasi(sinav)
        try:
            kagitlar = ook.parti_oku(sablon, sablon_yolu, [args.tara])
        finally:
            os.unlink(sablon_yolu)
        cevaplar = {}
        for k in kagitlar:
            for ders, sorular in (k.get("cevaplar") or {}).items():
                hedef = cevaplar.setdefault(ders, {})
                for no, c in sorular.items():
                    hedef[no] = c["sembol"] or ""
        if not any(v for d in cevaplar.values() for v in d.values()):
            raise SystemExit("HATA: taranan anahtar kâğıdında işaret "
                             "bulunamadı")
    else:
        if not args.cevaplar:
            raise SystemExit("HATA: --cevaplar veya --tara gerekli")
        cevaplar = _cevaplari_coz(args.cevaplar, sablon)
    # şablonla tutarlılık: bilinmeyen ders uyarısı
    bilinen = set(sablon.dersler() or [""])
    for ders in cevaplar:
        if ders not in bilinen:
            print(f"UYARI: {ders!r} şablon derslerinde yok "
                  f"(şablon: {', '.join(sorted(bilinen)) or 'tek bölüm'})")
    okt.anahtar_koy(conn, args.sinav, kitapcik, cevaplar)
    conn.close()
    adet = sum(1 for d in cevaplar.values() for v in d.values() if v)
    print(f"kitapçık {kitapcik} anahtarı kaydedildi ({adet} soru)")


def _sonuclari_hesapla(conn, sinav_id, yanlis_boler=None):
    sinav = _sinav_yukle(conn, sinav_id)
    kagitlar = okt.kagitlar(conn, sinav_id)
    anahtarlar = okt.anahtarlar(conn, sinav_id)
    kural = {"yanlis_boler":
             yanlis_boler if yanlis_boler is not None
             else sinav["sablon"].puan_kurali.get("yanlis_boler", 0)}
    return sinav, oan.puanla(kagitlar, anahtarlar, kural,
                             sinav["sablon"])


def cmd_puanla(args):
    conn = okt.baglan()
    sinav, sonuclar = _sonuclari_hesapla(conn, args.sinav,
                                         args.yanlis_boler)
    conn.close()
    if not sonuclar:
        print("okunmuş kağıt yok")
        return
    print(f"{sinav['ad']} — {len(sonuclar)} öğrenci")
    print(f"{'sıra':>4s} {'no':10s} {'ad soyad':24s} {'kit':3s} "
          f"{'D':>4s} {'Y':>4s} {'B':>4s} {'net':>7s}")
    for s in sonuclar:
        t = s["toplam"]
        isaret = " !" if s["sorunlar"] else ""
        print(f"{s['sira']:4d} {(s['ogrenci_no'] or '?'):10s} "
              f"{(s['ad_soyad'] or '?')[:24]:24s} "
              f"{(s['kitapcik'] or '-'):3s} {t['dogru']:4d} "
              f"{t['yanlis']:4d} {t['bos']:4d} {t['net']:7.2f}{isaret}")
    sorunlular = [s for s in sonuclar if s["sorunlar"]]
    if sorunlular:
        print(f"\n! işaretli {len(sorunlular)} öğrencide sorun var:")
        for s in sorunlular[:10]:
            print(f"  {s['ogrenci_no'] or s['ad_soyad'] or '?'}: "
                  f"{'; '.join(s['sorunlar'])}")


def cmd_analiz(args):
    conn = okt.baglan()
    sinav, sonuclar = _sonuclari_hesapla(conn, args.sinav, None)
    analiz = oan.madde_analizi(sonuclar, okt.anahtarlar(conn, args.sinav),
                               sinav["sablon"])
    test = analiz["test"]
    print(f"{sinav['ad']} — madde analizi "
          f"({test.get('katilimci', 0)} katılımcı)")
    if test.get("katilimci"):
        print(f"ortalama doğru: {test['ortalama_dogru']}  "
              f"ortalama net: {test['ortalama_net']}  ss: {test['ss']}  "
              f"KR-20: {test['kr20'] if test['kr20'] is not None else '-'}")
        print(f"{'ders':22s} {'soru':>4s} {'p':>6s} {'ayırt':>6s} "
              f"{'r_pb':>6s}  dağılım / uyarılar")
        for q in analiz["sorular"]:
            dagilim = " ".join(f"{s}:{a}" for s, a in
                               sorted(q["dagilim"].items()))
            uyari = ("  ⚠ " + "; ".join(q["uyarilar"])) \
                if q["uyarilar"] else ""
            print(f"{(q['ders'] or 'Genel')[:22]:22s} {q['soru']:>4s} "
                  f"{q['p']:6.2f} {q['ayirt_edicilik']:6.2f} "
                  f"{q['nokta_ciftserili']:6.2f}  {dagilim}{uyari}")
    kazanimlar = None
    if args.kazanim_csv:
        kazanimlar = oan.kazanim_csv_oku(args.kazanim_csv)
        okt.kazanim_koy(conn, args.sinav, kazanimlar)
    elif sinav.get("kazanimlar"):
        kazanimlar = sinav["kazanimlar"]      # köprüden otomatik gelmiş
    if kazanimlar:
        ka = oan.kazanim_analizi(
            sonuclar, kazanimlar,
            kitapcik_sira=sinav["ayarlar"].get("kitapcik_sira"))
        print("\nkazanım analizi (sınıf):")
        for k in ka["kazanimlar"]:
            print(f"  %{k['yuzde']:5.1f}  {k['kazanim']} "
                  f"({k['ders'] or 'Genel'}, {len(k['sorular'])} soru)")
    conn.close()


def cmd_disa(args):
    conn = okt.baglan()
    sinav, sonuclar = _sonuclari_hesapla(conn, args.sinav, None)
    if not sonuclar:
        conn.close()
        print("okunmuş kağıt yok")
        return
    cikti = args.cikti
    if args.tur == "csv":
        oan.disa_csv(sonuclar, cikti)
    elif args.tur == "txt":
        oan.disa_txt(sonuclar, cikti, sinav["sablon"])
    elif args.tur == "eokul":
        oan.disa_eokul(sonuclar, cikti)
    elif args.tur == "karne":
        kazanimlar = sinav.get("kazanimlar") or {}
        kazanim = None
        if kazanimlar:
            kazanim = oan.kazanim_analizi(
                sonuclar, kazanimlar,
                kitapcik_sira=sinav["ayarlar"].get("kitapcik_sira")
            )["ogrenciler"]
        oan.karne_pdf(sonuclar, cikti, sinav_ad=sinav["ad"],
                      kurum=sinav["ayarlar"].get("kurum", ""),
                      kazanim=kazanim)
    conn.close()
    print(f"yazıldı: {cikti}")


def cmd_durum(_args):
    import optik_oku as ook
    durum = ook.optik_dogrula(derin=True)
    print(("HAZIR: " if durum["ok"] else "KURULU DEĞİL: ")
          + durum["mesaj"])


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="optik.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    alt = p.add_subparsers(dest="komut", required=True)

    u = alt.add_parser("uret", help="optik form PDF'i + şablon üret")
    u.add_argument("--on-ayar", choices=None, metavar="AD",
                   help="yazili-20/50/100, lgs-sozel, lgs-sayisal, tyt, ayt")
    u.add_argument("--ad", metavar="BAŞLIK")
    u.add_argument("--kurum", metavar="KURUM")
    u.add_argument("--ders", action="append", metavar="AD:SORU:SECENEK",
                   help="tekrarlanabilir; ör. 'Matematik:20:4'")
    u.add_argument("--kitapcik", type=int, metavar="N",
                   help="kitapçık türü sayısı (1-4)")
    u.add_argument("--ogrenci-no", type=int, metavar="HANE",
                   help="öğrenci no hane sayısı (0=alan yok)")
    u.add_argument("--tc", choices=("acik", "kapali"))
    u.add_argument("--ad-soyad", choices=("acik", "kapali"))
    u.add_argument("--yanlis-boler", type=int, choices=(0, 3, 4))
    u.add_argument("-o", "--cikti", default="optik_form.pdf")
    u.set_defaults(f=cmd_uret)

    alt.add_parser("sinavlar", help="kayıtlı sınavları listele") \
       .set_defaults(f=cmd_sinavlar)

    o = alt.add_parser("oku", help="taramaları oku (görüntü/PDF)")
    o.add_argument("--sinav", required=True, metavar="KIMLIK")
    o.add_argument("girdiler", nargs="+", metavar="DOSYA")
    o.set_defaults(f=cmd_oku)

    a = alt.add_parser("anahtar", help="cevap anahtarı gir/tara")
    a.add_argument("--sinav", required=True, metavar="KIMLIK")
    a.add_argument("--kitapcik", metavar="A")
    a.add_argument("--cevaplar", action="append",
                   metavar="[DERS=]ABCD…",
                   help="nokta=iptal, [BC]=çoklu doğru; tekrarlanabilir")
    a.add_argument("--tara", metavar="DOSYA",
                   help="işaretlenmiş anahtar kâğıdını tara")
    a.set_defaults(f=cmd_anahtar)

    pu = alt.add_parser("puanla", help="netleri hesapla, sıralı listele")
    pu.add_argument("--sinav", required=True, metavar="KIMLIK")
    pu.add_argument("--yanlis-boler", type=int, choices=(0, 3, 4))
    pu.set_defaults(f=cmd_puanla)

    an = alt.add_parser("analiz", help="madde + kazanım analizi")
    an.add_argument("--sinav", required=True, metavar="KIMLIK")
    an.add_argument("--kazanim-csv", metavar="CSV",
                    help="ders,soru,kazanim başlıklı CSV")
    an.set_defaults(f=cmd_analiz)

    d = alt.add_parser("disa", help="sonuçları dışa aktar")
    d.add_argument("--sinav", required=True, metavar="KIMLIK")
    d.add_argument("--tur", required=True,
                   choices=("csv", "txt", "eokul", "karne"))
    d.add_argument("-o", "--cikti", required=True)
    d.set_defaults(f=cmd_disa)

    alt.add_parser("durum", help="okuma motoru kurulum durumu") \
       .set_defaults(f=cmd_durum)

    args = p.parse_args(argv)
    args.f(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())

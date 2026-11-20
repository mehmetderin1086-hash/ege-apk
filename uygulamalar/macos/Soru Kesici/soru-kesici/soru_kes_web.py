#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — tarayıcı tabanlı arayüz.

macOS'un eski Tk sürümündeki "boş pencere" sorununu tamamen atlamak için
arayüz, yerleşik bir HTTP sunucusu üzerinden tarayıcıda açılır. Dosya ve
kayıt yeri seçimi macOS'un yerel diyaloglarıyla (osascript) yapılır.
Çekirdek mantık soru_kes.py'den kullanılır.

Çalıştırma:
    .venv/bin/python soru_kes_web.py
Tarayıcı otomatik açılır; açılmazsa http://127.0.0.1:8756 adresine gidin.
"""

import atexit
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.request
import uuid
import webbrowser
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import soru_kes as sk
import veri_yollari

PORT = 8756
ONIZLEME_EN = 1100          # önizleme PNG'sinin en fazla genişliği (px)
YUKLEME_SINIR = 400 * 1024 * 1024   # sürükle-bırak yüklemede dosya sınırı
AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")
GECMIS_YOLU = os.path.join(veri_yollari.veri_koku(), "gecmis.json")
GECMIS_SINIR = 100
MERKEZ_PORTLARI = tuple(range(8020, 8031))  # Biyoloji Stüdyosu (biyo-cozucu) aralığı


def merkez_adresi_bul(portlar=MERKEZ_PORTLARI, zaman_asimi=0.4):
    """Biyoloji Stüdyosu'nun (biyo-cozucu) taban URL'sini imza yoklamasıyla bulur.

    Port dolu olması yetmez; /healthz yanıtında "app": "biyo-cozucu" imzası
    aranır ki yabancı bir servis Stüdyo sanılmasın.
    """
    for port in portlar:
        taban = "http://127.0.0.1:%d" % port
        try:
            with urllib.request.urlopen(
                    taban + "/healthz", timeout=zaman_asimi) as yanit:
                veri = json.loads(yanit.read().decode("utf-8", "replace"))
        except (OSError, ValueError):
            continue
        if isinstance(veri, dict) and veri.get("app") == "biyo-cozucu":
            return taban
    return None
TARANMIS_UYARI_ESIGI = 120   # bu kadar taranmış sayfa üstünde bellek/OCR uyarısı
ROL_GUVEN_ESIGI = 0.70
DUZEN_GUVEN_ESIGI = 0.70
EGIKLIK_ESIGI = 1.0

# Yüklenmiş belgenin durumu (tek kullanıcı, yerel)
DURUM = {
    "girdiler": [],
    "sayfalar": [],
    "acik": [],
    "sutun_xler": None,
    "fmt": None,
    "kutu_onbellek": {},
    "duzenlendi": set(),     # kullanıcı eliyle değiştirilen sayfa indeksleri
    "gecici_klasor": None,   # sürükle-bırak yüklemelerinin geçici dizini
    "ozet": None,            # _ozet_al önbelleği (test yapısı + kimlik haritaları)
    "ozet_kirli": True,      # yükleme/düzenleme sonrası yeniden hesaplama gerekir
    "cevaplar": None,        # cevap_anahtari_bul çıktısı (yükleme sonrası)
    "profil": None,          # BelgeProfili.to_dict() — V2 kalibrasyon sonucu
    "analizler": [],         # sayfa başına normalize SayfaAnalizi sözlükleri
    "kutu_meta": {},         # {sayfa: [{guven, inceleme_durumu, ...}, ...]}
    "inceleme_onaylari": set(),  # kullanıcının açıkça onayladığı kararlı kutu kimlikleri
    "sayfa_inceleme_kararlari": {},  # {sayfa: onayli|soru_yok}
    "sayfa_karar_yedekleri": {},     # soru_yok kararını geri almak için oturum içi kopya
    "kalite_modu": "strict",        # strict | balanced | legacy
    "kalibrasyon_hatasi": None,  # V2 hata verirse eski motorla devam nedeni
    "islem": None,           # {asama, yapilan, toplam, mesaj} — GET /ilerleme
    "indirmeler": {},        # {jeton: dosya_yolu} — tarayıcı indirmesi için
    "etiketler": {},         # {kimlik: {anahtar: değer}} elle etiketler
    "cevap_duzeltmeler": {},  # {kimlik: 'A'..'E'|''} elle cevap düzeltmeleri
    "konu_sozluk": [],       # konular.csv'den otomatik konu etiketleme sözlüğü
}
KONU_CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "konular.csv")
KILIT = threading.Lock()     # kutu_onbellek + ozet eşzamanlı erişimini korur
GECMIS_KILIT = threading.Lock()
# Ağır/durum-değiştiren işlemleri (yükle, kes, sınav, export, banka-aktar, AI)
# ATOMİK olarak serileştirir. Kilitsiz "if DURUM['islem']" guard'ı yarışa açıktı:
# iki eşzamanlı istek geçebiliyor, en tehlikelisi yükleme-sırasında-kesim fitz
# use-after-close (çökme). Non-blocking acquire → ikinci istek "işlem sürüyor".
AGIR_KILIT = threading.Lock()
AGIR_YOLLAR = {"/yukle", "/kes", "/sinav-pdf", "/disa-aktar",
               "/bankaya-aktar", "/banka-sinav", "/banka-ai-etiketle",
               "/optik-uret", "/optik-tara", "/optik-disa", "/sihirbaz-uret"}

# macOS'un yerel diyalog/Finder entegrasyonuna (osascript, "open -R") bağımlı
# uçlar — Windows'ta karşılığı yok, düğmeleri arayüzde dursun diye sunucu
# tarafında anlaşılır 501 döner (JS tarafı dokunulmadan aynı kalır).
MACOS_OZEL_YOLLAR = {"/sec", "/kayit-yeri", "/goster", "/gecmis-goster"}


def ayar_oku():
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def ayar_yaz(**yeni):
    d = ayar_oku()
    d.update(yeni)
    try:
        with open(AYAR_YOLU, "w", encoding="utf-8") as f:
            json.dump(d, f)
    except OSError:
        pass


# --------------------------------------------------------- macOS diyalogları

def osascript(satirlar):
    r = subprocess.run(["osascript"] + sum((["-e", s] for s in satirlar), []),
                       capture_output=True, text=True)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def dosya_sec():
    kod, cikti, _ = osascript([
        # Diyaloğu öne getir: arka plan (tarayıcı) sürecinden açılan seçici
        # aksi hâlde pencerenin arkasında kalıp "tepki yok" izlenimi verebilir.
        'tell application "System Events" to activate',
        'set theFiles to choose file with prompt '
        '"Test dosyalarını seçin (PDF / DOCX / PNG / JPG / TIFF / BMP / WebP / GIF)" '
        'with multiple selections allowed',
        'set thePaths to {}',
        'repeat with f in theFiles',
        '  set end of thePaths to POSIX path of f',
        'end repeat',
        "set AppleScript's text item delimiters to linefeed",
        'return thePaths as text',
    ])
    if kod != 0:
        return []
    return [l for l in cikti.split("\n") if l.strip()]


def _as_kacir(s):
    """AppleScript string-literal kaçışı (ters bölü + tırnak)."""
    return (s or "").replace("\\", "\\\\").replace('"', '\\"')


def kayit_yeri(varsayilan_ad, varsayilan_klasor, istem="Arşiv nereye "
              "kaydedilsin?"):
    # CLI/geçmiş için kalır; web üretim akışları artık tarayıcı indirmesi kullanır.
    satirlar = []
    secenek = ""
    if varsayilan_klasor and os.path.isdir(varsayilan_klasor):
        satirlar.append(f'set varsayilanKlasor to POSIX file "{_as_kacir(varsayilan_klasor)}"')
        secenek = " default location varsayilanKlasor"
    satirlar = ['tell application "System Events" to activate'] + satirlar + [
        f'set f to choose file name with prompt "{_as_kacir(istem)}" '
        f'default name "{_as_kacir(varsayilan_ad)}"' + secenek,
        'return POSIX path of f',
    ]
    kod, cikti, _ = osascript(satirlar)
    if kod != 0:
        return None
    return cikti.strip()


# --------------------------------------------------------- tarayıcı indirmesi

CIKTI_DIZIN = os.path.join(os.path.dirname(GECMIS_YOLU), "ciktilar")

_MIME = {".zip": "application/zip", ".pdf": "application/pdf",
         ".docx": "application/vnd.openxmlformats-officedocument."
                  "wordprocessingml.document",
         ".csv": "text/csv; charset=utf-8", ".html": "text/html; charset=utf-8",
         ".md": "text/markdown; charset=utf-8", ".png": "image/png"}


def _girdi_temel():
    return (os.path.splitext(os.path.basename(DURUM["girdiler"][0]))[0]
            if DURUM["girdiler"] else "Soru")


def _ciktilari_budala(tut=60):
    """Çıktı dizini sınırsız büyümesin — en eski dosyaları sil (son `tut` kalır).
    Tarayıcı zaten indirdi; bunlar yalnız geçmiş/Finder kopyası."""
    try:
        dosyalar = [os.path.join(CIKTI_DIZIN, d)
                    for d in os.listdir(CIKTI_DIZIN)]
        dosyalar = [d for d in dosyalar if os.path.isfile(d)]
        if len(dosyalar) > tut:
            dosyalar.sort(key=os.path.getmtime)
            for d in dosyalar[:-tut]:
                try:
                    os.remove(d)
                except OSError:
                    pass
    except OSError:
        pass


def _cikti_yolu(ad):
    """Kalıcı çıktı dizininde (App Support/ciktilar) benzersiz bir yol.
    Tarayıcı bir kopyayı İndirilenler'e indirir; bu kopya geçmiş/Finder içindir."""
    os.makedirs(CIKTI_DIZIN, exist_ok=True)
    _ciktilari_budala()
    kok, uz = os.path.splitext(ad)
    yol = os.path.join(CIKTI_DIZIN, ad)
    i = 2
    while os.path.exists(yol):
        yol = os.path.join(CIKTI_DIZIN, f"{kok}_{i}{uz}")
        i += 1
    return yol


def _indirme_hazirla(yollar, zip_adi="indirme.zip"):
    """Üretilen dosya(lar)dan indirme jetonu üretir (çok dosya → tek zip).
    Dönüş: (jeton, indirilecek_ad) | (None, None)."""
    yollar = [y for y in yollar if y and os.path.exists(y)]
    if not yollar:
        return None, None
    if len(yollar) == 1:
        hedef = yollar[0]
    else:
        hedef = _cikti_yolu(zip_adi)
        with zipfile.ZipFile(hedef, "w", zipfile.ZIP_DEFLATED) as z:
            for y in yollar:
                z.write(y, os.path.basename(y))
    jeton = uuid.uuid4().hex
    with KILIT:
        ind = DURUM["indirmeler"]
        ind[jeton] = hedef
        # sınırsız büyümeyi önle: en eski jetonları at (dosya diskte kalır)
        while len(ind) > 50:
            ind.pop(next(iter(ind)))
    return jeton, os.path.basename(hedef)


# --------------------------------------------------------- işlem geçmişi

def gecmis_oku():
    """Kayıt geçmişini okur (hoşgörülü: bozuk/yok → boş liste)."""
    try:
        with open(GECMIS_YOLU, encoding="utf-8") as f:
            veri = json.load(f)
        return veri if isinstance(veri, list) else []
    except (OSError, ValueError):
        return []


def gecmis_ekle(tur, cikti, soru, test, girdiler):
    """Bir kesim/sınav çıktısını geçmişe (en yeni başta) ekler; 100 ile sınırlar.
    Date.now() yasak (harness) — dosya mtime ile ISO zaman damgası kurulur."""
    import datetime
    with GECMIS_KILIT:
        kayitlar = gecmis_oku()
        try:
            ts = os.path.getmtime(cikti)
        except OSError:
            ts = None
        tarih = (datetime.datetime.fromtimestamp(ts).isoformat(timespec="seconds")
                 if ts else "")
        kayitlar.insert(0, {"tarih": tarih, "girdiler": list(girdiler),
                            "cikti": cikti, "tur": tur, "soru": soru,
                            "test": test})
        kayitlar = kayitlar[:GECMIS_SINIR]
        try:
            os.makedirs(os.path.dirname(GECMIS_YOLU), exist_ok=True)
            with open(GECMIS_YOLU, "w", encoding="utf-8") as f:
                json.dump(kayitlar, f, ensure_ascii=False)
        except OSError:
            pass


# --------------------------------------------------------- görüntü üretimi

def _kutular(idx):
    ob = DURUM["kutu_onbellek"]
    with KILIT:
        if idx not in ob:
            analizler = DURUM.get("analizler") or []
            if idx < len(analizler) and analizler[idx].get("adaylar") is not None:
                adaylar = analizler[idx].get("adaylar") or []
                ob[idx] = [tuple(a["kutu"]) for a in adaylar]
                DURUM.setdefault("kutu_meta", {})[idx] = [
                    {k: v for k, v in a.items() if k != "kutu"} for a in adaylar]
            else:
                ob[idx] = [tuple(k) for k in
                           sk.sorulari_tespit(DURUM["sayfalar"][idx], DURUM["fmt"])]
        return list(ob[idx])


def _sozluk(nesne):
    """Dataclass/nesne/sözlük V2 sonuçlarını JSON-güvenli sözlüğe çevir."""
    if isinstance(nesne, dict):
        return dict(nesne)
    donustur = getattr(nesne, "to_dict", None)
    if callable(donustur):
        sonuc = donustur()
        return dict(sonuc) if isinstance(sonuc, dict) else {}
    try:
        import dataclasses
        if dataclasses.is_dataclass(nesne):
            return dataclasses.asdict(nesne)
    except (ImportError, TypeError):
        pass
    return {}


def _kutu_dortlu(kutu):
    """Farklı Rect temsillerini [x0,y0,x1,y1] listesine indirger."""
    if isinstance(kutu, dict):
        kutu = [kutu.get(k) for k in ("x0", "y0", "x1", "y1")]
    elif all(hasattr(kutu, k) for k in ("x0", "y0", "x1", "y1")):
        kutu = [getattr(kutu, k) for k in ("x0", "y0", "x1", "y1")]
    try:
        degerler = [float(v) for v in list(kutu)[:4]]
    except (TypeError, ValueError):
        return None
    if len(degerler) != 4 or degerler[2] <= degerler[0] or degerler[3] <= degerler[1]:
        return None
    return degerler


def _durum_normalize(durum, guven):
    durum = str(durum or "").strip().lower().replace("ı", "i")
    es = {"otomatik": "otomatik", "automatic": "otomatik", "auto": "otomatik",
          "incele": "incele", "review": "incele", "bekliyor": "incele",
          "reddedildi": "reddedildi", "rejected": "reddedildi", "red": "reddedildi"}
    if durum in es:
        return es[durum]
    return "otomatik" if guven >= .82 else "incele" if guven >= .55 else "reddedildi"


def _kalite_modu():
    mod = str(DURUM.get("kalite_modu") or "strict").strip().lower()
    return mod if mod in ("strict", "balanced", "legacy") else "strict"


def _metin_listesi(deger):
    if deger is None:
        return []
    if isinstance(deger, (list, tuple, set, frozenset)):
        return [str(v) for v in deger if v is not None and str(v).strip()]
    return [str(deger)] if str(deger).strip() else []


def _kararli_kutu_kimligi(sayfa, kutu, kaynak=None, sira=0):
    """Çekirdek kimliği yoksa belge+sayfa+ilk geometri üzerinden üret.

    Kimlik, kullanıcı kutuyu taşıdığında ``kutulari_guncelle`` tarafından
    korunur. Böylece inceleme onayı kırılgan ``sayfa:kutu_indeksi`` anahtarına
    bağlı kalmaz.
    """
    kaynak = kaynak or {}
    cekirdek = next((kaynak.get(k) for k in
                     ("karar_kimligi", "kararli_kimlik", "stable_id",
                      "kimlik", "id")
                     if kaynak.get(k) not in (None, "")), None)
    profil = DURUM.get("profil") or {}
    belge = profil.get("kaynak_hash") or "|".join(
        os.path.abspath(str(y)) for y in (DURUM.get("girdiler") or []))
    if cekirdek is not None:
        if str(cekirdek).startswith(("v3_", "kutu-")):
            return str(cekirdek)
        ham = f"{belge}|{sayfa}|core|{cekirdek}"
    else:
        koord = ",".join(f"{float(v):.3f}" for v in kutu)
        ham = f"{belge}|{sayfa}|{sira}|{koord}|{kaynak.get('numara')}"
    return "kutu-" + hashlib.sha256(ham.encode("utf-8")).hexdigest()[:24]


def _aday_normalize(aday, sayfa_rolu=None, sayfa=0, sira=0):
    ham = _sozluk(aday)
    if ham.get("devam_aday"):
        return None                 # sütun başı yetimi, bağımsız soru değil
    kutu = _kutu_dortlu(ham.get("kutu", ham.get("bbox", ham.get("koordinat"))))
    if kutu is None:
        return None
    try:
        guven = max(0.0, min(1.0, float(
            ham.get("kalibre_guven", ham.get("guven", 0.0)))))
    except (TypeError, ValueError):
        guven = 0.0
    durum = _durum_normalize(ham.get("inceleme_durumu", ham.get("durum")), guven)
    kanitlar = _metin_listesi(ham.get("kanitlar"))
    kanitlar.extend(_metin_listesi(ham.get("kaynak_yontemler")))
    uyarilar = _metin_listesi(ham.get("uyarilar"))
    uyarilar.extend(_metin_listesi(ham.get("risk_nedenleri")))
    kararli_kimlik = _kararli_kutu_kimligi(
        sayfa, kutu, kaynak=ham, sira=sira)
    duzen_bolgeleri = []
    for bolge in ham.get("duzen_bolgeleri") or []:
        sozluk = _sozluk(bolge)
        duzen_bolgeleri.append(sozluk if sozluk else bolge)
    return {"kutu": kutu, "soru_turu": ham.get("soru_turu") or "bilinmiyor",
            "sayfa_rolu": ham.get("sayfa_rolu") or sayfa_rolu or "bilinmiyor",
            "guven": guven, "kalibre_guven": guven,
            "kanitlar": list(dict.fromkeys(kanitlar)),
            "uyarilar": list(dict.fromkeys(uyarilar)),
            "risk_nedenleri": list(dict.fromkeys(uyarilar)),
            "inceleme_durumu": durum,
            "kararli_kimlik": kararli_kimlik,
            "karar_kimligi": ham.get("karar_kimligi") or kararli_kimlik,
            "onay_durumu": ham.get("onay_durumu") or
                            ("otomatik" if durum == "otomatik" else "bekliyor"),
            "kaynak_yontemler": list(dict.fromkeys(kanitlar)),
            "duzen_bolgeleri": duzen_bolgeleri}


def _v2_sonuclarini_sakla(profil, analizler):
    """Core V2 sonucunu web durumuna alır ve kutu önbelleğini doldurur."""
    profil_sozluk = _sozluk(profil)
    yeni_analizler, kutu_meta, kutu_onbellek = [], {}, {}
    for idx, analiz in enumerate(analizler or []):
        ham = _sozluk(analiz)
        rol = ham.get("sayfa_rolu") or ham.get("rol") or "bilinmiyor"
        aday_nesneleri = getattr(analiz, "adaylar", None)
        if aday_nesneleri is None:
            aday_nesneleri = ham.get("adaylar") or []
        adaylar = []
        for sira, aday in enumerate(aday_nesneleri):
            norm = _aday_normalize(aday, rol, sayfa=idx, sira=sira)
            if norm is not None:
                adaylar.append(norm)
        ham["sayfa_rolu"] = rol
        ham["adaylar"] = adaylar
        yeni_analizler.append(ham)
        kutu_onbellek[idx] = [tuple(a["kutu"]) for a in adaylar]
        kutu_meta[idx] = [{k: v for k, v in a.items() if k != "kutu"}
                          for a in adaylar]
    with KILIT:
        DURUM["profil"] = profil_sozluk
        DURUM["analizler"] = yeni_analizler
        DURUM["kutu_onbellek"] = kutu_onbellek
        DURUM["kutu_meta"] = kutu_meta
        DURUM["inceleme_onaylari"] = set()
        DURUM["sayfa_inceleme_kararlari"] = {}
        DURUM["sayfa_karar_yedekleri"] = {}
        DURUM["kalibrasyon_hatasi"] = None
    return bool(profil_sozluk or yeni_analizler)


def _v2_analiz_et():
    """V2 mevcutsa çalıştır; eski kurulumda sessizce legacy'ye dön."""
    analiz_et = getattr(sk, "belge_analiz_et", None)
    if not callable(analiz_et):
        return False
    try:
        profil, analizler = analiz_et(
            DURUM["sayfalar"], fmt=DURUM["fmt"], girdiler=DURUM["girdiler"])
        return _v2_sonuclarini_sakla(profil, analizler)
    except Exception as e:  # noqa: BLE001 — V2 arızasında belgeyi kullanılabilir tut
        with KILIT:
            DURUM["profil"] = None
            DURUM["analizler"] = []
            DURUM["kutu_meta"] = {}
            DURUM["inceleme_onaylari"] = set()
            DURUM["sayfa_inceleme_kararlari"] = {}
            DURUM["sayfa_karar_yedekleri"] = {}
            DURUM["kalibrasyon_hatasi"] = str(e)
        return False


def _kutu_metalari(idx):
    kutular = _kutular(idx)
    with KILIT:
        meta = list((DURUM.get("kutu_meta") or {}).get(idx, []))
        onaylar = set(DURUM.get("inceleme_onaylari") or set())
        sayfa_karari = (DURUM.get("sayfa_inceleme_kararlari") or {}).get(idx)
    analiz_var = idx < len(DURUM.get("analizler") or [])
    legacy_riskli = (_kalite_modu() == "strict"
                      and (DURUM.get("kalibrasyon_hatasi") or not analiz_var))
    sonuc = []
    for i in range(len(kutular)):
        if i < len(meta):
            m = dict(meta[i])
        elif legacy_riskli:
            m = {"soru_turu": "bilinmiyor", "sayfa_rolu": "bilinmiyor",
                 "guven": 0.0, "kalibre_guven": 0.0,
                 "kanitlar": ["legacy_tespit"],
                 "uyarilar": ["kalibrasyon_dogrulanamadi"],
                 "risk_nedenleri": ["kalibrasyon_dogrulanamadi"],
                 "inceleme_durumu": "incele"}
        else:
            m = {"soru_turu": "bilinmiyor", "sayfa_rolu": "soru", "guven": 1.0,
                 "kalibre_guven": 1.0, "kanitlar": ["legacy"], "uyarilar": [],
                 "risk_nedenleri": [], "inceleme_durumu": "otomatik"}
        m.setdefault("kararli_kimlik", _kararli_kutu_kimligi(
            idx, kutular[i], kaynak=m, sira=i))
        kimlik_anahtari = "kutu:" + m["kararli_kimlik"]
        eski_anahtar = f"{idx}:{i}"
        kutu_onayli = kimlik_anahtari in onaylar or eski_anahtar in onaylar
        m["onayli"] = kutu_onayli or sayfa_karari == "onayli"
        m["onay_kaynagi"] = ("sayfa" if sayfa_karari == "onayli" else
                              "kutu" if kutu_onayli else None)
        sonuc.append(m)
    # Eski/çekirdek metasında kimlik yoksa bir kez kalıcılaştır; sonraki yeniden
    # sıralamalarda onay ve kanıt aynı kutuyla taşınır.
    if sonuc and any(i >= len(meta) or not meta[i].get("kararli_kimlik")
                     for i in range(len(sonuc))):
        with KILIT:
            DURUM.setdefault("kutu_meta", {})[idx] = [
                {k: v for k, v in m.items()
                 if k not in ("onayli", "onay_kaynagi")} for m in sonuc]
    return sonuc


def _olcek(sayfa):
    """Sayfa (layout) → gorsel() piksel ölçeği; render etmeden hesaplanır."""
    return (sayfa.dpi / 72) if not sayfa.raster else 1.0


def onizleme_olcek(idx):
    """(page_koord → önizleme PNG piksel) toplam ölçeği + sayfa boyutları.
    Tarayıcı, kutu koordinatlarını bu ölçekle ekrana çevirir (ve tersine)."""
    sayfa = DURUM["sayfalar"][idx]
    olcek = _olcek(sayfa)
    tam_en = sayfa.genislik * olcek
    oran = min(1.0, ONIZLEME_EN / max(tam_en, 1))
    return {"olcek": olcek * oran,
            "genislik": sayfa.genislik, "yukseklik": sayfa.yukseklik}


def sayfa_onizleme_png(idx, ciplak=False):
    """Önizleme PNG'si. ciplak=True: kutusuz temiz görüntü (düzenleme
    tuvali için — kutular tarayıcıda çizilir)."""
    sayfa = DURUM["sayfalar"][idx]
    if ciplak:
        gorsel, _ = sayfa.gorsel()
    else:
        gorsel = sk.onizleme_gorseli(sayfa, _kutular(idx))
    oran = min(1.0, ONIZLEME_EN / gorsel.width)
    if oran < 1.0:
        gorsel = gorsel.resize((int(gorsel.width * oran),
                                int(gorsel.height * oran)))
    tampon = io.BytesIO()
    gorsel.save(tampon, format="PNG")
    return tampon.getvalue()


def soru_onizleme_png(idx, kutu_no):
    """Tek bir kutunun traşlanmış kırpması — zip'e girecek görüntünün birebir
    önizlemesi (küçük resim şeridi)."""
    kutular = _kutular(idx)
    if not 0 <= kutu_no < len(kutular):
        return None
    img = sk.trasla(DURUM["sayfalar"][idx].kirp(kutular[kutu_no]))
    oran = min(1.0, 360 / img.width)
    if oran < 1.0:
        img = img.resize((int(img.width * oran), int(img.height * oran)))
    tampon = io.BytesIO()
    img.save(tampon, format="PNG")
    return tampon.getvalue()


def _oku_kutular(idx):
    """GET /kutular yanıtı: sayfa koordinatındaki kutular + ölçek + boyut."""
    veri = onizleme_olcek(idx)
    veri["kutular"] = [list(k) for k in _kutular(idx)]
    veri["kutu_meta"] = _kutu_metalari(idx)
    analizler = DURUM.get("analizler") or []
    veri["sayfa_rolu"] = (analizler[idx].get("sayfa_rolu", "bilinmiyor")
                           if idx < len(analizler) else None)
    veri["v2"] = bool(DURUM.get("profil") or DURUM.get("analizler"))
    veri["duzenlendi"] = idx in DURUM["duzenlendi"]
    veri["sayfa_inceleme"] = _sayfa_inceleme_kaydi(idx)
    return veri


def _kutu_ayni(a, b, tolerans=0.5):
    return all(abs(float(x) - float(y)) <= tolerans for x, y in zip(a, b))


def _kutu_iou(a, b):
    ix0, iy0 = max(a[0], b[0]), max(a[1], b[1])
    ix1, iy1 = min(a[2], b[2]), min(a[3], b[3])
    kesi = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    aa = max(0.0, a[2] - a[0]) * max(0.0, a[3] - a[1])
    bb = max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])
    return kesi / max(aa + bb - kesi, 1e-9)


def _kutu_girdisi(ham):
    if isinstance(ham, dict):
        kutu = ham.get("kutu", ham.get("bbox", ham.get("koordinat")))
        kimlik = ham.get("kararli_kimlik", ham.get("kimlik"))
    else:
        kutu, kimlik = ham, None
    return kutu, str(kimlik) if kimlik else None


def kutulari_guncelle(idx, ham_kutular):
    """Kutu snapshot'ını kimlik tabanlı fark olarak uygula.

    Değişmeyen kutunun kalibre güveni/kanıtları/onayı aynen korunur. Yalnız
    taşınan, yeniden boyutlanan veya eklenen kutu açık kullanıcı düzeltmesi
    olarak onaylanır; silinen kutuların eski onay anahtarları temizlenir.
    Eski istemcilerin yalnız koordinat gönderen snapshot'ları geometri/IoU ile
    eşleştirilir.
    """
    sayfa = DURUM["sayfalar"][idx]
    G, Y = sayfa.genislik, sayfa.yukseklik
    eski_kutular = _kutular(idx)
    eski_meta = _kutu_metalari(idx)
    eski_kimlik_indeks = {
        m.get("kararli_kimlik"): i for i, m in enumerate(eski_meta)
        if m.get("kararli_kimlik")}
    temiz_girdi = []
    for ham in ham_kutular:
        k, istenen_kimlik = _kutu_girdisi(ham)
        try:
            x0, y0, x1, y1 = (float(v) for v in list(k)[:4])
        except (TypeError, ValueError):
            continue
        x0, x1 = sorted((max(0, min(G, x0)), max(0, min(G, x1))))
        y0, y1 = sorted((max(0, min(Y, y0)), max(0, min(Y, y1))))
        if x1 - x0 >= 8 and y1 - y0 >= 8:      # dejenere kutuyu ele
            temiz_girdi.append(((x0, y0, x1, y1), istenen_kimlik))

    kullanilan = set()
    kayitlar = []
    for sira, (kutu, istenen_kimlik) in enumerate(temiz_girdi):
        eski_i = eski_kimlik_indeks.get(istenen_kimlik)
        if eski_i in kullanilan:
            eski_i = None
        if eski_i is None:
            # Önce tam geometriyi, sonra yalnız eski snapshot istemcileri için
            # güçlü örtüşmeyi kullan. Kararlı kimlik gönderen yeni istemcide
            # kimlik bulunamadıysa bunu yeni kutu saymak daha güvenlidir.
            tam = [i for i, k in enumerate(eski_kutular)
                   if i not in kullanilan and _kutu_ayni(k, kutu)]
            if tam:
                eski_i = tam[0]
            elif istenen_kimlik is None:
                adaylar = [(i, _kutu_iou(k, kutu))
                           for i, k in enumerate(eski_kutular)
                           if i not in kullanilan]
                if adaylar:
                    en_i, en_iou = max(adaylar, key=lambda t: t[1])
                    if en_iou >= 0.35:
                        eski_i = en_i

        if eski_i is None:
            kimlik = _kararli_kutu_kimligi(
                idx, kutu, kaynak={"numara": "kullanici"},
                sira=len(eski_kutular) + sira)
            meta = {"kararli_kimlik": kimlik, "soru_turu": "bilinmiyor",
                    "sayfa_rolu": "soru", "guven": 0.0,
                    "kalibre_guven": 0.0,
                    "kanitlar": ["kullanici_duzeltmesi"],
                    "uyarilar": ["kullanici_ekledi"],
                    "risk_nedenleri": ["kullanici_ekledi"],
                    "inceleme_durumu": "incele"}
            degisti = True
        else:
            kullanilan.add(eski_i)
            meta = {k: v for k, v in dict(eski_meta[eski_i]).items()
                    if k not in ("onayli", "onay_kaynagi")}
            kimlik = meta.setdefault("kararli_kimlik", _kararli_kutu_kimligi(
                idx, eski_kutular[eski_i], kaynak=meta, sira=eski_i))
            degisti = not _kutu_ayni(eski_kutular[eski_i], kutu)
            if degisti:
                meta["kanitlar"] = list(dict.fromkeys(
                    _metin_listesi(meta.get("kanitlar")) +
                    ["kullanici_duzeltmesi"]))
                meta["uyarilar"] = list(dict.fromkeys(
                    _metin_listesi(meta.get("uyarilar")) +
                    ["kullanici_geometri_duzeltmesi"]))
                meta["risk_nedenleri"] = list(dict.fromkeys(
                    _metin_listesi(meta.get("risk_nedenleri")) +
                    ["kullanici_geometri_duzeltmesi"]))
        kayitlar.append({"kutu": kutu, "meta": meta, "degisti": degisti,
                         "eski_i": eski_i, "kimlik": kimlik})

    sx = DURUM["sutun_xler"] or [0.0]
    kayitlar.sort(key=lambda r: (sk.sutun_indeksi(r["kutu"][0], sx),
                                 r["kutu"][1]))
    temiz = [r["kutu"] for r in kayitlar]
    gercek_degisim = (len(temiz) != len(eski_kutular)
                      or any(r["degisti"] for r in kayitlar)
                      or any(not _kutu_ayni(a, b)
                             for a, b in zip(temiz, eski_kutular)))
    with KILIT:
        DURUM["kutu_onbellek"][idx] = temiz
        DURUM.setdefault("kutu_meta", {})[idx] = [r["meta"] for r in kayitlar]
        onaylar = DURUM.setdefault("inceleme_onaylari", set())
        eski_sabitler = {"kutu:" + m.get("kararli_kimlik")
                         for m in eski_meta if m.get("kararli_kimlik")}
        kalan_sabitler = {"kutu:" + r["kimlik"] for r in kayitlar}
        onaylar.difference_update(eski_sabitler - kalan_sabitler)
        # Eski indeks onaylarını kararlı kimliğe taşı; yeniden sıralanmış indeks
        # yanlış kutuya onay vermesin.
        for r in kayitlar:
            if r["eski_i"] is not None and f"{idx}:{r['eski_i']}" in onaylar:
                onaylar.add("kutu:" + r["kimlik"])
            if r["degisti"]:
                onaylar.add("kutu:" + r["kimlik"])
        onaylar.difference_update({k for k in onaylar if k.startswith(f"{idx}:")})
        if gercek_degisim:
            DURUM.setdefault("sayfa_inceleme_kararlari", {}).pop(idx, None)
            DURUM.setdefault("sayfa_karar_yedekleri", {}).pop(idx, None)
            DURUM["duzenlendi"].add(idx)
            DURUM["ozet_kirli"] = True
    if gercek_degisim:
        _profil_duzeltmesini_yay(idx, temiz)
    return temiz


def _profil_duzeltmesini_yay(idx, kutular):
    """Elle düzeltilen sütun geometrisini aynı düzen ailesine uygula.

    Yalnız iki veya daha çok sütunlu ve beklenen sütun sayısı açıkça çıkarılan
    profillerde çalışır. Başka elle düzenlenmiş sayfaya dokunmaz; hedef adayın
    yalnız yatay sınırını öğrenilmiş banda sıkıştırır ve mevcut inceleme
    durumunu korur. Böylece profil düzeltmesi bankaya sessiz otomatik onay
    vermeden benzer sayfalara anında yansır.
    """
    analizler = DURUM.get("analizler") or []
    if idx >= len(analizler) or not kutular:
        return 0
    aile = analizler[idx].get("duzen_ailesi") or ""
    try:
        beklenen = int(aile.split("_", 1)[0])
    except (ValueError, IndexError):
        return 0
    if beklenen < 2:
        return 0
    G = DURUM["sayfalar"][idx].genislik
    gruplar = []
    for kutu in sorted(kutular, key=lambda k: (k[0] + k[2]) / 2):
        merkez = (kutu[0] + kutu[2]) / 2
        if gruplar and merkez - gruplar[-1][-1][0] <= G * 0.18:
            gruplar[-1].append((merkez, kutu))
        else:
            gruplar.append([(merkez, kutu)])
    if len(gruplar) != beklenen:
        return 0
    bantlar = [(min(k[0] for _, k in grup) / G,
                max(k[2] for _, k in grup) / G) for grup in gruplar]
    yayilan = 0
    with KILIT:
        profil = DURUM.get("profil")
        if isinstance(profil, dict):
            profil.setdefault("kullanici_duzeltmeleri", {})[aile] = {
                "kaynak_sayfa": idx + 1,
                "bantlar": [[round(a, 5), round(b, 5)] for a, b in bantlar],
            }
        for si, analiz in enumerate(analizler):
            if si == idx or si in DURUM["duzenlendi"] \
                    or analiz.get("duzen_ailesi") != aile:
                continue
            sayfa = DURUM["sayfalar"][si]
            hedef = []
            for kutu in DURUM["kutu_onbellek"].get(si, []):
                merkez = ((kutu[0] + kutu[2]) / 2) / sayfa.genislik
                a, b = min(bantlar, key=lambda ab: abs(merkez - (ab[0] + ab[1]) / 2))
                sol, sag = a * sayfa.genislik, b * sayfa.genislik
                x0 = max(sol, min(kutu[0], sag - 8))
                x1 = min(sag, max(kutu[2], x0 + 8))
                hedef.append((x0, kutu[1], x1, kutu[3]))
            if not hedef:
                continue
            DURUM["kutu_onbellek"][si] = hedef
            for meta in DURUM.get("kutu_meta", {}).get(si, []):
                meta["kanitlar"] = list(dict.fromkeys(
                    list(meta.get("kanitlar") or []) + ["kullanici_duzen_kumesi"]))
                meta["uyarilar"] = list(dict.fromkeys(
                    list(meta.get("uyarilar") or []) +
                    ["benzer_sayfaya_yayilim_onay_bekliyor"]))
                meta["risk_nedenleri"] = list(dict.fromkeys(
                    list(meta.get("risk_nedenleri") or []) +
                    ["benzer_sayfaya_yayilim_onay_bekliyor"]))
                meta["inceleme_durumu"] = "incele"
                kimlik = meta.get("kararli_kimlik")
                if kimlik:
                    DURUM.setdefault("inceleme_onaylari", set()).discard(
                        "kutu:" + kimlik)
            DURUM.setdefault("sayfa_inceleme_kararlari", {}).pop(si, None)
            yayilan += 1
        if yayilan:
            DURUM["ozet_kirli"] = True
    return yayilan


def kutulari_sifirla(idx):
    """Bir sayfayı otomatik tespite geri döndür (düzenlemeyi iptal)."""
    with KILIT:
        eski_meta = list(DURUM.setdefault("kutu_meta", {}).get(idx, []))
        DURUM["kutu_onbellek"].pop(idx, None)
        DURUM["kutu_meta"].pop(idx, None)
        onaylar = DURUM.setdefault("inceleme_onaylari", set())
        onaylar.difference_update({k for k in onaylar
                                   if k.startswith(f"{idx}:")})
        onaylar.difference_update({"kutu:" + m["kararli_kimlik"]
                                   for m in eski_meta
                                   if m.get("kararli_kimlik")})
        DURUM.setdefault("sayfa_inceleme_kararlari", {}).pop(idx, None)
        DURUM.setdefault("sayfa_karar_yedekleri", {}).pop(idx, None)
        DURUM["duzenlendi"].discard(idx)
        DURUM["ozet_kirli"] = True
    return _kutular(idx)


def _toplam_soru():
    return sum(len(_kutular(i)) for i in range(len(DURUM["sayfalar"])))


def _kalibrasyon_verisi(profil_dahil=True):
    """UI ve /kalibrasyon için küçük, kararlı kalite durum sözleşmesi."""
    analizler = DURUM.get("analizler") or []
    aktif = bool(DURUM.get("profil") or analizler)
    durumlar = {"otomatik": 0, "incele": 0, "reddedildi": 0,
                "onayli": 0, "bekleyen": 0}
    roller, turler = {}, {}
    duzen_guvenleri, duzen_yontemleri = [], set()
    dusuk_duzen = bolgesel_gecis = egik_sayfa = 0
    for si in range(len(DURUM.get("sayfalar") or [])):
        meta = _kutu_metalari(si)
        for ki, m in enumerate(meta):
            durum = _durum_normalize(m.get("inceleme_durumu"), m.get("guven", 0))
            durumlar[durum] += 1
            onayli = bool(m.get("onayli"))
            if onayli:
                durumlar["onayli"] += 1
            elif durum != "otomatik":
                durumlar["bekleyen"] += 1
            tur = m.get("soru_turu") or "bilinmiyor"
            turler[tur] = turler.get(tur, 0) + 1
    for a in analizler:
        rol = a.get("sayfa_rolu") or "bilinmiyor"
        roller[rol] = roller.get(rol, 0) + 1
        try:
            dg = max(0.0, min(1.0, float(a.get("duzen_guveni", 1.0))))
            duzen_guvenleri.append(dg)
            dusuk_duzen += dg < 0.62
        except (TypeError, ValueError):
            pass
        duzen_yontemleri.update(a.get("sutun_kanitlari") or [])
        uyarilar = set(a.get("uyarilar") or [])
        bolgesel_gecis += "bolgesel_sutun_gecisi" in uyarilar
        egik_sayfa += abs(float(a.get("egiklik_derece") or 0)) >= 1.0
    duzen_ozeti = {
        "ortalama": (round(sum(duzen_guvenleri) / len(duzen_guvenleri), 3)
                      if duzen_guvenleri else None),
        "en_dusuk": round(min(duzen_guvenleri), 3) if duzen_guvenleri else None,
        "dusuk_sayfa": dusuk_duzen, "bolgesel_gecis": bolgesel_gecis,
        "egik_sayfa": egik_sayfa, "yontemler": sorted(duzen_yontemleri),
    }
    sayfa_kayitlari = [_sayfa_inceleme_kaydi(si)
                       for si in range(len(DURUM.get("sayfalar") or []))]
    bekleyen_sayfa = sum(bool(k["bekliyor"]) for k in sayfa_kayitlari)
    sonuc = {"aktif": aktif,
             "inceleme_aktif": bool(DURUM.get("sayfalar")),
             "kalite_modu": _kalite_modu(), "algoritma_surumu":
             (DURUM.get("profil") or {}).get("algoritma_surumu"),
             "durumlar": durumlar, "sayfa_rolleri": roller,
             "soru_turleri": turler, "duzen": duzen_ozeti,
             "bekleyen_sayfa": bekleyen_sayfa,
             "hata": DURUM.get("kalibrasyon_hatasi")}
    if profil_dahil:
        sonuc["profil"] = DURUM.get("profil")
    return sonuc


def _guven_sayisi(deger):
    try:
        return max(0.0, min(1.0, float(deger)))
    except (TypeError, ValueError):
        return None


def _risk_norm(metin):
    return (str(metin or "").strip().lower().replace("ı", "i")
            .replace("ş", "s").replace("ğ", "g").replace("ü", "u")
            .replace("ö", "o").replace("ç", "c").replace(" ", "_"))


def _sayfa_inceleme_kaydi(sayfa):
    """Tek sayfanın kutudan bağımsız risk ve inceleme durumunu üretir."""
    analizler = DURUM.get("analizler") or []
    analiz = dict(analizler[sayfa]) if sayfa < len(analizler) else {}
    kutular = _kutular(sayfa)
    metalar = _kutu_metalari(sayfa)
    karar = (DURUM.get("sayfa_inceleme_kararlari") or {}).get(sayfa)
    riskler, kanitlar, uyarilar = [], [], []

    def risk_ekle(kod):
        if kod and kod not in riskler:
            riskler.append(kod)

    kanitlar.extend(_metin_listesi(analiz.get("kanitlar")))
    kanitlar.extend(_metin_listesi(analiz.get("sutun_kanitlari")))
    kanitlar.extend(_metin_listesi(analiz.get("kaynak_yontemler")))
    uyarilar.extend(_metin_listesi(analiz.get("uyarilar")))
    uyarilar.extend(_metin_listesi(analiz.get("risk_nedenleri")))
    for alan in ("hata", "analiz_hatasi", "pipeline_hatasi", "ocr_hatasi",
                 "model_hatasi", "error"):
        if analiz.get(alan):
            risk_ekle("analiz_veya_pipeline_hatasi")
            uyarilar.append(f"{alan}: {analiz[alan]}")
    pipeline_hatalari = _metin_listesi(analiz.get("pipeline_hatalari"))
    if pipeline_hatalari:
        risk_ekle("analiz_veya_pipeline_hatasi")
        uyarilar.extend(pipeline_hatalari)
    if DURUM.get("kalibrasyon_hatasi"):
        risk_ekle("kalibrasyon_hatasi")
        uyarilar.append(str(DURUM["kalibrasyon_hatasi"]))
    if not analiz and _kalite_modu() == "strict":
        risk_ekle("analiz_sonucu_yok")
    cekirdek_bekliyor = (
        bool(analiz.get("inceleme_gerekli"))
        or str(analiz.get("onay_durumu") or "").lower()
        in ("bekliyor", "incele", "review"))

    rol = analiz.get("sayfa_rolu") or analiz.get("rol") or "bilinmiyor"
    rol_guveni = _guven_sayisi(analiz.get("rol_guveni"))
    if rol_guveni is not None and rol_guveni < ROL_GUVEN_ESIGI:
        risk_ekle("dusuk_rol_guveni")
    if rol in ("bilinmiyor", "unknown", "ood"):
        risk_ekle("bilinmeyen_sayfa_rolu")
    duzen_guveni = _guven_sayisi(analiz.get("duzen_guveni"))
    if duzen_guveni is not None and duzen_guveni < DUZEN_GUVEN_ESIGI:
        risk_ekle("dusuk_duzen_guveni")
    try:
        egiklik = abs(float(analiz.get("egiklik_derece") or 0.0))
    except (TypeError, ValueError):
        egiklik = 0.0
    if egiklik >= EGIKLIK_ESIGI:
        risk_ekle("egik_kaynak")
    if (analiz.get("bolgesel_gecis") or analiz.get("duzen_gecisi")
            or len(analiz.get("duzen_bolgeleri") or []) > 1):
        risk_ekle("bolgesel_duzen_gecisi")
    if (analiz.get("dagilim_disi") or analiz.get("ood")
            or analiz.get("yeni_duzen")):
        risk_ekle("dagilim_disi_duzen")

    # Çekirdeğin açık risk kodları arayüzde kaybolmamalı. Düşük aday güveni
    # kutu durumundan türetilir; kullanıcı o kutuyu onayladığında bağımsız bir
    # sayfa riski gibi yapışıp kalmamalıdır.
    aday_turevli_cekirdek = {"dusuk_aday_guveni"}
    cekirdek_riskleri = {
        _risk_norm(kod)
        for kod in _metin_listesi(analiz.get("risk_nedenleri"))
        if _risk_norm(kod)
    }
    for kod in sorted(cekirdek_riskleri - aday_turevli_cekirdek):
        risk_ekle(kod)

    # ``inceleme_gerekli`` ve ``reddedilen_aday_var`` aday durumundan türetilir;
    # kutu/sayfa onayı bunları çözer. Diğer risk uyarıları sayfa kararı ister.
    turetilen = {
        "inceleme_gerekli", "reddedilen_aday_var", "dusuk_aday_guveni"}
    for uyari in uyarilar:
        norm = _risk_norm(uyari)
        if norm in turetilen:
            continue
        if any(parca in norm for parca in (
                "hata", "error", "dusuk_", "egik", "perspektif",
                "bolgesel", "gecis", "ood", "dagilim_disi", "yeni_duzen",
                "bilinmeyen_duzen", "aday_yok", "ocr_okunamadi")):
            risk_ekle(norm)

    soru_sinyali = (rol in ("soru", "karma") or analiz.get("soru_sinyali")
                    or any("aday_yok" in _risk_norm(u) for u in uyarilar))
    if not kutular and soru_sinyali:
        risk_ekle("soru_sinyali_var_aday_yok")

    bekleyen_aday = []
    for i, meta in enumerate(metalar):
        durum = _durum_normalize(meta.get("inceleme_durumu"),
                                  meta.get("guven", 0))
        if durum != "otomatik" and not meta.get("onayli"):
            bekleyen_aday.append(i)
            risk_ekle("aday_incelemesi")
        kanitlar.extend(_metin_listesi(meta.get("kanitlar")))
        uyarilar.extend(_metin_listesi(meta.get("uyarilar")))

    # Eski/haricî bir çekirdek "bekliyor" deyip hiçbir sebep vermediyse
    # güvenli tarafta kal. Açık aday-türevli sebep varsa ve tüm adaylar
    # onaylandıysa bu genel bayrak yeniden eklenmez.
    if (cekirdek_bekliyor and not cekirdek_riskleri
            and not bekleyen_aday):
        risk_ekle("cekirdek_sayfa_incelemesi")

    riskler = list(dict.fromkeys(riskler))
    kanitlar = list(dict.fromkeys(kanitlar))
    uyarilar = list(dict.fromkeys(uyarilar))
    cozuldu = karar in ("onayli", "soru_yok")
    return {"anahtar": analiz.get("karar_kimligi") or f"sayfa:{sayfa}",
            "sayfa": sayfa,
            "sayfa_no": sayfa + 1, "sayfa_rolu": rol,
            "rol_guveni": rol_guveni, "duzen_guveni": duzen_guveni,
            "egiklik_derece": egiklik, "aday_sayisi": len(kutular),
            "bekleyen_adaylar": bekleyen_aday,
            "risk_nedenleri": riskler, "kanitlar": kanitlar,
            "uyarilar": uyarilar, "karar": karar or "bekliyor",
            "onayli": karar == "onayli", "soru_yok": karar == "soru_yok",
            "bekliyor": bool(riskler) and not cozuldu}


def _inceleme_listesi(bekleyen_only=True):
    """Sayfa tabanlı kuyruk + geriye uyumlu aday ayrıntılarını döndür."""
    kayitlar = []
    for si in range(len(DURUM.get("sayfalar") or [])):
        kutular = _kutular(si)
        for ki, (kutu, meta) in enumerate(zip(kutular, _kutu_metalari(si))):
            durum = _durum_normalize(meta.get("inceleme_durumu"), meta.get("guven", 0))
            if durum == "otomatik":
                continue
            anahtar = "kutu:" + meta["kararli_kimlik"]
            onayli = bool(meta.get("onayli"))
            if bekleyen_only and onayli:
                continue
            kayit = dict(meta)
            kayit.update({"anahtar": anahtar, "sayfa": si, "kutu_no": ki,
                          "kutu": list(kutu), "onayli": onayli})
            kayitlar.append(kayit)
    tum_sayfa = [_sayfa_inceleme_kaydi(si)
                 for si in range(len(DURUM.get("sayfalar") or []))]
    sayfa_kayitlari = [k for k in tum_sayfa
                       if k["risk_nedenleri"] and
                       (not bekleyen_only or k["bekliyor"])]
    sayfalar = [k["sayfa"] for k in sayfa_kayitlari]
    bekleyen_aday = sum(1 for si in range(len(DURUM.get("sayfalar") or []))
                        for m in _kutu_metalari(si)
                        if _durum_normalize(m.get("inceleme_durumu"),
                                            m.get("guven", 0)) != "otomatik"
                        and not m.get("onayli"))
    return {"aktif": bool(DURUM.get("sayfalar")), "adaylar": kayitlar,
            "sayfa_kayitlari": sayfa_kayitlari, "sayfalar": sayfalar,
            "adet": len(kayitlar), "sayfa_adet": len(sayfa_kayitlari),
            "bekleyen": bekleyen_aday,
            "bekleyen_sayfa": sum(k["bekliyor"] for k in tum_sayfa)}


def _inceleme_onayla(sayfa, kutu_no, onay=True):
    sayfa, kutu_no = int(sayfa), int(kutu_no)
    if sayfa < 0 or sayfa >= len(DURUM.get("sayfalar") or []):
        raise ValueError("geçersiz sayfa")
    if kutu_no < 0 or kutu_no >= len(_kutular(sayfa)):
        raise ValueError("geçersiz kutu")
    meta = _kutu_metalari(sayfa)[kutu_no]
    if onay and meta.get("inceleme_durumu") == "reddedildi":
        raise ValueError("reddedilen adayı bankaya almak için kutuyu elle düzeltin")
    anahtar = "kutu:" + meta["kararli_kimlik"]
    eski_anahtar = f"{sayfa}:{kutu_no}"
    with KILIT:
        onaylar = DURUM.setdefault("inceleme_onaylari", set())
        if onay:
            onaylar.add(anahtar)
            onaylar.discard(eski_anahtar)
        else:
            onaylar.discard(anahtar)
            onaylar.discard(eski_anahtar)
    return {"ok": True, "anahtar": anahtar, "onayli": bool(onay),
            "kalibrasyon": _kalibrasyon_verisi(False)}


def _sayfa_inceleme_karari(sayfa, karar):
    """Sayfayı doğru/no-question olarak sonuçlandır veya kararı geri al."""
    sayfa = int(sayfa)
    if sayfa < 0 or sayfa >= len(DURUM.get("sayfalar") or []):
        raise ValueError("geçersiz sayfa")
    karar = str(karar or "").strip().lower()
    if karar not in ("onayli", "soru_yok", "bekliyor"):
        raise ValueError("geçersiz sayfa kararı")
    # Soru-yok yedeği ve sayfa-onayı, kullanıcının ekranda gördüğü kesin planı
    # temel alsın; önbellek henüz tembel doldurulmadıysa burada doldur.
    _kutular(sayfa)
    _kutu_metalari(sayfa)
    with KILIT:
        kararlar = DURUM.setdefault("sayfa_inceleme_kararlari", {})
        yedekler = DURUM.setdefault("sayfa_karar_yedekleri", {})
        onceki = kararlar.get(sayfa)
        if onceki == "soru_yok" and karar != "soru_yok":
            yedek = yedekler.pop(sayfa, None)
            if yedek is not None:
                DURUM["kutu_onbellek"][sayfa] = list(yedek["kutular"])
                DURUM.setdefault("kutu_meta", {})[sayfa] = [
                    dict(m) for m in yedek["metalar"]]
                DURUM.setdefault("inceleme_onaylari", set()).update(
                    yedek["onaylar"])
                if yedek["duzenlendi"]:
                    DURUM["duzenlendi"].add(sayfa)
                else:
                    DURUM["duzenlendi"].discard(sayfa)
                DURUM["ozet_kirli"] = True
        if karar == "soru_yok" and onceki != "soru_yok":
            kutular = list(DURUM["kutu_onbellek"].get(sayfa, []))
            metalar = [dict(m) for m in
                       DURUM.setdefault("kutu_meta", {}).get(sayfa, [])]
            kimlikler = {"kutu:" + m["kararli_kimlik"] for m in metalar
                         if m.get("kararli_kimlik")}
            onaylar = DURUM.setdefault("inceleme_onaylari", set())
            sayfa_onaylari = {a for a in onaylar if a in kimlikler
                              or a.startswith(f"{sayfa}:")}
            yedekler[sayfa] = {"kutular": kutular, "metalar": metalar,
                               "onaylar": sayfa_onaylari,
                               "duzenlendi": sayfa in DURUM["duzenlendi"]}
            onaylar.difference_update(sayfa_onaylari)
            DURUM["kutu_onbellek"][sayfa] = []
            DURUM["kutu_meta"][sayfa] = []
            DURUM["duzenlendi"].add(sayfa)
            DURUM["ozet_kirli"] = True
        if karar == "bekliyor":
            kararlar.pop(sayfa, None)
        else:
            kararlar[sayfa] = karar
        if onceki != (None if karar == "bekliyor" else karar):
            DURUM["ozet_kirli"] = True
    return {"ok": True, "sayfa": sayfa, "karar": karar,
            "inceleme": _sayfa_inceleme_kaydi(sayfa),
            "kalibrasyon": _kalibrasyon_verisi(False)}


class KaliteKapisiHatasi(RuntimeError):
    def __init__(self, rapor):
        self.rapor = dict(rapor)
        super().__init__(self.rapor.get("hata") or "katı kalite kapısı")


def _kalite_kapisi_raporu(secim_kimlikler=None):
    """ZIP/sınav/export/banka için tek, sayfa tabanlı katı kapı.

    ``secim_kimlikler`` arayüz uyumluluğu için alınır; strict modda sıfır
    adaylı riskli sayfanın seçimle gizlenememesi için kapı belge genelidir.
    """
    del secim_kimlikler
    mod = _kalite_modu()
    if mod != "strict":
        return {"ok": True, "kalite_modu": mod, "bekleyen_sayfa": 0,
                "sayfalar": []}
    inceleme = _inceleme_listesi(bekleyen_only=True)
    sayfalar = [s + 1 for s in inceleme["sayfalar"]]
    if not sayfalar:
        return {"ok": True, "kalite_modu": mod, "bekleyen_sayfa": 0,
                "sayfalar": []}
    liste = ", ".join(str(s) for s in sayfalar[:12])
    if len(sayfalar) > 12:
        liste += ", …"
    return {"ok": False, "kalite_modu": mod,
            "inceleme_gerekli": True, "bekleyen_sayfa": len(sayfalar),
            "sayfalar": sayfalar,
            "hata": (f"Katı kalite kapısı: {len(sayfalar)} sayfa inceleme "
                     f"bekliyor (sayfa {liste}). Sayfayı doğru olarak onaylayın, "
                     "soru olmadığını işaretleyin veya kutuları düzeltin.")}


def _kalite_kapisi_dogrula(secim_kimlikler=None):
    rapor = _kalite_kapisi_raporu(secim_kimlikler)
    if not rapor["ok"]:
        raise KaliteKapisiHatasi(rapor)
    return rapor


# --------------------------------------------------------- test özeti / seçim

def _kutu_atama():
    """Düzenlenen veya bütünüyle onaylanan sayfanın görünür kutu planı.

    Çekirdek reddedilen adayları normal plandan çıkarır. Kullanıcının "sayfa
    doğru" kararı ise ekranda gördüğü planın tamamını açıkça kabul eder; bu
    nedenle onaylanan sayfa da ``kutu_atama`` ile birebir sabitlenir.
    """
    kararlar = DURUM.get("sayfa_inceleme_kararlari") or {}
    sayfalar = set(DURUM["duzenlendi"]) | {
        i for i, karar in kararlar.items() if karar in ("onayli", "soru_yok")}
    return {i: DURUM["kutu_onbellek"][i] for i in sayfalar
            if i in DURUM["kutu_onbellek"]} or None


def _ozet_hesapla():
    """test_ozeti'ni çağırıp web için kimlik/etiket ile zenginleştirir.
    Dönüş: {testler, kutu_kimlik ({"si:ki": kimlik}), kimlik_parca
    ({kimlik: [[si,ki],...]}), parca_meta, toplam, test_sayisi, cevapli}."""
    testler, parca_meta = sk.test_ozeti(
        DURUM["sayfalar"], DURUM["fmt"], kutu_atama=_kutu_atama(),
        cevaplar=DURUM["cevaplar"])

    def _etiket(pm):
        if pm["test_no"] is not None and pm["soru_no"] is not None:
            return f"T{pm['test_no']} S{pm['soru_no']}"
        if pm["soru_no"] is not None:
            return f"S{pm['soru_no']}"
        return "?"

    kutu_kimlik = {}
    kimlik_parca = {}
    kimlik_liste = []
    el_etiket = DURUM.get("etiketler") or {}
    cevap_duzelt = DURUM.get("cevap_duzeltmeler") or {}
    sozluk = DURUM.get("konu_sozluk") or []
    for kml, pm in zip(sk.soru_kimlikleri(parca_meta), parca_meta):
        pm["_kimlik"] = kml
        if kml in cevap_duzelt:      # elle düzeltme anahtar eşlemesini ezer
            pm["cevap"] = cevap_duzelt[kml] or None
            pm["_cevap_elle"] = True
        pm["_etiket"] = _etiket(pm)
        # düz metin (parca_meta['metin'] satır listesi) → arama + konu
        pm["_metin"] = " ".join(pm.get("metin") or [])
        pm["_konu"] = (sk.konu_etiketle(pm["_metin"], sozluk)[0]
                       if sozluk else None)
        pm["_el_etiket"] = el_etiket.get(kml, {})
        kimlik_liste.append(kml)
        kimlik_parca[kml] = [list(p) for p in pm["parcalar_idx"]]
        for si, ki in pm["parcalar_idx"]:
            if ki is not None:
                kutu_kimlik[f"{si}:{ki}"] = kml

    # testleri kimlik/etiketli sorularla döndür
    testler_web = []
    for t in testler:
        sorular = []
        for pm in parca_meta:
            if pm["test_sira"] == t["test_sira"]:
                sorular.append({
                    "kimlik": pm["_kimlik"], "etiket": pm["_etiket"],
                    "soru_no": pm["soru_no"], "cevap": pm.get("cevap"),
                    "metin": pm["_metin"][:160], "konu": pm.get("_konu"),
                    "el_etiket": pm.get("_el_etiket") or {}})
        testler_web.append({
            "test_sira": t["test_sira"], "test_no": t["test_no"],
            "baslik": t["baslik"], "soru_bas": t["soru_bas"],
            "soru_son": t["soru_son"], "adet": t["adet"], "sorular": sorular})
    cevapli = any(pm.get("cevap") for pm in parca_meta)
    cozumlu = any(pm.get("sayfa_rolu") == "çözüm" for pm in parca_meta)
    return {"testler": testler_web, "kutu_kimlik": kutu_kimlik,
            "kimlik_parca": kimlik_parca, "kimlik_liste": kimlik_liste,
            "parca_meta": parca_meta, "toplam": len(parca_meta),
            "test_sayisi": len(testler), "cevapli": cevapli,
            "cozumlu": cozumlu}


def _ozet_al():
    """Tembel önbellek: kirliyse yeniden hesaplar (KİLİT altında çağrılmalı)."""
    if DURUM["ozet_kirli"] or DURUM["ozet"] is None:
        DURUM["ozet"] = _ozet_hesapla()
        DURUM["ozet_kirli"] = False
    return DURUM["ozet"]


def _kimlikten_secim(kimlikler):
    """Kimlik listesi → {(sayfa_idx, kutu_idx), ...} kesim seçimi.
    None → tümü; [] → hiçbiri. Bilinmeyen kimlikler sessizce atlanır,
    fakat hiçbir zaman yanlışlıkla "tümü"ne dönüşmez."""
    if kimlikler is None:
        return None
    with KILIT:
        oz = _ozet_al()
    kume = set()
    for kml in kimlikler:
        for si, ki in oz["kimlik_parca"].get(kml, []):
            if ki is not None:
                kume.add((si, ki))
    return kume


# --------------------------------------------------------- iş mantığı

def _ilerleme_yaz(asama, yapilan, toplam, mesaj):
    with KILIT:
        DURUM["islem"] = {"asama": asama, "yapilan": yapilan,
                          "toplam": toplam, "mesaj": mesaj}


def belge_yukle(girdiler, dpi):
    sk.belge_kapat(DURUM["acik"])  # eski açık PDF'leri kapat
    DURUM.update({"girdiler": girdiler, "sayfalar": [], "acik": [],
                  "sutun_xler": None, "kutu_onbellek": {},
                  "duzenlendi": set(), "ozet": None, "ozet_kirli": True,
                  "cevaplar": None, "etiketler": {},
                  "cevap_duzeltmeler": {},
                  "profil": None, "analizler": [], "kutu_meta": {},
                  "inceleme_onaylari": set(), "kalibrasyon_hatasi": None,
                  "sayfa_inceleme_kararlari": {},
                  "sayfa_karar_yedekleri": {},
                  "kalite_modu": _kalite_modu(),
                  "konu_sozluk": sk.konu_sozlugu_oku(KONU_CSV)})

    def _il(i, n):
        _ilerleme_yaz("yukleme", i, n, f"Sayfa {i}/{n} okunuyor…")

    _ilerleme_yaz("yukleme", 0, 1, "Belge açılıyor…")
    try:
        sayfalar, acik, fmt, sx = sk.belge_hazirla(girdiler, dpi, ilerleme=_il)
        DURUM.update({"sayfalar": sayfalar, "acik": acik,
                      "sutun_xler": sx, "fmt": fmt})
        _ilerleme_yaz("kalibrasyon", 0, max(1, len(sayfalar)),
                       "Belge düzeni ve sayfa türleri kalibre ediliyor…")
        v2_aktif = _v2_analiz_et()
        _ilerleme_yaz("kalibrasyon", max(1, len(sayfalar)),
                       max(1, len(sayfalar)),
                       "Kalibrasyon tamamlandı." if v2_aktif
                       else "Eski tespit motoruyla devam ediliyor.")
        _ilerleme_yaz("tespit", 0, len(sayfalar),
                       "Soru bölgeleri ve test yapısı tespit ediliyor…")
        DURUM["cevaplar"] = sk.cevap_anahtari_bul(sayfalar)
        with KILIT:
            oz = _ozet_al()
        sayfa_soru = []
        for i in range(len(sayfalar)):
            sayfa_soru.append(len(_kutular(i)))
            _ilerleme_yaz("tespit", i + 1, len(sayfalar),
                           f"Soru bölgeleri denetleniyor… {i + 1}/{len(sayfalar)}")
        toplam = sum(sayfa_soru)
        raster = sum(1 for s in sayfalar if s.raster)
        mod = ("taranmış (OCR)" if raster == len(sayfalar)
               else "metin katmanı" if raster == 0 else "karışık")
        # Büyük TARANMIŞ belge uyarısı: her sayfa yüksek çözünürlükte belleğe render
        # edilir (~11 MB/sayfa) → yüzlerce sayfa yüksek bellek/süre. Kullanıcıyı uyar.
        uyarilar = []
        if raster > TARANMIS_UYARI_ESIGI:
            uyarilar.append(
                f"{raster} taranmış sayfa — OCR ve bellek yoğun olabilir; "
                f"gerekirse belgeyi bölmeyi düşünün.")
        ocr_sorunlari = sk.ocr_hatalari(sayfalar)
        if ocr_sorunlari:
            sayfa_liste = ", ".join(str(i) for i, _ in ocr_sorunlari[:8])
            ek = "…" if len(ocr_sorunlari) > 8 else ""
            uyarilar.append(
                f"{len(ocr_sorunlari)} sayfa OCR ile okunamadı "
                f"(sayfa {sayfa_liste}{ek}); diğer sayfalar işlendi.")
        if DURUM.get("kalibrasyon_hatasi"):
            uyarilar.append(
                "V2 kalibrasyonu tamamlanamadı; eski tespit motoru kullanıldı.")
        return {"sayfa": len(sayfalar), "sutun": len(sx), "mod": mod,
                "format": fmt, "toplam": toplam,
                "test_sayisi": oz["test_sayisi"], "cevapli": oz["cevapli"],
                "uyari": " ".join(uyarilar) or None,
                "sayfa_soru": sayfa_soru,
                "kalibrasyon": _kalibrasyon_verisi(False)}
    finally:
        with KILIT:
            DURUM["islem"] = None


def _kes_ortak(secim_kimlikler, numara_temizle=False, rastgele=None,
               tohum=None, cevap_bandi=False, cozum_ilistir=False):
    """kirpma_seti çağrısı için ortak hazırlık. Dönüş: (kirpmalar, sorular).
    cevap_bandi/cozum_ilistir yalnız ZIP kesim yolunda True olmalı — banka
    dedup'ı ve sınav PDF'i bantsız/iliştirmesiz görüntü ister."""
    _kalite_kapisi_dogrula(secim_kimlikler)
    secim_kutular = _kimlikten_secim(secim_kimlikler)

    def _il(i, n):
        _ilerleme_yaz("kesim", i, n, f"Soru {i}/{n} kesiliyor…")

    try:
        kirpmalar, sorular, _uyar = sk.kirpma_seti(
            DURUM["sayfalar"], DURUM["fmt"], girdiler=DURUM["girdiler"],
            kutu_atama=_kutu_atama(), secim_kutular=secim_kutular,
            cevaplar=DURUM["cevaplar"], numara_temizle=numara_temizle,
            ilerleme=_il, rastgele=rastgele, tohum=tohum,
            konu_sozluk=DURUM.get("konu_sozluk") or None,
            etiketler=DURUM.get("etiketler") or None,
            cevap_duzeltmeler=DURUM.get("cevap_duzeltmeler") or None)
        # ``kutu_atama`` çekirdekte geometriyi elle-belirlendi/1.0 olarak
        # işaretler. Web'deki kalibre güven ve kanıtları geri bindir ki tek bir
        # düzenleme, ZIP/banka metasında diğer kutuları sahte %100 yapmasın.
        for soru in sorular:
            kaynak = soru.get("kaynak_kutu")
            if not isinstance(kaynak, (list, tuple)) or len(kaynak) < 2:
                continue
            try:
                si, ki = int(kaynak[0]), int(kaynak[1])
                meta = _kutu_metalari(si)[ki]
            except (TypeError, ValueError, IndexError):
                continue
            kalibre = meta.get("kalibre_guven", meta.get("guven", 0.0))
            soru.update({
                "guven": kalibre, "kalibre_guven": kalibre,
                "inceleme_durumu": meta.get("inceleme_durumu", "incele"),
                "onay_durumu": ("onaylandi" if meta.get("onayli") else
                                 meta.get("onay_durumu", "bekliyor")),
                "karar_kimligi": meta.get("karar_kimligi") or
                                  meta.get("kararli_kimlik"),
                "tespit_kanitlari": list(meta.get("kanitlar") or []),
                "tespit_uyarilari": list(meta.get("uyarilar") or []),
                "risk_nedenleri": list(meta.get("risk_nedenleri") or []),
                "kaynak_yontemler": list(meta.get("kaynak_yontemler") or [])})
    finally:
        with KILIT:
            DURUM["islem"] = None
    # Sıra önemli: önce çözüm iliştirme (görüntüler birleşir), sonra cevap
    # bandı (bant en altta kalsın).
    if cozum_ilistir and kirpmalar:
        kirpmalar, sorular, _cu = sk.cozumleri_ilistir(kirpmalar, sorular)
    if cevap_bandi and kirpmalar:
        kirpmalar = [sk.cevap_bandi_ekle(im, so["cevap"])
                     if so.get("cevap") else im
                     for im, so in zip(kirpmalar, sorular)]
    return kirpmalar, sorular


def kes_ve_kaydet(yol, klasor_de, secim=None, numara_gizle=True,
                  cevap_bandi=False, cozum_ilistir=False):
    # numara_gizle: kesilen görüntüde soru numarasını beyazlat (yalnız etikette/
    # dosya adında/sorular.json'da kalır). Kullanıcı tercihi: varsayılan açık.
    kirpmalar, sorular = _kes_ortak(secim, numara_temizle=numara_gizle,
                                    cevap_bandi=cevap_bandi,
                                    cozum_ilistir=cozum_ilistir)
    if not kirpmalar:
        return 0, 0
    sk.zip_yaz(kirpmalar, yol, klasor_de, sorular=sorular)
    tst = len({so["test_sira"] for so in sorular if so["test_sira"]})
    gecmis_ekle("zip", yol, len(kirpmalar), tst, DURUM["girdiler"])
    return len(kirpmalar), tst


def _secim_coz(metin):
    """Aralık metnini kimlik listesine çevirir (canlı geri bildirim).
    Dönüş: {kimlikler, adet, eslesmeyen} | {hata}."""
    try:
        kurallar = sk.secim_ayristir(metin)
    except ValueError as e:
        return {"hata": str(e)}
    with KILIT:
        oz = _ozet_al()
    indeksler, uyarilar = sk.secim_uygula(oz["parca_meta"], kurallar,
                                          _test_ozeti_ham())
    kimlikler = [oz["parca_meta"][j]["_kimlik"] for j in sorted(indeksler)]
    return {"kimlikler": kimlikler, "adet": len(kimlikler),
            "eslesmeyen": uyarilar}


def disa_aktar_kaydet(tur, secim_kimlikler):
    """Seçili (ya da tüm) soruları CSV/MD/HTML olarak diske yazar.
    CSV/MD kesimsiz (özetten hızlı); HTML görüntüleri gömer (kesim yapar).
    Dönüş: (yol, adet)."""
    _kalite_kapisi_dogrula(secim_kimlikler)
    with KILIT:
        oz = _ozet_al()
    sec = None if secim_kimlikler is None else set(secim_kimlikler)
    secili_pm = [pm for pm in oz["parca_meta"]
                 if sec is None or pm["_kimlik"] in sec]
    if not secili_pm:
        return None, 0
    klasor = CIKTI_DIZIN                    # tarayıcı indirmesi: çıktı dizinine yaz
    os.makedirs(klasor, exist_ok=True)
    temel = (os.path.splitext(os.path.basename(DURUM["girdiler"][0]))[0]
             if DURUM["girdiler"] else "soru_bankasi")

    if tur in ("docx", "pdf-metin"):
        # editlenebilir metin + korunmuş şekil → seçiliyi kes + OCR
        import belge_disa
        kirpmalar, sorular = _kes_ortak(secim_kimlikler)
        uz = "docx" if tur == "docx" else "pdf"
        yol = os.path.join(klasor, f"{temel}_soru.{uz}")
        if tur == "docx":
            belge_disa.docx_uret(sorular, kirpmalar, yol)
        else:
            belge_disa.pdf_metin_uret(sorular, kirpmalar, yol)
        return yol, len(sorular)
    if tur == "html":
        # görüntü gömülü tek dosya → seçiliyi kes
        kirpmalar, sorular = _kes_ortak(secim_kimlikler)
        metin, uz = sk.disa_aktar(sorular, "html", kirpmalar=kirpmalar)
    else:
        sorular = [{"test_no": pm["test_no"], "soru_no": pm["soru_no"],
                    "sayfa": pm["sayfa"], "cevap": pm.get("cevap"),
                    "kaynak": (os.path.basename(DURUM["girdiler"][0])
                               if DURUM["girdiler"] else None),
                    "konu": pm.get("_konu"),
                    "etiketler": pm.get("_el_etiket") or {},
                    "metin": pm.get("_metin", "")} for pm in secili_pm]
        metin, uz = sk.disa_aktar(sorular, tur)
    yol = os.path.join(klasor, f"{temel}_soru_bankasi.{uz}")
    with open(yol, "w", encoding="utf-8") as f:
        f.write(metin)
    return yol, len(secili_pm)


def _ara(metin):
    """Soru metni + konu + etiket üzerinde Türkçe-güvenli anahtar kelime
    araması. Dönüş: {kimlikler, adet}. Boş sorgu → tümü."""
    with KILIT:
        oz = _ozet_al()
    q = sk._tr_normalize(metin.strip())
    if not q:
        return {"kimlikler": oz["kimlik_liste"], "adet": len(oz["kimlik_liste"])}
    kelimeler = q.split()
    bulunan = []
    for pm in oz["parca_meta"]:
        havuz = sk._tr_normalize(
            " ".join([pm.get("_metin", ""), pm.get("_konu") or "",
                      " ".join(f"{k} {v}" for k, v
                               in (pm.get("_el_etiket") or {}).items())]))
        if all(k in havuz for k in kelimeler):
            bulunan.append(pm["_kimlik"])
    return {"kimlikler": bulunan, "adet": len(bulunan)}


def _etiket_ata(kimlikler, anahtar, deger):
    """Seçili sorulara elle etiket (anahtar:değer) atar. Boş değer → siler.
    Oturum içi DURUM'da tutulur; kesim/sınavda sorular.json'a yazılır."""
    anahtar = (anahtar or "").strip()
    if not anahtar or not kimlikler:
        return {"hata": "etiket anahtarı ve en az bir soru gerekli"}
    et = DURUM["etiketler"]
    for kml in kimlikler:
        d = et.setdefault(kml, {})
        if deger:
            d[anahtar] = deger
        else:
            d.pop(anahtar, None)
            if not d:
                et.pop(kml, None)
    with KILIT:
        DURUM["ozet_kirli"] = True
    return {"ok": True, "etiketlenen": len(kimlikler)}


def _cevap_duzelt(kimlikler, cevap, geri_al=False):
    """Seçili soruların cevabını elle düzeltir. cevap 'A'..'E' | ''
    ('' = cevabı sil; anahtar eşlemesi de bastırılır). geri_al=True →
    düzeltme kaldırılır, otomatik eşleme geri gelir. Oturum içi tutulur;
    özet listesine ve kesimde sorular.json'a yansır."""
    if not kimlikler:
        return {"hata": "en az bir soru gerekli"}
    cevap = (cevap or "").strip().upper()
    if cevap and cevap not in ("A", "B", "C", "D", "E"):
        return {"hata": "cevap A-E ya da boş olmalı"}
    cd = DURUM["cevap_duzeltmeler"]
    for kml in kimlikler:
        if geri_al:
            cd.pop(kml, None)
        else:
            cd[kml] = cevap
    with KILIT:
        DURUM["ozet_kirli"] = True
    return {"ok": True, "duzeltilen": len(kimlikler)}


def _test_ozeti_ham():
    """secim_uygula'nın beklediği ham test özeti (test_ozeti çıktısındaki
    testler kısmı). _ozet_al testleri web biçiminde tutuyor; ham alanlar
    (soru_bas/soru_son/adet) orada da mevcut."""
    with KILIT:
        oz = _ozet_al()
    return [{"test_sira": t["test_sira"], "test_no": t["test_no"],
             "baslik": t["baslik"], "soru_bas": t["soru_bas"],
             "soru_son": t["soru_son"], "adet": t["adet"]}
            for t in oz["testler"]]


def sinav_pdf_kaydet(yol, ayarlar, secim=None, optik=False):
    import sinav_pdf
    kirpmalar, sorular = _kes_ortak(
        secim, numara_temizle=True, rastgele=ayarlar.get("rastgele"),
        tohum=ayarlar.get("tohum"))
    if not kirpmalar:
        return 0, None
    if not ayarlar.get("baslik"):
        ayarlar["baslik"] = (os.path.splitext(
            os.path.basename(DURUM["girdiler"][0]))[0]
            if DURUM["girdiler"] else "Sınav")
    sonuc = sinav_pdf.sinav_pdf_uret(kirpmalar, sorular, ayarlar, yol)
    if optik:
        sonuc["optik"] = _optik_esi_uret(sorular, ayarlar, yol)
        if sonuc["optik"] and "hata" not in sonuc["optik"]:
            sonuc["yollar"] = list(sonuc["yollar"]) + \
                [sonuc["optik"]["pdf"]]
    tst = len({so["test_sira"] for so in sorular if so["test_sira"]})
    gecmis_ekle("sinav_pdf", yol, len(kirpmalar), tst, DURUM["girdiler"])
    return len(kirpmalar), sonuc


def _optik_esi_uret(meta, ayarlar, sinav_yolu):
    """Sınavın optik cevap kâğıdı eşini üretir (optik_koprusu).

    Anahtar + kazanım + kitapçık sırası optik veritabanına yazılır; hata
    sınav üretimini asla bozmaz (None döner, kullanıcıya mesajla iletilir)."""
    try:
        import optik_koprusu
        kok, _ = os.path.splitext(sinav_yolu)
        return optik_koprusu.sinavdan_optik(meta, ayarlar,
                                            kok + "_optik.pdf")
    except Exception as e:  # noqa: BLE001 — optik eşi isteğe bağlı katman
        return {"hata": str(e)}


# --------------------------------------------------------- soru bankası

def _banka_ocr_zenginlestir(sorular, kirpmalar):
    """Metni boş kalan soruları (görüntü-gömülü kaynak) kırpma OCR'ıyla doldurur:
    gövde/şık + otomatik konu etiketi. Zaten metni olan sorulara dokunmaz →
    normal taranmış/metin-katmanlı PDF'ler yavaşlamaz."""
    konu_sozluk = DURUM.get("konu_sozluk") or None
    # yalnız metni boş sorular OCR'lanır; ilerleme onların üzerinden yayınlanır
    bos = [(so, img) for so, img in zip(sorular, kirpmalar) if img is not None
           and len((so.get("govde") or "").strip()) < 8
           and len(so.get("siklar") or {}) < 2]
    for i, (so, img) in enumerate(bos, 1):
        _ilerleme_yaz("zenginlestir", i, len(bos),
                      f"Metin OCR'lanıyor… ({i}/{len(bos)})")
        try:
            ay = sk.soru_metni_ocr(img)
        except Exception:  # noqa: BLE001 — OCR hatası: metinsiz devam
            continue
        so["metin"], so["govde"], so["siklar"] = \
            ay["metin"], ay["govde"], ay["siklar"]
        if konu_sozluk and not so.get("konu") and ay["metin"]:
            konu, adaylar = sk.konu_etiketle(ay["metin"], konu_sozluk)
            so["konu"], so["konu_adaylari"] = konu, adaylar


def _bankaya_secim_filtresi(secim_kimlikler):
    """V2 kalite kapısı: incele/reddedildi adayları açık onay yoksa ele.

    Dönüş ``(guvenli_kimlikler, atlanan)``. V2 bulunmayan eski kurulumda
    girdi aynen döner; böylece mevcut davranış değişmez.
    """
    if not (DURUM.get("profil") or DURUM.get("analizler")):
        return secim_kimlikler, 0
    with KILIT:
        oz = _ozet_al()
    istenen = (list(oz["kimlik_liste"]) if secim_kimlikler is None
               else list(dict.fromkeys(secim_kimlikler)))
    guvenli, atlanan = [], 0
    for kimlik in istenen:
        parcalar = oz["kimlik_parca"].get(kimlik, [])
        engelli = False
        for si, ki in parcalar:
            if ki is None:
                continue
            metalar = _kutu_metalari(si)
            if ki >= len(metalar):
                continue
            meta = metalar[ki]
            durum = _durum_normalize(meta.get("inceleme_durumu"),
                                      meta.get("guven", 0))
            if durum != "otomatik" and not meta.get("onayli"):
                engelli = True
                break
        if engelli:
            atlanan += 1
        else:
            guvenli.append(kimlik)
    return guvenli, atlanan


def bankaya_aktar_kaydet(secim_kimlikler):
    """Seçili (ya da tüm) soruları kesip kalıcı yerel bankaya ekler.
    numara_temizle=True → eski numara beyazlatılır + numara_px saklanır;
    böylece bankadan üretilen sınavlar 1..N temiz yeniden numaralanabilir
    (sinav_pdf ile aynı davranış). Dönüş: {"eklenen","atlanan"}."""
    import soru_bankasi
    guvenli_secim, kalite_atlanan = _bankaya_secim_filtresi(secim_kimlikler)
    kirpmalar, sorular = _kes_ortak(guvenli_secim, numara_temizle=True)
    if not kirpmalar:
        return {"eklenen": 0, "atlanan": 0,
                "kalite_atlanan": kalite_atlanan}
    # metni metadata'da boş kalan sorular (görüntü-gömülü hibrit sayfalar) →
    # kırpmayı OCR'la, gövde/şık + konu etiketini doldur (banka araması/gruplaması)
    try:
        _banka_ocr_zenginlestir(sorular, kirpmalar)
    finally:
        with KILIT:
            DURUM["islem"] = None       # zenginleştirme ilerlemesini temizle
    kaynak = (os.path.basename(DURUM["girdiler"][0])
              if DURUM["girdiler"] else None)
    r = soru_bankasi.banka_ekle(sorular, kirpmalar, kaynak=kaynak)
    r["kalite_atlanan"] = kalite_atlanan
    gecmis_ekle("banka", kaynak or "-", r["eklenen"], 0, DURUM["girdiler"])
    return r


def banka_sinav_kaydet(secili_idler, bicim, ayarlar, yol, optik=False):
    """Bankadan seçilen sorulardan yazdırılabilir sınav üretir.
    bicim='pdf' → sinav_pdf (görüntü tabanlı); 'docx' → belge_disa (editlenebilir
    metin + şekil). banka_getir seçim SIRASINI korur. optik=True → eşleşen
    optik cevap kâğıdı da üretilir (anahtar+kazanım otomatik).
    Dönüş: (adet, sonuc)."""
    import soru_bankasi
    if not secili_idler:
        return 0, None
    kirpmalar, meta = soru_bankasi.banka_getir(secili_idler)
    if not kirpmalar:
        return 0, None
    if not ayarlar.get("baslik"):
        ayarlar["baslik"] = "Sınav"
    if bicim == "docx":
        import belge_disa
        sonuc = belge_disa.docx_uret(meta, kirpmalar, yol, ayarlar=ayarlar)
        sonuc.setdefault("yollar", [yol])
        sonuc.setdefault("kitapcik", 1)
        sonuc.setdefault("sayfa", sonuc.get("adet", len(kirpmalar)))
    else:
        import sinav_pdf
        sonuc = sinav_pdf.sinav_pdf_uret(kirpmalar, meta, ayarlar, yol)
    if optik:
        sonuc["optik"] = _optik_esi_uret(meta, ayarlar, yol)
        if sonuc["optik"] and "hata" not in sonuc["optik"]:
            sonuc["yollar"] = list(sonuc["yollar"]) + \
                [sonuc["optik"]["pdf"]]
    gecmis_ekle("banka_" + bicim, sonuc["yollar"][0], len(kirpmalar), 0, [])
    return len(kirpmalar), sonuc


def sihirbaz_uret_islemi(veri):
    """Sınav sihirbazı Adım 5: seçili sorulardan PDF/DOCX/optik/cevap
    anahtarı üretir. veri: {idler, ayarlar, ciktilar:{pdf,docx,optik}}.
    Dönüş: {jeton, ad, dosyalar, onizleme(base64)}."""
    import soru_bankasi
    idler = [int(i) for i in (veri.get("idler") or [])]
    if not idler:
        return {"hata": "önce soru seçin"}
    ayarlar = dict(veri.get("ayarlar") or {})
    ayarlar.setdefault("baslik", "Sınav")
    ciktilar = veri.get("ciktilar") or {"pdf": True}
    temel = "".join(c if c.isalnum() else "_"
                    for c in ayarlar["baslik"])[:40] or "sinav"
    dosyalar = []
    onizleme = None
    if ciktilar.get("pdf"):
        yol = _cikti_yolu(f"{temel}.pdf")
        adet, sonuc = banka_sinav_kaydet(idler, "pdf", dict(ayarlar), yol)
        if sonuc:
            dosyalar += sonuc.get("yollar", [yol])
            onizleme = _pdf_onizleme(sonuc.get("yollar", [yol])[0])
    if ciktilar.get("docx"):
        yol = _cikti_yolu(f"{temel}.docx")
        adet, sonuc = banka_sinav_kaydet(idler, "docx", dict(ayarlar), yol)
        if sonuc:
            dosyalar += sonuc.get("yollar", [yol])
    if ciktilar.get("optik"):
        try:
            import optik_koprusu
            _, meta = soru_bankasi.banka_getir(idler)
            oyol = _cikti_yolu(f"{temel}_optik.pdf")
            osonuc = optik_koprusu.sinavdan_optik(meta, dict(ayarlar), oyol)
            dosyalar.append(osonuc["pdf"])
        except Exception:  # noqa: BLE001 — optik yoksa sınav yine üretilir
            pass
    if not dosyalar:
        return {"hata": "hiçbir çıktı üretilemedi"}
    jeton, ad = _indirme_hazirla(dosyalar)
    return {"jeton": jeton, "ad": ad, "dosyalar": [os.path.basename(d)
                                                   for d in dosyalar],
            "onizleme": onizleme}


def _pdf_onizleme(yol, en=560):
    """PDF ilk sayfasını base64 PNG data-URI'ye render eder (önizleme)."""
    try:
        import fitz
        import base64
        doc = fitz.open(yol)
        pix = doc[0].get_pixmap(matrix=fitz.Matrix(en / doc[0].rect.width,
                                                   en / doc[0].rect.width))
        veri = base64.b64encode(pix.tobytes("png")).decode()
        doc.close()
        return "data:image/png;base64," + veri
    except Exception:  # noqa: BLE001
        return None


AI_ONAY_ESIGI = 300      # bu sayıdan çok soru → önce kullanıcı onayı iste


def banka_ai_etiketle_kaydet(kapsam, filtre, idler, onay=False):
    """Bankadaki soruları Gemini ile konu + başlık etiketler. kapsam: 'sepet'
    (idler) | 'filtre' | 'tumu'. Çok soru (>AI_ONAY_ESIGI) ve onay yoksa
    {"onay_gerek": N} döner (UI onaylayınca onay=True ile yeniden çağrılır).
    Dönüş: {etiketlenen, toplam, basarisiz} | {hata} | {onay_gerek}."""
    import gemini_konu
    import soru_bankasi
    if not gemini_konu.gemini_anahtar_al():
        return {"hata": "Gemini API anahtarı ayarlı değil (⚙ AI Anahtarı)"}
    if kapsam == "sepet" and idler:
        kayitlar = [k for k in (soru_bankasi.banka_kayit(i) for i in idler) if k]
    else:
        f = filtre or {}
        kayitlar = soru_bankasi.banka_sorgula(
            konu=f.get("konu"), kaynak=f.get("kaynak"), cevap=f.get("cevap"),
            etiket=f.get("etiket"), arama=f.get("arama"), bos=f.get("bos"),
            zorluk=f.get("zorluk"), limit=100000, ofset=0)["kayitlar"]
    hedef = [{"id": k["id"], "metin": k.get("metin") or ""}
             for k in kayitlar if (k.get("metin") or "").strip()]
    if not hedef:
        return {"hata": "etiketlenecek metinli soru yok"}
    if len(hedef) > AI_ONAY_ESIGI and not onay:
        return {"onay_gerek": len(hedef)}   # UI: "N soru etiketlenecek, sürebilir"
    konu_listesi = [k for k, _ in sk.konu_sozlugu_oku(KONU_CSV)]
    _ilerleme_yaz("ai", 0, len(hedef), "AI etiketleme başlıyor…")

    def il(a, t):
        _ilerleme_yaz("ai", a, t, f"AI ile konu belirleniyor… ({a}/{t} grup)")
    try:
        cikti = gemini_konu.gemini_etiketle_toplu(
            hedef, konu_listesi=konu_listesi, ilerleme=il)
    finally:
        with KILIT:
            DURUM["islem"] = None
    guncel = [{"id": sid, "konu": v.get("konu"), "baslik": v.get("baslik"),
               "zorluk": v.get("zorluk")}
              for sid, v in cikti["sonuc"].items()]
    n = soru_bankasi.banka_guncelle_konu(guncel)
    return {"etiketlenen": n, "toplam": len(hedef),
            "basarisiz": len(cikti["basarisiz"])}


# --------------------------------------------------------- dosya yükleme

def _gecici_klasor():
    if not DURUM["gecici_klasor"] or not os.path.isdir(DURUM["gecici_klasor"]):
        DURUM["gecici_klasor"] = tempfile.mkdtemp(prefix="soru_kesici_")
    return DURUM["gecici_klasor"]


def yukleme_kaydet(ad, veri):
    """Sürükle-bırakla gelen dosya baytlarını geçici diske yazar, yolu döndürür.
    Uzantı doğrulanır; yol bileşenleri atılır (yalnız temel ad)."""
    ad = os.path.basename(ad or "dosya")
    uzanti = os.path.splitext(ad)[1].lower()
    desteklenen = set(getattr(
        sk, "GIRDI_UZANTILARI",
        set(getattr(sk, "GORUNTU_UZANTILARI", ())) | {".pdf", ".docx"}))
    if uzanti not in desteklenen:
        raise ValueError(f"desteklenmeyen format: {ad}")
    klasor = _gecici_klasor()
    hedef = os.path.join(klasor, ad)
    say = 1
    while os.path.exists(hedef):   # aynı ada sahip birden çok yükleme
        kok, uz = os.path.splitext(ad)
        hedef = os.path.join(klasor, f"{kok}_{say}{uz}")
        say += 1
    with open(hedef, "wb") as f:
        f.write(veri)
    return hedef


def _temizle():
    if DURUM["gecici_klasor"] and os.path.isdir(DURUM["gecici_klasor"]):
        shutil.rmtree(DURUM["gecici_klasor"], ignore_errors=True)


atexit.register(_temizle)


# ------------------------------------------------------------------- HTML

SAYFA = """<!doctype html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Soru Kesici</title>
<style>
 /* ---- Tema sistemi: koyu (varsayılan) + açık; JS data-theme'i ayarlar ---- */
 :root,:root[data-theme=dark]{
   --bg:#0e1117;--panel:#151b26;--kart:#1a2131;--input:#0c1119;--kenar:#2a3450;
   --ayrac:#232b3f;--metin:#e8edf6;--sol:#93a1bd;--ipuc-c:#6b7894;
   --mavi:#3b82f6;--mavi-h:#2f6fd6;--yesil:#22c55e;--yesil-h:#1ba34d;
   --vurgu:#ef4444;--uyari:#eab308;--golge:0 8px 30px rgba(0,0,0,.45);
   --ikincil-bg:#222c42;--ikincil-h:#2e3a56;--imgbg:#fff;
   --c1:#3987e5;--c-kolay:#0ca30c;--c-orta:#eab308;--c-zor:#e05555;
   --grid:#2c3245;--tuval:#141b29;}
 :root[data-theme=light]{
   --bg:#eef1f6;--panel:#ffffff;--kart:#ffffff;--input:#f5f7fb;--kenar:#dde2ea;
   --ayrac:#eceff4;--metin:#0f172a;--sol:#4b5563;--ipuc-c:#8a93a6;
   --mavi:#2a78d6;--mavi-h:#256abf;--yesil:#0ca30c;--yesil-h:#088a08;
   --vurgu:#dc2626;--uyari:#c07a00;--golge:0 6px 22px rgba(15,23,42,.10);
   --ikincil-bg:#eef1f6;--ikincil-h:#e1e6ef;--imgbg:#fff;
   --c1:#2a78d6;--c-kolay:#0ca30c;--c-orta:#c07a00;--c-zor:#d03b3b;
   --grid:#e6e9f0;--tuval:#f8fafc;}
 @media (prefers-color-scheme:light){:root:not([data-theme=dark]){
   --bg:#eef1f6;--panel:#fff;--kart:#fff;--input:#f5f7fb;--kenar:#dde2ea;
   --ayrac:#eceff4;--metin:#0f172a;--sol:#4b5563;--ipuc-c:#8a93a6;
   --mavi:#2a78d6;--mavi-h:#256abf;--yesil:#0ca30c;--yesil-h:#088a08;
   --vurgu:#dc2626;--uyari:#c07a00;--golge:0 6px 22px rgba(15,23,42,.10);
   --ikincil-bg:#eef1f6;--ikincil-h:#e1e6ef;--imgbg:#fff;
   --c1:#2a78d6;--c-kolay:#0ca30c;--c-orta:#c07a00;--c-zor:#d03b3b;
   --grid:#e6e9f0;--tuval:#f8fafc;}}
 *{box-sizing:border-box}
 body{margin:0;font:15px/1.55 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
   background:var(--bg);color:var(--metin);height:100vh;display:flex;flex-direction:column;
   transition:background .25s,color .25s;-webkit-font-smoothing:antialiased}
 header{padding:12px 20px;background:var(--panel);border-bottom:1px solid var(--kenar);
   display:flex;align-items:center;gap:10px;box-shadow:0 1px 0 rgba(0,0,0,.04)}
 header h1{font-size:17px;margin:0 8px 0 0;font-weight:700;letter-spacing:-.01em}
 header .alt{color:var(--sol);font-size:12.5px;margin-left:auto}
 #temaBtn{margin-left:8px;background:var(--ikincil-bg);color:var(--metin);
   padding:8px 11px;font-size:15px}
 main{flex:1;display:flex;min-height:0}
 #onizleme{flex:1;overflow:auto;padding:22px;display:flex;
   align-items:flex-start;background:var(--bg)}
 #onizleme.surukle{outline:3px dashed var(--mavi);outline-offset:-8px;border-radius:12px}
 #sahne{position:relative;display:inline-block;line-height:0;margin-left:auto;margin-right:auto}
 #sahne.ciz{cursor:crosshair}
 #sahne.pan{cursor:grab}
 #gorsel{max-width:100%;border-radius:10px;box-shadow:var(--golge);background:var(--imgbg)}
 .kutu{position:absolute;border:2px solid var(--vurgu);cursor:move;
   background:rgba(239,68,68,.06)}
 .kutu.sec{border-color:var(--mavi);background:rgba(59,130,246,.14);z-index:5}
 .kutu .no{position:absolute;top:0;left:0;font:600 12px/1.4 sans-serif;color:#fff;
   background:var(--vurgu);padding:0 5px;border-radius:0 0 4px 0;white-space:nowrap}
 .kutu.sec .no{background:var(--mavi)}
 #sahne.sec-modu .kutu{cursor:pointer}
 #sahne.sec-modu .tut{display:none}
 .kutu.kesime{border-color:var(--yesil);background:rgba(34,197,94,.16);z-index:4}
 .kutu.kesime .no{background:var(--yesil)}
 .kutu.kesime::after{content:"✓";position:absolute;right:2px;top:0;color:#fff;
   font-weight:700;font-size:12px;background:var(--yesil);padding:0 3px;border-radius:0 0 0 4px}
 .kutu.kalite-otomatik{border-color:var(--yesil);background:rgba(34,197,94,.08)}
 .kutu.kalite-incele{border-color:var(--uyari);background:rgba(234,179,8,.10)}
 .kutu.kalite-reddedildi{border-color:var(--vurgu);background:rgba(239,68,68,.12)}
 .kalite-rozet{position:absolute;right:2px;bottom:2px;padding:2px 6px!important;
   border-radius:6px!important;font:700 10px/1.35 system-ui,sans-serif!important;color:#fff!important;
   z-index:8;box-shadow:0 1px 4px #0008;white-space:nowrap;transform:none!important}
 .kalite-rozet.otomatik{background:var(--yesil)}
 .kalite-rozet.incele{background:var(--uyari);color:#161616!important}
 .kalite-rozet.reddedildi{background:var(--vurgu)}
 .kalite-rozet.onayli{background:var(--mavi)}
 .tut{position:absolute;width:13px;height:13px;background:#fff;border:2px solid var(--mavi);
   border-radius:2px;display:none}
 .kutu.sec .tut{display:block}
 .tut.nw{left:-7px;top:-7px;cursor:nwse-resize} .tut.ne{right:-7px;top:-7px;cursor:nesw-resize}
 .tut.sw{left:-7px;bottom:-7px;cursor:nesw-resize} .tut.se{right:-7px;bottom:-7px;cursor:nwse-resize}
 #sahne.bol .kutu.sec{cursor:row-resize}
 .bol-cizgi{position:absolute;height:2px;background:var(--mavi);z-index:9;
   pointer-events:none;box-shadow:0 0 4px var(--mavi)}
 #bos{color:var(--ipuc-c);margin-top:60px;text-align:center;line-height:1.9}
 aside{width:320px;background:var(--panel);border-left:1px solid var(--kenar);
   padding:18px;display:flex;flex-direction:column;gap:12px;overflow:auto}
 button{font:inherit;border:0;border-radius:10px;padding:11px 14px;cursor:pointer;
   font-weight:600;transition:.16s ease;color:#fff}
 button:hover:not(:disabled){transform:translateY(-1px)}
 button:active:not(:disabled){transform:translateY(0)}
 button:disabled{opacity:.4;cursor:not-allowed}
 button:focus-visible{outline:2px solid var(--mavi);outline-offset:2px}
 .birincil{background:var(--mavi);box-shadow:0 2px 8px rgba(59,130,246,.3)}
 .birincil:hover:not(:disabled){background:var(--mavi-h)}
 .kes{background:var(--yesil);box-shadow:0 2px 8px rgba(34,197,94,.28)}
 .kes:hover:not(:disabled){background:var(--yesil-h)}
 .ikincil{background:var(--ikincil-bg);color:var(--metin)}
 .ikincil:hover:not(:disabled){background:var(--ikincil-h)}
 .ikincil.etkin{background:var(--mavi);color:#fff}
 .kart{background:var(--kart);border:1px solid var(--kenar);border-radius:12px;padding:13px;
   box-shadow:var(--golge)}
 .kart h3{margin:0 0 9px;font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;
   color:var(--sol);font-weight:700}
 .satir{display:flex;align-items:center;justify-content:space-between;gap:8px;margin:6px 0}
 .duzen{display:grid;grid-template-columns:1fr 1fr;gap:7px}
 .duzen button{padding:9px 8px;font-size:13px}
 .ozet b{color:var(--metin)} .ozet div{margin:3px 0;color:var(--sol)}
 .kalibrasyon-sayac{display:grid;grid-template-columns:repeat(3,1fr);gap:5px;margin:7px 0}
 .kalibrasyon-sayac span{padding:5px 4px;border-radius:7px;text-align:center;font-size:11px;font-weight:700}
 .kalibrasyon-sayac .oto{background:rgba(34,197,94,.16);color:var(--yesil)}
 .kalibrasyon-sayac .inc{background:rgba(234,179,8,.16);color:var(--uyari)}
 .kalibrasyon-sayac .red{background:rgba(239,68,68,.16);color:var(--vurgu)}
 .mod{display:grid;grid-template-columns:1fr 1fr;gap:0;border:1px solid var(--kenar);
   border-radius:10px;overflow:hidden}
 .mod button{border-radius:0;background:var(--kart);color:var(--sol)}
 .mod button.etkin{background:var(--mavi);color:#fff}
 details.kart{padding:0} details.kart>summary{padding:13px;cursor:pointer;
   font-size:11.5px;text-transform:uppercase;letter-spacing:.06em;color:var(--sol);
   font-weight:700;list-style:none} details.kart>summary::-webkit-details-marker{display:none}
 details.kart>summary::before{content:"▸ ";color:var(--mavi)}
 details.kart[open]>summary::before{content:"▾ "}
 details.kart>div{padding:0 13px 13px}
 #testListe{max-height:200px;overflow:auto;margin-top:6px}
 .test-satir{display:flex;align-items:center;gap:8px;padding:5px 0;font-size:13px;
   color:var(--metin);cursor:pointer;border-bottom:1px solid var(--ayrac)}
 .test-satir:hover{color:var(--mavi)} .test-satir .adet{margin-left:auto;color:var(--sol);font-size:12px}
 .test-satir input{width:16px;height:16px;accent-color:var(--yesil)}
 input,select,textarea{font:inherit}
 input[type=text],input:not([type]),#aralik,#ara,#etAnahtar,#etDeger{width:100%;
   background:var(--input);border:1px solid var(--kenar);color:var(--metin);
   border-radius:8px;padding:8px 10px;margin-top:4px;transition:border-color .15s}
 input:focus,select:focus{outline:none;border-color:var(--mavi)}
 .canli{font-size:12px;color:var(--yesil);min-height:16px;margin:4px 0}
 .canli.uyari{color:var(--uyari)}
 .sayac{color:var(--sol);font-size:13px;margin-top:6px}
 .sayac b{color:var(--yesil)}
 .gecmis-satir{font-size:12px;padding:7px 0;border-bottom:1px solid var(--ayrac);
   display:flex;flex-direction:column;gap:4px}
 .gecmis-satir .yol{color:var(--metin)} .gecmis-satir .alt{color:var(--sol)}
 .gecmis-satir .btnlar{display:flex;gap:6px}
 .gecmis-satir button{padding:4px 8px;font-size:11px;font-weight:500}
 .gez{display:flex;align-items:center;gap:8px}
 .gez button{padding:8px 12px}
 .gez span{flex:1;text-align:center;color:var(--sol);font-size:13px}
 input[type=number]{width:70px;background:var(--input);border:1px solid var(--kenar);
   color:var(--metin);border-radius:8px;padding:7px}
 select{background:var(--input);border:1px solid var(--kenar);color:var(--metin);
   border-radius:8px;padding:8px}
 label.chk{display:flex;align-items:center;gap:8px;color:var(--sol);cursor:pointer;font-size:13.5px}
 footer{padding:9px 20px;background:var(--panel);border-top:1px solid var(--kenar);
   color:var(--sol);font-size:13px;min-height:38px;display:flex;align-items:center;gap:10px}
 .spin{width:15px;height:15px;border:2px solid var(--kenar);border-top-color:var(--mavi);
   border-radius:50%;animation:d .8s linear infinite;display:none}
 @keyframes d{to{transform:rotate(360deg)}}
 @keyframes gir{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}
 .dosyalar{font-size:12px;color:var(--sol);word-break:break-word;max-height:150px;overflow:auto}
 .dosya-satir{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:2px 8px;
   align-items:center;padding:6px 0;border-bottom:1px solid var(--ayrac)}
 .dosya-satir:last-child{border-bottom:0}.dosya-ad{overflow:hidden;text-overflow:ellipsis;
   white-space:nowrap;color:var(--metin)}.dosya-durum{font-size:11px;white-space:nowrap}
 .dosya-durum.hata{color:var(--vurgu)}.dosya-durum.tamam{color:var(--yesil)}
 .dosya-ilerleme{grid-column:1/-1;height:4px;background:var(--tuval);border-radius:4px;overflow:hidden}
 .dosya-ilerleme span{display:block;height:100%;background:var(--mavi);transition:width .15s ease}
 .ilerleme-yol{display:none;align-items:center;gap:8px;margin-left:auto;min-width:220px}
 .ilerleme-yol.acik{display:flex}.ilerleme-ray{height:7px;flex:1;background:var(--tuval);
   border-radius:8px;overflow:hidden}.ilerleme-dolgu{display:block;height:100%;width:0;
   background:var(--mavi);transition:width .2s ease}.ilerleme-yuzde{min-width:36px;text-align:right;
   color:var(--metin);font-variant-numeric:tabular-nums;font-size:12px}
 .ipuc{font-size:12px;color:var(--ipuc-c);line-height:1.5}
 /* rozet/chip */
 .chip{display:inline-block;font-size:10.5px;font-weight:600;padding:1px 7px;border-radius:20px;
   line-height:1.6;white-space:nowrap}
 .zor-kolay{background:color-mix(in srgb,var(--c-kolay) 22%,transparent);color:var(--c-kolay)}
 .zor-orta{background:color-mix(in srgb,var(--c-orta) 24%,transparent);color:var(--c-orta)}
 .zor-zor{background:color-mix(in srgb,var(--c-zor) 22%,transparent);color:var(--c-zor)}
 /* --- soru bankası görünümü --- */
 #banka{flex:1;display:none;min-height:0}
 #bankaSol{flex:1;display:flex;flex-direction:column;overflow:auto;padding:18px;gap:12px;background:var(--bg)}
 #bankaFiltre{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px}
 #bankaFiltre select,#bankaFiltre input{width:100%;background:var(--input);border:1px solid var(--kenar);
   color:var(--metin);border-radius:8px;padding:8px 10px;font:inherit;margin-top:0}
 #bankaGrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(158px,1fr));gap:12px}
 .bkart{background:var(--kart);border:2px solid var(--kenar);border-radius:12px;overflow:hidden;
   cursor:pointer;display:flex;flex-direction:column;transition:.15s ease;box-shadow:var(--golge)}
 .bkart:hover{border-color:var(--mavi);transform:translateY(-2px)}
 .bkart.sec{border-color:var(--yesil);box-shadow:0 0 0 2px var(--yesil)}
 .bkart img{width:100%;background:#fff;display:block;object-fit:contain;max-height:210px}
 .bkart .et{font-size:11px;color:var(--sol);padding:6px 8px;line-height:1.35}
 .bkart .et b{color:var(--metin);font-size:11.5px}
 .bkart.sec .et b{color:var(--yesil)}
 #bankaSepet{width:308px;background:var(--panel);border-left:1px solid var(--kenar);
   padding:16px;display:flex;flex-direction:column;gap:12px;overflow:auto}
 #sepetListe{max-height:260px;overflow:auto}
 .sepet-satir{display:flex;align-items:center;gap:5px;font-size:12px;color:var(--metin);
   padding:4px 0;border-bottom:1px solid var(--ayrac)}
 .sepet-satir span{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 .sepet-satir button{padding:2px 6px;font-size:11px;font-weight:500;background:var(--ikincil-bg);color:var(--metin)}
 #bankaSepet input:not([type=checkbox]),#bankaSepet select{width:100%;background:var(--input);
   border:1px solid var(--kenar);color:var(--metin);border-radius:8px;padding:8px 10px;font:inherit;margin-bottom:6px}
 #bankaSepet label.chk{margin:5px 0} #bankaSepet .satir select{width:auto}
 #bankaSepet .satir input[type=number]{width:80px;margin-bottom:0}
 #optik{flex:1;display:none;flex-direction:column;min-height:0;background:var(--bg)}
 .optik-nav{display:flex;gap:6px;align-items:center;padding:10px 18px;border-bottom:1px solid var(--kenar);flex-wrap:wrap}
 .optik-nav button{background:var(--input);border:1px solid var(--kenar);color:var(--metin);
   border-radius:8px;padding:7px 13px;cursor:pointer;font-size:13px}
 .optik-nav button.etkin{background:var(--birincil,#2563eb);border-color:transparent;color:#fff}
 .optik-pane{flex:1;overflow:auto;padding:18px;display:flex;flex-direction:column;gap:14px;min-height:0}
 .optik-pane table{border-collapse:collapse;width:100%;font-size:12.5px}
 .optik-pane th,.optik-pane td{border-bottom:1px solid var(--kenar);padding:5px 8px;text-align:left;white-space:nowrap}
 .optik-pane th{color:var(--sol);font-weight:600;position:sticky;top:0;background:var(--panel)}
 .optik-pane tr.secilebilir{cursor:pointer} .optik-pane tr.secilebilir:hover{background:var(--input)}
 .optik-pane tr.aktif{outline:2px solid var(--birincil,#2563eb)}
 .optik-pane input,.optik-pane select,.optik-pane textarea{background:var(--input);border:1px solid var(--kenar);
   color:var(--metin);border-radius:6px;padding:6px 8px;font-size:13px}
 .op-ders{display:flex;gap:6px;align-items:center;margin-top:6px}
 .op-ders input[type=text]{flex:1} .op-ders input[type=number]{width:64px}
 #opWarpKutu{position:relative;align-self:flex-start;max-width:100%}
 #opWarp{max-width:100%;border-radius:8px;background:#fff;display:block}
 .op-balon{position:absolute;border-radius:50%;border:2px solid transparent;cursor:pointer;
   transform:translate(-50%,-50%);box-sizing:border-box}
 .op-balon.isaretli{background:#2563eb66;border-color:#2563eb}
 .op-balon.sorunlu{border-color:#dc2626}
 .op-balon.duzeltildi{border-color:#16a34a;background:#16a34a55}
 .op-balon:hover{border-color:var(--metin)}
 .op-rozet{display:inline-block;border-radius:6px;padding:1px 7px;font-size:11px;font-weight:600}
 .op-rozet.okundu{background:#16a34a33;color:#16a34a}
 .op-rozet.incelenecek{background:#eab30833;color:#b45309}
 .op-rozet.hatali{background:#dc262633;color:#dc2626}
 /* --- Dashboard / Panel --- */
 #dashboard{flex:1;display:none;overflow:auto;padding:24px;background:var(--bg);flex-direction:column;gap:20px}
 #dashboard.acik{display:flex}
 .dash-baslik{font-size:20px;font-weight:750;letter-spacing:-.02em;margin:0}
 .stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px}
 .stat{background:var(--kart);border:1px solid var(--kenar);border-radius:14px;padding:16px 18px;
   box-shadow:var(--golge);animation:gir .3s ease both}
 .stat .v{font-size:28px;font-weight:750;letter-spacing:-.02em;line-height:1.1}
 .stat .l{color:var(--sol);font-size:12.5px;margin-top:4px}
 .chart-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}
 .chart{background:var(--kart);border:1px solid var(--kenar);border-radius:14px;padding:16px 18px;
   box-shadow:var(--golge);animation:gir .35s ease both}
 .chart h4{margin:0 0 12px;font-size:13px;font-weight:700;color:var(--metin)}
 .chart .bar-satir{display:grid;grid-template-columns:120px 1fr 42px;align-items:center;gap:10px;
   margin:7px 0;font-size:12.5px;cursor:pointer}
 .chart .bar-satir:hover .bar-ad{color:var(--mavi)}
 .bar-ad{color:var(--sol);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
 .bar-yol{display:block;background:var(--tuval);border-radius:5px;height:16px;overflow:hidden}
 .bar-dolu{display:block;height:100%;border-radius:5px;min-width:3px;transition:width .5s ease}
 .bar-deg{text-align:right;color:var(--metin);font-variant-numeric:tabular-nums;font-weight:600}
 .lightbox{position:fixed;inset:0;background:rgba(0,0,0,.82);display:none;align-items:center;
   justify-content:center;z-index:50;padding:32px;cursor:zoom-out}
 .lightbox.acik{display:flex;animation:gir .18s ease}
 .lightbox img{max-width:100%;max-height:100%;border-radius:10px;background:#fff;box-shadow:0 20px 60px #000a}
 #toastAlan{position:fixed;right:18px;bottom:56px;display:flex;flex-direction:column;gap:8px;
   z-index:60;max-width:340px}
 .toast{background:var(--kart);border:1px solid var(--kenar);border-left:4px solid var(--mavi);
   border-radius:8px;padding:10px 14px;font-size:13px;color:var(--metin);box-shadow:var(--golge);
   cursor:pointer;animation:gir .22s ease}
 .toast.basari{border-left-color:var(--yesil)}
 .toast.hata{border-left-color:var(--vurgu)}
 .galeri-overlay{position:fixed;inset:0;background:rgba(0,0,0,.82);display:none;align-items:center;
   justify-content:center;z-index:55;padding:32px}
 .galeri-overlay.acik{display:flex;animation:gir .18s ease}
 .galeri-panel{background:var(--panel);border-radius:14px;padding:20px;max-width:1000px;
   max-height:90vh;overflow:auto;width:100%}
 .galeri-baslik{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px;gap:12px}
 .galeri-izgara{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
 .galeri-kart{border:1px solid var(--kenar);border-radius:8px;overflow:hidden;background:var(--kart);
   cursor:pointer;display:flex;flex-direction:column}
 .galeri-kart:hover{border-color:var(--mavi)}
 .galeri-kart img{width:100%;height:120px;object-fit:contain;background:#fff}
 .galeri-kart .alt{padding:5px 7px;font-size:11px;display:flex;align-items:center;
   justify-content:space-between;gap:4px;color:var(--sol)}
 .galeri-kart .cikar{background:none;border:0;color:var(--sol);cursor:pointer;
   font-size:11px;padding:2px 4px;border-radius:4px;white-space:nowrap}
 .galeri-kart .cikar:hover{background:var(--vurgu);color:#fff}
 #sihirbaz{flex:1;display:none;flex-direction:column;min-height:0;background:var(--bg);overflow:auto;padding:18px 24px}
 .sh-stepper{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px}
 .sh-stepper .adim{padding:8px 14px;border-radius:20px;background:var(--kart);border:1px solid var(--kenar);
   color:var(--sol);font-size:13px;font-weight:600}
 .sh-stepper .adim.etkin{background:var(--mavi,#2563eb);color:#fff;border-color:transparent}
 .sh-stepper .adim.tamam{color:var(--c-kolay,#16a34a);border-color:var(--c-kolay,#16a34a)}
 .sh-panel{display:none;background:var(--kart);border:1px solid var(--kenar);border-radius:14px;padding:18px;max-width:900px}
 .sh-panel.etkin{display:block;animation:gir .25s ease}
 .sh-matris{border-collapse:collapse;width:100%;margin:10px 0}
 .sh-matris th,.sh-matris td{border:1px solid var(--kenar);padding:6px 8px;text-align:center;font-size:13px}
 .sh-matris input{width:52px;text-align:center;background:var(--input);border:1px solid var(--kenar);
   color:var(--metin);border-radius:5px;padding:3px}
 .sh-matris .stok{font-size:11px;color:var(--sol)}
 .sh-matris .eksik{color:var(--c-zor,#dc2626);font-weight:700}
 .sh-nav{display:flex;gap:10px;margin-top:16px}
 .sh-kart{display:inline-flex;flex-direction:column;width:150px;margin:5px;border:1px solid var(--kenar);
   border-radius:8px;overflow:hidden;background:var(--kart)}
 .sh-kart img{width:100%;height:100px;object-fit:contain;background:#fff}
 .sh-kart .alt{padding:4px 6px;font-size:11px;display:flex;gap:4px;justify-content:space-between}
</style></head><body>
<header><h1>✂️ Soru Kesici</h1>
  <button id="tabKesim" class="ikincil etkin" onclick="gorunumAyarla('kesim')">✂️ Kesim</button>
  <button id="tabBanka" class="ikincil" onclick="gorunumAyarla('banka')">🗂 Soru Bankası</button>
  <button id="tabPanel" class="ikincil" onclick="gorunumAyarla('panel')">📊 Panel</button>
  <button id="tabSihirbaz" class="ikincil" onclick="gorunumAyarla('sihirbaz')">🧙 Sınav Sihirbazı</button>
  <button id="tabOptik" class="ikincil" onclick="gorunumAyarla('optik')">🔘 Optik</button>
  <button id="merkezBtn" class="ikincil" onclick="window.location='/merkez'" title="Biyoloji Stüdyosu Merkezi">🏠 Merkez</button>
  <span class="alt">PDF, DOCX ve PNG/JPG/TIFF/BMP/WebP/GIF testleri soru soru keser · bankaya aktarıp sınav üretir</span>
  <button id="temaBtn" onclick="temaDegis()" title="Açık/koyu tema">🌙</button></header>
<main>
 <div id="onizleme">
   <div id="bos">Başlamak için sağdan <b>Dosya Seç</b>e basın<br>
     ya da dosyaları buraya <b>sürükleyip bırakın</b>.<br><br>
     Ardından <b>Ön İzle</b> ile kutuları görün, gerekiyorsa<br>
     taşıyıp/silip/çizerek düzeltin, sonra <b>Kes ve Kaydet</b>.</div>
   <div id="sahne" style="display:none"><img id="gorsel"></div>
 </div>
 <aside id="kesimAside">
   <button class="birincil" id="secBtn" onclick="dosyaSec()">📂 Dosya Seç…</button>
   <input id="dosyaInput" type="file" hidden multiple
     accept=".pdf,.docx,.png,.jpg,.jpeg,.tif,.tiff,.bmp,.webp,.gif,application/pdf,application/vnd.openxmlformats-officedocument.wordprocessingml.document,image/png,image/jpeg,image/tiff,image/bmp,image/webp,image/gif"
     onchange="dosyaInputDegisti(event)">
   <div class="dosyalar" id="dosyalar"></div>
   <div class="kart">
     <h3>Ayarlar</h3>
     <div class="satir"><span>Çözünürlük (DPI)</span>
       <input type="number" id="dpi" value="300" min="120" max="600" step="30"></div>
     <label class="chk"><input type="checkbox" id="numaraGizle" checked> Kesilen görüntüde soru numarasını gizle</label>
     <label class="chk" id="cevapBandiSatir"><input type="checkbox" id="cevapBandi"> Cevabı görüntünün altına bas (cevap bandı)</label>
     <label class="chk" id="cozumIlistirSatir" style="display:none"><input type="checkbox" id="cozumIlistir"> Çözümü sorunun altına iliştir</label>
     <label class="chk"><input type="checkbox" id="bankaAyni"> Kesince soru bankasına da ekle</label>
     <label class="chk"><input type="checkbox" id="mlDuzen" onchange="mlDuzenKaydet()"> ML düzen tespiti (deneysel)</label>
     <label class="chk"><input type="checkbox" id="geminiVision" onchange="geminiVisionKaydet()">
       Düşük güvenli sayfalarda Gemini Vision</label>
     <span class="ipuc">Varsayılan kapalıdır. Açılırsa yalnız düşük güvenli sayfalar
       harici servise gönderilebilir; gizlilik ve API ücreti size aittir.</span>
     <span id="mlDurum" class="ipuc"></span>
     <div class="satir" style="margin-top:8px"><span>OCR modu</span>
       <select id="ocrModu" onchange="ocrModuKaydet()"
         style="background:var(--input);border:1px solid var(--kenar);color:var(--metin);border-radius:6px;padding:5px">
         <option value="hizli">Hızlı (yalnız Apple Vision)</option>
         <option value="dengeli">Dengeli (şüpheli satırlarda 5-motor)</option>
         <option value="tam">Tam (tüm sayfa oylaması, yavaş)</option>
       </select></div>
     <span id="ocrDurum" class="ipuc"></span>
   </div>
   <button class="ikincil" id="onizleBtn" onclick="onizle()" disabled>🔍 Ön İzle</button>
   <div class="kart ozet" id="ozet" style="display:none"></div>
   <div class="kart" id="kalibrasyonKart" style="display:none">
     <h3>Otomatik Kalibrasyon</h3>
     <div id="kalibrasyonOzet" class="ipuc"></div>
     <button class="ikincil" id="incelemeBtn" style="width:100%;margin-top:8px;padding:8px"
       onclick="incelemeModuDegis()" disabled>⚠ İncelenecek sayfa yok</button>
     <button class="ikincil" id="topluOnayBtn" style="width:100%;margin-top:6px;padding:8px"
       onclick="topluOnayla()" disabled>✓ Sayfadaki İncele kutularını onayla</button>
   </div>
   <div class="kart" id="sayfaIncelemeKart" style="display:none">
     <h3>Sayfa İncelemesi</h3>
     <div id="sayfaIncelemeOzet" class="ipuc"></div>
     <div class="duzen" style="margin-top:8px">
       <button class="ikincil" onclick="sayfaKarar('onayli')">✓ Sayfa doğru</button>
       <button class="ikincil" onclick="sayfaKarar('soru_yok')">∅ Soru yok</button>
       <button class="ikincil" id="sayfaKararGeri" onclick="sayfaKarar('bekliyor')"
         style="display:none">↺ Kararı geri al</button>
     </div>
   </div>
   <div class="gez" id="gez" style="display:none">
     <button class="ikincil" onclick="sayfaGez(-1)">◀</button>
     <span id="sayfaEtiket">–</span>
     <button class="ikincil" onclick="sayfaGez(1)">▶</button>
     <button class="ikincil" onclick="zoomAyarla(yakZoom/1.25)" title="Uzaklaştır">−</button>
     <span id="zoomEtiket">100%</span>
     <button class="ikincil" onclick="zoomAyarla(yakZoom*1.25)" title="Yakınlaştır">+</button>
   </div>
   <div class="mod" id="modAnahtar" style="display:none">
     <button id="modDuzen" class="etkin" onclick="modAyarla('duzenle')">✏️ Düzenle</button>
     <button id="modSec" onclick="modAyarla('sec')">☑️ Seç</button>
   </div>
   <div class="kart" id="duzenKart" style="display:none">
     <h3>Kutu Düzenle <span id="duzenRozet" style="color:var(--yesil)"></span></h3>
     <div class="duzen">
       <button class="ikincil" id="cizBtn" onclick="cizAc()">➕ Kutu Ekle</button>
       <button class="ikincil" id="bolBtn" onclick="bolAc()" disabled>✂ Böl</button>
       <button class="ikincil" id="birlestirBtn" onclick="kutuBirlestir()" disabled>⛶ Birleştir</button>
       <button class="ikincil" id="silBtn" onclick="kutuSil()" disabled>🗑 Sil</button>
       <button class="ikincil" onclick="sayfaSifirla()">↺ Sıfırla</button>
       <button class="ikincil" id="geriAlBtn" onclick="geriAl()" disabled>↶ Geri Al</button>
       <button class="ikincil" id="yineleBtn" onclick="yinele()" disabled>↷ Yinele</button>
     </div>
     <div class="ipuc" style="margin-top:8px">Tıkla: seç · Shift+tıkla: çoklu ·
       Delete: sil · sürükle: taşı · köşe: boyutlandır · ←/→: sayfa ·
       ⌘Z: geri al · B: böl · N/O: incele gez/onayla · ⌘±: zoom</div>
     <div id="kucukResim" style="margin-top:10px;display:none">
       <div class="ipuc" style="margin-bottom:4px">Kesilecek görüntü:</div>
       <img style="max-width:100%;border-radius:6px;background:#fff" alt="">
     </div>
   </div>
   <div class="kart" id="secimKart" style="display:none">
     <h3>Soru Seç</h3>
     <div class="ipuc">Kutulara tıklayın ya da aralık yazın:</div>
     <input id="aralik" placeholder="test 5: 2-10; t3: 10-15" oninput="aralikDegis()">
     <div class="canli" id="aralikCanli"></div>
     <div class="ipuc" style="margin-top:8px">🔎 Konu/kelime ara (soru metninde):</div>
     <input id="ara" placeholder="fotosentez, nöron…" oninput="aramaDegis()">
     <div class="canli" id="aramaCanli"></div>
     <div class="satir" style="margin:2px 0">
       <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="tumunuSec(true)">Tümünü seç</button>
       <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="tumunuSec(false)">Temizle</button>
     </div>
     <button class="ikincil" style="width:100%;margin:4px 0" onclick="galeriAc()">🔍 Seçimi Gözden Geçir</button>
     <div id="testListe"></div>
     <div class="sayac">Seçili: <b id="secimSayi">0</b> soru</div>
     <div class="ipuc" style="margin-top:10px">🏷 Seçili sorulara etiket ata (örn. konu / kazanım):</div>
     <div class="satir" style="gap:5px">
       <input id="etAnahtar" placeholder="konu" style="flex:1;margin:0">
       <input id="etDeger" placeholder="değer" style="flex:1;margin:0">
       <button class="ikincil" style="padding:8px 10px;font-size:12px" onclick="etiketAta()">Ata</button>
     </div>
     <div class="canli" id="etiketCanli"></div>
     <div class="ipuc" style="margin-top:10px">✏️ Seçili soruların cevabını düzelt:</div>
     <div class="satir" style="gap:4px" id="cevapDuzeltSatir">
       <button class="ikincil cvp" onclick="cevapDuzelt('A')">A</button>
       <button class="ikincil cvp" onclick="cevapDuzelt('B')">B</button>
       <button class="ikincil cvp" onclick="cevapDuzelt('C')">C</button>
       <button class="ikincil cvp" onclick="cevapDuzelt('D')">D</button>
       <button class="ikincil cvp" onclick="cevapDuzelt('E')">E</button>
       <button class="ikincil cvp" onclick="cevapDuzelt('')" title="cevabı sil">∅</button>
       <button class="ikincil cvp" onclick="cevapDuzelt(null)" title="otomatik eşlemeye dön">↺</button>
     </div>
     <div class="canli" id="cevapCanli"></div>
   </div>
   <details class="kart" id="sinavKart" style="display:none">
     <summary>Sınav Kağıdı (PDF)</summary>
     <div>
       <input id="sinavKurum" placeholder="Kurum / okul adı (isteğe bağlı)"
         style="width:100%;background:var(--input);border:1px solid var(--kenar);color:var(--metin);border-radius:6px;padding:8px;font:inherit;margin-bottom:6px">
       <input id="sinavBaslik" placeholder="Sınav başlığı"
         style="width:100%;background:var(--input);border:1px solid var(--kenar);color:var(--metin);border-radius:6px;padding:8px;font:inherit;margin-bottom:8px">
       <label class="chk"><input type="checkbox" id="alanAd" checked> Adı Soyadı alanı</label>
       <label class="chk"><input type="checkbox" id="alanSinif" checked> Sınıf alanı</label>
       <label class="chk"><input type="checkbox" id="alanTarih" checked> Tarih alanı</label>
       <label class="chk"><input type="checkbox" id="yenidenNo" checked> Soruları 1'den numarala</label>
       <label class="chk"><input type="checkbox" id="cevapAnah"> Cevap anahtarı ekle</label>
       <label class="chk"><input type="checkbox" id="optikForm"> 🔘 Optik cevap kâğıdı da üret</label>
       <div class="satir" style="margin-top:6px"><span>Sütun</span>
         <select id="sinavSutun" style="background:var(--input);border:1px solid var(--kenar);color:var(--metin);border-radius:6px;padding:6px">
           <option value="2">2 sütun</option><option value="1">1 sütun</option></select></div>
       <div class="satir"><span>Toplam puan</span>
         <input type="number" id="sinavPuan" min="0" max="1000" placeholder="—" style="width:80px"></div>
       <div class="satir"><span>Kitapçık (A/B/C/D)</span>
         <select id="sinavKitapcik" style="background:var(--input);border:1px solid var(--kenar);color:var(--metin);border-radius:6px;padding:6px">
           <option value="1">1 (tek)</option><option value="2">2 (A-B)</option>
           <option value="3">3 (A-B-C)</option><option value="4">4 (A-B-C-D)</option></select></div>
       <div class="satir"><span>Her testten rastgele</span>
         <input type="number" id="sinavRast" min="0" max="200" placeholder="tümü" style="width:80px"></div>
       <button class="birincil" style="width:100%;margin-top:8px" onclick="sinavPdf()">📄 Sınav PDF'i Oluştur</button>
     </div>
   </details>
   <details class="kart" id="disaKart" style="display:none">
     <summary>Dışa Aktar</summary>
     <div>
       <div class="ipuc">Seçili (ya da tüm) soruları bilgisayara kaydet:</div>
       <div class="satir" style="gap:6px;margin-top:6px">
         <button class="ikincil" style="flex:1;padding:8px;font-size:12px" onclick="disaAktar('csv')">CSV</button>
         <button class="ikincil" style="flex:1;padding:8px;font-size:12px" onclick="disaAktar('html')">HTML</button>
         <button class="ikincil" style="flex:1;padding:8px;font-size:12px" onclick="disaAktar('md')">Markdown</button>
       </div>
       <div class="ipuc" style="margin-top:10px">📝 OCR ile düzenlenebilir belge (şekilsiz soru = metin, şekilli soru = şekil korunur):</div>
       <div class="satir" style="gap:6px;margin-top:6px">
         <button class="ikincil" style="flex:1;padding:8px;font-size:12px" onclick="disaAktar('docx')">Word (.docx)</button>
         <button class="ikincil" style="flex:1;padding:8px;font-size:12px" onclick="disaAktar('pdf-metin')">PDF (metin)</button>
       </div>
     </div>
   </details>
   <button class="kes" id="kesBtn" onclick="kes()" disabled>✅ Kes ve Kaydet →</button>
   <button class="ikincil" id="bankayaBtn" onclick="bankayaAktar()" disabled>➕ Soru Bankasına Aktar</button>
   <details class="kart" id="gecmisKart">
     <summary>🕘 Geçmiş</summary>
     <div id="gecmisListe"><div class="ipuc">Henüz kayıt yok.</div></div>
   </details>
 </aside>
 <section id="banka">
   <div id="bankaSol">
     <div class="kart">
       <h3>Filtreler</h3>
       <div id="bankaFiltre">
         <select id="bfKonu" onchange="bankaAra()"><option value="">Tüm konular</option></select>
         <select id="bfKaynak" onchange="bankaAra()"><option value="">Tüm kaynaklar</option></select>
         <select id="bfCevap" onchange="bankaAra()"><option value="">Tüm cevaplar</option>
           <option>A</option><option>B</option><option>C</option><option>D</option><option>E</option></select>
         <select id="bfZorluk" onchange="bankaAra()"><option value="">Tüm zorluklar</option>
           <option value="kolay">Kolay</option><option value="orta">Orta</option><option value="zor">Zor</option></select>
         <select id="bfBos" onchange="bankaAra()"><option value="">Cevaplı + cevapsız</option>
           <option value="dolu">Yalnız cevaplı</option><option value="bos">Yalnız cevapsız</option></select>
         <input id="bfEtiket" placeholder="🏷 etiket (örn. konu=zor)" oninput="bankaAraGecikmeli()">
         <input id="bfArama" placeholder="🔎 metinde ara" oninput="bankaAraGecikmeli()">
       </div>
       <div class="satir" style="margin-top:8px;flex-wrap:wrap">
         <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="bankaSepeteHepsi()">Sayfadakileri sepete</button>
         <input type="number" id="bfRastN" placeholder="N" style="width:56px;background:var(--input);border:1px solid var(--kenar);color:var(--metin);border-radius:6px;padding:6px">
         <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="bankaKonudanRastgele()">Filtreden N rastgele</button>
         <label class="chk" style="font-size:12px"><input type="checkbox" id="grupla" onchange="bankaGridCiz()"> Konuya göre grupla</label>
         <span id="bankaBilgi" class="ipuc" style="margin-left:auto"></span>
       </div>
       <div class="satir" style="margin-top:8px;flex-wrap:wrap;gap:6px">
         <button class="birincil" style="padding:6px 10px;font-size:12px" onclick="bankaAiEtiketle()">🤖 AI ile konu/başlık belirle</button>
         <select id="aiKapsam" style="width:auto;background:var(--input);border:1px solid var(--kenar);color:var(--metin);border-radius:6px;padding:6px;font-size:12px">
           <option value="filtre">filtredekiler</option>
           <option value="sepet">sepettekiler</option>
           <option value="tumu">tüm banka</option></select>
         <span id="aiDurum" class="ipuc"></span>
       </div>
       <details style="margin-top:6px"><summary style="cursor:pointer;font-size:12px;color:var(--sol)">⚙ AI Anahtarı (Gemini)</summary>
         <div class="satir" style="gap:6px;margin-top:6px">
           <input id="aiAnahtar" type="password" placeholder="Gemini API anahtarı" style="flex:1">
           <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="aiAnahtarKaydet()">Kaydet</button>
         </div>
       </details>
     </div>
     <div class="kart" id="yenidenKart" style="display:none">
       <h3>Yeniden İşleme Karşılaştırması</h3>
       <div id="yenidenOzet" class="ipuc"></div>
     </div>
     <div id="bankaGrid"><div class="ipuc">Yükleniyor…</div></div>
     <div class="gez" id="bankaGez">
       <button class="ikincil" onclick="bankaSayfa(-1)">◀</button>
       <span id="bankaGezEt">–</span>
       <button class="ikincil" onclick="bankaSayfa(1)">▶</button>
     </div>
   </div>
   <aside id="bankaSepet">
     <div class="kart">
       <h3>Sınav Sepeti (<span id="sepetSayi">0</span>)</h3>
       <div id="sepetListe"><div class="ipuc">Izgaradan soru seçin.</div></div>
       <button class="ikincil" style="width:100%;margin-top:6px;padding:6px;font-size:12px" onclick="sepetTemizle()">Sepeti temizle</button>
     </div>
     <details class="kart" open>
       <summary>Sınav Ayarları</summary>
       <div>
         <input id="bKurum" placeholder="Kurum / okul adı">
         <input id="bBaslik" placeholder="Sınav başlığı">
         <label class="chk"><input type="checkbox" id="bAlanAd" checked> Adı Soyadı alanı</label>
         <label class="chk"><input type="checkbox" id="bAlanSinif" checked> Sınıf alanı</label>
         <label class="chk"><input type="checkbox" id="bAlanTarih" checked> Tarih alanı</label>
         <label class="chk"><input type="checkbox" id="bYeniden" checked> Soruları 1'den numarala</label>
         <label class="chk"><input type="checkbox" id="bCevapAnah"> Cevap anahtarı ekle</label>
         <label class="chk"><input type="checkbox" id="bOptik"> 🔘 Optik cevap kâğıdı da üret</label>
         <div class="satir" style="margin-top:6px"><span>Sütun</span>
           <select id="bSutun" style="width:auto"><option value="2">2 sütun</option><option value="1">1 sütun</option></select></div>
         <div class="satir"><span>Toplam puan</span>
           <input type="number" id="bPuan" placeholder="—" style="width:80px;margin:0"></div>
         <div class="satir"><span>Kitapçık</span>
           <select id="bKitapcik" style="width:auto"><option value="1">1 (tek)</option>
             <option value="2">2 (A-B)</option><option value="3">3 (A-B-C)</option>
             <option value="4">4 (A-B-C-D)</option></select></div>
       </div>
     </details>
     <button class="birincil" onclick="bankaSinav('pdf')">📄 PDF Sınav Üret</button>
     <button class="birincil" onclick="bankaSinav('docx')">📝 Word Sınav Üret</button>
     <div class="ipuc">Word: şekilsiz sorular editlenebilir metin, şekilli sorular şekli korunur.</div>
   </aside>
 </section>
 <section id="sihirbaz">
   <div class="sh-stepper">
     <span class="adim" data-adim="1">1 · Kapsam</span>
     <span class="adim" data-adim="2">2 · Taslak (kota)</span>
     <span class="adim" data-adim="3">3 · Gözden geçir</span>
     <span class="adim" data-adim="4">4 · Ayarlar</span>
     <span class="adim" data-adim="5">5 · Çıktılar</span>
   </div>
   <!-- Adım 1: Kapsam -->
   <div class="sh-panel" data-panel="1">
     <h3>Kapsam — hangi havuzdan?</h3>
     <div class="satir"><span>Kaynak</span><select id="shKaynak"><option value="">(tümü)</option></select></div>
     <div class="satir"><span>Konu</span><select id="shKonu"><option value="">(tümü)</option></select></div>
     <div class="satir"><span>Tarih başı</span><input type="date" id="shTarihBas"></div>
     <div class="satir"><span>Tarih sonu</span><input type="date" id="shTarihSon"></div>
     <div class="satir"><span>Metin ara</span><input id="shArama" placeholder="fotosentez…"></div>
     <div class="ipuc" id="shHavuz">Havuz: —</div>
     <div class="sh-nav"><button onclick="shGit(2)">Devam →</button></div>
   </div>
   <!-- Adım 2: Blueprint matrisi -->
   <div class="sh-panel" data-panel="2">
     <h3>Taslak — konu × zorluk kotası</h3>
     <div class="ipuc">Her hücreye kaç soru istediğinizi yazın. "Stok" o hücrede bankada kaç soru olduğunu gösterir.</div>
     <table class="sh-matris" id="shMatris"></table>
     <div class="satir"><span>Tohum (tekrarlanabilirlik)</span><input id="shTohum" type="number" placeholder="ör. 42" style="width:90px"></div>
     <div id="shOzet" class="ipuc"></div>
     <div class="sh-nav">
       <button class="ikincil" onclick="shGit(1)">← Geri</button>
       <button class="ikincil" onclick="shDengeliDagit()">Dengeli dağıt</button>
       <button onclick="shOrnekle()">Örnekle →</button>
     </div>
   </div>
   <!-- Adım 3: Gözden geçirme -->
   <div class="sh-panel" data-panel="3">
     <h3>Gözden geçir — <span id="shSecimSayi">0</span> soru</h3>
     <div id="shKartlar"></div>
     <div class="sh-nav">
       <button class="ikincil" onclick="shGit(2)">← Geri</button>
       <button onclick="shGit(4)">Devam →</button>
     </div>
   </div>
   <!-- Adım 4: Ayarlar -->
   <div class="sh-panel" data-panel="4">
     <h3>Sınav ayarları</h3>
     <div class="satir"><span>Başlık</span><input id="shBaslik" placeholder="11. Sınıf Biyoloji Sınavı"></div>
     <div class="satir"><span>Kurum</span><input id="shKurum" placeholder="Okul adı"></div>
     <div class="satir"><span>Sütun</span><input id="shSutun" type="number" value="2" min="1" max="4" style="width:70px"></div>
     <div class="satir"><span>Kitapçık (A/B/…)</span><input id="shKitapcik" type="number" value="1" min="1" max="4" style="width:70px"></div>
     <div class="satir"><span>Toplam puan</span><input id="shPuan" type="number" placeholder="100" style="width:90px"></div>
     <label class="chk"><input type="checkbox" id="shYenidenNo" checked> Soruları 1'den numarala</label>
     <label class="chk"><input type="checkbox" id="shCevapAnah" checked> Cevap anahtarı sayfası</label>
     <div class="sh-nav">
       <button class="ikincil" onclick="shGit(3)">← Geri</button>
       <button onclick="shGit(5)">Devam →</button>
     </div>
   </div>
   <!-- Adım 5: Çıktılar -->
   <div class="sh-panel" data-panel="5">
     <h3>Çıktılar</h3>
     <label class="chk"><input type="checkbox" id="shCPdf" checked> Sınav PDF'i</label>
     <label class="chk"><input type="checkbox" id="shCDocx"> Word (.docx, editlenebilir)</label>
     <label class="chk"><input type="checkbox" id="shCOptik"> Optik form (baloncuk cevap kağıdı)</label>
     <div class="sh-nav">
       <button class="ikincil" onclick="shGit(4)">← Geri</button>
       <button onclick="shUret()">🖨 Üret ve İndir</button>
       <button class="ikincil" onclick="shSablonKaydet()">💾 Şablon kaydet</button>
     </div>
     <div id="shSonuc" class="ipuc" style="margin-top:12px"></div>
     <img id="shOnizleme" style="max-width:100%;margin-top:12px;border-radius:8px;display:none">
   </div>
 </section>
 <section id="optik">
  <div class="optik-nav">
    <button id="osekform" class="etkin" onclick="optikSekme('form')">📄 Formlar</button>
    <button id="osektara" onclick="optikSekme('tara')">📷 Tara</button>
    <button id="oseksonuc" onclick="optikSekme('sonuc')">🏆 Sonuçlar</button>
    <button id="osekincele" onclick="optikSekme('incele')">🔍 İncele</button>
    <button id="osekanaliz" onclick="optikSekme('analiz')">📈 Analiz</button>
    <span id="optikSinavEtiket" class="ipuc" style="margin-left:12px"></span>
    <span id="optikKurulum" class="ipuc" style="margin-left:auto"></span>
  </div>
  <div id="opform" class="optik-pane">
    <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-start">
      <div class="kart" style="flex:1;min-width:330px">
        <h3>Yeni Optik Form</h3>
        <div class="satir" style="gap:6px;flex-wrap:wrap;margin-top:8px">
          <select id="opOnAyar" onchange="optikOnAyarSec()" style="flex:1">
            <option value="">— boş form (elle tasarla) —</option></select>
        </div>
        <div class="satir" style="gap:6px;margin-top:8px">
          <input id="opAd" type="text" placeholder="Sınav adı" style="flex:2">
          <input id="opKurum" type="text" placeholder="Kurum (isteğe bağlı)" style="flex:2">
        </div>
        <div class="satir" style="gap:10px;margin-top:8px;flex-wrap:wrap;font-size:12.5px">
          <label>Kitapçık <select id="opKitapcik"><option>1</option><option selected>2</option>
            <option>3</option><option>4</option></select></label>
          <label>Öğr. no hane <select id="opNoHane"><option>0</option><option>4</option>
            <option selected>5</option><option>6</option></select></label>
          <label class="chk"><input type="checkbox" id="opTc"> TC Kimlik</label>
          <label class="chk"><input type="checkbox" id="opAdSoyad" checked> Ad-Soyad grid</label>
          <label>Yanlış <select id="opBolen"><option value="0">götürmez</option>
            <option value="3">3 Y → 1 D (LGS)</option><option value="4">4 Y → 1 D (YKS)</option></select></label>
        </div>
        <div id="opDersler" style="margin-top:6px"></div>
        <div class="satir" style="gap:6px;margin-top:8px">
          <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="optikDersEkle()">+ Ders/bölüm ekle</button>
          <button class="birincil" style="margin-left:auto" onclick="optikUret()">📄 PDF Üret ve İndir</button>
        </div>
        <div id="opUretDurum" class="ipuc" style="margin-top:6px"></div>
      </div>
      <div class="kart" style="flex:1.4;min-width:380px">
        <h3>Sınavlar</h3>
        <div style="overflow:auto;max-height:430px"><table id="opSinavTablo">
          <thead><tr><th>Ad</th><th>Kimlik</th><th>Kağıt</th><th>Kuyruk</th>
            <th>Anahtar</th><th>Oluşturma</th></tr></thead><tbody></tbody></table></div>
        <div class="ipuc" style="margin-top:6px">Bir sınava tıklayın → Tara/Sonuçlar/İncele o sınav üzerinde çalışır.</div>
      </div>
    </div>
  </div>
  <div id="optara" class="optik-pane" style="display:none">
    <div class="kart">
      <h3>Taramaları Yükle ve Oku</h3>
      <div id="opBirakma" style="border:2px dashed var(--kenar);border-radius:10px;padding:34px;
        text-align:center;cursor:pointer" onclick="$('opTaraInput').click()">
        Telefon fotoğraflarını veya tarayıcı PDF'ini buraya bırakın<br>ya da tıklayıp seçin
        <input id="opTaraInput" type="file" hidden multiple
          accept=".png,.jpg,.jpeg,.pdf,.tif,.tiff,.bmp,.webp,.heic"
          onchange="optikDosyalar([...this.files]); this.value=''">
      </div>
      <div id="opTaraDurum" class="ipuc" style="margin-top:8px"></div>
    </div>
  </div>
  <div id="opsonuc" class="optik-pane" style="display:none">
    <div class="kart">
      <h3>Cevap Anahtarı</h3>
      <div class="satir" style="gap:6px;flex-wrap:wrap">
        <label>Kitapçık <select id="opAnahtarKitapcik"></select></label>
        <span class="ipuc" id="opAnahtarDurum"></span>
      </div>
      <textarea id="opAnahtarMetin" rows="3" style="width:100%;margin-top:6px;font-family:monospace"
        placeholder="Tek bölüm: ABCDABCD…   Çok dersli: her satıra Ders=ABCD…  (nokta = iptal soru)"></textarea>
      <div class="satir" style="gap:6px;margin-top:6px">
        <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="optikAnahtarKaydet()">Anahtarı Kaydet</button>
        <span class="ipuc">veya İncele sekmesinde bir kağıdı açıp “Bu kağıdı anahtar yap”.</span>
      </div>
    </div>
    <div class="kart">
      <div class="satir" style="gap:6px;flex-wrap:wrap">
        <h3 style="margin-right:auto">Sonuçlar</h3>
        <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="optikDisa('csv')">CSV</button>
        <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="optikDisa('txt')">Optik TXT</button>
        <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="optikDisa('eokul')">e-Okul</button>
        <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="optikDisa('karne')">Karne PDF</button>
      </div>
      <div style="overflow:auto;max-height:520px"><table id="opSonucTablo">
        <thead></thead><tbody></tbody></table></div>
    </div>
  </div>
  <div id="opincele" class="optik-pane" style="display:none">
    <div style="display:flex;gap:14px;min-height:0;flex:1">
      <div class="kart" style="width:330px;overflow:auto">
        <div class="satir"><h3 style="margin-right:auto">Kağıtlar</h3>
          <label class="chk" style="font-size:12px"><input type="checkbox" id="opSadeceKuyruk"
            checked onchange="optikKagitlarYukle()"> yalnız incelenecekler</label></div>
        <table id="opKagitTablo"><tbody></tbody></table>
      </div>
      <div class="kart" style="flex:1;overflow:auto">
        <div class="satir" style="gap:6px;flex-wrap:wrap" id="opKagitBaslik"></div>
        <div class="satir" style="gap:6px;margin:6px 0;flex-wrap:wrap" id="opKagitDuzelt" hidden>
          <input id="opDuzNo" type="text" placeholder="öğrenci no" style="width:110px">
          <input id="opDuzAd" type="text" placeholder="ad soyad" style="width:170px">
          <select id="opDuzKitapcik"></select>
          <button class="ikincil" style="padding:5px 9px;font-size:12px" onclick="optikKimlikDuzelt()">Kimliği Kaydet</button>
          <button class="ikincil" style="padding:5px 9px;font-size:12px" onclick="optikKagidiAnahtarYap()">Bu kağıdı anahtar yap</button>
        </div>
        <div id="opWarpKutu"><img id="opWarp" alt="" onload="optikOverlayCiz()">
          <div id="opOverlay" style="position:absolute;inset:0"></div></div>
        <div class="ipuc" style="margin-top:6px">Balona tıkla → cevabı o şık yap · işaretli balona tıkla → boşa çevir.
          Kırmızı halka = belirsiz/çoklu.</div>
      </div>
    </div>
  </div>
  <div id="opanaliz" class="optik-pane" style="display:none">
    <div class="kart"><div class="satir" style="gap:8px;flex-wrap:wrap">
      <h3 style="margin-right:auto">Madde Analizi</h3>
      <span id="opTestOzet" class="ipuc"></span></div>
      <div style="overflow:auto;max-height:420px"><table id="opAnalizTablo">
        <thead><tr><th>Ders</th><th>Soru</th><th>Doğru</th><th>p</th><th>Ayırt</th>
          <th>r-pb</th><th>Dağılım</th><th>Uyarı</th></tr></thead><tbody></tbody></table></div>
    </div>
    <div class="kart"><h3>Kazanım Analizi</h3>
      <div class="satir" style="gap:6px;flex-wrap:wrap;margin-top:6px">
        <input id="opKazanimDosya" type="file" accept=".csv" style="font-size:12px">
        <button class="ikincil" style="padding:6px 10px;font-size:12px" onclick="optikKazanimYukle()">CSV Yükle (ders;soru;kazanim)</button>
      </div>
      <div id="opKazanimListe" style="margin-top:8px"></div>
    </div>
  </div>
 </section>
 <section id="dashboard">
   <h2 class="dash-baslik">📊 Soru Bankası Paneli</h2>
   <div class="stat-grid" id="statGrid"></div>
   <div class="chart-grid" id="chartGrid"></div>
   <div class="chart" id="aktiviteKart" style="max-width:640px">
     <h4>Son aktivite</h4><div id="aktiviteListe"></div>
   </div>
 </section>
</main>
<div class="lightbox" id="lightbox" onclick="lightboxKapat()"><img id="lightboxImg" alt=""></div>
<div class="galeri-overlay" id="galeriOverlay" onclick="galeriKapat()">
  <div class="galeri-panel" onclick="event.stopPropagation()">
    <div class="galeri-baslik"><h3>Seçimi Gözden Geçir</h3>
      <button class="ikincil" onclick="galeriKapat()">✕ Kapat</button></div>
    <div class="galeri-izgara" id="galeriIzgara"></div>
  </div>
</div>
<div id="toastAlan" role="status" aria-live="polite"></div>
<footer role="status" aria-live="polite"><div class="spin" id="spin"></div>
  <span id="durum">Hazır.</span>
  <div class="ilerleme-yol" id="ilerlemeYol" aria-label="İşlem ilerlemesi">
    <span class="ilerleme-ray"><span class="ilerleme-dolgu" id="ilerlemeDolgu"></span></span>
    <span class="ilerleme-yuzde" id="ilerlemeYuzde">0%</span>
  </div></footer>
<script>
let sayfa=0, toplamSayfa=0;
let olcek=1, sayfaGen=0, sayfaYuk=0;        // page→PNG ölçeği ve sayfa boyutu
let kutular=[], kutuMeta=[], secili=new Set(), cizModu=false, bolModu=false, kaydetZaman=null;
let kutuDivleri=[];                         // cizKutular'ın yarattığı .kutu div'leri (artımlı stil güncellemesi için)
let geriYigin=[], ileriYigin=[];            // belge-geneli geri al/yinele: {sayfa, once, sonra}
const UNDO_SINIR=100;
const MIN_BOL_YUKSEKLIK=24;   // bundan ince kutularda 8px kenar payı clamp'i tersine döner (bkz. bolAc)
let yakZoom=1, fitGen=0;                    // genişlik-tabanlı zoom (1=fit); fitGen=ilk zoomda kaydedilen clientWidth
let spaceBasili=false;                      // space+sürükle pan bayrağı
let kaydetBekleyen=null, kaydetKuyruk=Promise.resolve(true), kutuRev=0;
let mod='duzenle';                          // 'duzenle' | 'sec'
let kesSecim=new Set();                     // seçili soru KİMLİKLERİ
let kesSecimModu='all', belgeHazir=false;    // null=tümü, []=hiçbiri, dolu=açık seçim
let ozet=null, kutuKimlik={};               // /ozet verisi ve "si:ki"→kimlik
let kalibrasyon=null, incelemeSayfalari=[], incelemeModu=false, sayfaInceleme=null;
let galeriAcik=false;                       // galeri overlay açıkken arka plan kısayolları susar
let aralikZaman=null;
let yuklemeKayitlari=[], dosyaYukleniyor=false;
// soru bankası görünümü durumu
let bankaKayitlar=[], bankaSepet=[], bankaSecili=new Set();  // sepet=SIRALI id
let bankaOfset=0, bankaLimit=60, bankaToplam=0, bankaAramaZaman=null, bankaYuklendi=false;
const $=id=>document.getElementById(id);
function ilerlemeAyarla(yapilan,toplam){
  const yol=$('ilerlemeYol'), dolgu=$('ilerlemeDolgu'), yazi=$('ilerlemeYuzde');
  if(!yol||!dolgu||!yazi) return;
  const oran=toplam>0?Math.max(0,Math.min(1,yapilan/toplam)):0;
  yol.classList.add('acik'); dolgu.style.width=Math.round(oran*100)+'%';
  yazi.textContent=Math.round(oran*100)+'%';
}
function ilerlemeGizle(){ const y=$('ilerlemeYol'); if(y)y.classList.remove('acik'); }
function durum(t,mesgul){
  $('durum').textContent=t; $('spin').style.display=mesgul?'block':'none';
  if(!mesgul) ilerlemeGizle();
}
// olay bildirimi (footer #durum sürekli durumu anlatır; toast yalnız tekil olayları duyurur)
function toastGoster(mesaj,tur='bilgi'){
  const alan=$('toastAlan'); if(!alan) return;
  tur=tur==='basari'||tur==='hata'?tur:'bilgi';
  while(alan.children.length>=4) alan.firstElementChild.remove();
  const el=document.createElement('div'); el.className='toast '+tur; el.textContent=mesaj;
  el.addEventListener('click',()=>el.remove());
  alan.appendChild(el);
  setTimeout(()=>el.remove(),tur==='hata'?8000:4000);
}
async function post(u,g){ const r=await fetch(u,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(g||{})}); return r.json(); }
function indirBaslat(jeton,ad){ if(!jeton) return;
  const a=document.createElement('a'); a.href='/indir?jeton='+encodeURIComponent(jeton);
  if(ad) a.download=ad; document.body.appendChild(a); a.click(); a.remove(); }
async function jget(u){ return (await fetch(u)).json(); }
function htmlKacir(v){ return String(v??'').replace(/[&<>"']/g,c=>
  ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]); }
// page koordinatı ↔ ekran pikseli (CSS ölçeği dahil)
function ekranOlcek(){ const g=$('gorsel'); return g.naturalWidth ? olcek*(g.clientWidth/g.naturalWidth) : olcek; }
// elemanın GERÇEKTEN görünür olup olmadığı (kendi ya da bir üst öğesi display:none ise
// offsetParent null döner) — id'nin kendi inline style'ına bakmak yeterli değil, çünkü
// sekme değişince yalnız üst kapsayıcı (#kesimAside/#onizleme) gizlenir, iç kart'ların
// kendi inline display'i olduğu gibi kalır (bkz. gorunumAyarla).
function gorunurMu(id){ const el=$(id); return !!(el && el.offsetParent); }

const DOSYA_UZANTILARI=new Set(['pdf','docx','png','jpg','jpeg','tif','tiff','bmp','webp','gif']);
const DOSYA_MAKS=400*1024*1024;
function dosyaSec(){
  const g=$('dosyaInput'); g.value=''; g.click();
}
async function dosyaInputDegisti(e){ await dosyalariYukle(e.target.files); e.target.value=''; }
function dosyaUzantisi(ad){ const p=(ad||'').split('.'); return p.length>1?p.pop().toLocaleLowerCase('tr-TR'):''; }
function dosyaListesiCiz(){
  const l=$('dosyalar'); l.replaceChildren();
  yuklemeKayitlari.forEach(k=>{
    const sat=document.createElement('div'); sat.className='dosya-satir';
    const ad=document.createElement('span'); ad.className='dosya-ad'; ad.textContent=k.ad;
    const ds=document.createElement('span'); ds.className='dosya-durum '+(k.durum||'');
    ds.textContent=k.durum==='tamam'?'✓ Hazır':k.durum==='hata'?'⚠ '+k.hata:
      k.durum==='yukleniyor'?`Yükleniyor %${k.yuzde||0}`:'Bekliyor';
    const ray=document.createElement('span'); ray.className='dosya-ilerleme';
    const dolgu=document.createElement('span'); dolgu.style.width=(k.yuzde||0)+'%'; ray.appendChild(dolgu);
    sat.append(ad,ds,ray); l.appendChild(sat);
  });
}
function hamDosyaYukle(dosya,ilerleme){
  return new Promise((coz,reject)=>{
    const x=new XMLHttpRequest();
    x.open('POST','/yukle-dosya?ad='+encodeURIComponent(dosya.name));
    x.upload.onprogress=e=>{ if(e.lengthComputable) ilerleme(Math.round(e.loaded/e.total*100)); };
    x.onerror=()=>reject(new Error('bağlantı kurulamadı'));
    x.onload=()=>{
      let j={}; try{ j=JSON.parse(x.responseText||'{}'); }catch(e){}
      if(x.status>=200&&x.status<300&&j.yol) coz(j.yol);
      else reject(new Error(j.hata||`yükleme başarısız (HTTP ${x.status})`));
    };
    x.send(dosya);
  });
}
async function dosyalariYukle(dosyaListesi){
  const dosyalar=[...dosyaListesi]; if(!dosyalar.length) return;
  if(dosyaYukleniyor){ durum('Bir dosya yüklemesi zaten sürüyor.',true); return; }
  dosyaYukleniyor=true; $('secBtn').disabled=true;
  try{
  belgeHazir=false; kesSecimModu='all'; kesSecim.clear();
  $('onizleBtn').disabled=true; $('kesBtn').disabled=true; $('bankayaBtn').disabled=true;
  yuklemeKayitlari=dosyalar.map(f=>({ad:f.name,durum:'bekliyor',yuzde:0}));
  dosyalariAyarla([],true); dosyaListesiCiz();
  durum(`${dosyalar.length} dosya yükleniyor…`,true);
  const yollar=[];
  for(let i=0;i<dosyalar.length;i++){
    const f=dosyalar[i], k=yuklemeKayitlari[i], uz=dosyaUzantisi(f.name);
    if(!DOSYA_UZANTILARI.has(uz)){
      k.durum='hata'; k.hata='desteklenmeyen format'; dosyaListesiCiz(); continue;
    }
    if(f.size<=0||f.size>DOSYA_MAKS){
      k.durum='hata'; k.hata=f.size<=0?'dosya boş':'400 MB sınırını aşıyor';
      dosyaListesiCiz(); continue;
    }
    k.durum='yukleniyor'; dosyaListesiCiz();
    try{
      k.yol=await hamDosyaYukle(f,p=>{k.yuzde=p; dosyaListesiCiz();});
      k.yuzde=100; k.durum='tamam'; yollar.push(k.yol);
    }catch(e){ k.durum='hata'; k.hata=e.message||String(e); }
    dosyaListesiCiz();
  }
  if(yollar.length) dosyalariAyarla(yollar,true);
  else $('dosyalar').dataset.yollar='[]';
  const hata=yuklemeKayitlari.filter(k=>k.durum==='hata').length;
  if(hata) durum(`${yollar.length} dosya hazır · ${hata} dosya yüklenemedi (ayrıntı listede).`,false);
  else durum(`${yollar.length} dosya hazır. Ön İzle ile tespiti başlatın.`,false);
  }finally{ dosyaYukleniyor=false; $('secBtn').disabled=false; }
}
function dosyalariAyarla(yollar,listeyiKoru=false){
  if(!listeyiKoru){
    yuklemeKayitlari=yollar.map(y=>({ad:y.split(/[\\/]/).pop(),durum:'tamam',yuzde:100,yol:y}));
    dosyaListesiCiz();
  }
  $('dosyalar').dataset.yollar=JSON.stringify(yollar);
  $('onizleBtn').disabled=!yollar.length; $('kesBtn').disabled=true; $('bankayaBtn').disabled=true;
  belgeHazir=false; kesSecimModu='all'; kesSecim.clear();
  kalibrasyon=null; incelemeSayfalari=[]; incelemeModu=false; kutuMeta=[]; sayfaInceleme=null;
  geriYigin=[]; ileriYigin=[]; undoButonTazele();
  yakZoom=1; fitGen=0; $('gorsel').style.maxWidth=''; $('gorsel').style.width=''; zoomEtiketTazele();
  $('ozet').style.display='none'; $('kalibrasyonKart').style.display='none'; $('gez').style.display='none';
  $('modAnahtar').style.display='none'; $('duzenKart').style.display='none';
  $('secimKart').style.display='none'; $('sinavKart').style.display='none'; $('disaKart').style.display='none';
  mod='duzenle'; $('modDuzen').classList.add('etkin'); $('modSec').classList.remove('etkin');
  $('sahne').classList.remove('sec-modu');
  $('sahne').style.display='none'; $('bos').style.display='block';
}
function formatEtiketi(f){ return ({coktan_secmeli:'çoktan seçmeli',acik_uclu:'açık uçlu',
  cozumlu:'çözümlü',konu_anlatimi:'konu anlatımı',karisik:'karışık',slayt:'slayt'})[f]||f; }
function dagilimYaz(d){ return Object.entries(d||{}).filter(([,n])=>n)
  .map(([k,n])=>`${htmlKacir(k.replaceAll('_',' '))}: <b>${n}</b>`).join(' · ')||'—'; }
function kalibrasyonCiz(k){
  kalibrasyon=k||{aktif:false,durumlar:{}}; const kart=$('kalibrasyonKart'), alan=$('kalibrasyonOzet');
  kart.style.display='block'; const d=kalibrasyon.durumlar||{}, dz=kalibrasyon.duzen||{};
  if(!kalibrasyon.aktif){
    alan.innerHTML='<div>Eski tespit motoru kullanılıyor.</div>'+(
      kalibrasyon.hata?`<div style="color:var(--uyari)">⚠ ${htmlKacir(kalibrasyon.hata)}</div>`:'');
  }else{
    alan.innerHTML=`<div class="kalibrasyon-sayac">
      <span class="oto">${d.otomatik||0} Otomatik</span>
      <span class="inc">${d.incele||0} İncele</span>
      <span class="red">${d.reddedildi||0} Reddedildi</span></div>
      <div>Sayfalar: ${dagilimYaz(kalibrasyon.sayfa_rolleri)}</div>
      <div>Soru türleri: ${dagilimYaz(kalibrasyon.soru_turleri)}</div>
      <div style="margin-top:5px">Sütun güveni: <b>${dz.ortalama==null?'—':Math.round(dz.ortalama*100)+'%'}</b>
        · en düşük: <b>${dz.en_dusuk==null?'—':Math.round(dz.en_dusuk*100)+'%'}</b>
        · düşük sayfa: <b>${dz.dusuk_sayfa||0}</b></div>
      <div>Düzen: ${dz.bolgesel_gecis||0} geçişli · ${dz.egik_sayfa||0} eğik
        · yöntemler: ${htmlKacir((dz.yontemler||[]).map(x=>x.replaceAll('_',' ')).join(', ')||'—')}</div>`;
  }
  const bek=kalibrasyon.bekleyen_sayfa??d.bekleyen??0, b=$('incelemeBtn');
  b.disabled=!(kalibrasyon.inceleme_aktif??kalibrasyon.aktif)||!bek;
  b.textContent=bek?(incelemeModu?`← Tüm sayfalara dön (${bek} bekliyor)`:
    `⚠ Yalnız inceleme sayfaları (${bek} sayfa)`):'✓ İnceleme tamamlandı';
}
async function incelemeYukle(){
  const r=await jget('/inceleme'); incelemeSayfalari=r.sayfalar||[];
  if(kalibrasyon){ kalibrasyon.durumlar=kalibrasyon.durumlar||{};
    kalibrasyon.durumlar.bekleyen=r.bekleyen||0;
    kalibrasyon.bekleyen_sayfa=r.bekleyen_sayfa||0; kalibrasyonCiz(kalibrasyon); }
  return r;
}
async function kalibrasyonYukle(){ kalibrasyon=await jget('/kalibrasyon'); kalibrasyonCiz(kalibrasyon); }
async function incelemeModuDegis(){
  if(incelemeModu){ incelemeModu=false; kalibrasyonCiz(kalibrasyon); return; }
  const r=await incelemeYukle();
  if(!r.sayfalar.length){ durum('İncelenecek sayfa kalmadı.',false); return; }
  if(!(await kaydetSimdi())) return;
  incelemeModu=true; sayfa=r.sayfalar.includes(sayfa)?sayfa:r.sayfalar[0];
  kalibrasyonCiz(kalibrasyon); await gosterSayfa();
  durum(`İnceleme modu: ${r.sayfa_adet} sayfa. Kanıtları inceleyip sayfayı onaylayın, soru yok deyin veya kutuyu düzeltin.`,false);
}
async function onizle(){
  const yollar=JSON.parse($('dosyalar').dataset.yollar||'[]'); if(!yollar.length) return;
  if(!(await kaydetSimdi())) return;
  belgeHazir=false; secimSayaci();
  durum('Dosyalar okunuyor ve kalibre ediliyor… (taranmışsa OCR sürebilir)',true);
  ilerlemeAyarla(0,1); islemYokla();
  $('onizleBtn').disabled=true; $('secBtn').disabled=true;
  try{
    const r=await post('/yukle',{yollar:yollar,dpi:+$('dpi').value});
    if(r.hata){ durum('Hata: '+r.hata,false); return; }
    toplamSayfa=r.sayfa; sayfa=0;
    geriYigin=[]; ileriYigin=[]; undoButonTazele();
    const testMet = r.test_sayisi ? `<b>${r.test_sayisi}</b> test · ` : '';
    $('ozet').style.display='block';
    $('ozet').innerHTML=`<h3>Tespit</h3>
      <div><b>${r.sayfa}</b> sayfa · <b>${r.sutun}</b> sütun</div>
      <div>${r.mod} · ${formatEtiketi(r.format)}</div>
      <div>${testMet}Toplam <b id="toplamSoru">${r.toplam}</b> soru bulundu</div>
      ${r.uyari?`<div style="color:#eab308;margin-top:4px">⚠ ${htmlKacir(r.uyari)}</div>`:''}`;
    kalibrasyonCiz(r.kalibrasyon);
    $('gez').style.display='flex'; $('modAnahtar').style.display='grid';
    $('duzenKart').style.display='block';
    $('sinavKart').style.display='block'; $('disaKart').style.display='block';
    $('bos').style.display='none'; $('sahne').style.display='inline-block';
    kesSecim.clear(); kesSecimModu='all';
    await ozetYukle();
    await gosterSayfa();
    await incelemeYukle();
    belgeHazir=true; secimSayaci();
    const bek=(kalibrasyon?.bekleyen_sayfa||0);
    durum(r.toplam?`${r.toplam} soru tespit edildi.${bek?` ${bek} sayfa inceleme bekliyor.`:''} Kutuları düzelt ya da 'Seç' moduyla seçip kes.`:
      (bek?`Hiç soru tespit edilmedi; ${bek} riskli sayfa inceleme bekliyor.`:
       'Hiç soru tespit edilmedi. Düzenle modunda kutu ekleyin.'),false);
  }catch(e){ durum('Hata: '+e,false); }
  finally{
    durdurYokla(); $('onizleBtn').disabled=false; $('secBtn').disabled=false; secimSayaci();
  }
}
// --- test özeti + seçim modeli ---
async function ozetYukle(){
  ozet=await jget('/ozet'); kutuKimlik=ozet.kutu_kimlik||{};
  // düzenleme sonrası: hâlâ var olan kimlikleri koru, yetimleri düş
  const gecerli=new Set(); (ozet.testler||[]).forEach(t=>t.sorular.forEach(s=>gecerli.add(s.kimlik)));
  Object.values(kutuKimlik).forEach(k=>gecerli.add(k));
  if(kesSecimModu==='explicit') kesSecim=new Set([...kesSecim].filter(k=>gecerli.has(k)));
  $('cevapAnah').disabled=!ozet.cevapli;
  $('cevapBandi').disabled=!ozet.cevapli;
  $('cevapBandiSatir').style.opacity=ozet.cevapli?'1':'0.55';
  $('cozumIlistirSatir').style.display=ozet.cozumlu?'':'none';
  testListeCiz(); secimSayaci();
}
function tumKimlikler(){
  const s=new Set(Object.values(kutuKimlik||{}));
  (ozet?.testler||[]).forEach(t=>t.sorular.forEach(q=>s.add(q.kimlik)));
  return [...s];
}
function secimKimligiVar(k){ return kesSecimModu==='all'||kesSecim.has(k); }
function secimKimlikleri(){ return kesSecimModu==='all'?tumKimlikler():[...kesSecim]; }
function secimiAcigaCevir(){
  if(kesSecimModu==='all'){ kesSecim=new Set(tumKimlikler()); kesSecimModu='explicit'; }
}
function secimVarMi(){ return belgeHazir&&(kesSecimModu==='all'?tumKimlikler().length>0:kesSecim.size>0); }
function secimHepsiMi(){
  const tum=tumKimlikler(); return tum.length>0&&(kesSecimModu==='all'||kesSecim.size===tum.length);
}
function testListeCiz(){
  const l=$('testListe');
  if(!ozet||!ozet.testler.length){ l.innerHTML='<div class="ipuc">Test bölümü yok — kutulara tıklayarak ya da sıra (27-40) yazarak seçin.</div>'; return; }
  l.innerHTML=ozet.testler.map((t,i)=>{
    const ad=t.test_no!=null?`Test ${t.test_no}`:'(numarasız)';
    const soru=t.soru_bas!=null?`${t.soru_bas}–${t.soru_son}`:'—';
    return `<label class="test-satir"><input type="checkbox" data-t="${i}" onchange="testTikla(${i},this.checked)">
      <span>${ad}</span><span class="adet">${soru} · ${t.adet} soru</span></label>`;
  }).join('');
  testKutulariGuncelle();
}
function testTikla(i,ac){
  if(kesSecimModu==='all'&&ac) return;
  secimiAcigaCevir();
  ozet.testler[i].sorular.forEach(s=>{ if(ac) kesSecim.add(s.kimlik); else kesSecim.delete(s.kimlik); });
  cizKutular(); secimSayaci();
}
function testKutulariGuncelle(){   // üçlü durum checkbox'lar
  if(!ozet) return;
  ozet.testler.forEach((t,i)=>{
    const cb=$('testListe').querySelector(`[data-t="${i}"]`); if(!cb) return;
    const secen=t.sorular.filter(s=>secimKimligiVar(s.kimlik)).length;
    cb.checked=secen===t.sorular.length&&secen>0;
    cb.indeterminate=secen>0&&secen<t.sorular.length;
  });
}
function secimSayaci(){
  const n=kesSecimModu==='all'?tumKimlikler().length:kesSecim.size;
  $('secimSayi').textContent=kesSecimModu==='all'?`tümü (${n})`:n;
  $('kesBtn').textContent=kesSecimModu==='all'?`✅ Kes ve Kaydet (tümü: ${n}) →`:
    n?`✅ Kes ve Kaydet (${n} soru) →`:'✅ Kes ve Kaydet (seçim yok)';
  $('kesBtn').disabled=!secimVarMi(); $('bankayaBtn').disabled=!secimVarMi();
  testKutulariGuncelle();
}
function tumunuSec(hepsi){
  kesSecim.clear(); kesSecimModu=hepsi?'all':'explicit';
  $('aralik').value=''; $('aralikCanli').textContent='';
  cizKutular(); secimSayaci();
}
function soruSecTog(i){
  const kml=kutuKimlik[sayfa+':'+i]; if(!kml) return;
  secimiAcigaCevir();
  if(kesSecim.has(kml)) kesSecim.delete(kml); else kesSecim.add(kml);
  cizKutular(); secimSayaci();
}
// --- kesim seçim anlık görüntüsü (galeriCikar'ın geri al yığınına tek adım olarak girmesi için) ---
function secimSnapshot(){ return {mod:kesSecimModu, kumesi:kesSecimModu==='all'?null:[...kesSecim]}; }
function secimSnapshotUygula(sn){
  kesSecimModu=sn.mod; kesSecim=sn.mod==='all'?new Set():new Set(sn.kumesi||[]);
}
// --- galeri (5.6): kesime dahil seçili soruların küçük resimlerle gözden geçirilmesi ---
function galeriKimlikListesi(){ return kesSecimModu==='all'?tumKimlikler():[...kesSecim]; }
function galeriIzgaraCiz(){
  const izgara=$('galeriIzgara'); if(!izgara) return;
  const kimlikler=galeriKimlikListesi();
  if(!kimlikler.length){ izgara.innerHTML='<div class="ipuc">Seçili soru yok.</div>'; return; }
  const yerler={};   // kimlik → {sayfa,kutu} (soru-onizleme için, mevcut kırpma uç noktası)
  Object.entries(kutuKimlik).forEach(([sk,kml])=>{
    const [si,ki]=sk.split(':').map(Number); yerler[kml]={sayfa:si,kutu:ki};
  });
  izgara.innerHTML=kimlikler.map(kml=>{
    const yer=yerler[kml];
    const etiket=htmlKacir(ozet?ozetEtiket(kml):'?');
    const sayfaMet=yer?`Sayfa ${yer.sayfa+1}`:'—';
    const resim=yer?`<img src="/soru-onizleme?sayfa=${yer.sayfa}&kutu=${yer.kutu}&t=${Date.now()}"
        alt="" onerror="this.style.opacity='.15'">`:
      '<div class="ipuc" style="padding:30px 6px;text-align:center">Önizleme yok</div>';
    return `<div class="galeri-kart" data-kimlik="${htmlKacir(kml)}">${resim}
      <div class="alt"><span>${etiket} · ${sayfaMet}</span>
        <button class="cikar" title="Kesim seçiminden çıkar">✕ Çıkar</button></div>
    </div>`;
  }).join('');
}
// kart butonuna inline click-handler basmak YERİNE olay delegasyonu: kimlik hash'i
// htmlKacir'dan geçse bile (ör. içinde apostrof olsaydı) inline JS string bağlamında
// &#39; HTML ayrıştırıcı tarafından gerçek ' karakterine geri çözülüp bir string
// literalini erken kapatabilirdi — dataset okuma böyle bir bağlam karışıklığı taşımaz.
$('galeriIzgara').addEventListener('click',e=>{
  const btn=e.target.closest('.cikar'); if(!btn) return;
  const kart=btn.closest('.galeri-kart'); if(!kart) return;
  galeriCikar(kart.dataset.kimlik);
});
async function galeriAc(){
  if(!secimVarMi()){ toastGoster('Gözden geçirmek için en az bir soru seçin.','bilgi'); return; }
  if(!(await kaydetSimdi())) return;
  galeriIzgaraCiz();
  $('galeriOverlay').classList.add('acik'); galeriAcik=true;
}
function galeriKapat(){ $('galeriOverlay').classList.remove('acik'); galeriAcik=false; }
function galeriCikar(kml){
  const once=secimSnapshot();
  secimiAcigaCevir(); kesSecim.delete(kml);
  undoPush(null,once,secimSnapshot(),'secim');
  cizKutular(); secimSayaci();
  if(galeriAcik) galeriIzgaraCiz();
}
function aralikDegis(){
  clearTimeout(aralikZaman);
  aralikZaman=setTimeout(async()=>{
    const metin=$('aralik').value.trim();
    if(!metin){ $('aralikCanli').textContent=''; return; }
    const r=await post('/secim-coz',{metin});
    const c=$('aralikCanli');
    if(r.hata){ c.className='canli uyari'; c.textContent='⚠ '+r.hata; return; }
    kesSecim=new Set(r.kimlikler); kesSecimModu='explicit';
    c.className=r.adet?'canli':'canli uyari'; c.textContent=`${r.adet} soru eşleşti`+
      (r.eslesmeyen&&r.eslesmeyen.length?' · '+r.eslesmeyen.length+' uyarı':'');
    cizKutular(); secimSayaci();
  },400);
}
let aramaZaman=null;
function aramaDegis(){
  clearTimeout(aramaZaman);
  aramaZaman=setTimeout(async()=>{
    const metin=$('ara').value.trim();
    if(!metin){ $('aramaCanli').textContent=''; return; }
    const r=await post('/ara',{metin});
    kesSecim=new Set(r.kimlikler); kesSecimModu='explicit';
    $('aramaCanli').className=r.adet?'canli':'canli uyari';
    $('aramaCanli').textContent=`${r.adet} soru bulundu (seçildi)`;
    cizKutular(); secimSayaci();
  },400);
}
async function cevapDuzelt(cevap){
  const kimlikler=secimKimlikleri();
  const c=$('cevapCanli');
  if(!kimlikler.length){ c.className='canli uyari';
    c.textContent='⚠ en az bir seçili soru gerekli'; return; }
  const govde=cevap===null?{kimlikler,geri_al:true}:{kimlikler,cevap};
  const r=await post('/cevap-duzelt',govde);
  if(r.hata){ c.className='canli uyari'; c.textContent='⚠ '+r.hata; return; }
  c.className='canli';
  c.textContent=cevap===null?`${r.duzeltilen} soru otomatik eşlemeye döndü`:
    cevap?`${r.duzeltilen} sorunun cevabı ${cevap} yapıldı`:
    `${r.duzeltilen} sorunun cevabı silindi`;
  await ozetYukle();
}
async function etiketAta(){
  const anahtar=$('etAnahtar').value.trim(), deger=$('etDeger').value.trim();
  const kimlikler=secimKimlikleri();
  if(!anahtar||!kimlikler.length){ $('etiketCanli').className='canli uyari';
    $('etiketCanli').textContent='⚠ anahtar ve en az bir seçili soru gerekli'; return; }
  const r=await post('/etiket',{kimlikler,anahtar,deger});
  if(r.hata){ $('etiketCanli').className='canli uyari'; $('etiketCanli').textContent='⚠ '+r.hata; return; }
  $('etiketCanli').className='canli';
  $('etiketCanli').textContent=`${r.etiketlenen} soruya "${anahtar}${deger?': '+deger:''}" ${deger?'atandı':'silindi'}`;
  $('etDeger').value=''; await ozetYukle();
}
async function disaAktar(tur){
  if(!secimVarMi()){ durum('Dışa aktarmak için en az bir soru seçin.',false); return; }
  if(!(await kaydetSimdi())) return;
  const ocr=(tur==='docx'||tur==='pdf-metin');
  durum(ocr?'OCR ile belge üretiliyor… (sürebilir)':'Dışa aktarılıyor…',true);
  islemYokla();
  try{
    const r=await post('/disa-aktar',{tur,secim:secimListe()});
    if(r.hata){ durum('Hata: '+r.hata,false); return; }
    indirBaslat(r.jeton,r.ad);
    durum(`✅ ${r.adet} soru indirildi: ${r.ad}`,false);
  }catch(e){ durum('Bağlantı hatası: '+e,false); }
  finally{ durdurYokla(); }
}
function modAyarla(m){
  mod=m; cizAyar(false); secili.clear();
  $('modDuzen').classList.toggle('etkin',m==='duzenle');
  $('modSec').classList.toggle('etkin',m==='sec');
  $('sahne').classList.toggle('sec-modu',m==='sec');
  $('duzenKart').style.display=m==='duzenle'?'block':'none';
  $('secimKart').style.display=m==='sec'?'block':'none';
  cizKutular();
}
async function gosterSayfa(){
  const r=await jget('/kutular?sayfa='+sayfa);
  olcek=r.olcek; sayfaGen=r.genislik; sayfaYuk=r.yukseklik;
  kutuMeta=r.kutu_meta||[];
  kutular=r.kutular.map((k,i)=>({x0:k[0],y0:k[1],x1:k[2],y1:k[3],
    kimlik:kutuMeta[i]?.kararli_kimlik||null}));
  sayfaInceleme=r.sayfa_inceleme||null; sayfaIncelemeCiz();
  secili.clear(); kutuRev++;
  const g=$('gorsel');
  g.onload=cizKutular;
  g.src='/onizleme?sayfa='+sayfa+'&ciplak=1&t='+Date.now();
  const rol=r.sayfa_rolu?` · ${String(r.sayfa_rolu).replaceAll('_',' ')}`:'';
  const modEt=incelemeModu?' · inceleme':'';
  $('sayfaEtiket').textContent=`Sayfa ${sayfa+1} / ${toplamSayfa}${rol}${modEt}`;
  $('duzenRozet').textContent=r.duzenlendi?'· düzenlendi':'';
  cizAyar(false);
}
function sayfaIncelemeCiz(){
  const kart=$('sayfaIncelemeKart'), alan=$('sayfaIncelemeOzet'), s=sayfaInceleme;
  if(!s||(!(s.risk_nedenleri||[]).length&&s.karar==='bekliyor')){
    kart.style.display='none'; return;
  }
  kart.style.display='block';
  const risk=(s.risk_nedenleri||[]).map(x=>String(x).replaceAll('_',' '));
  const kanit=(s.kanitlar||[]).map(x=>String(x).replaceAll('_',' '));
  const uyari=s.uyarilar||[];
  const karar=s.karar==='onayli'?'✓ Sayfa doğru olarak onaylandı':
    s.karar==='soru_yok'?'∅ Bu sayfada soru yok olarak işaretlendi':'⚠ İnceleme bekliyor';
  alan.innerHTML=`<div><b>${htmlKacir(karar)}</b></div>`+
    (risk.length?`<div style="color:var(--uyari);margin-top:5px">Risk: ${htmlKacir(risk.join(', '))}</div>`:'')+
    (kanit.length?`<div style="margin-top:5px">Kanıt: ${htmlKacir(kanit.join(', '))}</div>`:'')+
    (uyari.length?`<div style="margin-top:5px">Uyarı: ${htmlKacir(uyari.join(' · '))}</div>`:'');
  $('sayfaKararGeri').style.display=s.karar==='bekliyor'?'none':'inline-block';
}
async function sayfaKarar(karar){
  if(!(await kaydetSimdi())) return;
  const r=await post('/inceleme-sayfa',{sayfa,karar});
  if(r.hata){ durum('Sayfa kararı kaydedilemedi: '+r.hata,false);
    toastGoster('Sayfa kararı kaydedilemedi: '+r.hata,'hata'); return; }
  await ozetYukle(); await kalibrasyonYukle();
  const bek=await incelemeYukle();
  if(incelemeModu&&!bek.sayfalar.includes(sayfa)){
    if(bek.sayfalar.length) sayfa=bek.sayfalar[0]; else incelemeModu=false;
  }
  await gosterSayfa(); secimSayaci();
  durum(karar==='onayli'?'✓ Sayfa doğru olarak onaylandı.':
    karar==='soru_yok'?'∅ Sayfa soru içermiyor olarak işaretlendi.':'Sayfa kararı geri alındı.',false);
}
function cizKutular(){
  const sahne=$('sahne');
  [...sahne.querySelectorAll('.kutu')].forEach(e=>e.remove());
  kutuDivleri=[];
  const eo=ekranOlcek();
  kutular.forEach((k,i)=>{
    const kml=kutuKimlik[sayfa+':'+i];
    const etk=kml&&ozet?(ozetEtiket(kml)):'S'+(i+1);
    const kesli=mod==='sec'&&kml&&secimKimligiVar(kml);
    const meta=kutuMeta[i]||{}, kd=meta.inceleme_durumu||'otomatik';
    const d=document.createElement('div');
    d.className='kutu kalite-'+kd+(secili.has(i)?' sec':'')+(kesli?' kesime':'');
    d.style.left=(k.x0*eo)+'px'; d.style.top=(k.y0*eo)+'px';
    d.style.width=((k.x1-k.x0)*eo)+'px'; d.style.height=((k.y1-k.y0)*eo)+'px';
    d.innerHTML='<span class="no">'+etk+'</span>'+
      ['nw','ne','sw','se'].map(c=>'<span class="tut '+c+'" data-k="'+c+'"></span>').join('');
    if(kalibrasyon?.aktif){
      const sayfaOnayi=meta.onay_kaynagi==='sayfa';
      const etkilesim=kd==='incele'&&!sayfaOnayi, b=document.createElement(etkilesim?'button':'span');
      const yuz=Math.round((Number(meta.guven)||0)*100);
      if(etkilesim)b.type='button'; b.className='kalite-rozet '+(meta.onayli?'onayli':kd);
      b.textContent=meta.onayli?'✓ Onaylandı':kd==='otomatik'?`Otomatik ${yuz}%`:
        kd==='incele'?`İncele ${yuz}%`:`Reddedildi ${yuz}%`;
      const temelBaslik=sayfaOnayi?'Bu kutu sayfa kararıyla onaylandı; kararı sayfa kartından geri alabilirsiniz.':
        kd==='reddedildi'?'Çıktıya almak için kutuyu elle düzeltin.':
        kd==='otomatik'?'Kalite kapısından otomatik geçti.':meta.onayli?
        'Onayı geri almak için tıkla':'Çıktıya alınabilir olarak onaylamak için tıkla';
      const kanit=(meta.kanitlar||[]).join(', '), uyari=(meta.uyarilar||[]).join(', ');
      b.title=temelBaslik+(kanit?'\\nKanıt: '+kanit:'')+(uyari?'\\nUyarı: '+uyari:'');
      if(etkilesim){ b.addEventListener('pointerdown',e=>e.stopPropagation());
        b.addEventListener('click',e=>{e.stopPropagation(); incelemeOnayla(i,!meta.onayli);}); }
      d.appendChild(b);
    }
    d.addEventListener('pointerdown',e=>kutuBasla(e,i));
    sahne.appendChild(d);
    kutuDivleri[i]=d;
  });
  $('silBtn').disabled=secili.size===0;
  $('birlestirBtn').disabled=secili.size<2;
  $('bolBtn').disabled=secili.size!==1||
    (secili.size===1&&(kutular[[...secili][0]].y1-kutular[[...secili][0]].y0)<MIN_BOL_YUKSEKLIK);
  if(bolModu&&secili.size!==1) bolAyar(false);
  if(mod==='sec') testKutulariGuncelle();
  kucukResimGoster();
  topluOnayBtnTazele();
}
function topluOnayBtnTazele(){
  const b=$('topluOnayBtn'); if(!b) return;
  const bekleyen=kutuMeta.filter(m=>m&&m.inceleme_durumu==='incele'&&!m.onayli).length;
  b.disabled=!bekleyen;
  b.textContent=bekleyen?`✓ Sayfadaki İncele kutularını onayla (${bekleyen})`:
    '✓ Sayfadaki İncele kutuları onaylı';
}
// yalnız left/top/width/height günceller (kutuHareket/cizHareket sürüklemesi için); div yoksa tam çizime düşer
function kutuStilGuncelle(i){
  const d=kutuDivleri[i]; if(!d){ cizKutular(); return; }
  const k=kutular[i], eo=ekranOlcek();
  d.style.left=(k.x0*eo)+'px'; d.style.top=(k.y0*eo)+'px';
  d.style.width=((k.x1-k.x0)*eo)+'px'; d.style.height=((k.y1-k.y0)*eo)+'px';
}
async function incelemeOnayla(i,onay){
  if(!(await kaydetSimdi())) return;   // kutu_no'lar sunucuyla senkron olmadan onay atma (bkz. topluOnayla)
  const r=await post('/inceleme',{sayfa,kutu_no:i,onay});
  if(r.hata){ durum('Onay kaydedilemedi: '+r.hata,false); toastGoster('Onay kaydedilemedi: '+r.hata,'hata'); return; }
  // yalnız onaylama (onay=true) undo'ya girer — badge'den geri alma (onay=false) şimdilik
  // izlenmiyor; O kısayolu da bu yolu kullandığından tek tık onaylar tek Ctrl+Z ile geri alınır.
  if(onay) undoPush(sayfa,null,null,'onay',[i]);
  if(r.kalibrasyon){ kalibrasyon={...(kalibrasyon||{}),...r.kalibrasyon}; }
  const bek=await incelemeYukle();
  if(incelemeModu&&!bek.sayfalar.includes(sayfa)){
    if(bek.sayfalar.length) sayfa=bek.sayfalar[0]; else incelemeModu=false;
  }
  await gosterSayfa();
  durum(onay?'✓ Aday onaylandı; katı kalite çıktısına alınabilir.':'Aday onayı geri alındı.',false);
}
function incelemeAdaylari(){   // mevcut sayfada henüz onaylanmamış 'incele' kutu indeksleri
  return kutuMeta.map((m,i)=>({m,i}))
    .filter(({m})=>m&&m.inceleme_durumu==='incele'&&!m.onayli).map(({i})=>i);
}
// N: sayfadaki bir sonraki inceleme adayına odaklan (secili tekil seçim olarak kullanılır);
// tükenirse /inceleme'nin bekleyen sayfa listesinden bir sonraki adaya atlar; hiçbir sayfada
// aday kalmadıysa başlangıç sayfasına geri döner. gezinmeMesgul, N'e art arda (tuş tekrarı)
// basıldığında üst üste binen eşzamanlı gezinmeleri engeller.
let gezinmeMesgul=false;
async function incelemeSonrakineGit(){
  if(gezinmeMesgul) return;
  const suan=secili.size===1?[...secili][0]:-1;
  const sonrakiBu=incelemeAdaylari().find(i=>i>suan);
  if(sonrakiBu!=null){
    secili=new Set([sonrakiBu]); cizKutular();
    kutuDivleri[sonrakiBu]?.scrollIntoView({behavior:'smooth',block:'center',inline:'center'});
    return;
  }
  gezinmeMesgul=true;
  const baslangicSayfa=sayfa;
  try{
    const bek=await incelemeYukle();
    for(const s of bek.sayfalar.filter(s=>s!==sayfa)){
      if(!(await kaydetSimdi())) return;
      sayfa=s; await gosterSayfa();
      const ilk=incelemeAdaylari()[0];
      if(ilk!=null){
        secili=new Set([ilk]); cizKutular();
        kutuDivleri[ilk]?.scrollIntoView({behavior:'smooth',block:'center',inline:'center'});
        durum(`İnceleme: sayfa ${sayfa+1}'e geçildi.`,false);
        return;
      }
    }
    if(sayfa!==baslangicSayfa){   // hiçbir sayfada aday bulunamadı — başlandığı sayfaya dön
      if(!(await kaydetSimdi())) return;
      sayfa=baslangicSayfa; await gosterSayfa();
    }
    toastGoster('İncelenecek kutu kalmadı.','bilgi');
  } finally { gezinmeMesgul=false; }
}
// O: N ile odaklanmış tekil kutuyu onaylar (mevcut incelemeOnayla → /inceleme yolu, tek undo adımı)
function incelemeOdaktakiOnayla(){
  if(secili.size!==1){ toastGoster('Önce N ile bir inceleme kutusuna odaklanın.','bilgi'); return; }
  const i=[...secili][0], m=kutuMeta[i];
  if(!m||m.inceleme_durumu!=='incele'||m.onayli){ toastGoster('Odakta onaylanacak bir inceleme kutusu yok.','bilgi'); return; }
  incelemeOnayla(i,true);
}
// sayfadaki tüm bekleyen (incele, henüz onaylanmamış) kutuları tek seferde onaylar;
// tek geri-al adımı olarak yığına girer (bkz. undoPush 'onay' türü)
async function topluOnayla(){
  // ÖNCE flush: kaydetSnapshot başarıda kutuMeta'yı sunucunun (olası y-sıralı) yanıtıyla
  // değiştirir — adaylar bu değişimden ÖNCE hesaplanırsa bekleyen bir sürükleme sırayı
  // kaydırmışsa yanlış kutu_no'larla /inceleme'ye gidilir (bkz. inceleme bulgusu #2).
  if(!(await kaydetSimdi())) return;
  const adaylar=incelemeAdaylari();
  if(!adaylar.length) return;
  const btn=$('topluOnayBtn'); if(btn) btn.disabled=true;
  try{
    const sonuclar=await Promise.all(adaylar.map(i=>post('/inceleme',{sayfa,kutu_no:i,onay:true})
      .catch(e=>({hata:String((e&&e.message)||e)}))));
    const basarili=adaylar.filter((_,k)=>sonuclar[k]&&!sonuclar[k].hata);
    const hatalilar=sonuclar.filter(r=>r&&r.hata);
    if(basarili.length) undoPush(sayfa,null,null,'onay',basarili);   // yalnız gerçekten değişenler tek adımda geri alınır
    const kalOk=sonuclar.find(r=>r&&r.kalibrasyon);
    if(kalOk) kalibrasyon={...(kalibrasyon||{}),...kalOk.kalibrasyon};
    const bek=await incelemeYukle();
    if(incelemeModu&&!bek.sayfalar.includes(sayfa)){
      if(bek.sayfalar.length) sayfa=bek.sayfalar[0]; else incelemeModu=false;
    }
    await gosterSayfa();
    if(hatalilar.length){
      durum(`${basarili.length} kutu onaylandı · ${hatalilar.length} kutu onaylanamadı: ${hatalilar[0].hata}`,false);
      toastGoster(`${hatalilar.length} kutu onaylanamadı: ${hatalilar[0].hata}`,'hata');
    }else{
      durum(`${adaylar.length} kutu onaylandı.`,false);
      toastGoster(`${adaylar.length} kutu onaylandı`,'basari');
    }
  }catch(e){
    durum('Toplu onay sırasında beklenmeyen hata: '+(e.message||e),false);
    toastGoster('Toplu onay sırasında beklenmeyen hata: '+(e.message||e),'hata');
  } finally { topluOnayBtnTazele(); }
}
function ozetEtiket(kml){
  for(const t of ozet.testler) for(const s of t.sorular) if(s.kimlik===kml) return s.etiket;
  return '?';
}
function kucukResimGoster(){
  const kr=$('kucukResim');
  // tam olarak bir kutu seçiliyse ve düzenlenmemiş/kaydedilmişse kırpması gösterilir
  if(secili.size===1){
    const i=[...secili][0], im=kr.querySelector('img');
    im.src='/soru-onizleme?sayfa='+sayfa+'&kutu='+i+'&t='+Date.now();
    im.onerror=()=>{kr.style.display='none';}; kr.style.display='block';
  } else kr.style.display='none';
}
function secDegis(i,ekle){ if(!ekle) secili.clear(); if(secili.has(i)&&ekle) secili.delete(i); else secili.add(i); cizKutular(); }

let surukle=null;
function kutuBasla(e,i){
  if(spaceBasili||e.button===1) return;   // pan önceliklidir
  if(mod==='sec'){ e.stopPropagation(); e.preventDefault(); soruSecTog(i); return; }
  if(bolModu){
    if(secili.size===1&&secili.has(i)){
      e.stopPropagation(); e.preventDefault();
      const k=kutular[i], rect=$('gorsel').getBoundingClientRect(), eo=ekranOlcek();
      const yPage=Math.max(k.y0+8,Math.min(k.y1-8,(e.clientY-rect.top)/eo));
      kutuBol(i,yPage);
    }
    return;
  }
  if(cizModu) return;
  e.stopPropagation(); e.preventDefault();
  const tut=e.target.dataset.k;
  if(!secili.has(i)) secDegis(i, e.shiftKey);
  else if(e.shiftKey){ secDegis(i,true); return; }
  const eo=ekranOlcek();
  surukle={i, tut, bx:e.clientX, by:e.clientY, k0:{...kutular[i]}, eo, once:derinKopya(kutular)};
  window.addEventListener('pointermove',kutuHareket);
  window.addEventListener('pointerup',kutuBitir);
}
function kutuHareket(e){
  if(!surukle) return;
  const dx=(e.clientX-surukle.bx)/surukle.eo, dy=(e.clientY-surukle.by)/surukle.eo;
  const k={...surukle.k0}, t=surukle.tut;
  if(!t){ k.x0+=dx; k.x1+=dx; k.y0+=dy; k.y1+=dy; }
  else{ if(t.includes('w'))k.x0+=dx; if(t.includes('e'))k.x1+=dx;
        if(t.includes('n'))k.y0+=dy; if(t.includes('s'))k.y1+=dy; }
  k.x0=Math.max(0,Math.min(sayfaGen,k.x0)); k.x1=Math.max(0,Math.min(sayfaGen,k.x1));
  k.y0=Math.max(0,Math.min(sayfaYuk,k.y0)); k.y1=Math.max(0,Math.min(sayfaYuk,k.y1));
  kutular[surukle.i]=k; kutuStilGuncelle(surukle.i);
}
function kutuBitir(){
  window.removeEventListener('pointermove',kutuHareket);
  window.removeEventListener('pointerup',kutuBitir);
  if(surukle){
    const s=surukle; surukle=null;
    if(!kutuAyniMi(s.once[s.i],kutular[s.i])) undoPush(sayfa,s.once,derinKopya(kutular));
    cizKutular(); kaydet();
  }
}
// yeni kutu çizme
function cizAc(){ cizAyar(!cizModu); }
function cizAyar(ac){ cizModu=ac; if(ac) bolAyar(false);
  $('cizBtn').classList.toggle('etkin',ac); $('sahne').classList.toggle('ciz',ac);
  if(ac){ secili.clear(); cizKutular(); } }
// kutu bölme: seçili kutu içinde imleci izleyen yatay çizgi, tıklayınca böler
function bolAc(){
  if(secili.size!==1) return;
  if(!bolModu){
    const k=kutular[[...secili][0]];
    if((k.y1-k.y0)<MIN_BOL_YUKSEKLIK){
      toastGoster(`Bu kutu bölünemeyecek kadar ince (en az ${MIN_BOL_YUKSEKLIK}px yükseklik gerekir).`,'bilgi');
      return;
    }
  }
  bolAyar(!bolModu);
}
function bolAyar(ac){
  if(ac&&secili.size!==1) return;
  bolModu=ac; if(ac) cizAyar(false);
  $('bolBtn').classList.toggle('etkin',ac); $('sahne').classList.toggle('bol',ac);
  if(!ac) bolCizgiKaldir();
}
function bolCizgiKaldir(){ const el=$('sahne').querySelector('.bol-cizgi'); if(el) el.remove(); }
function bolCizgiGuncelle(yPage){
  const i=[...secili][0]; if(i==null) return;
  const k=kutular[i], eo=ekranOlcek();
  let el=$('sahne').querySelector('.bol-cizgi');
  if(!el){ el=document.createElement('div'); el.className='bol-cizgi'; $('sahne').appendChild(el); }
  el.style.left=(k.x0*eo)+'px'; el.style.width=((k.x1-k.x0)*eo)+'px'; el.style.top=(yPage*eo)+'px';
}
$('sahne').addEventListener('pointermove',e=>{
  if(!bolModu||secili.size!==1) return;
  const i=[...secili][0], k=kutular[i];
  const rect=$('gorsel').getBoundingClientRect(), eo=ekranOlcek();
  const yPage=Math.max(k.y0+8,Math.min(k.y1-8,(e.clientY-rect.top)/eo));
  bolCizgiGuncelle(yPage);
});
// KRİTİK: kimlikli üst yarı dizide alt (kimliksiz) yarıdan ÖNCE olmalı — kutulari_guncelle'nin
// IoU-yedek eşlemesi (istenen_kimlik None iken) yalnız henüz 'kullanilan' olmayan eski kutulara
// bakar; üst önce işlenirse eski kutuyu tüketir, alt ona ikinci kez eşlenemez (kimlik çalınmaz).
function kutuBol(i,yPage){
  const k=kutular[i], once=derinKopya(kutular);
  const ust={x0:k.x0,y0:k.y0,x1:k.x1,y1:yPage,kimlik:k.kimlik};
  const alt={x0:k.x0,y0:yPage,x1:k.x1,y1:k.y1,kimlik:null};
  kutular.splice(i,1,ust,alt);
  secili.clear(); bolAyar(false);
  undoPush(sayfa,once,derinKopya(kutular));
  cizKutular(); kaydet();
}
let ciz=null, cizOnce=null;
$('sahne').addEventListener('pointerdown',e=>{
  if(spaceBasili||!cizModu||e.target.classList.contains('tut')) return;
  const rect=$('gorsel').getBoundingClientRect(), eo=ekranOlcek();
  ciz={x:(e.clientX-rect.left)/eo, y:(e.clientY-rect.top)/eo};
  cizOnce=derinKopya(kutular);
  kutular.push({x0:ciz.x,y0:ciz.y,x1:ciz.x,y1:ciz.y});
  window.addEventListener('pointermove',cizHareket); window.addEventListener('pointerup',cizBitir);
});
function cizHareket(e){
  const rect=$('gorsel').getBoundingClientRect(), eo=ekranOlcek();
  const x=Math.max(0,Math.min(sayfaGen,(e.clientX-rect.left)/eo));
  const y=Math.max(0,Math.min(sayfaYuk,(e.clientY-rect.top)/eo));
  const k=kutular[kutular.length-1];
  k.x0=Math.min(ciz.x,x); k.x1=Math.max(ciz.x,x); k.y0=Math.min(ciz.y,y); k.y1=Math.max(ciz.y,y);
  kutuStilGuncelle(kutular.length-1);
}
function cizBitir(){
  window.removeEventListener('pointermove',cizHareket); window.removeEventListener('pointerup',cizBitir);
  const k=kutular[kutular.length-1];
  if((k.x1-k.x0)<8||(k.y1-k.y0)<8) kutular.pop();   // minik çizimi at
  else undoPush(sayfa,cizOnce,derinKopya(kutular));
  cizOnce=null; cizAyar(false); cizKutular(); kaydet();
}
function kutuSil(){
  const once=derinKopya(kutular);
  kutular=kutular.filter((_,i)=>!secili.has(i)); secili.clear();
  undoPush(sayfa,once,derinKopya(kutular));
  cizKutular(); kaydet();
}
function kutuBirlestir(){
  const s=[...secili]; if(s.length<2) return;
  const once=derinKopya(kutular);
  const b={x0:1e9,y0:1e9,x1:-1e9,y1:-1e9};
  s.forEach(i=>{const k=kutular[i]; b.x0=Math.min(b.x0,k.x0); b.y0=Math.min(b.y0,k.y0); b.x1=Math.max(b.x1,k.x1); b.y1=Math.max(b.y1,k.y1);});
  kutular=kutular.filter((_,i)=>!secili.has(i)); kutular.push(b); secili.clear();
  undoPush(sayfa,once,derinKopya(kutular));
  cizKutular(); kaydet();
}
async function sayfaSifirla(){
  if(!(await kaydetSimdi())) return;
  const once=derinKopya(kutular);
  const r=await post('/kutu-sifirla',{sayfa});
  kutuMeta=r.kutu_meta||[];
  kutular=r.kutular.map((k,i)=>({x0:k[0],y0:k[1],x1:k[2],y1:k[3],
    kimlik:kutuMeta[i]?.kararli_kimlik||null}));
  undoPush(sayfa,once,derinKopya(kutular));
  sayfaInceleme=r.sayfa_inceleme||null; sayfaIncelemeCiz();
  secili.clear(); kutuRev++; await ozetYukle(); await kalibrasyonYukle(); await incelemeYukle(); cizKutular();
  $('duzenRozet').textContent=''; guncelleOzet(r.toplam);
}
// --- belge-geneli geri al / yinele (gui_kutu_editor.py GeriAlYigini deseni) ---
// Bilinen sınır: silinen bir kutunun undo'su sunucuda YENİ kimlik alır (kutulari_guncelle
// kimlik-diff sözleşmesi) — geometri tam geri gelir ama kutu "kullanıcı düzeltmesi" olarak
// oto-onaylanır; _profil_duzeltmesini_yay ile başka sayfalara yayılmış düzeltmeler geri alınmaz.
function derinKopya(arr){ return arr.map(k=>({...k})); }
function kutuAyniMi(a,b){ return Math.abs(a.x0-b.x0)<0.5&&Math.abs(a.y0-b.y0)<0.5&&
  Math.abs(a.x1-b.x1)<0.5&&Math.abs(a.y1-b.y1)<0.5; }
// tur='geometri' (varsayılan, once/sonra=kutu dizisi anlık görüntüsü) |
// 'onay' (once/sonra kullanılmaz, ekstra=onaylanan kutu_no listesi) |
// 'secim' (once/sonra=secimSnapshot(), sayfa gereksiz — belge-geneli)
function undoPush(sayfaIdx,once,sonra,tur='geometri',ekstra){
  geriYigin.push({sayfa:sayfaIdx,once,sonra,tur,ekstra});
  if(geriYigin.length>UNDO_SINIR) geriYigin.shift();
  ileriYigin=[]; undoButonTazele();
}
function undoButonTazele(){
  const g=$('geriAlBtn'), y=$('yineleBtn');
  if(g) g.disabled=!geriYigin.length;
  if(y) y.disabled=!ileriYigin.length;
}
// dönüş değeri BAŞARI/BAŞARISIZ'dır — geriAl/yinele bunu görmeden yığınları değiştirmemeli
// (aksi halde kaydetSimdi başarısız olduğunda adım sessizce "tüketilir" ama hiç uygulanmaz).
async function anlikUygula(sayfaIdx,anlik){
  if(sayfaIdx!==sayfa){ if(!(await kaydetSimdi())) return false; sayfa=sayfaIdx; await gosterSayfa(); }
  kutular=derinKopya(anlik); secili.clear(); kutuRev++;
  cizKutular(); kaydet();
  return true;
}
// topluOnayla/incelemeOnayla ile onaylanan kutu_no listesini geri alır (onay=false) ya da
// yineler (onay=true). Sayfa değişse de değişmese de ÖNCE kaydetSimdi() beklenir: aksi halde
// bekleyen (350ms debounce'lı) bir geometri kaydı henüz sunucuya ulaşmadan kutu_no'lar kayabilir
// ve /inceleme yanlış kutuyu onaylayabilir/geri alabilir.
async function onayGeriYinele(kayit,onay){
  if(!(await kaydetSimdi())) return false;
  try{
    const hedefSayfa=kayit.sayfa;
    if(hedefSayfa!==sayfa){ sayfa=hedefSayfa; await gosterSayfa(); }
    const liste=kayit.ekstra||[];
    const sonuclar=await Promise.all(liste.map(i=>post('/inceleme',{sayfa:hedefSayfa,kutu_no:i,onay})
      .catch(e=>({hata:String((e&&e.message)||e)}))));
    const hatalilar=sonuclar.filter(r=>r&&r.hata);
    const bek=await incelemeYukle();
    if(incelemeModu&&!bek.sayfalar.includes(sayfa)){
      if(bek.sayfalar.length) sayfa=bek.sayfalar[0]; else incelemeModu=false;
    }
    await gosterSayfa();
    if(hatalilar.length){
      // KISMİ başarı BAŞARISIZ sayılır (return false) — aksi halde başarısız kutular onaylı/
      // onaysız kalırken yığın "işlem tamamlandı" sanıp adımı tüketir (bkz. inceleme bulgusu #5).
      // Aynı kayıt yığında kalır; tekrar Ctrl+Z/⇧Ctrl+Z ile denenebilir (aynı onay değerini
      // tekrar göndermek sunucuda etkisizdir/idempotenttir).
      toastGoster(`${liste.length-hatalilar.length} kutu ${onay?'onayı yinelendi':'onayı geri alındı'} · `+
        `${hatalilar.length} hata: ${hatalilar[0].hata}`,'hata');
      return false;
    }
    toastGoster(onay?`${liste.length} kutu onayı yinelendi`:`${liste.length} kutu onayı geri alındı`,'bilgi');
    return true;
  }catch(e){
    toastGoster('Onay geri al/yinele sırasında hata: '+(e.message||e),'hata');
    return false;
  }
}
// bir yığın kaydını uygular; 'ileriMi' redo yönünde mi (sonra'yı) yoksa undo yönünde mi
// (once'ı) uygulayacağını belirler. Yalnız BAŞARILI uygulamadan sonra geriAl/yinele
// kaydı karşı yığına taşır — aksi halde başarısız bir adım sessizce tüketilip yığınlar
// gerçek durumla senkronsuz kalır (bkz. inceleme bulgusu #3).
async function undoAdimUygula(k,ileriMi){
  if(k.tur==='onay') return await onayGeriYinele(k,ileriMi);
  if(k.tur==='secim'){ secimSnapshotUygula(ileriMi?k.sonra:k.once); cizKutular(); secimSayaci(); return true; }
  return await anlikUygula(k.sayfa,ileriMi?k.sonra:k.once);
}
// undoMesgul: bir geriAl/yinele async uygulaması sürerken (ör. /inceleme ağ isteği) tuş
// tekrarıyla (Cmd+Z basılı tutma) art arda gelen çağrılar no-op olur. Aksi halde iki çağrı
// aynı tepe kaydı eşzamanlı okuyup ikisi de pop çağırır — ikinci pop bir ALT kaydı hiç
// uygulanmadan tüketip karşı yığına atar (bkz. inceleme bulgusu #1). Pop'tan önceki
// eşitlik kontrolü ekstra bir güvence katmanıdır.
let undoMesgul=false;
async function geriAl(){
  if(undoMesgul) return;
  const k=geriYigin[geriYigin.length-1]; if(!k) return;
  undoMesgul=true;
  try{
    if(!(await undoAdimUygula(k,false))) return;
    if(geriYigin[geriYigin.length-1]===k){ geriYigin.pop(); ileriYigin.push(k); undoButonTazele(); }
    if(galeriAcik) galeriIzgaraCiz();
  } finally { undoMesgul=false; }
}
async function yinele(){
  if(undoMesgul) return;
  const k=ileriYigin[ileriYigin.length-1]; if(!k) return;
  undoMesgul=true;
  try{
    if(!(await undoAdimUygula(k,true))) return;
    if(ileriYigin[ileriYigin.length-1]===k){ ileriYigin.pop(); geriYigin.push(k); undoButonTazele(); }
    if(galeriAcik) galeriIzgaraCiz();
  } finally { undoMesgul=false; }
}
// --- genişlik-tabanlı zoom + pan (A yaklaşımı: ekranOlcek'e DOKUNULMAZ) ---
function zoomEtiketTazele(){ const e=$('zoomEtiket'); if(e) e.textContent=Math.round(yakZoom*100)+'%'; }
function zoomAyarla(yeni,sabitNokta){
  const g=$('gorsel'); if(!g.naturalWidth) return;
  yeni=Math.max(1,Math.min(8,yeni));
  if(Math.abs(yeni-yakZoom)<1e-6) return;
  const onz=$('onizleme'), onzRect=onz.getBoundingClientRect();
  const nokta=sabitNokta||{clientX:onzRect.left+onzRect.width/2, clientY:onzRect.top+onzRect.height/2};
  const rectOnce=g.getBoundingClientRect(), eoOnce=ekranOlcek();
  const px=(nokta.clientX-rectOnce.left)/eoOnce, py=(nokta.clientY-rectOnce.top)/eoOnce;
  if(!fitGen) fitGen=g.clientWidth;           // ilk zoomda "fit" genişliği sabitlenir
  yakZoom=yeni;
  if(yakZoom<=1.0001){ yakZoom=1; g.style.maxWidth=''; g.style.width=''; }
  else{ g.style.maxWidth='none'; g.style.width=(fitGen*yakZoom)+'px'; }
  cizKutular();
  // imleç/görünüm-merkezi altındaki sayfa noktasını sabit tut: yeniden ölçüm + fark kadar kaydır
  const rectSonra=g.getBoundingClientRect(), eoSonra=ekranOlcek();
  onz.scrollLeft+=(rectSonra.left+px*eoSonra)-nokta.clientX;
  onz.scrollTop+=(rectSonra.top+py*eoSonra)-nokta.clientY;
  zoomEtiketTazele();
}
$('onizleme').addEventListener('wheel',e=>{
  if(!(e.metaKey||e.ctrlKey)||$('sahne').style.display==='none') return;
  e.preventDefault();
  zoomAyarla(yakZoom*Math.pow(1.1,-e.deltaY/40),{clientX:e.clientX,clientY:e.clientY});
},{passive:false});
// space+sürükle pan (kutuBasla/çizim pointerdown'ları spaceBasili'nde erken çıkar)
let pan=null;
$('onizleme').addEventListener('pointerdown',e=>{
  if(!(spaceBasili||e.button===1)) return;
  e.preventDefault();
  const onz=$('onizleme');
  pan={x:e.clientX,y:e.clientY,sl:onz.scrollLeft,st:onz.scrollTop};
  window.addEventListener('pointermove',panHareket);
  window.addEventListener('pointerup',panBitir);
});
function panHareket(e){
  if(!pan) return;
  const onz=$('onizleme');
  onz.scrollLeft=pan.sl-(e.clientX-pan.x); onz.scrollTop=pan.st-(e.clientY-pan.y);
}
function panBitir(){
  window.removeEventListener('pointermove',panHareket);
  window.removeEventListener('pointerup',panBitir);
  pan=null;
}
function kaydet(){   // 350ms debounce ile sunucuya yaz
  clearTimeout(kaydetZaman); kutuRev++;
  kaydetBekleyen={sayfa,rev:kutuRev,
    kutular:kutular.map(k=>({kutu:[k.x0,k.y0,k.x1,k.y1],kararli_kimlik:k.kimlik||null}))};
  kaydetZaman=setTimeout(()=>{kaydetZaman=null; kaydetSimdi();},350);
}
async function kaydetSnapshot(kayit){
  try{
    const r=await post('/kutu-guncelle',{sayfa:kayit.sayfa,kutular:kayit.kutular});
    if(r.hata) throw new Error(r.hata);
    await ozetYukle(); await kalibrasyonYukle(); await incelemeYukle(); guncelleOzet(r.toplam);
    // Yalnız hâlâ aynı sayfanın aynı revizyonundaysak ekrandaki kutuları değiştir.
    if(sayfa===kayit.sayfa&&kutuRev===kayit.rev){
      kutuMeta=r.kutu_meta||[];
      kutular=r.kutular.map((k,i)=>({x0:k[0],y0:k[1],x1:k[2],y1:k[3],
        kimlik:kutuMeta[i]?.kararli_kimlik||null}));
      sayfaInceleme=r.sayfa_inceleme||null; sayfaIncelemeCiz();
      secili.clear(); cizKutular(); $('duzenRozet').textContent='· düzenlendi';
      durum(`Sayfada ${r.sayfa_soru} soru · kaydedildi`,false);
    }
    return true;
  }catch(e){
    if(!kaydetBekleyen||kaydetBekleyen.rev<kayit.rev) kaydetBekleyen=kayit;
    durum('Kutu düzenlemesi kaydedilemedi: '+(e.message||e),false);
    toastGoster('Kutu düzenlemesi kaydedilemedi: '+(e.message||e),'hata'); return false;
  }
}
async function kaydetSimdi(){   // bekleyen snapshot'ı doğru sayfaya seri biçimde uygula
  clearTimeout(kaydetZaman); kaydetZaman=null;
  const kayit=kaydetBekleyen; kaydetBekleyen=null;
  if(!kayit) return kaydetKuyruk;
  const gorev=kaydetKuyruk.then(()=>kaydetSnapshot(kayit));
  kaydetKuyruk=gorev.then(()=>true); return gorev;
}
function guncelleOzet(toplam){ const e=$('toplamSoru'); if(e&&toplam!=null) e.textContent=toplam; }
async function sayfaGez(y){
  let n;
  if(incelemeModu&&incelemeSayfalari.length){
    let i=incelemeSayfalari.indexOf(sayfa); if(i<0)i=0;
    n=incelemeSayfalari[Math.max(0,Math.min(incelemeSayfalari.length-1,i+y))];
  }else n=Math.max(0,Math.min(toplamSayfa-1,sayfa+y));
  if(n===sayfa)return;
  if(!(await kaydetSimdi())) return; sayfa=n; await gosterSayfa();
}
window.addEventListener('resize',()=>{ if($('sahne').style.display!=='none') cizKutular(); });
function secimListe(){ return kesSecimModu==='all'?null:[...kesSecim]; }
async function kes(){
  if(!secimVarMi()){ durum('Kesmek için en az bir soru seçin.',false); return; }
  if(!(await kaydetSimdi())) return;
  durum('Sorular kesiliyor…',true); islemYokla();
  $('kesBtn').disabled=true;
  try{
    const r=await post('/kes',{secim:secimListe(),numara_gizle:$('numaraGizle').checked,
      cevap_bandi:$('cevapBandi').checked,cozum_ilistir:$('cozumIlistir').checked});
    if(r.hata){ durum('Hata: '+r.hata,false); return; }
    indirBaslat(r.jeton,r.ad);
    const tm=r.test?` · ${r.test} test`:'';
    let msg=`✅ ${r.adet} soru${tm} indirildi: ${r.ad}`;
    if($('bankaAyni').checked){
      const rb=await post('/bankaya-aktar',{secim:secimListe()});
      if(!rb.hata) msg+=` · ${rb.eklenen} bankaya eklendi`+(rb.atlanan?` (${rb.atlanan} kopya)`:'')+
        (rb.kalite_atlanan?` · ${rb.kalite_atlanan} düşük güvenli aday aktarılmadı`: '');
      bankaYuklendi=false;
    }
    durum(msg,false); gecmisYukle();
  }catch(e){ durum('Bağlantı hatası: '+e,false); }
  finally{ durdurYokla(); secimSayaci(); }
}
// --- soru bankasına aktar (kesim görünümünden) ---
async function bankayaAktar(){
  if(!secimVarMi()){ durum('Bankaya aktarmak için en az bir soru seçin.',false); return; }
  if(!(await kaydetSimdi())) return;
  durum('Soru bankasına aktarılıyor…',true); islemYokla();
  try{
    const r=await post('/bankaya-aktar',{secim:secimListe()});
    if(r.hata){ durum('Hata: '+r.hata,false); return; }
    const kalite=r.kalite_atlanan?` · ⚠ ${r.kalite_atlanan} düşük güvenli aday aktarılmadı`:'';
    durum(`✅ ${r.eklenen} soru bankaya eklendi`+(r.atlanan?` · ${r.atlanan} kopya atlandı`:'')+kalite,false);
    bankaYuklendi=false;
  }catch(e){ durum('Bağlantı hatası: '+e,false); }
  finally{ durdurYokla(); }
}
async function sinavPdf(){
  if(!secimVarMi()){ durum('Sınav oluşturmak için en az bir soru seçin.',false); return; }
  if(!(await kaydetSimdi())) return;
  durum('Sınav PDF\\'i oluşturuluyor…',true); islemYokla();
  try{
    const puan=+$('sinavPuan').value, rast=+$('sinavRast').value;
    const r=await post('/sinav-pdf',{secim:secimListe(),
      baslik:$('sinavBaslik').value.trim(), kurum:$('sinavKurum').value.trim(),
      ad_soyad:$('alanAd').checked, sinif:$('alanSinif').checked,
      tarih:$('alanTarih').checked, sutun:+$('sinavSutun').value,
      yeniden_numarala:$('yenidenNo').checked, cevap_anahtari:$('cevapAnah').checked,
      toplam_puan:puan||null, kitapcik:+$('sinavKitapcik').value, rastgele:rast||null,
      optik_form:$('optikForm').checked});
    if(r.hata){ durum('Hata: '+r.hata,false); return; }
    indirBaslat(r.jeton,r.ad);
    const km=r.kitapcik>1?` · ${r.kitapcik} kitapçık`:'';
    durum(`📄 Sınav kağıdı indirildi (${r.soru} soru, ${r.sayfa} sayfa${km}): ${r.ad}`
      +optikMesaji(r.optik),false);
    gecmisYukle();
  }catch(e){ durum('Bağlantı hatası: '+e,false); }
  finally{ durdurYokla(); }
}
// ilerleme yoklama (uzun OCR/kesim sırasında)
let yoklaZaman=null, yoklaNesil=0;
async function ilerlemeYokla(nesil){
  try{
    const j=await jget('/ilerleme'); if(nesil!==yoklaNesil) return;
    if(j&&j.asama){
      if(j.mesaj) durum(j.mesaj,true);
      ilerlemeAyarla(Number(j.yapilan)||0,Number(j.toplam)||0);
    }
  }catch(e){}
}
function islemYokla(){
  clearInterval(yoklaZaman); const nesil=++yoklaNesil;
  ilerlemeAyarla(0,1); ilerlemeYokla(nesil);
  yoklaZaman=setInterval(()=>ilerlemeYokla(nesil),600);
}
function durdurYokla(){
  ++yoklaNesil; clearInterval(yoklaZaman); yoklaZaman=null; ilerlemeGizle();
}
// geçmiş
async function gecmisYukle(){
  const r=await jget('/gecmis'); const l=$('gecmisListe');
  if(!r.kayitlar||!r.kayitlar.length){ l.innerHTML='<div class="ipuc">Henüz kayıt yok.</div>'; return; }
  l.innerHTML=r.kayitlar.slice(0,30).map((k,i)=>{
    const girdi=(k.girdiler[0]||'').split('/').pop();
    const cikti=(k.cikti||'').split('/').pop();
    const t=k.tarih?k.tarih.replace('T',' ').slice(5,16):'';
    const tur=k.tur==='sinav_pdf'?'📄 PDF':'🗜 zip';
    return `<div class="gecmis-satir"><span class="yol">${girdi} → ${cikti}</span>
      <span class="alt">${t} · ${k.soru} soru${k.test?' · '+k.test+' test':''} · ${tur}</span>
      <span class="btnlar">
        <button class="ikincil" ${k.cikti_var?'':'disabled'} onclick="gecmisGoster(${i})">📂 Göster</button>
        <button class="ikincil" ${k.girdi_var?'':'disabled'} onclick="gecmisAc(${i})">↺ Yeniden aç</button>
      </span></div>`;
  }).join('');
}
async function gecmisGoster(i){ await post('/gecmis-goster',{indeks:i}); }
async function gecmisAc(i){
  const r=await post('/gecmis-ac',{indeks:i});
  if(r.hata){ durum('Hata: '+r.hata,false); return; }
  dosyalariAyarla(r.yollar); onizle();
}
// klavye kısayolları
document.addEventListener('keydown',e=>{
  if(galeriAcik){   // overlay açıkken arka plan kısayolları susar — geri al/yinele hariç (galeriCikar'ın
                     // ürettiği 'secim' kaydı da buradan geri alınabilsin diye)
    if(e.key==='Escape'){ galeriKapat(); return; }
    if((e.metaKey||e.ctrlKey)&&(e.key==='z'||e.key==='Z')){ e.preventDefault(); if(e.shiftKey) yinele(); else geriAl(); return; }
    if((e.metaKey||e.ctrlKey)&&(e.key==='y'||e.key==='Y')){ e.preventDefault(); yinele(); return; }
    return;
  }
  if(e.target.tagName==='INPUT'||e.target.tagName==='SELECT'||e.target.tagName==='TEXTAREA'||e.target.isContentEditable) return;
  if(!gorunurMu('sahne')) return;   // Kesim sekmesi etkin ve belge yüklü değilse hiçbir kesim kısayolu çalışmaz
  if(e.key==='ArrowLeft') sayfaGez(-1);
  else if(e.key==='ArrowRight') sayfaGez(1);
  else if(e.key==='s'||e.key==='S'){ if($('modAnahtar').style.display!=='none') modAyarla('sec'); }
  else if(e.key==='d'||e.key==='D'){ if($('modAnahtar').style.display!=='none') modAyarla('duzenle'); }
  else if((e.key==='a'||e.key==='A')&&mod==='sec'){ e.preventDefault(); tumunuSec(!secimHepsiMi()); }
  else if((e.key==='Delete'||e.key==='Backspace')&&mod==='duzenle'&&secili.size){ e.preventDefault(); kutuSil(); }
  else if((e.key==='b'||e.key==='B')&&mod==='duzenle'&&gorunurMu('duzenKart')){ bolAc(); }
  else if((e.key==='n'||e.key==='N')&&mod==='duzenle'&&gorunurMu('duzenKart')){ e.preventDefault(); incelemeSonrakineGit(); }
  else if((e.key==='o'||e.key==='O')&&mod==='duzenle'&&gorunurMu('duzenKart')){ e.preventDefault(); incelemeOdaktakiOnayla(); }
  else if(e.key==='Escape'){ if(mod==='sec'){ tumunuSec(false); } else { secili.clear(); cizAyar(false); bolAyar(false); cizKutular(); } }
  else if((e.metaKey||e.ctrlKey)&&e.key==='Enter'){ if(!$('kesBtn').disabled) kes(); }
  else if((e.metaKey||e.ctrlKey)&&(e.key==='z'||e.key==='Z')){
    e.preventDefault(); if(e.shiftKey) yinele(); else geriAl();
  }
  else if((e.metaKey||e.ctrlKey)&&(e.key==='y'||e.key==='Y')){
    e.preventDefault(); yinele();
  }
  else if((e.metaKey||e.ctrlKey)&&(e.key==='+'||e.key==='=')){
    e.preventDefault(); zoomAyarla(yakZoom*1.25);
  }
  else if((e.metaKey||e.ctrlKey)&&(e.key==='-'||e.key==='_')){
    e.preventDefault(); zoomAyarla(yakZoom/1.25);
  }
  else if((e.metaKey||e.ctrlKey)&&e.key==='0'){
    e.preventDefault(); zoomAyarla(1);
  }
  else if(e.code==='Space'&&!spaceBasili){
    spaceBasili=true; e.preventDefault(); $('sahne').classList.add('pan');
  }
});
document.addEventListener('keyup',e=>{
  if(e.code==='Space'){ spaceBasili=false; $('sahne').classList.remove('pan'); }
});
gecmisYukle();
mlDurumYukle();
ocrDurumYukle();
if(location.hash==='#banka') gorunumAyarla('banka');   // derin bağlantı
// sürükle-bırak yükleme
const ana=$('onizleme');
['dragenter','dragover'].forEach(t=>ana.addEventListener(t,e=>{e.preventDefault();ana.classList.add('surukle');}));
['dragleave','drop'].forEach(t=>ana.addEventListener(t,e=>{e.preventDefault();if(t==='dragleave'&&e.target!==ana)return;ana.classList.remove('surukle');}));
ana.addEventListener('drop',async e=>{
  const dosyalar=[...e.dataTransfer.files]; if(!dosyalar.length) return;
  await dosyalariYukle(dosyalar);
});
// ==================== GÖRÜNÜM / TEMA ====================
function temaUygula(t){
  document.documentElement.dataset.theme=t;
  const b=$('temaBtn'); if(b) b.textContent = t==='light' ? '☀️' : '🌙';
  try{ localStorage.setItem('tema',t); }catch(e){}
}
function temaDegis(){ temaUygula(document.documentElement.dataset.theme==='light'?'dark':'light'); }
(function(){ let t; try{ t=localStorage.getItem('tema'); }catch(e){}
  if(t!=='light' && t!=='dark') t=matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';
  temaUygula(t); })();
// ==================== SORU BANKASI GÖRÜNÜMÜ ====================
function gorunumAyarla(hangi){
  const g={kesim:hangi==='kesim', banka:hangi==='banka', panel:hangi==='panel',
           optik:hangi==='optik', sihirbaz:hangi==='sihirbaz'};
  if(!g.kesim && !g.banka && !g.panel && !g.optik && !g.sihirbaz) g.kesim=true;
  $('onizleme').style.display=g.kesim?'flex':'none';
  $('kesimAside').style.display=g.kesim?'flex':'none';
  $('banka').style.display=g.banka?'flex':'none';
  $('optik').style.display=g.optik?'flex':'none';
  $('sihirbaz').style.display=g.sihirbaz?'flex':'none';
  $('dashboard').classList.toggle('acik',g.panel);
  $('tabKesim').classList.toggle('etkin',g.kesim);
  $('tabBanka').classList.toggle('etkin',g.banka);
  $('tabPanel').classList.toggle('etkin',g.panel);
  $('tabOptik').classList.toggle('etkin',g.optik);
  if($('tabSihirbaz'))$('tabSihirbaz').classList.toggle('etkin',g.sihirbaz);
  if(g.banka && !bankaYuklendi){ bankaYuklendi=true; bankaKonulariYukle(); bankaAra(); bankaAiDurumYukle(); bankaYenidenYukle(); }
  if(g.panel) panelYukle();
  if(g.optik && !optikYuklendi){ optikYuklendi=true; optikYukle(); }
  if(g.sihirbaz && !sihirbazYuklendi){ sihirbazYuklendi=true; shBaslat(); }
}
// ---------------------------------------------------- Sınav Sihirbazı
let sihirbazYuklendi=false, shAdim=1, shSecim=[], shHucreRaporu=[], shStok={};
async function shBaslat(){
  const st=await jget('/banka-istatistik');
  shStok=st.konu_zorluk||{};
  // kapsam açılırları
  const f=await jget('/banka-konular');
  const dold=(el,dizi)=>{ el.innerHTML='<option value="">(tümü)</option>'+
    (dizi||[]).map(x=>`<option>${x}</option>`).join(''); };
  dold($('shKaynak'),f.kaynak); dold($('shKonu'),f.konu);
  shMatrisKur(); shGit(1); shHavuzGuncelle();
  ['shKaynak','shKonu','shArama','shTarihBas','shTarihSon'].forEach(id=>
    $(id).addEventListener('change',shHavuzGuncelle));
}
function shKapsam(){
  return {kaynak:$('shKaynak').value||null, konu:$('shKonu').value||null,
    arama:$('shArama').value.trim()||null,
    tarih_bas:$('shTarihBas').value||null, tarih_son:$('shTarihSon').value||null};
}
async function shHavuzGuncelle(){
  const k=shKapsam(); const p=new URLSearchParams();
  Object.entries(k).forEach(([a,v])=>{ if(v)p.set(a,v); }); p.set('limit','1');
  const r=await jget('/banka-sorgula?'+p.toString());
  $('shHavuz').textContent='Havuz: '+(r.toplam||0)+' soru';
}
function shGit(n){
  shAdim=n;
  document.querySelectorAll('.sh-panel').forEach(p=>
    p.classList.toggle('etkin',+p.dataset.panel===n));
  document.querySelectorAll('.sh-stepper .adim').forEach(a=>{
    const i=+a.dataset.adim; a.classList.toggle('etkin',i===n);
    a.classList.toggle('tamam',i<n); });
}
function shMatrisKur(){
  const konular=Object.keys(shStok).filter(k=>k!=='(konusuz)');
  const zor=['kolay','orta','zor'];
  // Herhangi bir zorluk etiketi var mı? Yoksa yalnız "toplam" sütunu göster.
  const etiketVar=konular.some(k=>zor.some(z=>(shStok[k]||{})[z]));
  const sutunlar=etiketVar?zor.concat(['toplam']):['toplam'];
  const bas={kolay:'Kolay',orta:'Orta',zor:'Zor',toplam:'Zorluk farketmez'};
  let h='<tr><th>Konu</th>'+sutunlar.map(z=>`<th>${bas[z]}</th>`).join('')+'</tr>';
  konular.forEach(k=>{
    h+=`<tr><td style="text-align:left">${k}</td>`;
    sutunlar.forEach(z=>{
      const stok=z==='toplam'?Object.values(shStok[k]||{}).reduce((a,b)=>a+b,0)
                             :((shStok[k]||{})[z]||0);
      h+=`<td><input type="number" min="0" value="0" data-k="${k}" data-z="${z}">`+
         `<div class="stok">stok: ${stok}</div></td>`; });
    h+='</tr>';
  });
  $('shMatris').innerHTML=h||'<tr><td>Bankada konu etiketli soru yok. Önce AI ile etiketleyin.</td></tr>';
}
function shHucreler(){
  return [...$('shMatris').querySelectorAll('input')].map(i=>({
    konu:i.dataset.k, zorluk:i.dataset.z==='toplam'?null:i.dataset.z, adet:+i.value||0
  })).filter(h=>h.adet>0);
}
function shDengeliDagit(){
  const hedef=parseInt(prompt('Toplam kaç soru dağıtılsın?','20'))||0;
  const inputs=[...$('shMatris').querySelectorAll('input')];
  const stoklu=inputs.filter(i=>((shStok[i.dataset.k]||{})[i.dataset.z]||0)>0);
  if(!stoklu.length)return;
  const toplamStok=stoklu.reduce((s,i)=>s+((shStok[i.dataset.k]||{})[i.dataset.z]||0),0);
  inputs.forEach(i=>i.value=0);
  stoklu.forEach(i=>{ const stok=(shStok[i.dataset.k]||{})[i.dataset.z]||0;
    i.value=Math.min(stok,Math.round(hedef*stok/toplamStok)); });
}
async function shOrnekle(){
  const hucreler=shHucreler();
  if(!hucreler.length){ durum('En az bir hücreye adet girin.',false); return; }
  const r=await post('/banka-blueprint-sec',{hucreler,genel_filtre:shKapsam(),
    tohum:$('shTohum').value?+$('shTohum').value:null});
  shSecim=r.idler; shHucreRaporu=r.hucreler;
  let ozet=`Seçilen: ${r.idler.length} soru.`;
  if(r.eksik_toplam>0) ozet+=` <span class="eksik">${r.eksik_toplam} soru eksik (stok yetmedi).</span>`;
  $('shOzet').innerHTML=ozet;
  shKartlariCiz(); shGit(3);
}
function shKartlariCiz(){
  $('shSecimSayi').textContent=shSecim.length;
  $('shKartlar').innerHTML=shSecim.map(id=>
    `<div class="sh-kart"><img src="/banka-gorsel?id=${id}&kucuk=1" loading="lazy">`+
    `<div class="alt"><span>#${id}</span>`+
    `<span onclick="shCikar(${id})" style="cursor:pointer" title="çıkar">✕</span></div></div>`
  ).join('')||'<div class="ipuc">Seçim boş.</div>';
}
function shCikar(id){ shSecim=shSecim.filter(x=>x!==id); shKartlariCiz(); }
function shAyarlar(){
  return {baslik:$('shBaslik').value||'Sınav', kurum:$('shKurum').value||'',
    sutun:+$('shSutun').value||2, kitapcik:+$('shKitapcik').value||1,
    toplam_puan:$('shPuan').value?+$('shPuan').value:null,
    yeniden_numarala:$('shYenidenNo').checked, cevap_anahtari:$('shCevapAnah').checked};
}
async function shUret(){
  if(!shSecim.length){ durum('Önce soru örnekleyin.',false); return; }
  durum('Sınav üretiliyor…',true); islemYokla();
  const r=await post('/sihirbaz-uret',{idler:shSecim,ayarlar:shAyarlar(),
    ciktilar:{pdf:$('shCPdf').checked,docx:$('shCDocx').checked,optik:$('shCOptik').checked}});
  if(r.hata){ durum('Hata: '+r.hata,false); return; }
  indirBaslat(r.jeton,r.ad);
  $('shSonuc').textContent='✅ '+(r.dosyalar||[]).join(', ')+' indirildi.';
  if(r.onizleme){ $('shOnizleme').src=r.onizleme; $('shOnizleme').style.display='block'; }
  durum('Sınav hazır.',false);
}
async function shSablonKaydet(){
  const ad=prompt('Şablon adı:','Sınav taslağı'); if(!ad)return;
  await post('/banka-sablon-kaydet',{ad,tur:'blueprint',veri:{
    surum:1,kapsam:shKapsam(),hucreler:shHucreler(),
    tohum:$('shTohum').value?+$('shTohum').value:null,ayarlar:shAyarlar()}});
  durum('Şablon kaydedildi.',false);
}
// ---- büyük önizleme (lightbox) ----
function lightboxAc(id){ $('lightboxImg').src='/banka-gorsel?id='+id+'&kucuk=0'; $('lightbox').classList.add('acik'); }
function lightboxKapat(){ $('lightbox').classList.remove('acik'); $('lightboxImg').src=''; }
// ---- analitik panel ----
function _dagilim(obj,n){
  return Object.entries(obj||{}).filter(([k])=>!['(konusuz)','(?)','(boş)'].includes(k))
    .map(([ad,deger])=>({ad,deger,filtre:ad})).sort((a,b)=>b.deger-a.deger).slice(0,n);
}
function _zorDagilim(obj){
  obj=obj||{};
  const sira=[['kolay','Kolay','var(--c-kolay)'],['orta','Orta','var(--c-orta)'],['zor','Zor','var(--c-zor)']];
  const r=sira.filter(([k])=>obj[k]).map(([k,ad,renk])=>({ad,deger:obj[k],renk,filtre:k}));
  if(obj['(?)']) r.push({ad:'Etiketsiz',deger:obj['(?)'],renk:'var(--ipuc-c)',filtre:null});
  return r;
}
function _abcde(obj){
  obj=obj||{}; return ['A','B','C','D','E'].filter(c=>obj[c]).map(c=>({ad:c,deger:obj[c],filtre:c}));
}
function _barChart(baslik, data, tip){
  if(!data.length) return '';
  const maks=Math.max(...data.map(d=>d.deger))||1;
  const satirlar=data.map(d=>{
    const w=Math.max(4,Math.round(d.deger/maks*100));
    const c=d.renk||'var(--c1)';
    const flt=(tip && d.filtre!=null)?` onclick="panelFiltre('${tip}','${(''+d.filtre).replace(/'/g,"\\'")}')" title="Bankada filtrele"`:'';
    return `<div class="bar-satir"${flt}><span class="bar-ad" title="${_kac(d.ad)}">${_kac(d.ad)}</span>`
      +`<span class="bar-yol"><span class="bar-dolu" style="width:${w}%;background:${c}"></span></span>`
      +`<span class="bar-deg">${d.deger}</span></div>`;
  }).join('');
  return `<div class="chart"><h4>${baslik}</h4>${satirlar}</div>`;
}
async function panelYukle(){
  let s; try{ s=await jget('/banka-istatistik'); }catch(e){ $('statGrid').innerHTML='<div class="ipuc">Panel yüklenemedi.</div>'; return; }
  const konuSay=Object.keys(s.konu||{}).filter(k=>k!=='(konusuz)').length;
  const kaynakSay=Object.keys(s.kaynak||{}).filter(k=>k!=='(?)').length;
  const bosCevap=(s.cevap||{})['(boş)']||0;
  const cevapli=s.toplam?Math.round((s.toplam-bosCevap)/s.toplam*100):0;
  const aiPct=s.toplam?Math.round((s.ai_etiketli||0)/s.toplam*100):0;
  $('statGrid').innerHTML=[
    ['Toplam soru',s.toplam||0],['Konu',konuSay],['Kaynak',kaynakSay],
    ['Cevaplı',cevapli+'%'],['AI etiketli',aiPct+'%']
  ].map(([l,v])=>`<div class="stat"><div class="v">${v}</div><div class="l">${l}</div></div>`).join('');
  if(!s.toplam){
    $('chartGrid').innerHTML='<div class="ipuc" style="padding:24px">Banka henüz boş — kesim yapıp soruları bankaya aktarın.</div>';
    $('aktiviteListe').innerHTML=''; return;
  }
  $('chartGrid').innerHTML=
    _barChart('Konu dağılımı (ilk 10)', _dagilim(s.konu,10), 'konu')
    +_barChart('Zorluk', _zorDagilim(s.zorluk), 'zorluk')
    +_barChart('Doğru cevap', _abcde(s.cevap), 'cevap')
    +_barChart('Kaynağa göre (ilk 8)', _dagilim(s.kaynak,8), 'kaynak');
  const turAd={zip:'Kesim (ZIP)', sinav_pdf:'Sınav PDF', banka:'Bankaya aktarım',
    banka_docx:'Word sınav', banka_pdf:'PDF sınav'};
  try{
    const g=await jget('/gecmis');
    const k=(g.kayitlar||[]);
    $('aktiviteListe').innerHTML=k.slice(0,8).map(x=>{
      const ad=(''+(x.cikti||'')).split('/').pop()||(turAd[x.tur]||x.tur||'');
      const alt=[turAd[x.tur]||x.tur, (x.soru!=null?x.soru+' soru':''), (''+(x.tarih||'')).replace('T',' ').slice(0,16)].filter(Boolean).join(' · ');
      return `<div class="gecmis-satir"><span class="yol">${_kac(ad)}</span><span class="alt">${_kac(alt)}</span></div>`;
    }).join('')||'<div class="ipuc">Aktivite yok.</div>';
  }catch(e){ $('aktiviteListe').innerHTML='<div class="ipuc">—</div>'; }
}
async function panelFiltre(tip, deger){
  gorunumAyarla('banka');
  try{ await bankaKonulariYukle(); }catch(e){}
  const id={konu:'bfKonu',kaynak:'bfKaynak',cevap:'bfCevap',zorluk:'bfZorluk'}[tip];
  const el=$(id); if(el) el.value=deger;
  bankaAra();
}
async function bankaKonulariYukle(){
  const r=await jget('/banka-konular');
  const dld=(id,bas,liste)=>{ $(id).innerHTML='<option value="">'+bas+'</option>'+
    (liste||[]).map(k=>`<option>${(''+k).replace(/</g,'&lt;')}</option>`).join(''); };
  dld('bfKonu','Tüm konular',r.konular);
  dld('bfKaynak','Tüm kaynaklar',r.kaynaklar);
}
async function bankaYenidenYukle(){
  let r; try{ r=await jget('/banka-yeniden-isleme'); }catch(e){ return; }
  const kart=$('yenidenKart'), alan=$('yenidenOzet');
  if(!r||!r.aktif||!r.kayit){ kart.style.display='none'; return; }
  const k=r.kayit, d=k.inceleme_durumlari||{};
  kart.style.display='block';
  alan.innerHTML=`<div><b>${htmlKacir(k.kaynak||'Kaynak')}</b> · V${htmlKacir(k.algoritma_surumu||'?')}</div>
    <div style="margin-top:5px">Eski: <b>${k.eski_toplam||0}</b> · Yeni aday: <b>${k.yeni_toplam||0}</b>
      · fark: <b>${k.fark>=0?'+':''}${k.fark||0}</b></div>
    <div style="margin-top:4px;color:var(--yesil)">${d.otomatik||0} otomatik</div>
    <div style="color:var(--uyari)">${d.incele||0} inceleme</div>
    <div style="color:var(--vurgu)">${d.reddedildi||0} ret</div>
    <div style="margin-top:5px">Durum: <b>Onay bekliyor</b>. Mevcut kayıtlar değiştirilmedi.</div>`;
}
function bankaFiltreObj(){
  const o={}; const al=(id,k)=>{const v=$(id).value.trim(); if(v)o[k]=v;};
  al('bfKonu','konu'); al('bfKaynak','kaynak'); al('bfCevap','cevap'); al('bfZorluk','zorluk');
  al('bfBos','bos'); al('bfEtiket','etiket'); al('bfArama','arama'); return o;
}
async function bankaAiDurumYukle(){
  try{ const r=await jget('/ai-durum');
    $('aiDurum').textContent=r.ok?('🟢 '+r.mesaj):('🔴 '+(r.mesaj||'AI kapalı')); }
  catch(e){ $('aiDurum').textContent=''; }
}
async function mlDurumYukle(){
  try{ const r=await jget('/ml-durum');
    $('mlDuzen').checked=!!r.aktif; $('geminiVision').checked=!!r.gemini_vision_aktif;
    $('mlDurum').textContent=r.ok?('🟢 '+r.mesaj):('🔴 '+r.mesaj); }
  catch(e){ $('mlDurum').textContent=''; }
}
async function mlDuzenKaydet(){
  await post('/ayar-kaydet',{duzen_model_aktif:$('mlDuzen').checked});
  durum('ML düzen tespiti '+($('mlDuzen').checked?'açıldı':'kapatıldı')+
        ' — yeni belge yüklemesinde geçerli.',false);
}
async function ocrDurumYukle(){
  try{ const r=await jget('/ocr-durum');
    if($('ocrModu')) $('ocrModu').value=r.mod||'hizli';
    const m=r.motorlar||{};
    const rozet=Object.keys(m).map(k=>(m[k]?'🟢':'🔴')+k).join(' ');
    if($('ocrDurum')) $('ocrDurum').textContent=r.kurulu?rozet:
      ('🔴 çok-motor OCR kurulu değil ('+r.kurulum_komutu+')'); }
  catch(e){ if($('ocrDurum')) $('ocrDurum').textContent=''; }
}
async function ocrModuKaydet(){
  const mod=$('ocrModu').value;
  await post('/ayar-kaydet',{ocr_modu:mod});
  durum('OCR modu: '+mod+' — yeni belge yüklemesinde geçerli.',false);
  ocrDurumYukle();
}
async function geminiVisionKaydet(){
  const aktif=$('geminiVision').checked;
  await post('/ayar-kaydet',{gemini_vision_aktif:aktif});
  durum(aktif?'Gemini Vision yalnız düşük güvenli sayfalar için etkinleştirildi.':
    'Gemini Vision yedeği kapatıldı; işleme tamamen yerel kalacak.',false);
}
async function aiAnahtarKaydet(){
  const k=$('aiAnahtar').value.trim(); if(!k){ durum('Anahtar boş.',false); return; }
  await post('/ayar-kaydet',{gemini_api_key:k});
  $('aiAnahtar').value=''; durum('AI anahtarı kaydedildi.',false);
  $('aiDurum').textContent='🟡 doğrulanıyor…'; bankaAiDurumYukle();
}
async function bankaAiEtiketle(onay){
  const kapsam=$('aiKapsam').value; const body={kapsam,onay:!!onay};
  if(kapsam==='sepet'){ if(!bankaSepet.length){ durum('Sepet boş — önce soru seçin.',false); return; } body.idler=bankaSepet; }
  else body.filtre=bankaFiltreObj();
  durum('🤖 AI ile konu/başlık belirleniyor… (sürebilir)',true); islemYokla();
  try{
    const r=await post('/banka-ai-etiketle',body);
    if(r.onay_gerek){ durdurYokla();
      if(confirm(r.onay_gerek+' soru AI ile etiketlenecek. Sürebilir ve kota kullanır. Devam?'))
        return bankaAiEtiketle(true);
      durum('İptal edildi.',false); return; }
    if(r.hata){ durum('Hata: '+r.hata,false); return; }
    const bas=r.basarisiz?` · ${r.basarisiz} etiketlenemedi (kota? yeniden deneyin)`:'';
    durum(`✅ ${r.etiketlenen}/${r.toplam} soru AI ile etiketlendi${bas}`,false);
    await bankaKonulariYukle(); bankaAra();
  }catch(e){ durum('Bağlantı hatası: '+e,false); }
  finally{ durdurYokla(); }
}
function bankaFiltreQuery(){
  const p=new URLSearchParams();
  const al=(id,ad)=>{ const v=$(id).value.trim(); if(v)p.set(ad,v); };
  al('bfKonu','konu'); al('bfKaynak','kaynak'); al('bfCevap','cevap'); al('bfZorluk','zorluk');
  al('bfBos','bos'); al('bfEtiket','etiket'); al('bfArama','arama');
  p.set('limit',bankaLimit); p.set('ofset',bankaOfset);
  return p.toString();
}
async function bankaAra(){
  bankaOfset=0;
  const r=await jget('/banka-sorgula?'+bankaFiltreQuery());
  if(r.hata){ $('bankaGrid').innerHTML='<div class="ipuc">Hata: '+r.hata+'</div>'; return; }
  bankaKayitlar=r.kayitlar||[]; bankaToplam=r.toplam||0;
  bankaGridCiz(); bankaGezGuncelle();
}
function bankaAraGecikmeli(){ clearTimeout(bankaAramaZaman); bankaAramaZaman=setTimeout(bankaAra,400); }
function _kac(s){ return (''+s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function _zorChip(z){ const m={kolay:'zor-kolay',orta:'zor-orta',zor:'zor-zor'}[z]; return m?`<span class="chip ${m}">${z}</span>`:''; }
function _bkart(k){
  const sec=bankaSecili.has(k.id);
  const bas=k.baslik||k.konu||'';
  const alt=[k.kaynak, k.soru_no!=null?('S'+k.soru_no):'', k.cevap?('· '+k.cevap):''].filter(Boolean).join(' ');
  return `<div class="bkart${sec?' sec':''}" onclick="bankaSecTog(${k.id})" ondblclick="lightboxAc(${k.id})" title="Tık: seç · Çift tık: büyüt">
    <img loading="lazy" src="/banka-gorsel?id=${k.id}&kucuk=1" alt="">
    <div class="et">${bas?('<b>'+_kac(bas)+'</b>'):''}${_zorChip(k.zorluk)}${bas||k.zorluk?'<br>':''}${_kac(alt)}</div></div>`;
}
function bankaGridCiz(){
  const g=$('bankaGrid');
  if(!bankaKayitlar.length){ g.style.display='grid'; g.innerHTML='<div class="ipuc">Eşleşen soru yok. Kesim görünümünde soru kesip “Soru Bankasına Aktar”a basın.</div>'; return; }
  const grupla=$('grupla')&&$('grupla').checked;
  if(grupla){
    g.style.display='block';
    const K={}; bankaKayitlar.forEach(k=>{ const c=k.konu||'(konusuz)'; (K[c]=K[c]||[]).push(k); });
    g.innerHTML=Object.keys(K).sort().map(c=>
      `<div style="display:flex;align-items:center;gap:8px;margin:12px 0 6px">
        <b style="color:var(--metin);font-size:15px">${_kac(c)}</b><span class="ipuc">${K[c].length} soru</span>
        <button class="ikincil" style="padding:3px 8px;font-size:11px;margin-left:auto" onclick="konuSepete('${c.replace(/'/g,"\\'")}')">konudan hepsini sepete</button></div>
       <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px">${K[c].map(_bkart).join('')}</div>`
    ).join('');
  } else {
    g.style.display='grid';
    g.innerHTML=bankaKayitlar.map(_bkart).join('');
  }
}
function konuSepete(konu){
  bankaKayitlar.filter(k=>(k.konu||'(konusuz)')===konu).forEach(k=>{
    if(!bankaSecili.has(k.id)){ bankaSecili.add(k.id); bankaSepet.push(k.id); } });
  bankaGridCiz(); sepetCiz();
}
function bankaSecTog(id){
  if(bankaSecili.has(id)){ bankaSecili.delete(id); bankaSepet=bankaSepet.filter(x=>x!==id); }
  else { bankaSecili.add(id); bankaSepet.push(id); }
  bankaGridCiz(); sepetCiz();
}
function bankaSepeteHepsi(){
  bankaKayitlar.forEach(k=>{ if(!bankaSecili.has(k.id)){ bankaSecili.add(k.id); bankaSepet.push(k.id); } });
  bankaGridCiz(); sepetCiz();
}
async function bankaKonudanRastgele(){
  const n=+$('bfRastN').value; if(!n){ durum('Rastgele için N girin.',false); return; }
  const r=await jget('/banka-sorgula?'+bankaFiltreQuery()+'&rastgele='+n);
  (r.kayitlar||[]).forEach(k=>{ if(!bankaSecili.has(k.id)){ bankaSecili.add(k.id); bankaSepet.push(k.id); } });
  sepetCiz(); bankaGridCiz();
}
function sepetCiz(){
  $('sepetSayi').textContent=bankaSepet.length;
  $('sepetListe').innerHTML=bankaSepet.length? bankaSepet.map((id,i)=>{
    const k=bankaKayitlar.find(x=>x.id===id);
    const ad=k?((k.konu||k.kaynak||'')+(k.soru_no!=null?(' S'+k.soru_no):'')):('#'+id);
    return `<div class="sepet-satir"><span>${i+1}. ${(''+ad).replace(/</g,'&lt;')}</span>
      <button onclick="sepetSirala(${id},-1)">▲</button>
      <button onclick="sepetSirala(${id},1)">▼</button>
      <button onclick="sepetCikar(${id})">✕</button></div>`;
  }).join('') : '<div class="ipuc">Izgaradan soru seçin.</div>';
}
function sepetSirala(id,yon){ const i=bankaSepet.indexOf(id),j=i+yon;
  if(j<0||j>=bankaSepet.length) return;
  [bankaSepet[i],bankaSepet[j]]=[bankaSepet[j],bankaSepet[i]]; sepetCiz(); }
function sepetCikar(id){ bankaSecili.delete(id); bankaSepet=bankaSepet.filter(x=>x!==id); sepetCiz(); bankaGridCiz(); }
function sepetTemizle(){ bankaSecili.clear(); bankaSepet=[]; sepetCiz(); bankaGridCiz(); }
async function bankaSayfa(yon){
  const yeni=bankaOfset+yon*bankaLimit;
  if(yeni<0||yeni>=bankaToplam) return; bankaOfset=yeni;
  const r=await jget('/banka-sorgula?'+bankaFiltreQuery());
  bankaKayitlar=r.kayitlar||[]; bankaToplam=r.toplam||bankaToplam;
  bankaGridCiz(); bankaGezGuncelle();
}
function bankaGezGuncelle(){ const bas=bankaToplam?bankaOfset+1:0;
  $('bankaGezEt').textContent=`${bas}–${Math.min(bankaOfset+bankaLimit,bankaToplam)} / ${bankaToplam} soru`;
  $('bankaBilgi').textContent=bankaToplam+' soru bankada'; }
function bSinavAyar(){ return {
  baslik:$('bBaslik').value.trim(), kurum:$('bKurum').value.trim(),
  ad_soyad:$('bAlanAd').checked, sinif:$('bAlanSinif').checked, tarih:$('bAlanTarih').checked,
  yeniden_numarala:$('bYeniden').checked, cevap_anahtari:$('bCevapAnah').checked,
  sutun:+$('bSutun').value, toplam_puan:+$('bPuan').value||null, kitapcik:+$('bKitapcik').value,
  optik_form:$('bOptik').checked }; }
function optikMesaji(o){
  if(!o) return '';
  if(o.hata) return ` · ⚠ optik form üretilemedi: ${o.hata}`;
  optikYuklendi=false;   // Optik sekmesi bir dahaki açılışta yeni sınavı görsün
  const a=o.anahtarli_soru?`, ${o.anahtarli_soru} cevap anahtarı`:'';
  const k=o.kazanimli_soru?`, ${o.kazanimli_soru} kazanım`:'';
  const u=(o.uyarilar&&o.uyarilar.length)?` · ⚠ ${o.uyarilar.join('; ')}`:'';
  return ` · 🔘 optik hazır (kimlik ${o.sinav_id}${a}${k})${u}`;
}
async function bankaSinav(bicim){
  if(!bankaSepet.length){ durum('Sepet boş — önce soru seçin.',false); return; }
  durum(bicim==='docx'?'Word üretiliyor…':'PDF üretiliyor…',true); islemYokla();
  const r=await post('/banka-sinav',{secili_idler:bankaSepet,bicim,ayarlar:bSinavAyar()});
  durdurYokla();
  if(r.hata){ durum('Hata: '+r.hata,false); return; }
  indirBaslat(r.jeton,r.ad);
  const km=r.kitapcik>1?` · ${r.kitapcik} kitapçık`:'';
  durum(`✅ ${r.soru} soru, ${r.sayfa||''} sayfa${km} indirildi: ${r.ad}`
    +optikMesaji(r.optik),false);
  gecmisYukle();
}
// ==================== OPTİK OKUYUCU ====================
let optikYuklendi=false, optikSinav=null, optikSinavAd='', optikKagitId=null,
    optikKagitDetay=null, optikDersListe=[], optikOnAyarlar=[];
async function oGet(u){ const r=await fetch(u); const j=await r.json();
  if(j&&j.hata) throw new Error(j.hata); return j; }
async function oPost(u,g){ const r=await fetch(u,{method:'POST',
  headers:{'Content-Type':'application/json'},body:JSON.stringify(g||{})});
  const j=await r.json(); if(j&&j.hata) throw new Error(j.hata); return j; }
function optikSekme(ad){
  for(const s of ['form','tara','sonuc','incele','analiz']){
    $('op'+s).style.display = s===ad?'flex':'none';
    $('osek'+s).classList.toggle('etkin', s===ad);
  }
  if(ad==='sonuc') optikSonuclarYukle();
  if(ad==='incele') optikKagitlarYukle();
  if(ad==='analiz') optikAnalizYukle();
}
async function optikYukle(){
  try{
    const d=await oGet('/optik-durum');
    optikOnAyarlar=d.on_ayarlar||[];
    const sel=$('opOnAyar');
    for(const o of optikOnAyarlar){ const e=document.createElement('option');
      e.value=o.ad; e.textContent=o.baslik+'  ('+o.ad+')'; sel.appendChild(e); }
    $('optikKurulum').textContent = d.ok ? '🟢 okuma motoru hazır'
      : '🔴 '+(d.mesaj||'okuma motoru kurulu değil');
  }catch(e){ $('optikKurulum').textContent='🔴 '+e.message; }
  optikDersEkle('','20','4');
  optikSinavlariYukle();
}
function optikOnAyarSec(){ /* ön ayar seçilince tasarımcı alanları kilitlenmez;
  ad boşsa ön ayar başlığı yazılır */
  const v=$('opOnAyar').value, o=optikOnAyarlar.find(x=>x.ad===v);
  if(o && !$('opAd').value) $('opAd').value=o.baslik;
  if(v.startsWith('lgs')) $('opBolen').value='3';
  else if(v==='tyt'||v==='ayt') $('opBolen').value='4';
}
function optikDersEkle(ad,soru,secenek){
  const kutu=document.createElement('div'); kutu.className='op-ders';
  kutu.innerHTML=`<input type="text" placeholder="Ders adı (tek bölümse boş)" value="${ad||''}">
    <input type="number" min="1" max="200" value="${soru||'20'}" title="soru sayısı">
    <select title="şık sayısı"><option value="3">3 şık</option>
      <option value="4" ${(secenek||'4')==='4'?'selected':''}>4 şık</option>
      <option value="5" ${secenek==='5'?'selected':''}>5 şık</option></select>
    <button class="ikincil" style="padding:4px 8px" onclick="this.parentNode.remove()">✕</button>`;
  $('opDersler').appendChild(kutu);
}
function optikDersleriOku(){
  return [...$('opDersler').children].map(k=>{
    const [ad,soru]=k.querySelectorAll('input');
    return {ad:ad.value.trim(), soru:+soru.value||0, secenek:+k.querySelector('select').value};
  }).filter(d=>d.soru>0);
}
async function optikUret(){
  const onAyar=$('opOnAyar').value;
  const g={on_ayar:onAyar||null, ad:$('opAd').value.trim()||null,
    kurum:$('opKurum').value.trim()||null, kitapcik:+$('opKitapcik').value,
    ogrenci_no_hane:+$('opNoHane').value, tc:$('opTc').checked,
    ad_soyad:$('opAdSoyad').checked, yanlis_boler:+$('opBolen').value};
  const dersler=optikDersleriOku();
  if(!onAyar && !dersler.length){ $('opUretDurum').textContent='En az bir ders girin veya ön ayar seçin.'; return; }
  if(dersler.length) g.dersler=dersler;
  $('opUretDurum').textContent='Üretiliyor…';
  try{
    const r=await oPost('/optik-uret',g);
    indirBaslat(r.jeton,r.ad);
    $('opUretDurum').textContent=`✅ ${r.soru} soru, ${r.sayfa} sayfa — kimlik ${r.sinav_id} (indirildi)`;
    optikSinavlariYukle(r.sinav_id);
  }catch(e){ $('opUretDurum').textContent='❌ '+e.message; }
}
async function optikSinavlariYukle(secilecek){
  try{
    const r=await oGet('/optik-sinavlar');
    const tb=$('opSinavTablo').querySelector('tbody'); tb.innerHTML='';
    for(const s of r.sinavlar){
      const tr=document.createElement('tr'); tr.className='secilebilir';
      if(s.id===(secilecek||optikSinav)) tr.classList.add('aktif');
      tr.innerHTML=`<td>${s.ad}</td><td><code>${s.id}</code></td><td>${s.kagit_sayisi}</td>
        <td>${s.inceleme_sayisi||''}</td><td>${s.anahtar_sayisi||''}</td>
        <td>${(s.olusturma||'').slice(0,16)}</td>`;
      tr.onclick=()=>optikSinavSec(s.id,s.ad);
      tb.appendChild(tr);
    }
    if(secilecek){ const s=r.sinavlar.find(x=>x.id===secilecek);
      if(s) optikSinavSec(s.id,s.ad); }
  }catch(e){ durum('Optik sınav listesi: '+e.message,true); }
}
function optikSinavSec(id,ad){
  optikSinav=id; optikSinavAd=ad; optikKagitId=null;
  $('optikSinavEtiket').textContent='🎯 '+ad+' ('+id+')';
  [...$('opSinavTablo').querySelectorAll('tr')].forEach(tr=>
    tr.classList.toggle('aktif',tr.cells&&tr.cells[1]&&tr.cells[1].textContent===id));
}
function optikSinavGerekli(){ if(!optikSinav){ durum('Önce Formlar sekmesinden bir sınav seçin.',true);
  optikSekme('form'); return false;} return true; }
async function optikDosyalar(dosyalar){
  if(!optikSinavGerekli()||!dosyalar.length) return;
  $('opTaraDurum').textContent='Yükleniyor…';
  const yollar=[];
  for(const d of dosyalar){
    const r=await fetch('/yukle-dosya?ad='+encodeURIComponent(d.name),
      {method:'POST',body:d});
    const j=await r.json();
    if(j.hata){ $('opTaraDurum').textContent='❌ '+j.hata; return; }
    yollar.push(j.yol);
  }
  $('opTaraDurum').textContent='Okunuyor… (ilk sayfa işçi açılışıyla ~5 sn sürebilir)';
  const izleyici=setInterval(async()=>{ try{
    const p=await oGet('/ilerleme');
    if(p.asama==='optik') $('opTaraDurum').textContent=`Okunuyor… ${p.yapilan}/${p.toplam}`;
  }catch(e){} },800);
  try{
    const r=await oPost('/optik-tara',{sinav:optikSinav,yollar});
    $('opTaraDurum').textContent=`✅ ${r.okunan} sayfa: ${r.temiz} temiz, ${r.kuyruk} incelemede, ${r.hatali} hatalı`
      +(r.kuyruk?' → İncele sekmesine bakın':'');
    optikSinavlariYukle();
  }catch(e){ $('opTaraDurum').textContent='❌ '+e.message; }
  finally{ clearInterval(izleyici); }
}
async function optikSonuclarYukle(){
  if(!optikSinavGerekli()) return;
  try{
    const r=await oGet('/optik-sonuclar?sinav='+optikSinav);
    const ks=$('opAnahtarKitapcik'); ks.innerHTML='';
    for(const k of r.kitapciklar){ const o=document.createElement('option');
      o.textContent=k; ks.appendChild(o); }
    $('opAnahtarDurum').textContent=r.anahtarli.length
      ? 'kayıtlı anahtar: '+r.anahtarli.join(', ') : 'henüz anahtar yok';
    const thead=$('opSonucTablo').querySelector('thead');
    const dersler=r.dersler.length?r.dersler:[''];
    thead.innerHTML='<tr><th>#</th><th>No</th><th>Ad Soyad</th><th>Kit</th>'
      +dersler.map(d=>`<th>${d||'Genel'} Net</th>`).join('')
      +'<th>D</th><th>Y</th><th>B</th><th>Net</th><th>%</th><th></th></tr>';
    const tb=$('opSonucTablo').querySelector('tbody'); tb.innerHTML='';
    for(const s of r.sonuclar){
      const tr=document.createElement('tr');
      tr.innerHTML=`<td>${s.sira}</td><td>${s.ogrenci_no||'?'}</td>
        <td>${s.ad_soyad||''}</td><td>${s.kitapcik||''}</td>
        ${dersler.map(d=>{const x=s.dersler[d];return `<td>${x?x.net:''}</td>`;}).join('')}
        <td>${s.dogru}</td><td>${s.yanlis}</td><td>${s.bos}</td>
        <td><b>${s.net}</b></td><td>${s.yuzde}</td>
        <td title="${(s.sorunlar||[]).join(' | ')}">${(s.sorunlar||[]).length?'⚠':''}</td>`;
      tb.appendChild(tr);
    }
  }catch(e){ durum('Sonuçlar: '+e.message,true); }
}
async function optikAnahtarKaydet(){
  if(!optikSinavGerekli()) return;
  const metin=$('opAnahtarMetin').value.trim();
  if(!metin){ durum('Anahtar metni boş.',true); return; }
  const cevaplar={};
  for(const satir of metin.split(/\\n+/)){
    let ders='', dizi=satir.trim(); if(!dizi) continue;
    const e=dizi.indexOf('='); if(e>0){ ders=dizi.slice(0,e).trim(); dizi=dizi.slice(e+1); }
    const h={}; let no=0;
    for(const c of dizi.trim().toUpperCase()){
      no++; h[String(no)] = ('.-'.includes(c)) ? '' : c;
    }
    cevaplar[ders]=h;
  }
  try{
    const r=await oPost('/optik-anahtar',{sinav:optikSinav,
      kitapcik:$('opAnahtarKitapcik').value, cevaplar});
    durum(`✅ kitapçık ${r.kitapcik} anahtarı kaydedildi (${r.soru} soru)`,false);
    optikSonuclarYukle();
  }catch(e){ durum('Anahtar: '+e.message,true); }
}
async function optikDisa(tur){
  if(!optikSinavGerekli()) return;
  try{ const r=await oPost('/optik-disa',{sinav:optikSinav,tur});
    indirBaslat(r.jeton,r.ad); durum('✅ indirildi: '+r.ad,false);
  }catch(e){ durum('Dışa aktarım: '+e.message,true); }
}
async function optikKagitlarYukle(){
  if(!optikSinavGerekli()) return;
  try{
    const d=$('opSadeceKuyruk').checked?'&durum=incelenecek':'';
    const r=await oGet('/optik-kagitlar?sinav='+optikSinav+d);
    const tb=$('opKagitTablo').querySelector('tbody'); tb.innerHTML='';
    for(const k of r.kagitlar){
      const tr=document.createElement('tr'); tr.className='secilebilir';
      if(k.id===optikKagitId) tr.classList.add('aktif');
      tr.innerHTML=`<td>#${k.id}</td><td>${k.ogrenci_no||'?'}</td>
        <td><span class="op-rozet ${k.durum}">${k.durum}</span></td>
        <td title="${(k.sorunlar||[]).join(' | ')||k.hata||''}">${(k.sorunlar||[]).length||k.hata?'⚠':''}</td>`;
      tr.onclick=()=>optikKagitAc(k.id);
      tb.appendChild(tr);
    }
    if(!r.kagitlar.length) tb.innerHTML='<tr><td class="ipuc">kağıt yok</td></tr>';
  }catch(e){ durum('Kağıtlar: '+e.message,true); }
}
async function optikKagitAc(id){
  optikKagitId=id;
  try{
    const r=await oGet('/optik-kagit?id='+id);
    optikKagitDetay=r;
    const k=r.kagit;
    $('opKagitBaslik').innerHTML=`<b>#${k.id}</b>
      <span class="op-rozet ${k.durum}">${k.durum}</span>
      <span class="ipuc">${k.kaynak?k.kaynak.split('/').pop():''} s.${k.kaynak_sayfa||''}</span>
      <span class="ipuc">${(k.sorunlar||[]).join(' · ')}${k.hata?' · '+k.hata:''}</span>`;
    $('opKagitDuzelt').hidden=false;
    $('opDuzNo').value=k.ogrenci_no||''; $('opDuzAd').value=k.ad_soyad||'';
    const ks=$('opDuzKitapcik'); ks.innerHTML='<option value="">kitapçık?</option>';
    for(const kt of (optikKagitDetay.kitapciklar||['A','B','C','D'])){
      const o=document.createElement('option'); o.textContent=kt;
      if(kt===k.kitapcik) o.selected=true; ks.appendChild(o); }
    $('opWarp').src='/optik-kagit-gorsel?id='+id+'&t='+Date.now();
    optikKagitlarYukle();
  }catch(e){ durum('Kağıt: '+e.message,true); }
}
function optikOverlayCiz(){
  const img=$('opWarp'), ov=$('opOverlay'); ov.innerHTML='';
  if(!optikKagitDetay||!img.naturalWidth) return;
  const f=img.clientWidth/img.naturalWidth;
  for(const g of optikKagitDetay.gruplar){
    const sorunlu=g.hukum==='belirsiz'||g.hukum==='coklu';
    for(const b of g.balonlar){
      const e=document.createElement('div');
      e.className='op-balon'+(b.isaretli?' isaretli':'')+(sorunlu?' sorunlu':'')
        +(g.duzeltildi?' duzeltildi':'');
      const r=Math.max(6,b.r*f);
      e.style.cssText=`left:${b.x*f}px;top:${b.y*f}px;width:${r*2}px;height:${r*2}px`;
      e.title=`${g.ders?g.ders+' ':''}${g.no}. soru — ${b.sembol}`
        +(g.hukum?` (okunan: ${g.hukum}${g.sembol?' '+g.sembol:''})`:'');
      e.onclick=()=>optikBalonTikla(g,b);
      ov.appendChild(e);
    }
  }
}
async function optikBalonTikla(g,b){
  const yeni = (g.sembol===b.sembol) ? '' : b.sembol;   // aynı şıka tıkla → boş
  try{
    await oPost('/optik-duzelt',{kagit:optikKagitId,ders:g.ders,soru:g.no,sembol:yeni});
    optikKagitAc(optikKagitId);
  }catch(e){ durum('Düzeltme: '+e.message,true); }
}
async function optikKimlikDuzelt(){
  try{
    await oPost('/optik-duzelt',{kagit:optikKagitId,
      ogrenci_no:$('opDuzNo').value.trim(), ad_soyad:$('opDuzAd').value.trim(),
      kitapcik:$('opDuzKitapcik').value});
    durum('✅ kimlik güncellendi',false); optikKagitAc(optikKagitId);
  }catch(e){ durum('Düzeltme: '+e.message,true); }
}
async function optikKagidiAnahtarYap(){
  if(!optikKagitId) return;
  const kitapcik=$('opDuzKitapcik').value||'A';
  try{
    const r=await oPost('/optik-anahtar',{sinav:optikSinav,kitapcik,kagit_id:optikKagitId});
    durum(`✅ kağıt #${optikKagitId} → kitapçık ${r.kitapcik} anahtarı (${r.soru} soru)`,false);
  }catch(e){ durum('Anahtar: '+e.message,true); }
}
async function optikAnalizYukle(){
  if(!optikSinavGerekli()) return;
  try{
    const r=await oGet('/optik-analiz?sinav='+optikSinav);
    const t=r.test||{};
    $('opTestOzet').textContent = t.katilimci
      ? `${t.katilimci} katılımcı · ort. doğru ${t.ortalama_dogru} · ort. net ${t.ortalama_net} · ss ${t.ss} · KR-20 ${t.kr20??'-'}`
      : 'analiz için okunmuş kağıt + anahtar gerekli';
    const tb=$('opAnalizTablo').querySelector('tbody'); tb.innerHTML='';
    for(const s of (r.sorular||[])){
      const tr=document.createElement('tr');
      const dag=Object.entries(s.dagilim).map(([k,v])=>k+':'+v).join(' ');
      tr.innerHTML=`<td>${s.ders||'Genel'}</td><td>${s.soru}</td><td>${s.dogru_cevap||''}</td>
        <td>${s.p}</td><td>${s.ayirt_edicilik}</td><td>${s.nokta_ciftserili}</td>
        <td>${dag}</td><td style="color:var(--c-zor,#dc2626)">${(s.uyarilar||[]).join('; ')}</td>`;
      tb.appendChild(tr);
    }
    const kl=$('opKazanimListe'); kl.innerHTML='';
    for(const k of (r.kazanim||[])){
      const d=document.createElement('div'); d.className='ipuc';
      d.style.cssText='padding:3px 0;font-size:12.5px;color:'
        +(k.yuzde<50?'#dc2626':k.yuzde>=80?'#16a34a':'var(--metin)');
      d.textContent=`%${k.yuzde}  ${k.kazanim} (${k.ders||'Genel'}, soru: ${k.sorular.join(',')})`;
      kl.appendChild(d);
    }
  }catch(e){ durum('Analiz: '+e.message,true); }
}
async function optikKazanimYukle(){
  if(!optikSinavGerekli()) return;
  const dosya=$('opKazanimDosya').files[0];
  if(!dosya){ durum('Önce CSV dosyası seçin.',true); return; }
  try{
    const csv=await dosya.text();
    const r=await oPost('/optik-kazanim',{sinav:optikSinav,csv});
    durum(`✅ ${r.soru} soru için kazanım eşlendi`,false);
    optikAnalizYukle();
  }catch(e){ durum('Kazanım: '+e.message,true); }
}
addEventListener('resize',()=>{ if($('optik').style.display!=='none') optikOverlayCiz(); });
// URL hash ile derin bağlantı: /#panel, /#banka, /#optik sekmeyi; /#panel,light temayı da açar
(function(){ (location.hash||'').replace('#','').split(',').forEach(x=>{
  if(x==='panel'||x==='banka'||x==='optik') gorunumAyarla(x);
  else if(x==='light'||x==='dark') temaUygula(x); }); })();
</script></body></html>"""


# --------------------------------------------------------- optik okuyucu

OPTIK_WARP_OLCEK = (200.0 / 72.0) / 2.0   # şablon pt → warp önizleme px


def _optik_baglan():
    import optik_kayit
    return optik_kayit.baglan()


def optik_durum_verisi():
    try:
        import optik_oku
        durum = optik_oku.optik_dogrula()
    except Exception as e:  # noqa: BLE001
        durum = {"ok": False, "mesaj": f"optik modülleri yüklenemedi: {e}"}
    try:
        import optik_form
        durum["on_ayarlar"] = [
            {"ad": k, "baslik": v.get("ad", k)}
            for k, v in sorted(optik_form.ON_AYARLAR.items())]
    except Exception:  # noqa: BLE001
        durum["on_ayarlar"] = []
    return durum


def optik_sinavlar_verisi():
    import optik_kayit
    conn = _optik_baglan()
    try:
        return {"sinavlar": optik_kayit.sinav_listesi(conn)}
    finally:
        conn.close()


def optik_uret_islemi(veri):
    import optik_form
    import optik_kayit
    tanim = {k: veri.get(k) for k in
             ("ad", "kurum", "kitapcik", "ogrenci_no_hane", "tc",
              "ad_soyad", "yanlis_boler", "dersler")}
    tanim = {k: v for k, v in tanim.items() if v is not None}
    on_ayar = veri.get("on_ayar") or None
    ad_slug = "".join(c if c.isalnum() else "_"
                      for c in (tanim.get("ad") or on_ayar or "optik"))[:40]
    yol = _cikti_yolu(f"optik_{ad_slug}.pdf")
    sonuc = optik_form.form_uret(tanim, yol=yol, on_ayar=on_ayar)
    conn = _optik_baglan()
    try:
        optik_kayit.sinav_ekle(
            conn, sonuc["sablon"],
            {"kurum": tanim.get("kurum", ""),
             "yanlis_boler":
             sonuc["sablon"].puan_kurali.get("yanlis_boler", 0)})
    finally:
        conn.close()
    jeton, ad = _indirme_hazirla([sonuc["pdf"]])
    return {"jeton": jeton, "ad": ad, "sinav_id": sonuc["sinav_id"],
            "sayfa": sonuc["sayfa"],
            "soru": sonuc["sablon"].soru_sayisi()}


def optik_tara_islemi(veri):
    import optik_kayit as okt
    import optik_oku
    import optik_sema
    sinav_id = veri.get("sinav") or ""
    yollar = [y for y in (veri.get("yollar") or []) if os.path.exists(y)]
    if not yollar:
        return {"hata": "okunacak dosya yok"}
    conn = _optik_baglan()
    try:
        sinav = okt.sinav_al(conn, sinav_id)
        if sinav is None:
            return {"hata": f"sınav bulunamadı: {sinav_id}"}
        import tempfile
        fd, sablon_yolu = tempfile.mkstemp(suffix=".sablon.json")
        os.close(fd)
        optik_sema.sablon_yaz(sinav["sablon"], sablon_yolu)

        def ilerleme(i, n, kaynak):
            with KILIT:
                DURUM["islem"] = {"asama": "optik", "yapilan": i,
                                  "toplam": n} if kaynak else None
        try:
            kagitlar = optik_oku.parti_oku(
                sinav["sablon"], sablon_yolu, yollar,
                warp_dizin=okt.media_dizin(sinav_id),
                ilerleme_cb=ilerleme)
        finally:
            os.unlink(sablon_yolu)
            with KILIT:
                DURUM["islem"] = None
        okundu = kuyruk = hatali = 0
        for k in kagitlar:
            okt.kagit_ekle(conn, sinav_id, k)
            if k["durum"] == "okundu":
                okundu += 1
            elif k["durum"] == "incelenecek":
                kuyruk += 1
            else:
                hatali += 1
        return {"okunan": len(kagitlar), "temiz": okundu,
                "kuyruk": kuyruk, "hatali": hatali}
    finally:
        conn.close()


def _optik_sonuclar(conn, sinav_id):
    import optik_analiz
    import optik_kayit
    sinav = optik_kayit.sinav_al(conn, sinav_id)
    if sinav is None:
        raise ValueError(f"sınav bulunamadı: {sinav_id}")
    kagitlar = optik_kayit.kagitlar(conn, sinav_id)
    anahtarlar = optik_kayit.anahtarlar(conn, sinav_id)
    kural = {"yanlis_boler":
             sinav["sablon"].puan_kurali.get("yanlis_boler", 0)}
    return sinav, optik_analiz.puanla(kagitlar, anahtarlar, kural,
                                      sinav["sablon"]), anahtarlar


def optik_sonuclar_verisi(sinav_id):
    conn = _optik_baglan()
    try:
        sinav, sonuclar, anahtarlar = _optik_sonuclar(conn, sinav_id)
        ozet = []
        for s in sonuclar:
            ozet.append({
                "sira": s.get("sira"), "ogrenci_no": s["ogrenci_no"],
                "ad_soyad": s["ad_soyad"], "kitapcik": s["kitapcik"],
                **{k: s["toplam"][k] for k in
                   ("dogru", "yanlis", "bos", "net", "yuzde", "soru")},
                "dersler": {d: {k: v[k] for k in
                                ("dogru", "yanlis", "bos", "net")}
                            for d, v in s["dersler"].items()},
                "sorunlar": s["sorunlar"]})
        return {"ad": sinav["ad"], "sonuclar": ozet,
                "dersler": sinav["sablon"].dersler(),
                "kitapciklar": list(sinav["sablon"].kitapcik_turleri),
                "anahtarli": sorted(anahtarlar)}
    finally:
        conn.close()


def optik_analiz_verisi(sinav_id):
    import optik_analiz
    import optik_kayit
    conn = _optik_baglan()
    try:
        sinav, sonuclar, _ = _optik_sonuclar(conn, sinav_id)
        analiz = optik_analiz.madde_analizi(
            sonuclar, optik_kayit.anahtarlar(conn, sinav_id),
            sinav["sablon"])
        veri = {"ad": sinav["ad"], **analiz}
        if sinav.get("kazanimlar"):
            veri["kazanim"] = optik_analiz.kazanim_analizi(
                sonuclar, sinav["kazanimlar"],
                kitapcik_sira=sinav["ayarlar"].get("kitapcik_sira")
            )["kazanimlar"]
        return veri
    finally:
        conn.close()


def optik_kagitlar_verisi(sinav_id, durum=None):
    import optik_kayit
    conn = _optik_baglan()
    try:
        liste = []
        for k in optik_kayit.kagitlar(conn, sinav_id,
                                      durum=durum or None):
            liste.append({k2: k.get(k2) for k2 in
                          ("id", "kaynak", "kaynak_sayfa", "sayfa_no",
                           "durum", "ogrenci_no", "ad_soyad", "kitapcik",
                           "sorunlar", "hata", "olusturma")})
        return {"kagitlar": liste}
    finally:
        conn.close()


def optik_kagit_detay(kagit_id):
    """İnceleme ekranı: kağıt + warp üzerine bindirilecek balon geometrisi."""
    import optik_kayit
    import optik_sema
    conn = _optik_baglan()
    try:
        k = optik_kayit.kagit_al(conn, kagit_id)
        if k is None:
            raise ValueError(f"kağıt yok: {kagit_id}")
        sinav = optik_kayit.sinav_al(conn, k["sinav_id"])
        sablon = sinav["sablon"]
        sayfa = next((s for s in sablon.sayfalar
                      if s.sayfa_no == k["sayfa_no"]), None)
        kaymalar = (k.get("kayit") or {}).get("yerel_kaymalar") or {}
        gruplar = []
        if sayfa:
            for alan in sayfa.alanlar:
                dx, dy = kaymalar.get(alan.ad, [0, 0])
                merkezler = optik_sema.baloncuk_merkezleri(alan)
                if alan.tip in ("coktan_secmeli", "dogru_yanlis"):
                    ders = alan.ders or ""
                    sorular = (k["cevaplar"] or {}).get(ders, {})
                    for r in range(alan.satir):
                        no = str(alan.soru_baslangic + r)
                        cevap = sorular.get(no) or {}
                        isaretli = set(cevap.get("adaylar") or [])
                        if cevap.get("sembol"):
                            isaretli.add(cevap["sembol"])
                        gruplar.append({
                            "tip": "soru", "ders": ders, "no": no,
                            "hukum": cevap.get("hukum"),
                            "sembol": cevap.get("sembol"),
                            "guven": cevap.get("guven"),
                            "duzeltildi": bool(cevap.get("duzeltildi")),
                            "balonlar": [
                                {"x": round((x * (200.0 / 72.0) + dx) / 2, 1),
                                 "y": round((y * (200.0 / 72.0) + dy) / 2, 1),
                                 "r": round(alan.hucre.cap * (200.0 / 72.0)
                                            / 4, 1),
                                 "sembol": alan.semboller[c],
                                 "isaretli":
                                 alan.semboller[c] in isaretli}
                                for r2, c, x, y in merkezler if r2 == r]})
        return {"kagit": {k2: k.get(k2) for k2 in
                          ("id", "sinav_id", "kaynak", "kaynak_sayfa",
                           "sayfa_no", "durum", "ogrenci_no", "ad_soyad",
                           "kitapcik", "sorunlar", "hata")},
                "kitapciklar": list(sablon.kitapcik_turleri),
                "gruplar": gruplar}
    finally:
        conn.close()


def optik_kagit_gorseli(kagit_id):
    import optik_kayit
    conn = _optik_baglan()
    try:
        k = optik_kayit.kagit_al(conn, kagit_id)
    finally:
        conn.close()
    if not k or not k.get("warp_png") or not os.path.exists(k["warp_png"]):
        return None
    with open(k["warp_png"], "rb") as f:
        return f.read()


def optik_anahtar_islemi(veri):
    """Elle anahtar ({"cevaplar": {ders: {no: harf}}}) veya taranmış
    kağıttan ({"kagit_id": N}) anahtar kaydeder."""
    import optik_kayit
    conn = _optik_baglan()
    try:
        sinav_id = veri.get("sinav") or ""
        sinav = optik_kayit.sinav_al(conn, sinav_id)
        if sinav is None:
            return {"hata": f"sınav bulunamadı: {sinav_id}"}
        kitapcik = veri.get("kitapcik") or \
            sinav["sablon"].kitapcik_turleri[0]
        if veri.get("kagit_id"):
            k = optik_kayit.kagit_al(conn, int(veri["kagit_id"]))
            if k is None:
                return {"hata": "kağıt bulunamadı"}
            cevaplar = {ders: {no: (c.get("sembol") or "")
                               for no, c in sorular.items()}
                        for ders, sorular in (k["cevaplar"] or {}).items()}
        else:
            cevaplar = veri.get("cevaplar") or {}
        adet = sum(1 for d in cevaplar.values() for v in d.values() if v)
        if not adet:
            return {"hata": "anahtar boş"}
        optik_kayit.anahtar_koy(conn, sinav_id, kitapcik, cevaplar)
        return {"kitapcik": kitapcik, "soru": adet}
    finally:
        conn.close()


def optik_duzelt_islemi(veri):
    import optik_kayit
    conn = _optik_baglan()
    try:
        duzeltme = {}
        for anahtar in ("ogrenci_no", "kitapcik", "ad_soyad"):
            if anahtar in veri:
                duzeltme[anahtar] = veri[anahtar]
        if veri.get("ders") is not None and veri.get("soru"):
            duzeltme["cevaplar"] = {veri["ders"]:
                                    {str(veri["soru"]):
                                     veri.get("sembol") or ""}}
        optik_kayit.kagit_duzelt(conn, int(veri["kagit"]), duzeltme)
        return {"ok": True}
    finally:
        conn.close()


def optik_kazanim_islemi(veri):
    """Kazanım eşlemesi: {"sinav": id, "csv": "ders;soru;kazanim\\n…"}"""
    import optik_analiz
    import optik_kayit
    import tempfile
    conn = _optik_baglan()
    try:
        fd, yol = tempfile.mkstemp(suffix=".csv")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(veri.get("csv") or "")
        try:
            kazanimlar = optik_analiz.kazanim_csv_oku(yol)
        finally:
            os.unlink(yol)
        if not kazanimlar:
            return {"hata": "CSV'den kazanım okunamadı "
                            "(başlık: ders;soru;kazanim)"}
        optik_kayit.kazanim_koy(conn, veri.get("sinav") or "", kazanimlar)
        adet = sum(len(v) for v in kazanimlar.values())
        return {"soru": adet}
    finally:
        conn.close()


def optik_disa_islemi(veri):
    import optik_analiz
    conn = _optik_baglan()
    try:
        sinav_id = veri.get("sinav") or ""
        tur = veri.get("tur") or "csv"
        sinav, sonuclar, _ = _optik_sonuclar(conn, sinav_id)
        if not sonuclar:
            return {"hata": "okunmuş kağıt yok"}
        slug = "".join(c if c.isalnum() else "_" for c in sinav["ad"])[:32]
        if tur == "csv":
            yol = optik_analiz.disa_csv(
                sonuclar, _cikti_yolu(f"{slug}_sonuclar.csv"))
        elif tur == "txt":
            yol = optik_analiz.disa_txt(
                sonuclar, _cikti_yolu(f"{slug}_optik.txt"),
                sinav["sablon"])
        elif tur == "eokul":
            yol = optik_analiz.disa_eokul(
                sonuclar, _cikti_yolu(f"{slug}_eokul.csv"))
        elif tur == "karne":
            kazanim = None
            if sinav.get("kazanimlar"):
                kazanim = optik_analiz.kazanim_analizi(
                    sonuclar, sinav["kazanimlar"],
                    kitapcik_sira=sinav["ayarlar"].get("kitapcik_sira")
                )["ogrenciler"]
            yol = optik_analiz.karne_pdf(
                sonuclar, _cikti_yolu(f"{slug}_karne.pdf"),
                sinav_ad=sinav["ad"],
                kurum=sinav["ayarlar"].get("kurum", ""), kazanim=kazanim)
        else:
            return {"hata": f"bilinmeyen tür: {tur}"}
        jeton, ad = _indirme_hazirla([yol])
        return {"jeton": jeton, "ad": ad}
    finally:
        conn.close()


# ------------------------------------------------------------------- server

def _ogretmen_api_belirteci():
    yol = os.environ.get("OGRETMEN_API_TOKEN_YOLU") or os.path.expanduser(
        "~/Library/Application Support/OgretmenCantasi/entegrasyonlar/yerel-api.token")
    try:
        with open(yol, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def _ogretmen_api_yetkili(handler):
    beklenen = _ogretmen_api_belirteci()
    gelen = handler.headers.get("Authorization", "")
    return bool(beklenen) and gelen == f"Bearer {beklenen}"


def _soru_paketi(idler):
    """Öğretmen Çantası protokolü v1 soru ZIP'i."""
    import soru_bankasi
    sorular = []
    gorseller = {}
    for sid in idler:
        kayit = soru_bankasi.banka_kayit(sid)
        if not kayit:
            continue
        png = soru_bankasi.banka_gorsel(sid, kucuk=False)
        gorsel = ""
        if png:
            gorsel = f"images/{sid}.png"
            gorseller[gorsel] = png
        etiketler = kayit.get("etiketler") or {}
        try:
            sinif = int(etiketler.get("sinif") or 9)
        except (TypeError, ValueError):
            sinif = 9
        sorular.append({
            "external_id": f"bank:{sid}:{kayit.get('icerik_hash') or ''}",
            "text": kayit.get("metin") or kayit.get("govde") or
                    f"Görsel soru #{sid}",
            "image": gorsel,
            "grade": sinif,
            "outcome_code": etiketler.get("kazanim") or "",
            "difficulty": kayit.get("zorluk") or "orta",
            "rubric": "",
            "source_document": kayit.get("kaynak") or "",
            "source_page": kayit.get("sayfa"),
            "quality_status": kayit.get("inceleme_durumu") or "belirsiz",
        })
    manifest = {
        "schema_version": 1,
        "protocol_version": "v1",
        "source_app": "soru-kesici",
        "source_version": sk.__dict__.get("__version__", "gelistirme"),
        "export_id": f"questions:{uuid.uuid4()}",
        "type": "questions",
        "questions": sorular,
    }
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr(
            "manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
        for ad, veri in gorseller.items():
            paket.writestr(ad, veri)
    return tampon.getvalue()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass  # sessiz

    def _json(self, veri, kod=200):
        gonder = json.dumps(veri).encode("utf-8")
        self.send_response(kod)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(gonder)))
        self.end_headers()
        self.wfile.write(gonder)

    def _merkez_yonlendir(self):
        taban = merkez_adresi_bul()
        if taban:
            self.send_response(302)
            self.send_header("Location", taban + "/merkez")
            self.end_headers()
            return
        govde = (
            '<!doctype html><html lang="tr"><head><meta charset="utf-8">'
            "<title>Merkez bulunamadı</title></head>"
            '<body style="font-family:-apple-system,sans-serif;padding:2em">'
            "<h2>Biyoloji Stüdyosu kapalı</h2>"
            "<p>Soru Çözücü sunucusu 8020-8030 aralığında bulunamadı. "
            "Biyoloji Stüdyosu uygulamasını açıp yeniden deneyin.</p>"
            "<p><a href=\"/\">← Soru Kesici'ye dön</a></p></body></html>"
        ).encode("utf-8")
        self.send_response(503)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(govde)))
        self.end_headers()
        self.wfile.write(govde)

    def _govde(self):
        n = int(self.headers.get("Content-Length", 0))
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            return {}

    def _png(self, png):
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(png)))
        self.end_headers()
        self.wfile.write(png)

    def _png_onbellek(self, png):
        """Banka görüntüsü — id içerik-hash'e bağlı, değişmez → uzun cache."""
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(png)))
        self.send_header("Cache-Control", "max-age=86400")
        self.end_headers()
        self.wfile.write(png)

    def _indir_gonder(self, jeton):
        """İndirme jetonuna karşılık gelen dosyayı attachment olarak akıtır
        (tarayıcı İndirilenler'e kaydeder; yerleşik kaydet penceresi gerekmez)."""
        with KILIT:
            yol = DURUM["indirmeler"].get(jeton)
        if not yol or not os.path.exists(yol):
            self.send_response(404); self.end_headers(); return
        ad = os.path.basename(yol)
        mime = _MIME.get(os.path.splitext(ad)[1].lower(),
                         "application/octet-stream")
        # RFC 5987: Türkçe/özel karakterli ad için filename* (UTF-8)
        from urllib.parse import quote
        boyut = os.path.getsize(yol)
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(boyut))
        self.send_header("Content-Disposition",
                         f"attachment; filename*=UTF-8''{quote(ad)}")
        self.end_headers()
        # İstemci indirmeyi yarıda keserse (BrokenPipe) sessizce çık — header
        # gönderildikten sonra JSON-hata gönderilemez (çift-yanıt/traceback olur).
        try:
            with open(yol, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
        except (BrokenPipeError, ConnectionResetError):
            return

    def do_GET(self):
        yol = urlparse(self.path)
        q = parse_qs(yol.query)
        try:
            if yol.path == "/healthz":
                # Token'sız imza ucu: Stüdyo launcher'ı ve Merkez sayfası
                # bu portta gerçekten Soru Kesici mi çalışıyor diye bakar.
                self._json({
                    "app": "soru-kesici", "status": "ready",
                    "version": "v" + sk.KALIBRASYON_SURUMU})
                return
            if yol.path == "/merkez":
                self._merkez_yonlendir()
                return
            if yol.path.startswith("/api/v1/") and not _ogretmen_api_yetkili(self):
                self._json({"error": "unauthorized"}, 401)
                return
            if yol.path == "/api/v1/health":
                self._json({
                    "app": "soru-kesici", "app_version": "v3.4",
                    "protocol_version": "v1", "status": "ready"})
                return
            if yol.path == "/api/v1/capabilities":
                self._json({
                    "protocol_version": "v1",
                    "capabilities": ["question-package-export"]})
                return
            if yol.path == "/api/v1/questions/export":
                idler = []
                for parca in q.get("ids", [""])[0].split(","):
                    if parca.strip().isdigit():
                        idler.append(int(parca))
                if not idler:
                    self._json({"error": "ids required"}, 400)
                    return
                veri = _soru_paketi(idler[:500])
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(len(veri)))
                self.send_header(
                    "Content-Disposition", "attachment; filename=soru-paketi.zip")
                self.end_headers()
                self.wfile.write(veri)
                return
            ham = q.get("sayfa", ["0"])[0]
            idx = int(ham) if ham.lstrip("-").isdigit() else 0
            if yol.path == "/":
                gonder = SAYFA.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(gonder)))
                self.end_headers()
                self.wfile.write(gonder)
            elif yol.path == "/onizleme":
                self._png(sayfa_onizleme_png(idx, ciplak=bool(q.get("ciplak"))))
            elif yol.path == "/kutular":
                self._json(_oku_kutular(idx))
            elif yol.path == "/soru-onizleme":
                png = soru_onizleme_png(idx, int(q.get("kutu", ["0"])[0]))
                if png is None:
                    self.send_response(404); self.end_headers()
                else:
                    self._png(png)
            elif yol.path == "/ozet":
                with KILIT:
                    oz = _ozet_al()
                self._json({"testler": oz["testler"],
                            "kutu_kimlik": oz["kutu_kimlik"],
                            "toplam": oz["toplam"],
                            "test_sayisi": oz["test_sayisi"],
                            "cevapli": oz["cevapli"],
                            "cozumlu": oz.get("cozumlu", False)})
            elif yol.path == "/kalibrasyon":
                self._json(_kalibrasyon_verisi())
            elif yol.path == "/inceleme":
                tumu = q.get("tumu", ["0"])[0] in ("1", "true", "evet")
                self._json(_inceleme_listesi(bekleyen_only=not tumu))
            elif yol.path == "/ilerleme":
                with KILIT:
                    self._json(DURUM["islem"] or {"asama": None})
            elif yol.path == "/gecmis":
                kayitlar = gecmis_oku()
                for k in kayitlar:
                    k["cikti_var"] = os.path.exists(k.get("cikti", ""))
                    k["girdi_var"] = all(os.path.exists(g)
                                         for g in k.get("girdiler", []))
                self._json({"kayitlar": kayitlar})
            elif yol.path == "/banka-sorgula":
                import soru_bankasi
                self._json(soru_bankasi.banka_sorgula(
                    konu=q.get("konu", [None])[0],
                    test=q.get("test", [None])[0],
                    kaynak=q.get("kaynak", [None])[0],
                    cevap=q.get("cevap", [None])[0],
                    etiket=q.get("etiket", [None])[0],
                    arama=q.get("arama", [None])[0],
                    bos=q.get("bos", [None])[0],
                    zorluk=q.get("zorluk", [None])[0],
                    rastgele=min(int(q["rastgele"][0]), 500)
                    if q.get("rastgele") else None,
                    limit=max(1, min(int(q.get("limit", ["60"])[0]), 500)),
                    ofset=max(0, int(q.get("ofset", ["0"])[0])),
                    sirala=q.get("sirala", ["yeni"])[0],
                    tarih_bas=q.get("tarih_bas", [None])[0],
                    tarih_son=q.get("tarih_son", [None])[0]))
            elif yol.path == "/banka-yeniden-isleme":
                import soru_bankasi
                kayit = soru_bankasi.banka_yeniden_isleme_son(
                    kaynak=q.get("kaynak", [None])[0])
                self._json({"aktif": bool(kayit), "kayit": kayit})
            elif yol.path == "/banka-gorsel":
                import soru_bankasi
                png = soru_bankasi.banka_gorsel(
                    q["id"][0], kucuk=q.get("kucuk", ["1"])[0] != "0")
                if png is None:
                    self.send_response(404); self.end_headers()
                else:
                    self._png_onbellek(png)
            elif yol.path == "/banka-konular":
                import soru_bankasi
                self._json(soru_bankasi.banka_filtreler())
            elif yol.path == "/banka-istatistik":
                import soru_bankasi
                self._json(soru_bankasi.banka_istatistik())
            elif yol.path == "/indir":
                self._indir_gonder(q.get("jeton", [""])[0])
            elif yol.path == "/ai-durum":
                import gemini_konu
                d = gemini_konu.gemini_dogrula()
                d["anahtar_var"] = bool(gemini_konu.gemini_anahtar_al())
                self._json(d)
            elif yol.path == "/ml-durum":
                try:
                    import duzen_model
                    d = duzen_model.duzen_dogrula()
                    d["aktif"] = duzen_model.aktif_mi()
                except Exception:  # noqa: BLE001 — modül eksikse de yanıt ver
                    d = {"ok": False, "mesaj": "duzen_model yüklenemedi",
                         "aktif": False}
                d["gemini_vision_aktif"] = bool(
                    ayar_oku().get("gemini_vision_aktif", False))
                self._json(d)
            elif yol.path == "/ocr-durum":
                try:
                    import ocr_ensemble
                    self._json(ocr_ensemble.motor_durumlari())
                except Exception as e:  # noqa: BLE001
                    self._json({"mod": "hizli", "kurulu": False,
                                "motorlar": {"vision": True},
                                "hata": str(e)})
            elif yol.path == "/banka-sablonlar":
                import soru_bankasi
                self._json({"sablonlar": soru_bankasi.sablon_liste(
                    tur=q.get("tur", [None])[0])})
            elif yol.path == "/banka-sablon":
                import soru_bankasi
                self._json(soru_bankasi.sablon_getir(
                    int(q.get("id", ["0"])[0])) or {"hata": "bulunamadı"})
            elif yol.path == "/optik-durum":
                self._json(optik_durum_verisi())
            elif yol.path == "/optik-sinavlar":
                self._json(optik_sinavlar_verisi())
            elif yol.path == "/optik-sonuclar":
                self._json(optik_sonuclar_verisi(q.get("sinav", [""])[0]))
            elif yol.path == "/optik-analiz":
                self._json(optik_analiz_verisi(q.get("sinav", [""])[0]))
            elif yol.path == "/optik-kagitlar":
                self._json(optik_kagitlar_verisi(
                    q.get("sinav", [""])[0], q.get("durum", [None])[0]))
            elif yol.path == "/optik-kagit":
                self._json(optik_kagit_detay(int(q.get("id", ["0"])[0])))
            elif yol.path == "/optik-kagit-gorsel":
                png = optik_kagit_gorseli(int(q.get("id", ["0"])[0]))
                if png is None:
                    self.send_response(404); self.end_headers()
                else:
                    self._png(png)
            else:
                self.send_response(404)
                self.end_headers()
        except (BrokenPipeError, ConnectionResetError):
            return                       # istemci kapattı → yanıt gönderme
        except Exception as e:  # noqa: BLE001
            self._json({"hata": str(e)}, 500)

    def _yukle_dosya(self, q):
        n = int(self.headers.get("Content-Length", 0))
        if n <= 0 or n > YUKLEME_SINIR:
            self._json({"hata": "dosya boş veya 400 MB sınırını aşıyor"}, 400)
            return
        ad = q.get("ad", ["dosya"])[0]
        try:
            yol = yukleme_kaydet(ad, self.rfile.read(n))
            self._json({"yol": yol})
        except ValueError as e:
            self._json({"hata": str(e)}, 400)

    def do_POST(self):
        yol = urlparse(self.path)
        if sys.platform != "darwin" and yol.path in MACOS_OZEL_YOLLAR:
            self._json({"hata": "Bu özellik Windows sürümünde yok"}, 501)
            return
        agir = yol.path in AGIR_YOLLAR
        if agir and not AGIR_KILIT.acquire(blocking=False):
            self._json({"hata": "işlem sürüyor — bitmesini bekleyin"}); return
        try:
            if yol.path == "/yukle-dosya":   # ham bayt — _govde'den ÖNCE
                self._yukle_dosya(parse_qs(yol.query))
                return
            g = self._govde()
            if yol.path == "/sec":
                self._json({"yollar": dosya_sec()})
            elif yol.path == "/yukle":
                self._json(belge_yukle(g["yollar"], int(g.get("dpi", 300))))
            elif yol.path == "/kutu-guncelle":
                idx = int(g["sayfa"])
                kutulari_guncelle(idx, g.get("kutular", []))
                sonuc = _oku_kutular(idx)
                sonuc.update({"sayfa_soru": len(_kutular(idx)),
                               "toplam": _toplam_soru()})
                self._json(sonuc)
            elif yol.path == "/kutu-sifirla":
                idx = int(g["sayfa"])
                kutulari_sifirla(idx)
                sonuc = _oku_kutular(idx)
                sonuc["toplam"] = _toplam_soru()
                self._json(sonuc)
            elif yol.path == "/inceleme":
                self._json(_inceleme_onayla(
                    g.get("sayfa"), g.get("kutu_no"), bool(g.get("onay", True))))
            elif yol.path == "/inceleme-sayfa":
                self._json(_sayfa_inceleme_karari(
                    g.get("sayfa"), g.get("karar")))
            elif yol.path == "/kayit-yeri":
                klasor = ayar_oku().get("son_klasor") or (
                    os.path.dirname(DURUM["girdiler"][0])
                    if DURUM["girdiler"] else os.path.expanduser("~"))
                tur = g.get("tur")
                temel = (os.path.splitext(os.path.basename(
                    DURUM["girdiler"][0]))[0] if DURUM["girdiler"] else "cikti")
                if tur == "docx":
                    ad = f"{temel} Sınav.docx"
                    istem = "Word belgesi nereye kaydedilsin?"
                elif tur in ("pdf", "pdf-metin"):
                    ad = f"{temel} Sınav.pdf"
                    istem = "Sınav PDF'i nereye kaydedilsin?"
                else:
                    ad = "Arşiv.zip"
                    istem = "Arşiv nereye kaydedilsin?"
                self._json({"yol": kayit_yeri(ad, klasor, istem)})
            elif yol.path == "/secim-coz":
                self._json(_secim_coz(g.get("metin", "")))
            elif yol.path == "/ara":
                self._json(_ara(g.get("metin", "")))
            elif yol.path == "/etiket":
                self._json(_etiket_ata(g.get("kimlikler", []),
                                       g.get("anahtar", ""), g.get("deger", "")))
            elif yol.path == "/cevap-duzelt":
                self._json(_cevap_duzelt(g.get("kimlikler", []),
                                         g.get("cevap", ""),
                                         geri_al=bool(g.get("geri_al"))))
            elif yol.path == "/disa-aktar":
                if DURUM["islem"]:
                    self._json({"hata": "işlem sürüyor"}); return
                yol_, adet = disa_aktar_kaydet(g.get("tur", "csv"),
                                               g.get("secim"))
                if adet == 0:
                    self._json({"hata": "aktarılacak soru yok"}); return
                jeton, ad = _indirme_hazirla([yol_])
                self._json({"jeton": jeton, "ad": ad, "adet": adet})
            elif yol.path == "/kes":
                if DURUM["islem"]:
                    self._json({"hata": "işlem sürüyor"}); return
                temel = _girdi_temel()
                hedef = _cikti_yolu(f"{temel} Arşiv.zip")
                adet, tst = kes_ve_kaydet(
                    hedef, False, g.get("secim"),
                    numara_gizle=g.get("numara_gizle", True),
                    cevap_bandi=bool(g.get("cevap_bandi")),
                    cozum_ilistir=bool(g.get("cozum_ilistir")))
                if adet == 0:
                    self._json({"hata": "seçime uyan soru bulunamadı"}); return
                jeton, ad = _indirme_hazirla([hedef])
                self._json({"adet": adet, "test": tst, "jeton": jeton, "ad": ad})
            elif yol.path == "/sinav-pdf":
                if DURUM["islem"]:
                    self._json({"hata": "işlem sürüyor"}); return
                ayarlar = {k: g.get(k) for k in
                           ("baslik", "kurum", "ad_soyad", "sinif", "tarih",
                            "no", "sutun", "yeniden_numarala", "cevap_anahtari",
                            "toplam_puan", "kitapcik", "rastgele", "tohum")}
                temel = _girdi_temel()
                hedef = _cikti_yolu(f"{temel} Sınav.pdf")
                adet, sonuc = sinav_pdf_kaydet(hedef, ayarlar,
                                               g.get("secim"),
                                               optik=bool(g.get("optik_form")))
                if adet == 0:
                    self._json({"hata": "seçime uyan soru bulunamadı"}); return
                jeton, ad = _indirme_hazirla(sonuc["yollar"],
                                             zip_adi=f"{temel} Sınav.zip")
                self._json({"soru": adet, "sayfa": sonuc["sayfa"],
                            "kitapcik": sonuc["kitapcik"], "jeton": jeton,
                            "ad": ad, "optik": sonuc.get("optik")})
            elif yol.path == "/bankaya-aktar":
                if DURUM["islem"]:
                    self._json({"hata": "işlem sürüyor"}); return
                sonuc = bankaya_aktar_kaydet(g.get("secim"))
                if (sonuc["eklenen"] == 0 and sonuc["atlanan"] == 0
                        and sonuc.get("kalite_atlanan", 0) == 0):
                    self._json({"hata": "aktarılacak soru yok"}); return
                self._json(sonuc)
            elif yol.path == "/banka-sinav":
                bicim = g.get("bicim", "pdf")
                uz = "docx" if bicim == "docx" else "pdf"
                hedef = _cikti_yolu(f"Banka Sınav.{uz}")
                ayarlar = dict(g.get("ayarlar", {}))
                adet, sonuc = banka_sinav_kaydet(
                    g.get("secili_idler", []), bicim, ayarlar, hedef,
                    optik=bool(ayarlar.pop("optik_form", False))
                    and bicim == "pdf")
                if adet == 0:
                    self._json({"hata": "seçilmiş banka sorusu yok"}); return
                jeton, ad = _indirme_hazirla(sonuc.get("yollar", [hedef]),
                                             zip_adi="Banka Sınav.zip")
                self._json({"soru": adet, "sayfa": sonuc.get("sayfa"),
                            "kitapcik": sonuc.get("kitapcik", 1),
                            "jeton": jeton, "ad": ad,
                            "optik": sonuc.get("optik")})
            elif yol.path == "/banka-sil":
                import soru_bankasi
                self._json({"ok": soru_bankasi.banka_sil(g["id"])})
            elif yol.path == "/banka-blueprint-sec":
                import soru_bankasi
                self._json(soru_bankasi.banka_blueprint_sec(
                    g.get("hucreler", []),
                    genel_filtre=g.get("genel_filtre"),
                    tohum=g.get("tohum")))
            elif yol.path == "/banka-soru-yenile":
                import soru_bankasi
                h = g.get("hucre") or {}
                r = soru_bankasi.banka_blueprint_sec(
                    [dict(h, adet=1)], genel_filtre=g.get("genel_filtre"),
                    tohum=g.get("tohum"), haric_idler=g.get("haric_idler"))
                self._json({"id": (r["idler"][0] if r["idler"] else None)})
            elif yol.path == "/banka-toplu-duzenle":
                import soru_bankasi
                self._json(soru_bankasi.banka_toplu_guncelle(
                    [int(i) for i in g.get("idler", [])],
                    konu=g.get("konu"), zorluk=g.get("zorluk"),
                    cevap=g.get("cevap"), etiket_ekle=g.get("etiket_ekle"),
                    etiket_sil=g.get("etiket_sil")))
            elif yol.path == "/banka-sablon-kaydet":
                import soru_bankasi
                self._json(soru_bankasi.sablon_kaydet(
                    g.get("ad", "Şablon"), g.get("veri", {}),
                    tur=g.get("tur", "blueprint"), sablon_id=g.get("id")))
            elif yol.path == "/banka-sablon-sil":
                import soru_bankasi
                self._json(soru_bankasi.sablon_sil(int(g["id"])))
            elif yol.path == "/sihirbaz-uret":
                self._json(sihirbaz_uret_islemi(g))
            elif yol.path == "/banka-ai-etiketle":
                self._json(banka_ai_etiketle_kaydet(
                    g.get("kapsam", "tumu"), g.get("filtre"), g.get("idler"),
                    onay=bool(g.get("onay"))))
            elif yol.path == "/optik-uret":
                self._json(optik_uret_islemi(g))
            elif yol.path == "/optik-tara":
                self._json(optik_tara_islemi(g))
            elif yol.path == "/optik-anahtar":
                self._json(optik_anahtar_islemi(g))
            elif yol.path == "/optik-duzelt":
                self._json(optik_duzelt_islemi(g))
            elif yol.path == "/optik-kazanim":
                self._json(optik_kazanim_islemi(g))
            elif yol.path == "/optik-disa":
                self._json(optik_disa_islemi(g))
            elif yol.path == "/ayar-kaydet":
                yeni = {k: g[k] for k in ("gemini_api_key", "gemini_model",
                                          "duzen_model_aktif", "gemini_vision_aktif",
                                          "ocr_modu")
                        if k in g and g[k] is not None}
                if yeni:
                    ayar_yaz(**yeni)
                self._json({"ok": True})
            elif yol.path == "/gecmis-ac":
                kayit = gecmis_oku()[int(g["indeks"])]
                yollar = [y for y in kayit.get("girdiler", [])
                          if os.path.exists(y)]
                if not yollar:
                    self._json({"hata": "girdi dosyaları bulunamadı"}); return
                self._json({"yollar": yollar})
            elif yol.path == "/gecmis-goster":
                kayit = gecmis_oku()[int(g["indeks"])]
                subprocess.run(["open", "-R", kayit["cikti"]])
                self._json({"ok": True})
            elif yol.path == "/goster":
                subprocess.run(["open", "-R", g["yol"]])
                self._json({"ok": True})
            else:
                self._json({"hata": "bilinmeyen yol"}, 404)
        except (BrokenPipeError, ConnectionResetError):
            pass                         # istemci kapattı → yanıt gönderme
        except KaliteKapisiHatasi as e:
            self._json(e.rapor, 409)
        except Exception as e:  # noqa: BLE001
            self._json({"hata": str(e)}, 500)
        finally:
            if agir:
                AGIR_KILIT.release()


def _banka_bakim_arka():
    """Sunucu açılışında bankayı arka planda bakımdan geçir (yetim medya temizle
    + integrity + VACUUM) — açılışı bloklamaz, hata sessizce yutulur."""
    try:
        import soru_bankasi
        if os.path.exists(soru_bankasi.db_yolu()):
            soru_bankasi.banka_bakim()
    except Exception:  # noqa: BLE001
        pass


def main():
    try:
        httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        # Port dolu — büyük olasılıkla uygulama zaten açık. Nazik mesaj, traceback yok.
        print(f"Soru Kesici zaten çalışıyor olabilir: http://127.0.0.1:{PORT}")
        webbrowser.open(f"http://127.0.0.1:{PORT}")
        sys.exit(1)
    url = f"http://127.0.0.1:{PORT}"
    print(f"Soru Kesici arayüzü: {url}")
    threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    threading.Thread(target=_banka_bakim_arka, daemon=True).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nKapatılıyor…")
        httpd.shutdown()


if __name__ == "__main__":
    main()

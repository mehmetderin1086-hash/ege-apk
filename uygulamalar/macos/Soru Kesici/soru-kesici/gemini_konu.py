#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gemini ile konu + başlık etiketleme — soru metninden AI ile KONU (konular.csv
listesinden) ve kısa BAŞLIK belirler. Kaba kelime-eşleştirmenin (soru_kes.
konu_etiketle) yerine değil, güçlü bir alternatifi; her hata durumunda çağıran
kelime-eşleştirme yedeğine düşebilir.

Yalnız stdlib `urllib.request` (yeni bağımlılık yok). Anahtar `~/.soru_kesici.json`
(gemini_api_key) ya da GEMINI_API_KEY ortam değişkeninden. Kimlik: `?key=` (bu
projedeki anahtar bu modu kullanır; Bearer OAuth jetonu içindir).
"""

import concurrent.futures
import json
import os
import random
import threading
import time
import urllib.error
import urllib.request


class _KotaHatasi(Exception):
    """HTTP 429 — kota/rate-limit. Proje-geneli olduğundan yedek model denemek
    aynı kotayı yer; sadece backoff+yeniden dene, sonra erken çık."""

    def __init__(self, retry_after=0):
        super().__init__("kota (429)")
        self.retry_after = retry_after

BASE = "https://generativelanguage.googleapis.com/v1beta"
VARSAYILAN_MODEL = "gemini-flash-latest"
# 404 (modele erişim yok) / 429 (kota) durumunda sırayla denenecek yedekler
_YEDEK_MODELLER = ["gemini-2.5-flash-lite", "gemini-2.0-flash-lite",
                   "gemini-2.0-flash"]
AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")

_TOPLU_SEMA = {
    "type": "array",
    "items": {"type": "object", "properties": {
        "id": {"type": "integer"},
        "konu": {"type": "string"},
        "baslik": {"type": "string"},
        "zorluk": {"type": "string", "enum": ["kolay", "orta", "zor"]}},
        "required": ["id", "konu", "baslik", "zorluk"]},
}


def _ayar():
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def gemini_anahtar_al():
    return os.environ.get("GEMINI_API_KEY") or _ayar().get("gemini_api_key")


def gemini_model_al():
    return _ayar().get("gemini_model") or VARSAYILAN_MODEL


def _cagir(model, istek, anahtar, timeout=45):
    """generateContent → yanıt metni. Sağlam ayrıştırma: 429→_KotaHatasi;
    boş/bloklu yanıt (SAFETY/MAX_TOKENS/candidate yok)→ValueError; 4xx→HTTPError;
    ağ/timeout→URLError. Böylece tek bir bozuk yanıt sessizce yutulmaz."""
    url = f"{BASE}/models/{model}:generateContent?key={anahtar}"
    req = urllib.request.Request(
        url, data=json.dumps(istek).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            d = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 429:
            try:
                ra = int(e.headers.get("Retry-After") or 0)
            except (TypeError, ValueError):
                ra = 0
            raise _KotaHatasi(ra) from e
        raise
    cand = d.get("candidates") or []
    if not cand:
        blok = (d.get("promptFeedback") or {}).get("blockReason")
        raise ValueError(f"yanıt boş (blok: {blok})" if blok else "yanıt boş")
    c0 = cand[0]
    parts = (c0.get("content") or {}).get("parts") or []
    if not parts:
        raise ValueError(f"içerik yok (finishReason: {c0.get('finishReason')})")
    return parts[0].get("text") or ""


def _modeller(model):
    return [model] + [m for m in _YEDEK_MODELLER if m != model]


def gemini_dogrula(anahtar=None):
    """Anahtar geçerli mi + hangi model erişilebilir. Dönüş: {ok, mesaj, mod}."""
    anahtar = anahtar or gemini_anahtar_al()
    if not anahtar:
        return {"ok": False, "mesaj": "API anahtarı ayarlı değil", "mod": None}
    istek = {"contents": [{"parts": [{"text": "Sadece 'OK' yaz."}]}]}
    kota = ag = False
    for model in _modeller(gemini_model_al()):
        try:
            _cagir(model, istek, anahtar, timeout=20)
            return {"ok": True, "mesaj": f"bağlı · {model}", "mod": model}
        except _KotaHatasi:
            kota = True; break        # kota proje-geneli → yedek model denemek boşuna
        except ValueError:
            # yanıt geldi ama içerik bloklandı → ANAHTAR GEÇERLİ (yalnız bu istem)
            return {"ok": True, "mesaj": f"bağlı · {model}", "mod": model}
        except urllib.error.HTTPError as e:
            if e.code in (400, 401, 403):
                return {"ok": False,
                        "mesaj": f"anahtar geçersiz (HTTP {e.code})", "mod": None}
            # 404 (modele erişim yok) → sonraki modeli dene
        except urllib.error.URLError:
            ag = True                 # DNS/bağlantı hatası (internet yok?)
        except Exception:  # noqa: BLE001 — timeout vb.: sonraki modeli dene
            pass
    if kota:
        mesaj = "kota aşıldı (429), biraz sonra deneyin"
    elif ag:
        mesaj = "ağ hatası — internet bağlantısını kontrol edin"
    else:
        mesaj = "hiçbir modele erişilemedi"
    return {"ok": False, "mesaj": mesaj, "mod": None}


def _istem(grup, konu_listesi):
    kl = ", ".join(konu_listesi) if konu_listesi else "(en uygun konu)"
    satirlar = [json.dumps({"id": s["id"], "soru": (s.get("metin") or "")[:900]},
                           ensure_ascii=False) for s in grup]
    return (
        "Sen bir sınav sorusu sınıflandırıcısısın. Aşağıdaki her soru için "
        "KONU, 3-6 kelimelik kısa BAŞLIK ve ZORLUK belirle.\n"
        f"KONU şu listeden EN UYGUN olanı olmalı: {kl}.\n"
        "Listede tam uygun yoksa anlamca en yakın olanı seç. BAŞLIK sorunun "
        "kazanımını/özünü anlatan kısa Türkçe bir etikettir (ör. 'Nöron Yapısı', "
        "'Mitoz Bölünme Evreleri'). ZORLUK yalnız 'kolay', 'orta' ya da 'zor' "
        "olabilir (bilgi düzeyi + çıkarım/işlem gereksinimine göre).\n"
        "Yanıt olarak her öğede id, konu, baslik, zorluk bulunan bir JSON dizisi "
        "ver.\n\n"
        "SORULAR (her satır bir soru):\n" + "\n".join(satirlar))


def gemini_etiketle_toplu(sorular, konu_listesi=None, anahtar=None,
                          model=None, ilerleme=None, grup_boy=15,
                          worker=2, maks_soru=None):
    """sorular: [{"id": int, "metin": str}]. Dönüş: {"sonuc": {id:{konu,baslik}},
    "basarisiz": [id]}. Metni boş sorular atlanır. Kota (429) proje-geneli
    olduğundan yedek modele GEÇMEZ — jitterli backoff, kalıcıysa kalan gruplar
    hızlıca 'başarısız' işaretlenir (çağıran kelime yedeğine düşebilir / yeniden
    dene diyebilir). worker=2: ücretsiz katman RPM sınırına dost."""
    anahtar = anahtar or gemini_anahtar_al()
    hedef = [s for s in sorular if (s.get("metin") or "").strip()]
    if maks_soru:
        hedef = hedef[:maks_soru]
    if not anahtar or not hedef:
        return {"sonuc": {}, "basarisiz": [s["id"] for s in hedef]}
    model = model or gemini_model_al()
    gruplar = [hedef[i:i + grup_boy] for i in range(0, len(hedef), grup_boy)]
    kota_dur = threading.Event()      # 429 kalıcıysa kalan grupları hızlı düşür

    def isle(grup):
        if kota_dur.is_set():
            return None
        istek = {"contents": [{"parts": [{"text": _istem(grup, konu_listesi)}]}],
                 "generationConfig": {
                     "responseMimeType": "application/json",
                     "responseSchema": _TOPLU_SEMA,
                     "maxOutputTokens": 64 * len(grup) + 512}}  # truncation önle
        for m in _modeller(model):
            for deneme in range(3):
                try:
                    return json.loads(_cagir(m, istek, anahtar))
                except _KotaHatasi as e:
                    if deneme == 2:       # kalıcı kota → dur, kalanı başarısız yap
                        kota_dur.set(); return None
                    time.sleep(max(e.retry_after, 2.0 * (deneme + 1))
                               + random.uniform(0, 1.5))
                    continue              # AYNI modeli yeniden dene (yedeğe geçme)
                except (urllib.error.HTTPError, ValueError,
                        json.JSONDecodeError):
                    break                 # 404 / bloklu / bozuk JSON → yedek model
                except Exception:  # noqa: BLE001 — timeout vb.
                    break
            if kota_dur.is_set():
                return None
        return None

    sonuc, basarisiz, yapilan = {}, [], 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=worker) as ex:
        for grup, cikti in zip(gruplar, ex.map(isle, gruplar)):
            yapilan += 1
            if ilerleme:
                ilerleme(yapilan, len(gruplar))
            islenen = set()
            for o in (cikti or []):
                try:
                    sid = int(o["id"])
                    z = (o.get("zorluk") or "").strip().lower()
                    sonuc[sid] = {"konu": (o.get("konu") or "").strip(),
                                  "baslik": (o.get("baslik") or "").strip(),
                                  "zorluk": z if z in ("kolay", "orta", "zor")
                                  else None}
                    islenen.add(sid)
                except (KeyError, ValueError, TypeError):
                    continue
            basarisiz += [s["id"] for s in grup if s["id"] not in islenen]
    return {"sonuc": sonuc, "basarisiz": basarisiz}

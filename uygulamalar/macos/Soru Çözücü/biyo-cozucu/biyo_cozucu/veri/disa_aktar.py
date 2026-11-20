"""Referans örnekleri LoRA eğitim verisine (mlx-lm / Unsloth chat jsonl) çevirir.

Biçim, çıkarım sırasında kurulan istemle BİREBİR aynı: aynı sistem mesajı, aynı
JSON çıktı şeması ve isteğe bağlı olarak aynı referans-örnek diyalogları. Eğitim
ve çıkarım istemleri ayrıştığında model, öğrendiği biçimi çıkarımda göremez ve
kazanç kaybolur.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

from ..hafiza.getirme import benzer_ornekler
from ..hafiza.indeks import OrnekIndeksi
from ..istemler import (
    VARSAYILAN_KANIT_ADIMI,
    cozumu_adimlara_bol,
    ornek_yaniti,
    sistem_istemi,
    soru_metni,
)
from ..metin import imza as metin_imzasi
from ..modeller import Ornek


@dataclass
class DisaAktarmaOzeti:
    dizin: Path
    egitim: int
    dogrulama: int
    test: int
    kanitli: bool
    etiket: str

    def sozluk(self) -> dict[str, object]:
        return {
            "dizin": str(self.dizin),
            "egitim": self.egitim,
            "dogrulama": self.dogrulama,
            "test": self.test,
            "kanitli": self.kanitli,
            "etiket": self.etiket,
        }


def _kararli_oran(metin: str) -> float:
    """Metne bağlı, çalıştırmalar arası değişmeyen 0-1 arası sayı.

    Rastgele bölme kullanılsaydı her dışa aktarımda test örnekleri değişir ve
    sürümler arası karşılaştırma anlamsızlaşırdı.
    """
    ozet = hashlib.sha256(metin.encode("utf-8")).digest()
    return int.from_bytes(ozet[:4], "big") / 0xFFFFFFFF


def ornekten_ornek_kaydi(
    ornek: Ornek,
    *,
    kanitlar: list | None = None,
    # Varsayılan None: etkin ŞEMA SÜRÜMÜNÜN istemi çağrı anında okunur.
    # Sabit v1 istemine bağlanmak, `ornek_yaniti` hedefe `on_cevap`
    # yazarken sistem isteminin onu hiç istememesine yol açıyordu —
    # yani eğitim verisi kendi içinde tutarsız üretiliyordu.
    sistem: str | None = None,
    kanit_azami_adim: int = VARSAYILAN_KANIT_ADIMI,
) -> dict[str, list[dict[str, str]]]:
    """Bir referans örneği eğitim kaydına (``{"messages": [...]}``) çevirir.

    `kanit_azami_adim` çıkarımdaki `Ayarlar.kanit_azami_adim` ile AYNI olmalı:
    model eğitimde gördüğü bağlam biçiminden farklı bir biçimle çalıştırılırsa
    eğitimin kazancı erir. Ölçümde kanıt bloğu eğitim kaydının %50'siydi.
    Kayıt HEDEFİ (öğrenilecek çözüm) kısaltılmaz — model tam çözüm üretmeyi
    öğrenmeli, yalnız bağlamı kısa görmeli.
    """
    mesajlar: list[dict[str, str]] = []
    # None = "etkin şemanın istemini kullan", "" = "sistem mesajı hiç ekleme".
    # İkisini ayırmak şart: `if sistem:` tek başına None'ı da boş sayıp
    # eğitim kayıtlarını sistem mesajsız üretirdi.
    etkin_sistem = sistem_istemi() if sistem is None else sistem
    if etkin_sistem:
        mesajlar.append({"role": "system", "content": etkin_sistem})
    for kanit in kanitlar or []:
        mesajlar.append(
            {"role": "user", "content": f"[REFERANS ÇÖZÜM {kanit.etiket}]\n{kanit.soru}"}
        )
        adimlar = cozumu_adimlara_bol(kanit.cozum)
        if kanit_azami_adim > 0:
            adimlar = adimlar[:kanit_azami_adim]
        mesajlar.append(
            {
                "role": "assistant",
                "content": ornek_yaniti(
                    adimlar,
                    kanit.cevap,
                    kanit.konu,
                    kanit.cozum_turu,
                ),
            }
        )
    mesajlar.append(
        {"role": "user", "content": soru_metni(ornek.soru, ornek.secenekler)}
    )
    mesajlar.append(
        {
            "role": "assistant",
            "content": ornek_yaniti(
                cozumu_adimlara_bol(ornek.cozum),
                ornek.cevap,
                ornek.konu,
                ornek.cozum_turu,
            ),
        }
    )
    return {"messages": mesajlar}


def bol(
    ornekler: list[Ornek], *, dogrulama_orani: float = 0.1, test_orani: float = 0.1
) -> tuple[list[Ornek], list[Ornek], list[Ornek]]:
    """Örnekleri kararlı biçimde eğitim/doğrulama/test olarak böler.

    Bölme sorunun imzasına bağlı olduğu için yeni örnek eklendiğinde eskilerin
    hangi kümede olduğu değişmez — sızıntısız sürüm karşılaştırması bunu gerektirir.
    """
    if dogrulama_orani + test_orani >= 1.0:
        raise ValueError("Doğrulama ve test oranlarının toplamı 1'den küçük olmalı.")
    egitim: list[Ornek] = []
    dogrulama: list[Ornek] = []
    test: list[Ornek] = []
    for ornek in ornekler:
        oran = _kararli_oran(metin_imzasi(ornek.soru))
        if oran < test_orani:
            test.append(ornek)
        elif oran < test_orani + dogrulama_orani:
            dogrulama.append(ornek)
        else:
            egitim.append(ornek)
    return egitim, dogrulama, test


def _jsonl_yaz(yol: Path, kayitlar: list[dict]) -> None:
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_text(
        "\n".join(json.dumps(k, ensure_ascii=False) for k in kayitlar) + ("\n" if kayitlar else ""),
        encoding="utf-8",
    )


def egitim_verisi_yaz(
    ornekler: list[Ornek],
    dizin: str | Path,
    *,
    etiket: str = "",
    kanitli: bool = True,
    kanit_sayisi: int = 2,
    kanit_azami_adim: int = VARSAYILAN_KANIT_ADIMI,
    # Varsayılan None: etkin ŞEMA SÜRÜMÜNÜN istemi çağrı anında okunur.
    # Sabit v1 istemine bağlanmak, `ornek_yaniti` hedefe `on_cevap`
    # yazarken sistem isteminin onu hiç istememesine yol açıyordu —
    # yani eğitim verisi kendi içinde tutarsız üretiliyordu.
    sistem: str | None = None,
    dogrulama_orani: float = 0.1,
    test_orani: float = 0.1,
    gomlemci=None,
) -> DisaAktarmaOzeti:
    """Örnekleri ``train.jsonl`` / ``valid.jsonl`` / ``test.jsonl`` olarak yazar.

    ``kanitli=True`` iken her eğitim kaydına, o örneğin KENDİSİ dışlanarak
    getirilmiş referans örnekler eklenir (retrieval-augmented fine-tuning):
    model, verilen örneklerden yararlanmayı da öğrenir.
    """
    dizin = Path(dizin)
    egitim, dogrulama, test = bol(
        ornekler, dogrulama_orani=dogrulama_orani, test_orani=test_orani
    )

    # Kanıt havuzu YALNIZ eğitim kümesinden kurulur. Tüm örnekler üzerinden
    # kurulsaydı, bir eğitim kaydının few-shot bölümüne benzer bir doğrulama
    # veya test sorusunun TAM ÇÖZÜMÜ girebilir ve model onu ezberleyebilirdi;
    # o örnekle yapılan ölçüm de anlamını yitirirdi.
    indeks = OrnekIndeksi.kur(egitim, gomlemci) if kanitli and egitim else None
    # Doğrulama kayıtları da aynı havuzu kullanır ve kendi kümesinden hiç kanıt
    # almaz; bu yüzden dışlanacak imzalar kümesi eğitim dışı her şeyi kapsar.
    egitim_disi = {metin_imzasi(o.soru) for o in (*dogrulama, *test)}

    def _kayitlar(kume: list[Ornek], kanit_ekle: bool) -> list[dict]:
        cikti = []
        for ornek in kume:
            kanitlar = None
            if kanit_ekle and indeks is not None:
                kanitlar = benzer_ornekler(
                    indeks,
                    ornek.soru,
                    gomlemci=gomlemci,
                    k=kanit_sayisi,
                    cozum_turu=ornek.cozum_turu,
                    konu=ornek.konu,
                    haric_imzalar=egitim_disi | {metin_imzasi(ornek.soru)},
                )
            cikti.append(
                ornekten_ornek_kaydi(
                    ornek,
                    kanitlar=kanitlar,
                    sistem=sistem,
                    kanit_azami_adim=kanit_azami_adim,
                )
            )
        return cikti

    _jsonl_yaz(dizin / "train.jsonl", _kayitlar(egitim, kanitli))
    _jsonl_yaz(dizin / "valid.jsonl", _kayitlar(dogrulama, kanitli))
    # Test kümesi kör değerlendirme içindir: ham örnek olarak saklanır, eğitim
    # biçimine sokulmaz.
    _jsonl_yaz(dizin / "test.jsonl", [o.sozluk() for o in test])

    ozet = DisaAktarmaOzeti(
        dizin=dizin,
        egitim=len(egitim),
        dogrulama=len(dogrulama),
        test=len(test),
        kanitli=kanitli,
        etiket=etiket or dizin.name,
    )
    (dizin / "ozet.json").write_text(
        json.dumps(ozet.sozluk(), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return ozet

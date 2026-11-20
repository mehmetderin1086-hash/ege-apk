import json

import pytest

from biyo_cozucu.depo import Depo
from scripts.guyton_colab_import import aktar
from scripts.guyton_colab_receiver import dogrula


def _yaz(yol, kayitlar):
    yol.write_text(
        "\n".join(json.dumps(kayit, ensure_ascii=False) for kayit in kayitlar),
        encoding="utf-8",
    )


def test_guyton_jsonl_tam_aktarilir_ve_yeniden_baslatilabilir(tmp_path):
    jsonl = tmp_path / "guyton.jsonl"
    veritabani = tmp_path / "biyo.db"
    metin = (
        "Kalp debisi, kalbin bir dakikada pompaladığı kan hacmidir. "
        "Venöz dönüş ve kalp hızı ile yakından ilişkilidir. " * 3
    )
    _yaz(
        jsonl,
        [
            {"page": 1, "text": metin, "confidence": 0.91, "error": ""},
            {"page": 2, "text": "kapak", "confidence": 0.2, "error": ""},
        ],
    )

    ilk = aktar(
        jsonl, veritabani, kaynak="Guyton ve Hall Tıbbi Fizyoloji", beklenen_sayfa=2
    )
    ikinci = aktar(
        jsonl, veritabani, kaynak="Guyton ve Hall Tıbbi Fizyoloji", beklenen_sayfa=2
    )

    assert ilk[0] > 0
    assert ilk[2:] == (1, 0, [])
    assert ikinci[0] == 0
    assert ikinci[1] == ilk[0]
    assert Depo(veritabani).pasaj_say(kaynak="Guyton ve Hall Tıbbi Fizyoloji") == ilk[0]


def test_guyton_jsonl_eksik_ve_yinelenen_sayfayi_reddeder(tmp_path):
    jsonl = tmp_path / "guyton.jsonl"
    veritabani = tmp_path / "biyo.db"
    _yaz(jsonl, [{"page": 1, "text": "x" * 150, "error": ""}])
    assert aktar(jsonl, veritabani, kaynak="Guyton", beklenen_sayfa=2)[4] == [2]

    _yaz(
        jsonl,
        [
            {"page": 1, "text": "x" * 150, "error": ""},
            {"page": 1, "text": "y" * 150, "error": ""},
        ],
    )
    with pytest.raises(ValueError, match="Yinelenen sayfa"):
        aktar(jsonl, veritabani, kaynak="Guyton", beklenen_sayfa=2)


def test_guyton_checkpoint_alicisi_sayfa_araligini_dogrular():
    govde = b'\n'.join(
        [
            json.dumps({"page": 1, "text": "bir", "error": ""}).encode(),
            json.dumps({"page": 2, "text": "iki", "error": "OCR"}).encode(),
        ]
    )
    assert dogrula(govde, 2) == (2, 1)

    with pytest.raises(ValueError, match="beklenmeyen sayfa"):
        dogrula(json.dumps({"page": 3}).encode(), 2)

#!/usr/bin/env python3
"""Package a completed run.sh export, then reread every archived question."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile

PROJECT = Path(__file__).resolve().parents[2]
PLATES = {f"assets/photos/plate{i:02}.webp" for i in range(1, 25)}
METADATA = ("ozet.json", "aile-ornekleri.json")
README_NAME = "OKU.txt"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def readme(summary):
    total = f"{summary['questions']:,}".replace(",", ".")
    return f"""BİLGİLİ 3.8.0 | Çevrimdışı soru bankası

Bu arşivde {total} soru, {summary['families']} soru ailesi ve görsel sorularda
kullanılan 24 WebP levha bulunur. İnceleme ve veri analizi için ZIP'i açın.
Aile ve düzey dağılımlarını ozet.json içinde, örnek kayıtları
aile-ornekleri.json içinde bulabilirsiniz. Örnekler ana bankadan seçilmiştir.

Soruları okuma

sorular/ içindeki her .jsonl.gz dosyası bir ailenin bütün sorularını içerir.
Gzip katmanını açınca her satır ayrı bir UTF-8 JSON nesnesidir. İsterseniz
dosyayı diske çıkarmadan Python ile ilk soruyu okuyabilirsiniz.

    import gzip, json
    from pathlib import Path
    dosya = next(Path("sorular").glob("*.jsonl.gz"))
    with gzip.open(dosya, "rt", encoding="utf-8") as akim:
        soru = json.loads(next(akim))
    print(soru["id"], soru["text"])

id soru kimliğidir. studyLevel düzeyi, bloom bilişsel basamağı, category
konuyu, explanation ise yanıtın gerekçesini verir. visual alanı tablo,
grafik ve şema verilerini içerir. Görsel türü image ise imageID, WebP
dosyasının uzantısız adıdır. Örneğin plate01, assets/photos/plate01.webp
dosyasını açar. gorseller.json görsellerin üretim kaynağını kaydeder.

Yanıt türleri ve puanlama

• choice ve trueFalse türlerinde options dizisinde answer konumundaki yanıt doğrudur.
  Dizi konumları sıfırdan başlar. responseType yoksa tür choice kabul edilir.
• multiSelect türünde multiSelect.correct doğru seçeneklerin tüm konumlarını içerir.
  Oyuncunun seçim kümesi anahtarla tam eşleştiğinde yanıt doğru sayılır.
  Bu türde yalnızca ana answer alanını okumak eksik sonuç verir.
• fill türünde oyuncu yanıtı yazar. Başvuru yanıtı options[answer] alanındadır.
  Uygulama eşdeğer sayısal yazımları ve desteklenen birim yazımlarını denetler.
• ordering türünde activity.solution, activity.items içindeki öğelerin doğru sırasını
  konum numaralarıyla verir. matching türünde aynı dizinin i numaralı değeri,
  activity.left[i] ile eşleşen öğenin activity.right içindeki konumudur.
• listening ve pronunciation türlerinde activity.transcript dinleme metnini veya
  söylenecek ifadeyi, activity.language dil bilgisini taşır. Uygulama bu
  alanları cihazın ses özellikleriyle kullanır.
• creation türünde öğrenci creation.brief yönergesine ve creation.criteria ölçütlerine
  göre kendi ürününü yazar. Uygulama bu yanıtı çalışma defterine kaydeder.
  Tur puanını ardından yanıtlanan kontrol sorusu belirler. Serbest metnin
  niteliğini değerlendirmek için verilen ölçütler ayrıca kullanılabilir.
"""


def verify_archive(path):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "ZIP CRC verification failed")
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP entry")
        summary = json.loads(archive.read("ozet.json"))
        families = json.loads(archive.read("aile-ornekleri.json"))
        counts = {row["key"]: row["count"] for row in families}
        require(len(counts) == len(families) == summary["families"], "Family count mismatch")
        sources = json.loads(archive.read("gorseller.json"))
        require(len(sources) == 24 and {s["file"] for s in sources} == PLATES,
                "Provenance does not match image assets")
        expected = {f"sorular/{key}.jsonl.gz" for key in counts}
        require(set(names) == expected | set(METADATA) | PLATES | {"gorseller.json", README_NAME},
                "Unexpected or missing archive members")
        for name in PLATES:
            data = archive.read(name)
            require(data[:4] == b"RIFF" and data[8:12] == b"WEBP" and
                    int.from_bytes(data[4:8], "little") + 8 == len(data), name)
        total, references = 0, Counter()
        for key, expected_count in counts.items():
            count = 0
            with archive.open(f"sorular/{key}.jsonl.gz") as compressed:
                with gzip.GzipFile(fileobj=compressed) as rows:
                    for line in rows:
                        question = json.loads(line)
                        require(question["id"] == f"ak38_{key}_{count}", f"{key} row {count}")
                        if (visual := question.get("visual")) and visual["kind"] == "image":
                            references[f"assets/photos/{visual['imageID']}.webp"] += 1
                        count += 1
            require(count == expected_count, f"{key}: {count} rows, expected {expected_count}")
            total += count
        require(total == summary["questions"] == summary["uniqueCases"], "Grand total mismatch")
        require(set(references) == PLATES, "Question image references do not match the 24 plates")
        return total, len(counts), sum(references.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, help="Directory produced by run.sh")
    parser.add_argument("output", type=Path, help="Output ZIP path")
    args = parser.parse_args()
    summary = json.loads((args.export / "ozet.json").read_text(encoding="utf-8"))
    rows = json.loads((args.export / "aile-ornekleri.json").read_text(encoding="utf-8"))
    expected = {f"{row['key']}.jsonl.gz" for row in rows}
    actual = {path.name for path in (args.export / "sorular").glob("*.jsonl.gz")}
    require(actual == expected, "Export directory differs from completed family manifest")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as temp:
        pending = Path(temp) / "bank.zip"
        with zipfile.ZipFile(pending, "w") as archive:
            archive.writestr(README_NAME, readme(summary), compress_type=zipfile.ZIP_DEFLATED)
            for name in METADATA:
                archive.write(args.export / name, name, compress_type=zipfile.ZIP_DEFLATED)
            archive.write(Path(__file__).with_name("gorseller.json"), "gorseller.json",
                          compress_type=zipfile.ZIP_DEFLATED)
            for name in sorted(PLATES):
                archive.write(PROJECT / name, name)
            for basename in sorted(actual):
                name = f"sorular/{basename}"
                archive.write(args.export / name, name)
        total, families, images = verify_archive(pending)
        with pending.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        size = pending.stat().st_size
        pending.replace(args.output)
    print(f"{args.output}\n{total} rows, {families} families, {images} image rows, "
          f"24 WebP assets, {size} bytes\nSHA-256 {digest}", flush=True)


if __name__ == "__main__":
    main()

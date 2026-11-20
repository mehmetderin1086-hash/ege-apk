# BioProf

BioProf, yüklediğiniz kaynaklardan kanıt toplayan; yanıtlarını değişmez kaynak
konumlarına bağlayan; yerel model, CLI Proxy API ve SesLab/Murat ile çalışabilen
Python tabanlı bir biyoloji ve tıp eğitim/araştırma uygulamasıdır.

Uygulamanın varsayılanı yereldir: FastAPI sunucusu `127.0.0.1:8765` üzerinde,
veriler `~/Library/Application Support/BioProf` altında çalışır. Arayüz Jinja2,
htmx uyumlu küçük bir yardımcı ve düz JavaScript kullanır; Node/React derlemesi
yoktur.

> **Kapsam sınırı:** BioProf tanı, tedavi, reçete, kişiye özel ilaç dozu veya
> klinik karar üretmez. Kimliklenebilir sağlık/genetik kişisel veriyi kabul
> etmek üzere tasarlanmamıştır. Eğitim ve araştırma yardımcısıdır; hekim veya
> laboratuvar uzmanı değerlendirmesinin yerini tutmaz.

## Mevcut sürümde çalışan ana yüzeyler

- Üç bölmeli yerel web arayüzü: kaynak seçimi, kaynaklı sohbet, Studio ve iş
  durumu.
- PDF/Office/metin/yapılandırılmış veri/biyoloji dosyaları için eklenti tabanlı
  içe aktarma; desteklenmeyen veya riskli dosyada açık inceleme durumu.
- SQLite FTS5 + yerel dense arama + RRF; `rag` eklentisi kuruluysa gömülü
  Qdrant. Varsayılan dense temsil, model indirmeyen 384 boyutlu hashing
  embedding'dir.
- `strict` kaynaklı cevap, iddia/alıntı zarfı ve kanıt yoksa cevap vermeme.
- Yerel deterministik sağlayıcı, CLI Proxy API adaptörü, genel OpenAI-uyumlu
  servis adaptörü ve açıkça başlatılan MLX/llama.cpp model sunucusu.
- OpenAI-uyumlu Chat Completions, Responses, embeddings, rerank ve ses
  uçları.
- SesLab üzerinden MLX-Whisper transkripsiyonu ve Murat/XTTS seslendirme.
- PubMed/PMC, NCBI Gene/Protein/Taxonomy/ClinVar ve ClinicalTrials.gov resmi
  konektörleri.
- Kaynaklı Studio çıktıları, izinli bilimsel hesap araçları, incelenebilir
  fine-tuning veri seti, Unsloth Colab QLoRA paketi ve candidate/champion
  kayıt defteri.
- Kalıcı iş kayıtları, SSE ilerleme olayları, yedek doğrulama ve güvenli staging
  restore.

Bu liste hedef mimariyi değil, mevcut kodu özetler. Özellikle BGE-M3 ve
`bge-reranker-v2-m3` adaptör sınıfları bulunsa da uygulama başlangıcında otomatik
yüklenmez; sahne/kare OCR'lı video çözümlemesi ve uygulama içinden yerel eğitim
çalıştırma henüz yoktur. Ayrıntılı durum için [Mimari](docs/ARCHITECTURE.md) ve
[sınırlar](#mevcut-sınırlar) bölümlerine bakın.

## Gereksinimler

- Python `>=3.11,<3.14`
- [uv](https://docs.astral.sh/uv/)
- Yerel model motorları için Apple Silicon macOS önerilir; çekirdek API diğer
  platformlarda da çalışabilir.
- Ses özellikleri için ayrı çalışan mevcut SesLab servisi.
- CLI Proxy kullanımı için ayrı çalışan CLI Proxy API ve onun sanal istemci
  anahtarı.

## Hızlı başlangıç

Depo kökünde:

```bash
uv sync --no-editable --extra rag
uv run bioprof doctor
uv run bioprof serve --open
```

Arayüz: <http://127.0.0.1:8765>

İlk açılışta boş veri dizininde `İlk Notebook` otomatik oluşturulur. Arayüzden
bir dosya ekleyin, indeksleme işi tamamlandıktan sonra kaynağı seçip soru sorun.
Varsayılan `local_evidence` sağlayıcısı, model indirmeden en ilgili kanıt
parçalarını alıntılı olarak gösterir.

macOS'ta Finder üzerinden başlatmak için:

```bash
open scripts/BioProf.command
```

Masaüstüne simgeli, tek tıklamalı `BioProf.app` kurmak için:

```bash
uv run python scripts/install_macos_app.py
open "$HOME/Desktop/BioProf.app"
```

Başlatıcı önce çalışan bir BioProf sürecini arar. Varsayılan 8765 başka bir
program tarafından kullanılıyorsa 8766–8775 arasındaki ilk boş loopback portunu
seçer, sunucunun `/healthz` kabulünü bekler ve web arayüzünü varsayılan
tarayıcıda açar. Finder'ın Documents erişim kısıtına takılmamak için salt çalışma
kopyası `~/Library/Application Support/BioProf/runtime` altına kurulur; notebook
ve kaynak verileri aynı üst dizindeki ayrı veri klasörlerinde kalır. Başlatma günlüğü
`~/Library/Logs/BioProf/desktop-launcher.log` altındadır.

Tanılama penceresi:

```bash
open scripts/doctor.command
```

### Neden `--no-editable`?

Bazı güncel macOS/Python 3.12 kurulumları uv'nin ürettiği alt çizgiyle başlayan
editable `.pth` dosyasını atlayabiliyor. Dağıtım benzeri yerel kurulum için
`uv sync --no-editable ...` kullanın. Geliştirici komutlarında pytest'in
`pythonpath = ["src"]` ayarı vardır; doğrudan modül çalıştırırken gerekirse:

```bash
PYTHONPATH=src uv run python -m bioprof.cli doctor
```

## İsteğe bağlı bağımlılıklar

Temel kurulum PDF, DOCX, PPTX, XLSX, metin, yapılandırılmış veri ve biyoloji
ayrıştırıcılarının güvenli yerel fallback'lerini içerir. Ağır bileşenler ayrı
gruplardadır:

| Extra | Kurulum | Sağladığı yetenek |
| --- | --- | --- |
| `rag` | `uv sync --no-editable --extra rag` | Gömülü Qdrant vektör deposu |
| `documents` | `uv sync --no-editable --extra documents` | Docling ile yapı/provenance ve görsel OCR yolu |
| `media` | `uv sync --no-editable --extra media` | PyAV, sahne yardımcı paketi ve Apple Silicon'da mlx-whisper kitaplığı; BioProf medya içe aktarması yine SesLab uçlarını kullanır |
| `models` | `uv sync --no-editable --extra models` | Hugging Face indirme, sentence-transformers/FlagEmbedding ve Apple Silicon MLX sunucuları |
| `training` | `uv sync --no-editable --extra training` | datasets, DVC, MLflow, PEFT, Transformers ve TRL çalışma ortamı |
| `all` | `uv sync --no-editable --extra all` | Yukarıdaki ağır grupların tamamı |
| `mcp` | `uv sync --no-editable --extra mcp` | stdio üzerinden BioProf MCP sunucusu |

Birden fazla extra birlikte verilebilir:

```bash
uv sync --no-editable --extra rag --extra documents --extra models --extra mcp
```

Eksik optional paket çekirdeği durdurmaz. Örneğin Docling yoksa desteklenen
belgelerde yerleşik parser devreye girer; görsel OCR ise dosyayı başarılı saymak
yerine `needs_review` durumuna taşır. PDF Studio dışa aktarımı için `reportlab`
çekirdek bağımlılık olarak kurulur.

## `doctor`: önce gerçek durumu görün

```bash
uv run bioprof doctor
uv run bioprof doctor --json
uv run bioprof doctor --active-provider-probe
```

`doctor` şunları salt okunur biçimde kontrol eder:

- işletim sistemi, Apple Silicon, CPU, RAM ve boş disk;
- çekirdek/isteğe bağlı Python paketleri;
- `uv`, `ffmpeg`, `tesseract`, `pdftotext`, `llama-server`, `ollama`
  komutlarının bulunabilirliği;
- SesLab'ın `/api/system/status` veya `/healthz` yanıtı;
- CLI Proxy'nin `/healthz`, `/readyz`, `/v1/models` ve ilan ettiği uyumlu
  yolları;
- CLI Proxy kimlik bilgisinin yalnız **varlık/kaynak** bilgisi; anahtar değeri
  çıktıya yazılmaz.

`--active-provider-probe`, bulunan ilk modelle ilan edilen Chat Completions ve
Responses yollarını birer tokenlık mini istekle sınayabilir; iki yol da varsa
iki upstream isteği oluşabilir. Kota veya dış ağ kullanabileceği için yalnız
açıkça istediğinizde kullanın.

## SesLab, Whisper ve Murat

Varsayılan SesLab adresi `http://127.0.0.1:8000`'dir. BioProf mevcut SesLab
kurulumunu veya Murat checkpoint'ini kopyalamaz/değiştirmez; yalnız şu uçlara
loopback üzerinden bağlanır:

- `POST /v1/audio/transcriptions`: `model=mlx-whisper`
- `POST /v1/audio/speech`: `model=xtts-v2`, `voice=Murat`

Örnekler:

```bash
uv run bioprof transcribe ders.m4a --language tr --response-format verbose_json
uv run bioprof speak "Mitokondrinin temel görevlerini açıklayalım." -o murat.wav
uv run bioprof speak "Titiz doğrulama örneği." -o kontrol.wav --strict
```

Web arayüzündeki mikrofon düğmesi tarayıcı `MediaRecorder` kaydını BioProf'un
ses API'sine, oradan SesLab'a gönderir. “Sesli yanıt” işaretliyse kaynaklı cevap
sonrasında ayrı bir Murat işi oluşturulur. Studio sesli dersinde bölümler ayrı
WAV parçaları olarak üretilip PCM özellikleri doğrulandıktan sonra birleştirilir.

SesLab kapalıysa metin/RAG çalışmaya devam eder; ses çağrısı açık hata döndürür.
BioProf yapay ses yanıtlarında `X-AI-Generated-Voice: true` başlığını ekler.
XTTS/Murat kullanımı kişisel, ticari olmayan ve izinli ses koşullarıyla
sınırlandırılmıştır; ayrıntı [THIRD_PARTY.md](THIRD_PARTY.md) içindedir.

## CLI Proxy API ve dış veri izinleri

CLI Proxy varsayılan olarak `http://127.0.0.1:8317` adresinde aranır. Daemon
loopback'te olsa bile seçtiği upstream uzak olabileceği için BioProf onu dış
veri aktarımı yapan bir sağlayıcı sayar. Otomatik/sessiz fallback yoktur.

Sanal istemci anahtarını macOS Keychain'e, kabuk geçmişine yazmadan eklemek için:

```bash
security add-generic-password -U \
  -s "BioProf CLI Proxy API Key" \
  -a bioprof \
  -w
```

Geçici geliştirme alternatifi `BIOPROF_CLIPROXY_API_KEY` ortam değişkenidir;
`.env` veya loglara sır koymayın.

Native notebook sorusunda CLI Proxy kullanmak için iki ayrı onay gerekir:

1. Uygulama düzeyi: `BIOPROF_ALLOW_REMOTE_EGRESS=true`.
2. Notebook düzeyi: `remote_egress_approved=true` ve `local_only` dışında bir
   gizlilik modu.

Örnek:

```bash
export BIOPROF_ALLOW_REMOTE_EGRESS=true
uv run bioprof serve
```

```bash
curl -sS -X PATCH http://127.0.0.1:8765/api/v1/notebooks/NOTEBOOK_ID \
  -H 'Content-Type: application/json' \
  -d '{"privacy_mode":"cloud_allowed","remote_egress_approved":true}'
```

Sonra:

```bash
uv run bioprof ask "Kaynaklara göre mekanizma nedir?" \
  --notebook NOTEBOOK_ID \
  --provider cliproxy \
  --model MODEL_ADI
```

OpenAI-uyumlu `/v1/*` yüzeyi, standart `metadata.bioprof_notebook_id` alanı
verildiğinde aynı native RAG ve notebook izin akışını kullanır; yanıt metninde
`[S1]` alıntıları, HTTP'de `X-BioProf-Trace-ID` ve yanıtta `bioprof` uzantısı
bulunur. Metadata verilmezse yüzey provider-level proxy olarak çalışır; uzak
provider için `BIOPROF_ALLOW_REMOTE_EGRESS=true` kapısına ek olarak
`BIOPROF_ALLOW_OPENAI_COMPAT_REMOTE=true` açık onayı gerekir. İzin modeli ve
tehdit sınırları [Güvenlik](docs/SECURITY.md) belgesindedir.

## Web arayüzü

Arayüzde şu akışlar uygulanmıştır:

- notebook oluşturma ve gizlilik modu seçme;
- dosya yükleme, kaynak durumunu/filtreyi ve kaynak seçimini görme;
- `strict`, `hybrid`, `research` istek modları ve sağlayıcı seçimi;
- tıklanabilir alıntı ayrıntısı;
- tarayıcı mikrofonu ile Türkçe transkripsiyon ve Murat sesli cevap işi;
- özet, çalışma kılavuzu, quiz, flashcard, zihin haritası, tablo, FAQ,
  zaman çizgisi, sesli ders ve video genel bakış Studio işleri;
- açık onay kutusuyla notebook dışa çıkış izni, resmi araştırma sonuçlarını
  seçip snapshot olarak içe aktarma;
- provider ve iş kuyruğu durumu;
- notebook başına tarayıcı `localStorage` notları.

Araştırma onayı yalnız notebook bayrağını değiştirir; global
`BIOPROF_ALLOW_REMOTE_EGRESS=true` şartını aşmaz. Model menüsü native katalogdaki
yerel profilleri, provider modellerini ve model registry kayıtlarını birleştirir;
indirilmemiş veya terfi edilmemiş modelleri seçilebilir gibi göstermez. Gene,
Protein, Taxonomy ve ClinVar araştırmalarında seçilen sonuçlar lisanslı tam
metin gibi değil, açıkça metadata JSON snapshot'ı olarak içe alınır.

## CLI

Sunucu açıkken CLI, varsayılan olarak `http://127.0.0.1:8765` ile konuşur.

| Komut | İşlev |
| --- | --- |
| `bioprof serve [--open]` | Yerel web/API sunucusu |
| `bioprof doctor [--json]` | Donanım, bağımlılık ve servis tanısı |
| `bioprof ingest PATH -n ID` | Dosya içe aktarma işini başlatır |
| `bioprof search QUERY -n ID` | Kaynaklarda arama |
| `bioprof ask QUESTION -n ID` | Tek kaynaklı soru |
| `bioprof chat -n ID` | Etkileşimli kaynaklı sohbet |
| `bioprof transcribe PATH` | SesLab/Whisper transkripsiyonu |
| `bioprof speak TEXT -o FILE` | SesLab/Murat seslendirmesi |
| `bioprof models list` | OpenAI-uyumlu yüzeyde hazır provider modelleri |
| `bioprof models pull PROFILE` | `fast`, `balanced` veya `biomedical` indirme işi |
| `bioprof models benchmark MODEL` | Önceden başlatılmış yerel sunucuyu ölçme işi |
| `bioprof providers test [NAME]` | Provider yetenek denetimi |
| `bioprof dataset build/validate` | İncelemeli veri seti akışı |
| `bioprof train export-colab/import/promote/rollback` | Eğitim manifesti ve model kayıt akışı |
| `bioprof eval run/report` | Altın set değerlendirmesi |
| `bioprof backup/restore` | Doğrulanmış yedek ve staging restore |

Notebook kimliğini bulma:

```bash
curl -sS http://127.0.0.1:8765/api/v1/notebooks
```

CLI komutları uzun işleri beklemez; dönen `job_id` değerini
`GET /api/v1/jobs/{job_id}` veya SSE olaylarıyla izleyin.

## API ve MCP

- Native API: notebook, kaynak, RAG, araştırma, Studio, işler, eğitim, araçlar,
  model yaşam döngüsü ve yedekleme.
- OpenAI-uyumlu API: `/v1/chat/completions`, `/v1/responses`,
  `/v1/embeddings`, `/v1/rerank`, `/v1/models`, ses uçları.
- Her HTTP yanıtına izlenebilirlik için `X-BioProf-Trace-ID` eklenir.
- İstek modelleri `extra="forbid"` kullanır; bilinmeyen alan sessizce
  yutulmaz.

Detaylar ve `curl` örnekleri: [API.md](docs/API.md).

MCP extra'sı kurulduğunda stdio sunucusu:

```bash
uv run --extra mcp bioprof-mcp
```

Sunucu varsayılan olarak yalnız `http://127.0.0.1:8765` adresine bağlanır ve
`search_sources`, `ask_notebook`, `resolve_citation`, `run_calculator`,
`ingest_source` araçlarını sunar. `ingest_source` varsayılan kapalıdır; yerel
dosya içe aktarmak için en az bir allowlist kökü verin:

```bash
uv run --extra mcp bioprof-mcp --import-root "$HOME/Documents/BioProf-Kaynaklari"
```

Alternatif ortam ayarı `BIOPROF_MCP_IMPORT_ROOTS`'tur (macOS'ta birden çok kök
`:` ile ayrılır). Allowlist dışı, symlink, boş veya `.env`/SSH/private-key gibi
hassas dosyalar reddedilir. Uzak BioProf hedefine bağlanma ayrıca
`--allow-remote` veya `BIOPROF_MCP_ALLOW_REMOTE=1` gerektirir ve uzak hedefte
`ingest_source` her koşulda kapalı kalır.

## Desteklenen içe aktarma biçimleri

“Destekleniyor”, dosyanın her varyantının kusursuz işlendiği anlamına gelmez.
Parser başarısızlığı `needs_review`, doğrudan tanımlayıcı bulgusu
`quarantined` durumuyla görünür tutulur.

| Grup | Uzantılar | Mevcut davranış |
| --- | --- | --- |
| Düz metin | `.txt`, `.md`, `.markdown`, `.rst`, `.tex`, `.log` | Yerel metin parser'ı |
| Web/e-kitap | `.html`, `.htm`, `.xhtml`, `.epub` | Docling tercihli HTML; güvenli EPUB ZIP okuma |
| PDF/Office | `.pdf`, `.docx`, `.pptx`, `.xlsx` | Docling tercihli; pypdf/python-docx/python-pptx/openpyxl fallback |
| OpenDocument | `.odt`, `.ods`, `.odp` | Güvenli ZIP + `content.xml` metni |
| Görsel | `.png`, `.jpg`, `.jpeg`, `.tif`, `.tiff`, `.webp`, `.heic` | Docling/OCR varsa; yoksa `needs_review` |
| Tablo/veri | `.csv`, `.tsv`, `.json`, `.xml`, `.jats` | Satır/öğe/XML yapı blokları |
| Kaynakça | `.bib`, `.ris` | Kayıt bazlı metin blokları |
| Dizi | `.fa`, `.fasta`, `.fna`, `.faa`, `.ffn`, `.fq`, `.fastq`, `.gb`, `.gbk`, `.genbank`, `.embl` | Biopython; 1-tabanlı dizi aralıkları |
| Genom özelliği | `.gff`, `.gff3`, `.gtf`, `.vcf` | Kromozom/kayıt grubu ve dizi aralığı |
| Yapı/kimya | `.pdb`, `.cif`, `.mmcif`, `.smi`, `.smiles`, `.sdf`, `.mol` | Yapı/kayıt blokları; kimyasal doğruluk motoru değildir |
| Ses | `.wav`, `.mp3`, `.m4a`, `.flac`, `.ogg`, `.aac` | SesLab transkripti ve zaman damgası (servis gerekli) |
| Video | `.mp4`, `.mov`, `.mkv`, `.webm`, `.m4v` | SesLab'a medya transkripsiyonu; mevcut sürüm sahne/kare OCR yapmaz |
| Diğer `text/*` | Uzantıdan bağımsız | Güvenli düz metin fallback |

Tek dosya sınırı varsayılan olarak 250 MiB'dir. URL içe aktarma yalnız açıkça
verilen HTTP(S) URL için çalışır; özel/loopback ağlar, kimlik bilgili URL'ler,
kontrolsüz yönlendirme ve boyut aşımı reddedilir.

## RAG davranışı

1. Kaynaklar yapı sınırlarına göre yaklaşık 2.400 karakter hedef ve 240
   karakter örtüşmeyle parçalanır.
2. SQLite FTS5/BM25 ve dense kanal paralel aranır.
3. `rag` kurulmuşsa dense vektörler gömülü Qdrant'ta; değilse SQLite
   parçalarında isteğe bağlı hesaplanır.
4. Kanallar RRF ile birleşir, ilk 30 aday değerlendirilir, kaynak başına en çok
   üç ve toplam en çok on kanıt seçilir.
5. Alıntı; kaynak/chunk kimliği ve sayfa/slayt/bbox, zaman veya dizi aralığına
   bağlanır. Kaynak kaydı ayrıca SHA-256 ile sürümlenir.
6. `strict` cevapta kanıtsız model cümleleri atılır; geçerli cümle kalmazsa
   extractive kanıt özeti, hiç kanıt yoksa abstention üretilir.

Mevcut bootstrap embedding (`bioprof-hashing-384`) küçük, deterministik ve
tamamen yereldir. `SentenceTransformerEmbedder` ve `CrossEncoderReranker`
genişleme noktaları kodda bulunur; uygulama ayarları şu an bunları otomatik
BGE-M3/bge-reranker olarak etkinleştirmez. Bu ayrım performans iddiası açısından
önemlidir.

## Fine-tuning özeti

BioProf, yüklenen belgeleri doğrudan modele ezberletmez. Kaynak chunk'larından
aday soru/yanıtlar üretir; adaylar başlangıçta `pending` ve hak onayı kapalıdır.
Yalnız insan tarafından `approved`, `rights_approved=true` ve lisansı doğrulanmış
örnekler veri setine girebilir.

Mevcut eğitim yüzeyi:

- family-level train/validation/test ayrımı ve içerik hash'i;
- QLoRA varsayımları: NF4, double quantization, `r=32`, `alpha=64`,
  dropout `0.05`, sıra uzunluğu 2048, etkin batch 16, LR `2e-4`, 2 epoch;
- incelenebilir `dataset_manifest.json` ve Unsloth Colab notebook'u;
- adapter + manifest içe aktarma, checksum'lı candidate kaydı;
- altın değerlendirme geçmeden champion olamama ve rollback.

BioProf sunucusu eğitimi kendi başına başlatmaz; Colab paketi dışarıda
çalıştırılır ve sonuç adapterı açıkça geri alınır. Adapter import varsayılan
kapalıdır ve `BIOPROF_TRAINING_IMPORT_ROOTS` allowlist'i gerektirir. Ayrıntılı iş akışı:
[FINE_TUNING.md](docs/FINE_TUNING.md).

## Veri dizini

Varsayılan kök: `~/Library/Application Support/BioProf`

| Yol | İçerik |
| --- | --- |
| `bioprof.sqlite3` (+ WAL) | Notebook, kaynak, chunk, sohbet, iş ve eğitim metadata'sı |
| `objects/<hash-prefix>/<sha256>` | Hash tabanlı özgün kaynak deposu |
| `quarantine/` | İndekslenmeyen riskli kaynak blob'ları |
| `qdrant/` | İsteğe bağlı gömülü vektör koleksiyonu |
| `artifacts/` | Studio, dataset, training, evaluation ve model registry çıktıları |
| `incoming/` | İş sırasında kullanılan geçici yüklemeler |
| `restore-staging/` | Canlı veriyi ezmeden açılan doğrulanmış yedekler |

Yerel model snapshot'ları veri dizininden ayrı olarak varsayılan
`~/Library/Caches/BioProf/models` altında tutulur; kök
`BIOPROF_MODEL_CACHE_DIR` ile değiştirilebilir.

## Test ve kalite komutları

```bash
uv sync --no-editable --group dev --extra rag
uv run pytest -q
uv run ruff check src tests
uv run mypy src
```

Belirli sözleşmeler:

```bash
uv run pytest tests/test_ingest_rag.py -q
uv run pytest tests/test_providers_voice_openai.py -q
uv run pytest tests/test_native_api.py tests/test_app_e2e.py -q
uv run pytest tests/test_studio_tools_training.py -q
uv run pytest tests/test_mcp_server.py -q
```

Migrations smoke testi:

```bash
BIOPROF_DATA_DIR=/tmp/bioprof-migration-test uv run alembic upgrade head
```

Canlı kabulte yalnız `/healthz` yeterli sayılmamalıdır: küçük bir dosya yükleyip
işi bekleyin, kaynaklı soru sorun; SesLab/CLI Proxy kullanılacaksa gerçek küçük
transkripsiyon, speech ve provider isteği de yapın. Operasyon kontrol listesi:
[OPERATIONS.md](docs/OPERATIONS.md).

## Mevcut sınırlar

- Klinik kullanım, FHIR/PACS ve kimlikli DICOM kapsam dışıdır.
- Kişisel veri taraması muhafazakâr regex tabanlı bir ön kapıdır; hukuki uyum
  veya kusursuz de-identification garantisi değildir.
- “Her format” iddiası yoktur. Registry'de olmayan dosya başarılı gösterilmez.
- Video içe aktarma şu an transkript üretir; sahne seçimi, kare OCR ve görsel
  zaman çizgisi uygulanmış değildir.
- BGE-M3, MedCPT ve neural reranker varsayılan runtime'a bağlı değildir;
  ölçülmüş altın set olmadan kalite hedeflerine ulaşıldığı iddia edilmez.
- Native `CitationAnchor` kaynak/chunk kimliği, değişmez kaynak SHA-256'sı ve
  sayfa/slayt/bbox/zaman/dizi konumu gibi parser'ın üretebildiği anchor bilgisini
  taşır.
- `hybrid` mod kaynak iddialarını doğrulamaya devam eder ve alıntısız model
  bilgisini “Modelin genel bilgisi — seçili kaynaklarla doğrulanmadı” başlığına
  ayırır; bu kısım `supported=false` claim'dir. `research` ask modu kendi başına
  konektör çağırmaz; resmi araştırma ayrı iş uç noktasındadır.
- Studio `infographic` şu an kaynaklı zihin haritası temsiline, `slides` kaynaklı
  çalışma kılavuzu temsiline dayanır. MP4 yalnız PyAV ve SesLab hazırsa oluşur;
  PyAV yoksa WAV + SRT sidecar döner.
- MP3 Studio talebi doğrulanabilir birleştirme için WAV'a normalize edilir.
- Yerel model profilini indirmek onu otomatik başlatmaz veya varsayılan yapmaz.
- Fine-tuning tarafı dataset/Colab/export/import/registry orkestrasyonudur;
  yerel uzun eğitim worker'ı uygulanmış değildir. LlamaFactory seçeneği şemada
  yer alsa da notebook exporter şu an yalnız Unsloth reçetesini üretir.
- Otomatik dataset adayı chunk'ı `untrusted_context` olarak instruction'a
  koyar; yanıta ilk cümleyi `[S1]` ile ekleyen, kaynakla sınırlı davranış
  bootstrap'ıdır. Uzman incelemesi ve görev çeşitlendirmesi olmadan genel eğitim
  kalitesi iddiası taşımaz.
- Kaynak silme canlı SQL/FTS/Qdrant/object-store türevlerini hedefler; daha önce
  dışa aktarılmış dataset, adapter, Studio çıktısı veya yedekleri geriye dönük
  olarak iptal edip silmez.
- Uygulama loopback erişimini zorunlu kılar; çok kullanıcılı/paylaşımlı sunucu
  ve genel paylaşım özelliği yoktur.

## Belgeler

- [Mimari ve veri akışı](docs/ARCHITECTURE.md)
- [API ve MCP](docs/API.md)
- [Güvenlik ve gizlilik](docs/SECURITY.md)
- [Fine-tuning ve model kayıt akışı](docs/FINE_TUNING.md)
- [Kurulum, işletim ve sorun giderme](docs/OPERATIONS.md)
- [Üçüncü taraf/model lisans envanteri](THIRD_PARTY.md)

## Lisans

BioProf kaynak kodu MIT lisanslıdır. Kütüphaneler, indirilen model ağırlıkları,
SesLab, Murat/XTTS ve kullanıcı kaynakları kendi lisans/izin koşullarını korur.
Bu depo hukuki danışmanlık sunmaz.

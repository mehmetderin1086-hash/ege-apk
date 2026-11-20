# Secde Vakti — 1024x1024 uygulama simgesinden tüm Android mipmap boyutlarını üretir.
# Kullanım: python simge_uret.py kaynak_1024.png cikti_klasoru
import os, sys
from PIL import Image

kaynak = sys.argv[1]
hedef = sys.argv[2]
os.makedirs(hedef, exist_ok=True)

# secde_vakti_1.0.0.apk içindeki res/ mipmap eşleşmeleri (aapt2 dump badging):
# 160dpi (mdpi)   -> res/9w.png  (48x48)
# 240dpi (hdpi)   -> res/yn.png  (72x72)
# 320dpi (xhdpi)  -> res/FS.png  (96x96)
# 480dpi (xxhdpi) -> res/RJ.png  (144x144)
# 640dpi (xxxhdpi)-> res/o-.png  (192x192)
ESLESME = [
    ("9w.png", 48),
    ("yn.png", 72),
    ("FS.png", 96),
    ("RJ.png", 144),
    ("o-.png", 192),
]

im = Image.open(kaynak).convert("RGBA")
for dosya, boyut in ESLESME:
    kucuk = im.resize((boyut, boyut), Image.Resampling.LANCZOS)
    kucuk.save(os.path.join(hedef, dosya), format="PNG", optimize=True)

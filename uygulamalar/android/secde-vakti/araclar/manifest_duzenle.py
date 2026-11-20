# İkili AndroidManifest.xml (AXML) düzenleyici.
# Kullanım: manifest_duzenle.py girdi.apk cikti_manifest.bin
import struct, sys, zipfile

def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]

data = zipfile.ZipFile(sys.argv[1]).read('AndroidManifest.xml')
assert u16(data, 0) == 0x0003

# --- parçalara ayır
chunks = []
pos = 8
while pos < len(data):
    t, hs, sz = struct.unpack_from('<HHI', data, pos)
    chunks.append([t, bytearray(data[pos:pos + sz])])
    pos += sz

# --- string havuzu
sp = chunks[0][1]
assert chunks[0][0] == 0x0001
sc, stc, fl, so, sso = struct.unpack_from('<IIIII', sp, 8)
assert stc == 0, 'stil beklenmiyor'
utf8 = bool(fl & 0x100)
offs = struct.unpack_from('<%dI' % sc, sp, 28)
strings = []
for o in offs:
    p = so + o
    if utf8:
        n = sp[p]; p += 1
        if n & 0x80: p += 1
        n = sp[p]; p += 1
        if n & 0x80: n = ((n & 0x7f) << 8) | sp[p]; p += 1
        strings.append(bytes(sp[p:p + n]).decode('utf8'))
    else:
        n = u16(sp, p); p += 2
        if n & 0x8000: n = ((n & 0x7fff) << 16) | u16(sp, p); p += 2
        strings.append(bytes(sp[p:p + 2 * n]).decode('utf-16le'))

def idx(s):
    if s in strings: return strings.index(s)
    strings.append(s); return len(strings) - 1

def enc_pool():
    body = bytearray(); offsets = []
    for s in strings:
        offsets.append(len(body))
        if utf8:
            b = s.encode('utf8'); cl = len(s); bl = len(b)
            for n in (cl, bl):
                body += bytes([0x80 | (n >> 8), n & 0xff]) if n > 0x7f else bytes([n])
            body += b + b'\0'
        else:
            b = s.encode('utf-16le'); n = len(b) // 2
            body += struct.pack('<H', n) if n < 0x8000 else struct.pack('<HH', 0x8000 | (n >> 16), n & 0xffff)
            body += b + b'\0\0'
    while len(body) % 4: body += b'\0'
    hdr = 28; sstart = hdr + 4 * len(strings)
    out = struct.pack('<HHIIIIII', 0x0001, 28, sstart + len(body), len(strings), 0, fl, sstart, 0)
    out += struct.pack('<%dI' % len(strings), *offsets) + body
    return bytearray(out)

# --- eleman yardımcıları
def el_name(c): return strings[struct.unpack_from('<i', c, 20)[0]]
def attrs(c):
    start, size, count = struct.unpack_from('<HHH', c, 24)
    res = []
    for i in range(count):
        a = 16 + start + i * size
        res.append(a)
    return res
def attr_name(c, a): return strings[struct.unpack_from('<i', c, a + 4)[0]]
def find_attr(c, nm):
    for a in attrs(c):
        if attr_name(c, a) == nm: return a
    raise KeyError(nm)
def set_str_attr(c, nm, value):
    a = find_attr(c, nm); i = idx(value)
    struct.pack_into('<i', c, a + 8, i)          # rawValue
    struct.pack_into('<HBBI', c, a + 12, 8, 0, 3, i)  # typedValue: string
def set_int_attr(c, nm, value):
    a = find_attr(c, nm)
    struct.pack_into('<i', c, a + 8, -1)
    struct.pack_into('<HBBI', c, a + 12, 8, 0, 0x10, value)
def set_ref_attr(c, nm, res_id):
    a = find_attr(c, nm)
    struct.pack_into('<i', c, a + 8, -1)
    struct.pack_into('<HBBI', c, a + 12, 8, 0, 0x01, res_id)
def get_attr_str(c, nm):
    a = find_attr(c, nm); r = struct.unpack_from('<i', c, a + 8)[0]
    return strings[r] if r >= 0 else None

START, END = 0x0102, 0x0103
degisiklik = []

# 1) manifest: sürüm
for t, c in chunks:
    if t == START and el_name(c) == 'manifest':
        set_int_attr(c, 'versionCode', 13)
        set_str_attr(c, 'versionName', '2.2.1')
        degisiklik.append('versionCode 13, versionName 2.2.1')
        break

# 2) application: sınıf ve etiket
for t, c in chunks:
    if t == START and el_name(c) == 'application':
        assert get_attr_str(c, 'name') == 'android.app.Application'
        set_str_attr(c, 'name', 'com.mehmetderin.secde_vakti.saglik.SecdeUygulama')
        set_str_attr(c, 'label', 'Secde Vakti')
        degisiklik.append('application name + label')
        break

# 3) yeni izin: WAKE_LOCK izninden hemen sonra
for i, (t, c) in enumerate(chunks):
    if t == START and el_name(c) == 'uses-permission' and get_attr_str(c, 'name') == 'android.permission.WAKE_LOCK':
        assert chunks[i + 1][0] == END
        yeni_s = bytearray(c); set_str_attr(yeni_s, 'name', 'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')
        yeni_e = bytearray(chunks[i + 1][1])
        chunks[i + 2:i + 2] = [[START, yeni_s], [END, yeni_e]]
        degisiklik.append('uses-permission REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')
        break

# 4) yeni alıcı: ScheduledNotificationReceiver'ın kopyası
for i, (t, c) in enumerate(chunks):
    if t == START and el_name(c) == 'receiver' and get_attr_str(c, 'name') == 'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver':
        assert chunks[i + 1][0] == END
        assert sorted(attr_name(c, a) for a in attrs(c)) == ['exported', 'name'], [attr_name(c, a) for a in attrs(c)]
        yeni_s = bytearray(c); set_str_attr(yeni_s, 'name', 'com.mehmetderin.secde_vakti.saglik.TestAlarmAlici')
        yeni_e = bytearray(chunks[i + 1][1])
        chunks[i + 2:i + 2] = [[START, yeni_s], [END, yeni_e]]
        degisiklik.append('receiver TestAlarmAlici')
        break

def set_bool_attr(c, nm, value):
    a = find_attr(c, nm)
    struct.pack_into('<i', c, a + 8, -1)
    struct.pack_into('<HBBI', c, a + 12, 8, 0, 0x12, 0xffffffff if value else 0)

def blok_sonu(i):
    """chunks[i] bir START ise, eşleşen END'in dizinini döndürür."""
    derinlik = 0
    for j in range(i, len(chunks)):
        if chunks[j][0] == START: derinlik += 1
        elif chunks[j][0] == END:
            derinlik -= 1
            if derinlik == 0: return j
    raise ValueError('kapanmayan eleman')

def bul(eleman, ad):
    for i, (t, c) in enumerate(chunks):
        if t == START and el_name(c) == eleman and get_attr_str(c, 'name') == ad:
            return i
    raise KeyError(ad)

def kopyala(i):
    return [[t, bytearray(c)] for t, c in chunks[i:blok_sonu(i) + 1]]

# 5) Ana başlatıcı etkinlik: DurumAktivitesi tekil görev (singleTask) ve MAIN/LAUNCHER olur;
# eski 1.0.0 Flutter MainActivity'nin LAUNCHER filtresi kaldırılır ve saydam yönlendiriciye çekilir.
i_main = bul('activity', 'com.mehmetderin.secde_vakti.MainActivity')
blok_durum = kopyala(i_main)
# blok_durum içindeki Flutter NormalTheme meta-data öğesini çıkar, yalnız intent-filter (MAIN/LAUNCHER) kalsın
m_idx = 1
while m_idx < len(blok_durum) - 1:
    if blok_durum[m_idx][0] == START and el_name(blok_durum[m_idx][1]) == 'meta-data':
        derin = 0
        son_m = m_idx
        for k_idx in range(m_idx, len(blok_durum)):
            if blok_durum[k_idx][0] == START: derin += 1
            elif blok_durum[k_idx][0] == END:
                derin -= 1
                if derin == 0: son_m = k_idx; break
        del blok_durum[m_idx:son_m + 1]
    else:
        m_idx += 1
set_ref_attr(blok_durum[0][1], 'theme', 0x01030007)  # @android:style/Theme.NoTitleBar
set_str_attr(blok_durum[0][1], 'name', 'com.mehmetderin.secde_vakti.saglik.DurumAktivitesi')
set_bool_attr(blok_durum[0][1], 'exported', True)
set_str_attr(blok_durum[0][1], 'taskAffinity', 'com.mehmetderin.secde_vakti')
set_int_attr(blok_durum[0][1], 'launchMode', 2)      # singleTask

# Eski MainActivity'nin LAUNCHER intent-filter bloğunu sil, saydam temaya ve singleTask moduna al
set_ref_attr(chunks[i_main][1], 'theme', 0x01030010) # @android:style/Theme.Translucent.NoTitleBar
set_int_attr(chunks[i_main][1], 'launchMode', 2)     # singleTask
f_idx = i_main + 1
while f_idx < blok_sonu(i_main):
    if chunks[f_idx][0] == START and el_name(chunks[f_idx][1]) == 'intent-filter':
        son_f = blok_sonu(f_idx)
        del chunks[f_idx:son_f + 1]
    else:
        f_idx += 1

j = blok_sonu(i_main) + 1
chunks[j:j] = blok_durum
degisiklik.append('activity DurumAktivitesi (MAIN/LAUNCHER, singleTask) + MainActivity gizlendi')

# 6) Zamanlayıcı alıcısı: FLN açılış alıcısının kopyası (BOOT_COMPLETED, MY_PACKAGE_REPLACED, QUICKBOOT)
i = bul('receiver', 'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver')
blok = kopyala(i)
set_str_attr(blok[0][1], 'name', 'com.mehmetderin.secde_vakti.saglik.ZamanlayiciAlici')
j = blok_sonu(i) + 1
chunks[j:j] = blok
degisiklik.append('receiver ZamanlayiciAlici (+açılış eylemleri)')

# 7) Hızlı Ayarlar kutucuğu: SystemJobService öğesinden servis + DiagnosticsReceiver'dan intent-filter
i = bul('service', 'androidx.work.impl.background.systemjob.SystemJobService')
servis_s = bytearray(chunks[i][1])
servis_e = bytearray(chunks[blok_sonu(i)][1])
set_str_attr(servis_s, 'name', 'com.mehmetderin.secde_vakti.saglik.SonrakiVakitKutucugu')
set_str_attr(servis_s, 'permission', 'android.permission.BIND_QUICK_SETTINGS_TILE')
set_bool_attr(servis_s, 'enabled', True)
set_bool_attr(servis_s, 'exported', True)
set_bool_attr(servis_s, 'directBootAware', False)
k = bul('receiver', 'androidx.work.impl.diagnostics.DiagnosticsReceiver')
filtre = None
for m in range(k + 1, blok_sonu(k)):
    if chunks[m][0] == START and el_name(chunks[m][1]) == 'intent-filter':
        filtre = kopyala(m); break
assert filtre and len(filtre) == 4, 'intent-filter > action bekleniyor'
set_str_attr(filtre[1][1], 'name', 'android.service.quicksettings.action.QS_TILE')
j = blok_sonu(i) + 1
chunks[j:j] = [[START, servis_s]] + filtre + [[END, servis_e]]
degisiklik.append('service SonrakiVakitKutucugu (QS_TILE)')

# 8) Tilavet servisi: GeolocatorLocationService öğesinin kopyası, ön plan türü mediaPlayback (2)
i = bul('service', 'com.baseflow.geolocator.GeolocatorLocationService')
blok = kopyala(i)
set_str_attr(blok[0][1], 'name', 'com.mehmetderin.secde_vakti.saglik.TilavetServisi')
a = find_attr(blok[0][1], 'foregroundServiceType')
struct.pack_into('<I', blok[0][1], a + 16, 0x2)   # değer; tür (int/hex) korunur
j = blok_sonu(i) + 1
chunks[j:j] = blok
degisiklik.append('service TilavetServisi (mediaPlayback)')

# 9) Android 14+: medya ön plan servisi izni (FOREGROUND_SERVICE izninden sonra)
i = bul('uses-permission', 'android.permission.FOREGROUND_SERVICE')
yeni = kopyala(i)
set_str_attr(yeni[0][1], 'name', 'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK')
j = blok_sonu(i) + 1
chunks[j:j] = yeni
degisiklik.append('uses-permission FOREGROUND_SERVICE_MEDIA_PLAYBACK')

assert len(degisiklik) == 9, degisiklik
chunks[0][1] = enc_pool()
body = b''.join(bytes(c) for _, c in chunks)
out = struct.pack('<HHI', 0x0003, 8, 8 + len(body)) + body
open(sys.argv[2], 'wb').write(out)
print('\n'.join(degisiklik))

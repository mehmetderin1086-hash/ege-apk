"""Kepçe indirme motoru: yt-dlp'yi telefonun içinde çalıştırır.

Swift tarafı bu modülü gömülü CPython'da yükler. YouTube'un JS sınavları (imza ve
n parametresi) için yt-dlp bir JS çalışma ortamı ister; iOS'ta alt süreç açılamadığı
için sınav betiği Swift'in JavaScriptCore'una (ctypes geri çağrısıyla) verilir.
Bu modül yalnız bilgi çıkarır (biçimler, adresler, başlıklar); indirmeyi Swift yapar.
"""
from __future__ import annotations

import ctypes
import json
import os
import sys
import traceback

_evaluate = None   # str -> str; JS betiğini çalıştırıp son ifadenin değerini döndürür
_cache_dir = None
_cookie_file = None
_iptaller = set()   # iptal edilen çağrı jetonları (set işlemleri GIL altında atomik)
_koruma_kuruldu = False

# console.log çıktısını toplayan kılıf: değerlendirici yalnız son ifadenin değerini döndürür.
_SHIM = ('var __kepceOut = [];'
         'var console = {log: function(){ __kepceOut.push(Array.prototype.map.call(arguments, String).join(" ")); },'
         ' warn: function(){}, error: function(){}, info: function(){}, debug: function(){}};\n')


def _wrap(script: str) -> str:
    return _SHIM + script + '\n;__kepceOut.join("\\n");'


def set_evaluator(function) -> None:
    global _evaluate
    _evaluate = function


def set_native_evaluator(address) -> str:
    """Swift'teki `char *eval(const char *)` işlevini bağlar; dönen bellek `free` ile bırakılır."""
    prototype = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_char_p)
    native = prototype(int(address))
    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]

    def evaluate(script: str) -> str:
        pointer = native(script.encode('utf-8'))
        if not pointer:
            raise RuntimeError('JavaScriptCore yanıt vermedi')
        try:
            return ctypes.string_at(pointer).decode('utf-8')
        finally:
            libc.free(pointer)

    set_evaluator(evaluate)
    return 'ok'


def _register_runtime() -> None:
    from yt_dlp.globals import supported_js_runtimes
    from yt_dlp.utils._jsruntime import JsRuntime, JsRuntimeInfo
    from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
    from yt_dlp.extractor.youtube.jsc.provider import (
        JsChallengeProviderError, register_preference, register_provider)
    from yt_dlp.extractor.youtube.pot._provider import BuiltinIEContentProvider

    if 'jsc' in supported_js_runtimes.value:
        return

    class JavaScriptCoreRuntime(JsRuntime):
        def _info(self):
            return JsRuntimeInfo(name='jsc', path='JavaScriptCore', version='1.0', version_tuple=(1, 0))

    supported_js_runtimes.value['jsc'] = JavaScriptCoreRuntime

    @register_provider
    class KepceJSCJCP(EJSBaseJCP, BuiltinIEContentProvider):
        PROVIDER_NAME = 'kepce-jsc'
        JS_RUNTIME_NAME = 'jsc'

        def _run_js_runtime(self, stdin: str, /) -> str:
            if _evaluate is None:
                raise JsChallengeProviderError('JS değerlendiricisi bağlı değil')
            try:
                return _evaluate(_wrap(stdin))
            except Exception as error:   # JS hatası yt-dlp'ye sağlayıcı hatası olarak gider
                raise JsChallengeProviderError(f'JavaScriptCore: {error}') from error

    @register_preference(KepceJSCJCP)
    def preference(provider, requests):
        return 1000


def configure(cache_dir: str, cookie_file: str = '') -> str:
    global _cache_dir, _cookie_file
    _cache_dir = cache_dir or None
    _cookie_file = cookie_file or None
    os.makedirs(cache_dir, exist_ok=True) if cache_dir else None
    try:
        import certifi
        os.environ.setdefault('SSL_CERT_FILE', certifi.where())
    except ImportError:
        pass
    _adres_korumasi_kur()
    _register_runtime()
    return version()


# Swift tarafındaki WebSayfa.ozelIPv4/ozelIPv6 ile aynı aralıklar (yerel ağ, geri döngü, CGNAT, çok noktaya yayın).
_OZEL_AGLAR = ('0.0.0.0/8', '10.0.0.0/8', '127.0.0.0/8', '169.254.0.0/16', '192.168.0.0/16', '172.16.0.0/12',
               '100.64.0.0/10', '224.0.0.0/3', '::1/128', '::/128', 'fc00::/7', 'fe80::/10', '::ffff:0:0/96')


def _ozel_adres(ip: str) -> bool:
    import ipaddress
    try:
        adres = ipaddress.ip_address(ip.split('%', 1)[0])
    except ValueError:
        return False
    for ag in _OZEL_AGLAR:
        ag = ipaddress.ip_network(ag)
        if ag.version == adres.version and adres in ag:
            return True
    return False


def _adres_korumasi_kur() -> None:
    """yt-dlp'nin kendi ağı (ilk sayfanın yönlendirmeleri, manifestler) yerel/özel adreslere gitmesin (SSRF).
    socket.getaddrinfo bir kez sarılır; create_connection ve urllib3 hep bunu kullanır."""
    global _koruma_kuruldu
    if _koruma_kuruldu:
        return
    import socket
    asil = socket.getaddrinfo

    def guvenli(host, *args, **kwargs):
        sonuc = asil(host, *args, **kwargs)
        if not host:
            return sonuc
        temiz = [r for r in sonuc if not (isinstance(r[4], tuple) and r[4] and _ozel_adres(str(r[4][0])))]
        if sonuc and not temiz:
            raise socket.gaierror(socket.EAI_NONAME, f'yerel/özel ağ adresi engellendi: {host}')
        return temiz

    socket.getaddrinfo = guvenli
    _koruma_kuruldu = True


def cancel(token: str) -> str:
    """Swift görevi iptal edilince ayrı bir iş parçacığından çağrılır; süren extract bir sonraki günlük satırında durur."""
    if len(_iptaller) > 200:   # bitmiş çağrılara gelen geç iptaller birikmesin
        _iptaller.clear()
    _iptaller.add(token)
    return 'ok'


def version() -> str:
    from yt_dlp.version import __version__
    try:
        import yt_dlp_ejs
        ejs = yt_dlp_ejs.version
    except Exception:
        ejs = '?'
    return json.dumps({'yt_dlp': __version__, 'ejs': ejs, 'python': sys.version.split()[0]})


class _Logger:
    def __init__(self, token=None):
        self.lines = []
        self.token = token

    def denetle(self):
        """Çağrı iptal edildiyse yt-dlp'yi durdurur (logger tanımlıyken her to_screen iletisi debug'a gelir)."""
        if self.token and self.token in _iptaller:
            from yt_dlp.utils import DownloadCancelled
            raise DownloadCancelled('İptal edildi')

    def debug(self, message):
        self.denetle()
        if not message.startswith('[debug] '):
            self.lines.append(message)

    def info(self, message):
        self.denetle()
        self.lines.append(message)

    def warning(self, message):
        self.lines.append('UYARI: ' + message)

    def error(self, message):
        self.lines.append('HATA: ' + message)


def _options(extra: dict) -> dict:
    options = {
        'quiet': True,
        'no_warnings': False,
        'skip_download': True,
        'noplaylist': not extra.get('playlist', False),
        'js_runtimes': {'jsc': {}},
        'remote_components': [],
        'socket_timeout': 20,
        'retries': 3,
        'extractor_retries': 2,
        'cachedir': _cache_dir or False,
        'ignore_no_formats_error': True,
        'logger': extra.get('_logger'),
    }
    # Liste öğeleri her zaman düz alınır: kanal/liste bağlantısında yüzlerce video tek tek çözülmez.
    # (Tek video bağlantısını etkilemez.)
    options['extract_flat'] = 'in_playlist'
    if extra.get('limit'):
        options['playlistend'] = int(extra['limit'])
    if extra.get('_cookie_copy'):
        options['cookiefile'] = extra['_cookie_copy']
    if extra.get('clients'):
        options['extractor_args'] = {'youtube': {'player_client': list(extra['clients'])}}
    return options


_FORMAT_KEYS = ('format_id', 'format_note', 'ext', 'vcodec', 'acodec', 'width', 'height', 'fps', 'tbr', 'abr', 'vbr', 'asr',
                'audio_channels', 'filesize', 'filesize_approx', 'url', 'protocol', 'http_headers', 'dynamic_range',
                'language', 'language_preference', 'quality', 'container', 'audio_ext', 'video_ext', 'downloader_options',
                'manifest_url', 'fragments', 'fragment_base_url', 'source_preference', 'has_drm', 'available_at')


def _format(f: dict) -> dict:
    out = {key: f.get(key) for key in _FORMAT_KEYS if f.get(key) is not None}
    if 'fragments' in out:   # parçalı (DASH/HLS) akışlarda yalnız parça adresleri gerekir
        out['fragments'] = [{'url': fr.get('url'), 'path': fr.get('path'), 'duration': fr.get('duration')}
                            for fr in out['fragments']]
    return out


def _captions(table: dict | None, only: set | None) -> dict:
    result = {}
    for language, tracks in (table or {}).items():
        if only is not None and not any(language == l or language.startswith(l + '-') for l in only):
            continue
        result[language] = [{'ext': t.get('ext'), 'url': t.get('url'), 'name': t.get('name')} for t in tracks if t.get('url')]
    return result


def _entry(e: dict) -> dict:
    thumbs = e.get('thumbnails') or []
    thumb = e.get('thumbnail') or (thumbs[-1].get('url') if thumbs else None)
    return {'id': e.get('id'), 'title': e.get('title'), 'url': e.get('url') or e.get('webpage_url'),
            'duration': e.get('duration'), 'thumbnail': thumb, 'uploader': e.get('uploader') or e.get('channel'),
            'view_count': e.get('view_count'), 'live_status': e.get('live_status')}


def _cookie_header(ydl, url: str) -> str | None:
    try:
        return ydl.cookiejar.get_cookie_header(url) or None
    except Exception:
        return None


def _video(info: dict, ydl=None) -> dict:
    keys = ('id', 'title', 'description', 'uploader', 'channel', 'channel_id', 'uploader_url', 'duration', 'upload_date',
            'view_count', 'like_count', 'thumbnail', 'webpage_url', 'extractor', 'extractor_key', 'live_status',
            'age_limit', 'chapters', 'categories', 'tags', 'track', 'artist', 'album', 'release_year')
    out = {key: info.get(key) for key in keys if info.get(key) is not None}
    if isinstance(out.get('description'), str):
        out['description'] = out['description'][:4000]
    out['kind'] = 'video'
    formats = info.get('formats') or ([info] if info.get('url') else [])
    out['formats'] = [_format(f) for f in formats if f.get('url') or f.get('fragments')]
    if ydl is not None:   # yt-dlp çerezleri ayrı tutar; Swift tarafı başlık olarak gönderir
        for f in out['formats']:
            cookie = f.get('url') and _cookie_header(ydl, f['url'])
            if cookie:
                f.setdefault('http_headers', {})['Cookie'] = cookie
    out['subtitles'] = _captions(info.get('subtitles'), None)
    out['automatic_captions'] = _captions(info.get('automatic_captions'), {'tr', 'en'})
    return out


def extract(url: str, options_json: str = '{}') -> str:
    """Bağlantıdaki videonun (ya da listenin) bilgisini JSON olarak döndürür; hata da JSON'dur."""
    import yt_dlp
    extra = json.loads(options_json or '{}')
    token = extra.get('token') or None
    logger = _Logger(token)
    extra['_logger'] = logger
    # yt-dlp kapanırken çerez dosyasını baştan yazar: asıl dosyaya dokunmasın diye geçici kopya verilir.
    cookie_copy = None
    if _cookie_file and os.path.exists(_cookie_file):
        import shutil
        import tempfile
        handle, cookie_copy = tempfile.mkstemp(suffix='.txt')
        os.close(handle)
        try:
            shutil.copyfile(_cookie_file, cookie_copy)
            extra['_cookie_copy'] = cookie_copy
        except OSError as error:
            logger.warning(f'çerez dosyası okunamadı: {error}')
    try:
        logger.denetle()   # kuyrukta beklerken iptal edildiyse hiç başlama
        with yt_dlp.YoutubeDL(_options(extra)) as ydl:
            info = ydl.extract_info(url, download=False, process=True)
            info = ydl.sanitize_info(info)
            single = not (info.get('_type') == 'playlist' or info.get('entries') is not None)
            video = _video(info, ydl) if single else None
        if not single:
            entries = [_entry(e) for e in (info.get('entries') or []) if e]
            result = {'kind': 'playlist', 'id': info.get('id'), 'title': info.get('title'),
                      'uploader': info.get('uploader') or info.get('channel'), 'webpage_url': info.get('webpage_url'),
                      'entries': entries}
        else:
            result = video
            if not result['formats']:
                reason = _neden(logger.lines)
                return json.dumps({'kind': 'error', 'error': 'İndirilebilir biçim bulunamadı. ' + reason,
                                   'log': logger.lines[-40:]}, ensure_ascii=False)
        result['log'] = logger.lines[-40:]
        return json.dumps(result, ensure_ascii=False)
    except Exception as error:
        message = str(error)
        try:
            from yt_dlp.utils import DownloadError
            if isinstance(error, DownloadError) and error.msg:
                message = error.msg
        except Exception:
            pass
        return json.dumps({'kind': 'error', 'error': message.replace('ERROR: ', ''), 'log': logger.lines[-40:],
                           'trace': traceback.format_exc()[-3000:]}, ensure_ascii=False)
    finally:
        if token:
            _iptaller.discard(token)
        if cookie_copy:
            try:
                os.remove(cookie_copy)
            except OSError:
                pass


# Biçim bulunamadığında son uyarı çoğu zaman "Requested format is not available" gibi sonuçtur, neden değildir;
# önce bilinen asıl nedenleri (bot doğrulaması, gizli/yaş/üyelik) taşıyan uyarıyı seç. Sıra önceliktir:
# genel imzalar ('blocked', 'unavailable') sonda. Yaş imzaları dar tutulur ('age' tek başına page/image/message'ı da yakalar).
_NEDEN_IMZALARI = ('not a bot', 'confirm your age', 'age-restricted', 'age restricted', 'inappropriate for some users',
                   'sign in to confirm', 'private video', 'members-only', 'join this channel', 'drm', 'login required',
                   'blocked', 'unavailable')


def _neden(lines: list) -> str:
    uyarilar = [line[7:] for line in lines if line.startswith('UYARI: ')]
    # Dış döngü imzalar: önce gelen sıradan bir uyarı (ör. 'Unable to download webpage') asıl nedenin önüne geçmesin.
    for imza in _NEDEN_IMZALARI:
        for u in uyarilar:
            if imza in u.lower():
                return u
    aday = [u for u in uyarilar if 'requested format' not in u.lower()]
    return (aday or uyarilar)[-1] if uyarilar else ''


def search(query: str, count: int = 20, token: str = '') -> str:
    secenek = {'flat': True, 'playlist': True}
    if token:
        secenek['token'] = token
    return extract(f'ytsearch{int(count)}:{query}', json.dumps(secenek))


def _latest_wheel(name: str) -> tuple[str, str, str]:
    import urllib.request
    with urllib.request.urlopen(f'https://pypi.org/pypi/{name}/json', timeout=20) as response:
        data = json.load(response)
    wheel = next(f for f in data['urls'] if f['url'].endswith('.whl'))
    return data['info']['version'], wheel['url'], wheel['digests']['sha256']


def update(target: str) -> str:
    """PyPI'den en yeni yt-dlp ve yt-dlp-ejs'i `target` dizinine kurar (paketteki sürümü gölgeler).
    Yeni sürüm yüklenip JS çözücü kaydı denenmeden eskisi silinmez; başarısızsa eski sürüme dönülür."""
    import hashlib
    import io
    import shutil
    import urllib.request
    import zipfile
    staging, backup = target + '.yeni', target + '.eski'
    shutil.rmtree(staging, ignore_errors=True)
    shutil.rmtree(backup, ignore_errors=True)
    os.makedirs(staging)
    versions = {}
    try:
        for name in ('yt-dlp', 'yt-dlp-ejs'):
            version_text, url, digest = _latest_wheel(name)
            with urllib.request.urlopen(url, timeout=60) as response:
                payload = response.read()
            if hashlib.sha256(payload).hexdigest() != digest:
                raise RuntimeError(f'{name} paketinin özeti PyPI ile uyuşmuyor')
            with zipfile.ZipFile(io.BytesIO(payload)) as archive:
                for member in archive.namelist():
                    top = member.split('/', 1)[0]
                    if top.endswith(('.dist-info', '.data')) or '..' in member.split('/') or member.startswith('/'):
                        continue
                    archive.extract(member, staging)
            versions[name] = version_text
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    had_old = os.path.isdir(target)
    if had_old:
        os.replace(target, backup)
    os.replace(staging, target)
    try:
        reload()
    except Exception:
        shutil.rmtree(target, ignore_errors=True)
        if had_old:
            os.replace(backup, target)
        reload()
        raise
    shutil.rmtree(backup, ignore_errors=True)
    return json.dumps({'updated': versions, 'now': json.loads(version())})


def reset(target: str) -> str:
    """Güncellenen sürümü siler ve paketteki sürüme döner (Python kuyruğunda çalışır)."""
    import shutil
    shutil.rmtree(target, ignore_errors=True)
    return reload()


def reload() -> str:
    """yt-dlp modüllerini bellekten atıp yeniden yükler (güncellemeden sonra)."""
    import importlib
    for name in [m for m in sys.modules if m == 'yt_dlp' or m.startswith(('yt_dlp.', 'yt_dlp_ejs'))]:
        del sys.modules[name]
    importlib.invalidate_caches()
    _register_runtime()
    import yt_dlp  # noqa: F401  (içe aktarma hatası burada görünsün)
    return version()

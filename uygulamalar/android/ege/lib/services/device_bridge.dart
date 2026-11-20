import 'speaker_identity.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/jarvis_models.dart';

class DeviceBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.jarvis.assistant/device',
  );
  static void Function(Map<dynamic, dynamic> event)? onDuplexEvent;
  static Future<Map<String, dynamic>> startDuplexCapture(
    int token,
    bool bargeIn,
  ) async {
    _ensureMethodHandler();
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
            'startDuplexCapture',
            {'token': token, 'bargeIn': bargeIn},
          ) ??
          {'status': 'UNAVAILABLE'};
    } catch (_) {
      return {'status': 'UNAVAILABLE'};
    }
  }

  static Future<bool> duplexPlaybackEnded(int token) =>
      _invokeBool('duplexPlaybackEnded', {'token': token});
  static Future<bool> duplexSpeakerDecision(int token, bool accepted) =>
      _invokeBool('duplexSpeakerDecision', {
        'token': token,
        'accepted': accepted,
      });
  static Future<bool> stopDuplexCapture() => _invokeBool('stopDuplexCapture');

  static bool _handlerRegistered = false;
  static void Function(double level)? _onMicLevel;
  static void Function()? _onMicSilence;
  static void Function(Uint8List chunk)? _onLivePcmChunk;
  static void Function(String method, dynamic args)? _onNativeEvent;
  static void Function(Uint8List chunk)? _onWakePcm;

  /// Uyandırma sözcüğü mikrofonu (16 kHz PCM16, ~100 ms parçalar).
  static void setWakeAudioCallback(void Function(Uint8List chunk)? f) {
    _onWakePcm = f;
    _ensureMethodHandler();
  }

  static Future<({String status, String text})> recognizePhoneSpeech() async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'startPhoneSpeech',
      );
      return (
        status: r?['status']?.toString() ?? 'UNAVAILABLE',
        text: r?['text']?.toString() ?? '',
      );
    } catch (_) {
      return (status: 'UNAVAILABLE', text: '');
    }
  }

  static Future<bool> stopPhoneSpeech() => _invokeBool('stopPhoneSpeech');
  /// [force] yalnız kullanıcı düğmeye bastığında true olur; otomatik çağrılar
  /// Android'in indirme penceresini haftada en çok bir kez açar.
  static Future<bool> preparePhoneSpeech({bool force = false}) async {
    try {
      return await _channel.invokeMethod<bool>('preparePhoneSpeech', {
            'force': force,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
  static Future<({String status, String text})> transcribePhoneAudio(
    Uint8List wav,
  ) async {
    final samples = SpeakerIdentity.pcmFromWav(wav);
    if (samples.isEmpty) return (status: 'INVALID_AUDIO', text: '');
    final pcm = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      pcm.setInt16(
        i * 2,
        (samples[i] * 32768).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'transcribePhoneAudio',
        {'pcm': pcm.buffer.asUint8List()},
      );
      return (
        status: r?['status']?.toString() ?? 'UNAVAILABLE',
        text: r?['text']?.toString() ?? '',
      );
    } catch (_) {
      return (status: 'UNAVAILABLE', text: '');
    }
  }

  static Future<bool> cancelPhoneSpeech() => _invokeBool('cancelPhoneSpeech');

  static Future<String> startWakeMic() =>
      _invokeString('startWakeMic', 'UNAVAILABLE');

  /// Kısa onay sesi (uyandırma algılandığında).
  static Future<bool> earcon() => _invokeBool('earcon');

  /// Telefon takvimindeki etkinlikler (null = izin yok; izin istenir).
  static Future<List<Map<String, dynamic>>?> calendarEvents({
    int days = 1,
  }) async {
    try {
      final r = await _channel.invokeMethod<List<dynamic>>('calendarEvents', {
        'days': days,
      });
      if (r == null) return null;
      return r
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> stopWakeMic() => _invokeBool('stopWakeMic');

  /// JARVIS varsayılan asistansa sistemin asistan oturumunu açar (arka
  /// plandayken ekrana gelmenin izinli yolu).
  static Future<bool> showAssistant() => _invokeBool('showAssistant');

  /// Diğer native olaylar: onLaunchAction, onKeepAliveStop, onNotification,
  /// onWakeWord (JARVIS 3.0).
  static set onNativeEvent(void Function(String method, dynamic args)? f) {
    _onNativeEvent = f;
    _ensureMethodHandler();
  }

  static void _ensureMethodHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'verifyWakeVoice') {
        final wav = (call.arguments as Map?)?['wav'];
        final accepted =
            wav is Uint8List &&
            await SpeakerIdentity.instance.acceptsWakeWav(wav);
        return {
          'accepted': accepted,
          'reason': SpeakerIdentity.instance.lastCheck,
        };
      } else if (call.method == 'onDuplexCapture') {
        if (call.arguments is Map) onDuplexEvent?.call(call.arguments as Map);
      } else if (call.method == 'onMicLevel') {
        final v = (call.arguments as num?)?.toDouble() ?? 0.0;
        _onMicLevel?.call(v);
      } else if (call.method == 'onMicSilence') {
        _onMicSilence?.call();
      } else if (call.method == 'onLivePcmChunk') {
        final raw = call.arguments;
        if (raw is Uint8List) {
          _onLivePcmChunk?.call(raw);
        }
      } else if (call.method == 'onWakePcm') {
        final raw = call.arguments;
        if (raw is Uint8List) _onWakePcm?.call(raw);
      } else {
        _onNativeEvent?.call(call.method, call.arguments);
      }
    });
  }

  static void setMicCallbacks({
    void Function(double level)? onLevel,
    void Function()? onSilence,
  }) {
    _onMicLevel = onLevel;
    _onMicSilence = onSilence;
    _ensureMethodHandler();
  }

  /// Mikrofonu açar; konuşma bitince (uyarlanabilir VAD, [endSilenceMs]
  /// sessizlik) ya da [noSpeechMs] boyunca hiç konuşma olmazsa `onMicSilence`
  /// gelir.
  static Future<String> startMicCapture({
    int endSilenceMs = 900,
    int noSpeechMs = 7000,
  }) async {
    try {
      return await _channel.invokeMethod<String>('startMicCapture', {
            'endSilenceMs': endSilenceMs,
            'noSpeechMs': noSpeechMs,
          }) ??
          'UNAVAILABLE';
    } catch (_) {
      return 'UNAVAILABLE';
    }
  }

  /// Son kaydın ölçümleri: heardSpeech, speechMs, noiseFloor, peakRms,
  /// durationMs, end (SPEECH_ENDED / NO_SPEECH / MAX_LENGTH / NONE).
  static Future<Map<String, dynamic>> micStats() async {
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>('micStats');
      return r == null ? const {} : r.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return const {};
    }
  }

  /// "Ses duyulmadı" türü kullanıcı mesajı (null = konuşma vardı).
  static Future<String?> noSpeechReason() async {
    final st = await micStats();
    if (st.isEmpty || st['heardSpeech'] == true) return null;
    final peak = (st['peakRms'] as num?)?.toDouble() ?? 0;
    if (peak < 0.004) {
      return 'Mikrofondan ses gelmiyor. Başka bir uygulama mikrofonu kullanıyor olabilir ya da mikrofon kapalı.';
    }
    return 'Konuşma duyulmadı. Mikrofona biraz daha yakın ve net konuşmayı dene.';
  }

  static Future<Uint8List?> stopMicCapture() async {
    try {
      return await _channel.invokeMethod<Uint8List>('stopMicCapture');
    } catch (_) {
      return null;
    }
  }

  static Future<void> cancelMicCapture() async {
    try {
      await _channel.invokeMethod('cancelMicCapture');
    } catch (_) {}
  }

  static Future<DeviceMetrics> getDeviceMetrics() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceInfo',
      );
      if (raw != null) {
        return DeviceMetrics.fromMap(raw);
      }
    } catch (_) {
      // Fallback when running in widget test / non-Android runner
    }
    return const DeviceMetrics();
  }

  static Future<void> playTimerChime() async {
    try {
      await _channel.invokeMethod('playTimerChime');
    } catch (_) {}
  }

  static Future<bool> playAudioBytes(
    Uint8List bytes, {
    String ext = 'mp3',
  }) async {
    if (bytes.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('playAudioBytes', {
        'bytes': bytes,
        'ext': ext,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopAudioPlayback() async {
    try {
      await _channel.invokeMethod('stopAudio');
    } catch (_) {}
  }

  static Future<String?> saveGeneratedImage(
    Uint8List bytes,
    String fileName,
  ) async {
    if (bytes.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>('saveImageBytes', {
        'bytes': bytes,
        'fileName': fileName,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        ![
          'http',
          'https',
          'tel',
          'mailto',
          'geo',
          'smsto',
          'sms',
        ].contains(uri.scheme.toLowerCase())) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  // -------------------- FULL-DUPLEX LIVE PCM AUDIO --------------------

  static void setLiveAudioCallbacks({
    void Function(Uint8List chunk)? onLivePcmChunk,
    void Function(double level)? onMicLevel,
  }) {
    _onLivePcmChunk = onLivePcmChunk;
    _onMicLevel = onMicLevel ?? _onMicLevel;
    _ensureMethodHandler();
  }

  static Future<bool> openLiveAudioStream({int sampleRate = 24000}) async {
    try {
      return await _channel.invokeMethod<bool>('openLiveAudioStream', {
            'sampleRate': sampleRate,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> feedLiveAudioPcm(Uint8List pcmBytes) async {
    if (pcmBytes.isEmpty) return;
    try {
      await _channel.invokeMethod('feedLiveAudioPcm', {'bytes': pcmBytes});
    } catch (_) {}
  }

  static Future<void> interruptLiveAudioStream() async {
    try {
      await _channel.invokeMethod('interruptLiveAudioStream');
    } catch (_) {}
  }

  static Future<void> closeLiveAudioStream() async {
    try {
      await _channel.invokeMethod('closeLiveAudioStream');
    } catch (_) {}
  }

  static Future<String> startLivePcmMic({
    int sampleRate = 16000,
    bool bargeIn = false,
  }) async {
    try {
      return await _channel.invokeMethod<String>('startLivePcmMic', {
            'sampleRate': sampleRate,
            'bargeIn': bargeIn,
          }) ??
          'UNAVAILABLE';
    } catch (_) {
      return 'UNAVAILABLE';
    }
  }

  static Future<void> stopLivePcmMic() async {
    try {
      await _channel.invokeMethod('stopLivePcmMic');
    } catch (_) {}
  }

  // -------------------- FULL ANDROID PHONE CONTROL --------------------

  static Future<bool> setFlashlight(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setFlashlight', {
            'enabled': enabled,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getVolumeState() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getVolumeState',
      );
      if (res != null) {
        return res.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {'mediaPct': 50, 'ringPct': 50, 'alarmPct': 70, 'torch': false};
  }

  static Future<bool> setVolumeLevel({
    String stream = 'media',
    required int percent,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('setVolumeLevel', {
            'stream': stream,
            'percent': percent,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> mediaSessionCommand(String package, String action) =>
      _invokeString('mediaSessionCommand', 'NO_ACCESS', {'package': package, 'action': action});

  static Future<bool> controlMedia(String action) async {
    try {
      return await _channel.invokeMethod<bool>('controlMedia', {
            'action': action,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<DeviceAppInfo>> listInstalledApps() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listInstalledApps',
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map(
            (e) => DeviceAppInfo(
              name: e['name']?.toString() ?? '',
              packageName: e['package']?.toString() ?? '',
              versionName: e['versionName']?.toString() ?? '',
              isSystem: e['isSystem'] == true,
              firstInstallMs: (e['firstInstallMs'] as num?)?.toInt() ?? 0,
              lastUpdateMs: (e['lastUpdateMs'] as num?)?.toInt() ?? 0,
            ),
          )
          .where((a) => a.name.isNotEmpty && a.packageName.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      return const [];
    }
  }

  static Future<Map<String, dynamic>> vaultCall(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
            method,
            arguments,
          ) ??
          const {};
    } catch (_) {
      return const {'error': 'Kasa bağlantısı kullanılamıyor.'};
    }
  }

  static Future<String> currentAppCommand(String action) =>
      _invokeString('currentAppCommand', 'Uygulama ekranına erişilemedi.', {'action': action});
  static Future<String> phoneSnapshot() =>
      _invokeString('phoneSnapshot', 'Ekran okunamadı.');
  static Future<String> resumePhoneScreen() =>
      _invokeString('resumePhoneScreen', 'Hata: Önceki ekran okunamadı.');
  static Future<Map<String, dynamic>> phoneScreenImage(String package) async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'phoneScreenImage',
        {'package': package},
      );
      return value ?? const {};
    } catch (_) {
      return const {};
    }
  }

  static Future<bool> appControlEnabled() => _invokeBool('appControlEnabled');
  static Future<String> controlApp({
    required String packageName,
    required String action,
    String target = '',
    String text = '',
    String query = '',
    String url = '',
  }) async {
    try {
      return await _channel.invokeMethod<String>('controlApp', {
            'package': packageName,
            'action': action,
            'target': target,
            'text': text,
            'query': query,
            'url': url,
          }) ??
          'İşlem uygulanamadı.';
    } catch (_) {
      return 'Uygulama kontrolü kullanılamıyor.';
    }
  }

  static Future<String> spotifyControl(String action) =>
      _invokeString('spotifyControl', 'Spotify durumuna erişilemedi.', {'action': action});

  static Future<String> playSpotifyMusic() =>
      _invokeString('playSpotifyMusic', 'Spotify oynatması doğrulanamadı.');

  /// Returns app/browser/unavailable; never treats a failed launch as success.
  static Future<String> openYouTube({String query = ''}) async {
    try {
      return await _channel.invokeMethod<String>('openYouTube', {
            'query': query,
          }) ??
          'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  static Future<String?> launchApp(String query) async {
    try {
      return await _channel.invokeMethod<String>('launchApp', {'query': query});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openSystemSettings(String target) async {
    try {
      return await _channel.invokeMethod<bool>('openSystemSettings', {
            'target': target,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> setSystemAlarm({
    required int hour,
    required int minute,
    String message = 'JARVIS Alarm',
    List<int> days = const [],
  }) async {
    try {
      return await _channel.invokeMethod<bool>('setSystemAlarm', {
            'hour': hour,
            'minute': minute,
            'message': message,
            if (days.isNotEmpty) 'days': days,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> addCalendarEvent({
    required String title,
    String description = '',
    required DateTime start,
    DateTime? end,
  }) async {
    final endDt = end ?? start.add(const Duration(hours: 1));
    try {
      return await _channel.invokeMethod<bool>('addCalendarEvent', {
            'title': title,
            'description': description,
            'startMs': start.millisecondsSinceEpoch,
            'endMs': endDt.millisecondsSinceEpoch,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> showNotification({
    required String title,
    required String body,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('showNotification', {
            'title': title,
            'body': body,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  // -------------------- INTERNAL HELPERS --------------------

  static Future<bool> _invokeBool(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String> _invokeString(
    String method,
    String fallback, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      return await _channel.invokeMethod<String>(method, args) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<List<Map<dynamic, dynamic>>> _invokeMapList(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(method, args);
      if (raw == null) return const [];
      return raw.whereType<Map<dynamic, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  // -------------------- DOWNLOADS --------------------

  /// Enqueues a download via Android DownloadManager into
  /// `Download/<subDir>/<fileName>`. Returns the download id or null.
  static Future<int?> enqueueDownload({
    required String url,
    String? fileName,
    String? mimeType,
    String subDir = 'Ege',
    String? title,
    Map<String, String>? headers,
  }) async {
    try {
      final id = await _channel.invokeMethod<num>('enqueueDownload', {
        'url': url,
        'fileName': fileName,
        'mimeType': mimeType,
        'subDir': subDir,
        'title': title,
        'headers': headers ?? const <String, String>{},
      });
      return id?.toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<int?> enqueueManagedDownload({
    required String url,
    String? fileName,
    String? mimeType,
  }) async {
    try {
      return await _channel.invokeMethod<int>('enqueueManagedDownload', {
        'url': url,
        'fileName': fileName,
        'mimeType': mimeType,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<bool> managedDownloadControl(int id, String action) =>
      _invokeBool('managedDownloadControl', {'id': id, 'action': action});
  static Future<bool> shareManagedDownload(int id) =>
      _invokeBool('shareManagedDownload', {'id': id});
  static Future<Map<String, dynamic>> downloadPreferences({
    bool save = false,
    bool wifiOnly = false,
    int limitKbps = 0,
    int concurrency = 2,
  }) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
            'downloadPreferences',
            {
              'save': save,
              'wifiOnly': wifiOnly,
              'limitKbps': limitKbps,
              'concurrency': concurrency,
            },
          ) ??
          {};
    } catch (_) {
      return {};
    }
  }

  /// Downloads started by JARVIS, newest first.
  static Future<List<DownloadItem>> queryDownloads() async {
    final rows = await _invokeMapList('queryDownloads');
    return rows.map(DownloadItem.fromMap).where((d) => d.id >= 0).toList();
  }

  static Future<bool> openDownload(int id) =>
      _invokeBool('openDownload', {'id': id});

  static Future<bool> removeDownload(int id) =>
      _invokeBool('removeDownload', {'id': id});

  /// Writes [bytes] into the public `Download/Ege` folder. Returns a
  /// content:// uri (Android 10+) or an absolute path, or null on failure.
  static Future<String?> saveBytesToDownloads({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
    String subDir = '',
  }) async {
    if (bytes.isEmpty) return null;
    try {
      return await _channel.invokeMethod<String>('saveBytesToDownloads', {
        'bytes': bytes,
        'fileName': fileName,
        'mimeType': mimeType,
        'subDir': subDir,
      });
    } catch (_) {
      return null;
    }
  }

  // -------------------- DOCUMENTS --------------------

  /// Renders a PDF (Windows JARVIS schema: title, paragraphs, sections,
  /// tables) with Android's PdfDocument. Returns the PDF bytes.
  static Future<Uint8List?> renderPdf(Map<String, dynamic> spec) async {
    try {
      return await _channel.invokeMethod<Uint8List>('renderPdf', {
        'spec': jsonEncode(spec),
      });
    } catch (_) {
      return null;
    }
  }

  // -------------------- MUSIC STREAM PLAYER --------------------

  static Future<bool> streamPlay(String url, {String title = ''}) =>
      _invokeBool('streamPlay', {'url': url, 'title': title});

  static Future<bool> streamPause() => _invokeBool('streamPause');

  static Future<bool> streamResume() => _invokeBool('streamResume');

  static Future<bool> streamStop() => _invokeBool('streamStop');

  static Future<bool> streamSeek(int ms) =>
      _invokeBool('streamSeek', {'ms': ms});

  /// Lowers the music while JARVIS speaks (Windows JARVIS behaviour).
  static Future<void> streamDuck(bool on) async {
    try {
      await _channel.invokeMethod('streamDuck', {'on': on});
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> streamStatus() async {
    try {
      final m = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'streamStatus',
      );
      return m == null ? const {} : Map<String, dynamic>.from(m);
    } catch (_) {
      return const {};
    }
  }

  // -------------------- REMINDER ALARMS --------------------

  /// Schedules a notification that fires even when JARVIS is closed.
  /// Returns 'exact', 'inexact' or an error text.
  static Future<bool> deliverDueTimer(String key) => _invokeBool('deliverDueTimer', {'key': key});
  static Future<String> scheduleAlarm({
    required String key,
    required DateTime at,
    required String title,
    required String body,
    bool daily = false,
    String? route,
  }) => _invokeString('scheduleAlarm', 'unsupported', {
    'key': key,
    'atMs': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    'daily': daily,
    'route': ?route,
  });

  // -------------------- JARVIS 3.0 --------------------

  /// Uygulamayı açan dış eylem (asistan hareketi, paylaş, seçili metin, hızlı
  /// ayar, bildirim) varsa bir kez döner: {action, text?, path?, screenshot?}.
  static Future<Map<String, dynamic>?> takeLaunchAction() async {
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'takeLaunchAction',
      );
      return r?.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// Ön plan servisi (bildirimli) – realme dondurmasın diye.
  static Future<bool> keepAlive(String reason, bool on, {String? text}) =>
      _invokeBool('keepAlive', {'reason': reason, 'on': on, 'text': ?text});

  /// Doğrudan arar (CALL_PHONE izni varsa) → 'CALLING'; yoksa izin ister ve
  /// çeviriciyi açar → 'DIALER'.
  static Future<String> callNumber(String number) =>
      _invokeString('callNumber', 'ERROR', {'number': number});

  static Future<String> endCall() => _invokeString('endCall', 'FAILED');
  static Future<bool> callControlPermission() =>
      _invokeBool('callControlPermission');
  static Future<String> requestCallControlPermission() =>
      _invokeString('requestCallControlPermission', 'UNSUPPORTED');

  static Future<bool> batteryOptimizationIgnored() =>
      _invokeBool('batteryOptStatus');
  static Future<bool> requestIgnoreBatteryOptimization() =>
      _invokeBool('requestBatteryOpt');

  static Future<bool> isDefaultAssistant() => _invokeBool('isDefaultAssistant');

  /// Android 10+: rol penceresi; olmazsa "Varsayılan uygulamalar" ayarı.
  static Future<String> requestDefaultAssistant() =>
      _invokeString('requestDefaultAssistant', 'UNAVAILABLE');

  static Future<bool> notificationAccessGranted() =>
      _invokeBool('notificationAccess');
  static Future<bool> openNotificationAccessSettings() =>
      _invokeBool('openNotificationAccess');

  static Future<bool> openWhatsAppNotification(String key) =>
      _invokeBool('openWhatsAppNotification', {'key': key});

  static Future<List<Map<String, dynamic>>> recentNotifications({
    int limit = 10,
  }) async => (await _invokeMapList('recentNotifications', {
    'limit': limit,
  })).map((m) => m.map((k, v) => MapEntry(k.toString(), v))).toList();

  /// "Hey Jarvis" uyandırma sözcüğü (cihazda). 'OK' ya da hata metni.
  static Future<String> wakeWordStart({double sensitivity = 0.5}) =>
      _invokeString('wakeWordStart', 'UNAVAILABLE', {
        'sensitivity': sensitivity,
      });
  static Future<bool> wakeWordPause() => _invokeBool('wakeWordPause');
  static Future<bool> closeAssistantTask() => _invokeBool('closeAssistantTask');
  static Future<bool> wakeWordStop() => _invokeBool('wakeWordStop');
  static Future<bool> wakeDiagnosticStart() =>
      _invokeBool('wakeDiagnosticStart');
  static Future<bool> wakeDiagnosticEnd() => _invokeBool('wakeDiagnosticEnd');
  static Future<Map<String, dynamic>> wakeWordInfo() async {
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'wakeWordInfo',
      );
      return r == null ? const {} : r.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return const {};
    }
  }

  static Future<bool> cancelAlarm(String key) =>
      _invokeBool('cancelAlarm', {'key': key});

  /// Zamanlanmış görev Dart'ta başladı: yedek bildirimi iptal et, tek seferlik
  /// alarm kaydını sil (Kotlin tarafında 'ack:' öneki).
  static Future<bool> cronAck(String id) =>
      _invokeBool('cancelAlarm', {'key': 'ack:cron_$id'});

  static Future<bool> canScheduleExactAlarms() =>
      _invokeBool('canScheduleExactAlarms');

  static Future<bool> openExactAlarmSettings() =>
      _invokeBool('openExactAlarmSettings');

  /// Opens a content:// uri or an absolute file path with an external app.
  static Future<bool> openFileUri(String uriOrPath, {String? mimeType}) =>
      _invokeBool('openFileUri', {'uri': uriOrPath, 'mimeType': mimeType});

  /// Writes [apkBytes] into the app cache and opens Android's installer.
  /// Returns a Turkish status message.
  static Future<String> installApk(Uint8List apkBytes) async {
    if (apkBytes.length < 1024) return 'APK dosyası geçersiz.';
    try {
      final dir = await _channel.invokeMethod<String>('getCacheDir');
      if (dir == null || dir.isEmpty) return 'Önbellek klasörü bulunamadı.';
      final updates = Directory('$dir/updates');
      if (!updates.existsSync()) updates.createSync(recursive: true);
      final file = File('${updates.path}/JARVIS-guncelleme.apk');
      await file.writeAsBytes(apkBytes, flush: true);
      final res = await _channel.invokeMethod<String>('installApk', {
        'path': file.path,
      });
      return switch (res) {
        'started' => 'Kurulum ekranı açıldı. "Güncelle" ye dokunun.',
        'needs_permission' => 'Bilinmeyen uygulama yükleme iznini JARVIS için açın, sonra tekrar deneyin.',
        'missing' => 'İndirilen APK bulunamadı.',
        _ => 'Kurulum başlatılamadı: ${res ?? 'bilinmeyen hata'}',
      };
    } catch (e) {
      return 'Kurulum hatası: $e';
    }
  }

  // -------------------- APP MANAGEMENT --------------------

  static final Map<String, Uint8List?> _iconCache = <String, Uint8List?>{};

  /// 96x96 PNG of the app's launcher icon (cached in memory).
  static Future<Uint8List?> getAppIcon(String packageName) async {
    if (packageName.isEmpty) return null;
    if (_iconCache.containsKey(packageName)) return _iconCache[packageName];
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('getAppIcon', {
        'package': packageName,
      });
      _iconCache[packageName] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openAppInfo(String packageName) =>
      _invokeBool('openAppInfo', {'package': packageName});

  static Future<bool> uninstallApp(String packageName) =>
      _invokeBool('uninstallApp', {'package': packageName});

  /// Opens Play Store details for a package name, or a search otherwise.
  static Future<bool> openPlayStore(String packageOrQuery) =>
      _invokeBool('openPlayStore', {'query': packageOrQuery});

  static Future<bool> isPackageInstalled(String packageName) =>
      _invokeBool('isPackageInstalled', {'package': packageName});

  static Future<bool> hasUsageAccess() => _invokeBool('hasUsageAccess');

  static Future<bool> openUsageAccessSettings() =>
      _invokeBool('openUsageAccessSettings');

  /// Top 30 apps by foreground time over the last [days] days. Empty when
  /// usage access has not been granted.
  static Future<List<AppUsageInfo>> getAppUsageStats({int days = 1}) async {
    final rows = await _invokeMapList('getAppUsageStats', {'days': days});
    return rows
        .map(AppUsageInfo.fromMap)
        .where((u) => u.packageName.isNotEmpty)
        .toList();
  }

  // -------------------- SYSTEM CONTROLS --------------------

  /// panel: internet, wifi, volume, nfc, bluetooth, hotspot, airplane, dnd,
  /// battery_saver, developer, storage, accessibility, date, language,
  /// security, notifications, location, display, sound, apps ...
  static Future<bool> openSettingsPanel(String panel) =>
      _invokeBool('openSettingsPanel', {'panel': panel});

  /// Current system brightness 0..100.
  static Future<int> getBrightness() async {
    try {
      final v = await _channel.invokeMethod<num>('getBrightness');
      return (v?.toInt() ?? 50).clamp(0, 100);
    } catch (_) {
      return 50;
    }
  }

  /// Returns 'OK', 'PERMISSION_NEEDED' (window brightness applied, write
  /// settings screen opened), 'ERROR' or 'UNAVAILABLE'.
  static Future<String> setBrightness(int percent) => _invokeString(
    'setBrightness',
    'UNAVAILABLE',
    {'percent': percent.clamp(0, 100)},
  );

  /// mode: 'normal' | 'vibrate' | 'silent'. Returns 'OK' |
  /// 'PERMISSION_NEEDED' | 'ERROR'.
  static Future<String> setRingerMode(String mode) =>
      _invokeString('setRingerMode', 'ERROR', {'mode': mode});

  static Future<String> getRingerMode() =>
      _invokeString('getRingerMode', 'normal');

  static Future<bool> keepScreenOn(bool on) =>
      _invokeBool('keepScreenOn', {'on': on});

  static Future<bool> vibrate({int ms = 300}) =>
      _invokeBool('vibrate', {'ms': ms});

  static Future<bool> shareText(String text, {String? packageName}) =>
      _invokeBool('shareText', {'text': text, 'package': packageName});

  // -------------------- CONTACTS & CALLING --------------------

  /// Searches contacts by name (Turkish-insensitive fallback). Requests the
  /// READ_CONTACTS permission and returns an empty list if not granted.
  static Future<List<ContactInfo>> searchContacts(
    String query, {
    int limit = 10,
  }) async {
    final rows = await _invokeMapList('searchContacts', {
      'query': query,
      'limit': limit,
    });
    return rows
        .map(ContactInfo.fromMap)
        .where((c) => c.phone.isNotEmpty)
        .toList();
  }

  static Future<bool> contactsPermissionGranted() async {
    final v = await _invokeString('contactsPermission', 'denied');
    return v == 'granted';
  }

  /// Opens the dialer pre-filled with [number] (does not place the call).
  static Future<bool> dialNumber(String number) =>
      _invokeBool('dialNumber', {'number': number});

  // -------------------- LOCATION --------------------

  /// Current location or null (permission requested on first call).
  static Future<({double lat, double lon, double accuracy})?>
  getCurrentLocation() async {
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getCurrentLocation')
          .timeout(const Duration(seconds: 20));
      if (raw == null) return null;
      final lat = (raw['lat'] as num?)?.toDouble();
      final lon = (raw['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      return (
        lat: lat,
        lon: lon,
        accuracy: (raw['accuracy'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------- TERMUX --------------------

  /// Runs a command through Termux's RUN_COMMAND service. Returns 'OK',
  /// 'TERMUX_NOT_INSTALLED', 'PERMISSION_NEEDED', `'ERROR:<msg>'` or
  /// 'UNAVAILABLE'. Termux must have `allow-external-apps=true`.
  static Future<String> runTermuxCommand({
    required String executable,
    required List<String> args,
    String? workDir,
    bool background = true,
  }) => _invokeString('runTermuxCommand', 'UNAVAILABLE', {
    'executable': executable,
    'args': args,
    'workDir': workDir,
    'background': background,
  });
}

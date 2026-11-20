import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/jarvis_models.dart';
import 'device_bridge.dart';
import 'math_evaluator.dart';
import 'web_tools.dart';
import 'voice_commands.dart' show TrNumbers;
import 'wake_strip.dart';

export 'wake_strip.dart';

class LocalCommandOutcome {
  final bool handled;
  final String reply;
  final String? actionBanner;
  final int? switchTabIndex;
  final int? switchToolsSubTab;

  const LocalCommandOutcome({
    required this.handled,
    this.reply = '',
    this.actionBanner,
    this.switchTabIndex,
    this.switchToolsSubTab,
  });
}

abstract class MobileStateDelegate {
  List<JarvisTimer> get timers;
  Future<JarvisTimer> addTimer(int seconds, String label);
  Future<int> cancelTimers({bool all = false, bool earliest = false});
  Future<void> appendToActiveNote(String text);
  void openTab(int mainTab, {int? toolsSubTab});

  /// Installed launcher apps (may be empty outside Android).
  List<DeviceAppInfo> get installedApps;

  /// Enqueues a file download and returns a user-facing Turkish message.
  Future<String> downloadFile(String url, {String? fileName});

  /// Finds a downloadable video on a page/URL and downloads it.
  Future<String> downloadVideo(String url);

  /// Starts a background multi-source deep research and returns a message.
  Future<String> startDeepResearch(String question);
}

class LocalCommandEngine {
  static const _uuid = Uuid();

  /// Turkish-insensitive folding used for fuzzy app/contact matching.
  static String foldTr(String input) =>
      normalizeTr(input)
          .replaceAll('ı', 'i')
          .replaceAll('ş', 's')
          .replaceAll('ğ', 'g')
          .replaceAll('ü', 'u')
          .replaceAll('ö', 'o')
          .replaceAll('ç', 'c')
          .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
          .trim();

  static String? reminderActionKey(Map<String, dynamic> action) {
    String label(String field, String fallback) => (action[field]?.toString() ?? fallback)
        .trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return switch (action['type']) {
      'create_timer' => jsonEncode(['timer', _asNum(action['seconds'])?.toInt(), label('label', 'Zamanlayıcı')]),
      'set_alarm' => jsonEncode(['alarm', _asNum(action['hour'])?.toInt(), _asNum(action['minute'])?.toInt() ?? 0, label('message', 'Ege Alarm')]),
      _ => null,
    };
  }

  static bool isAssistantExit(String text) => !const {'kapat', 'uygulamayi kapat', 'uygulamadan cik'}.contains(foldTr(text)) && RegExp(
    r'^(?:lutfen )?(?:(?:hey )?(?:ege|asistan) )?(?:(?:kendini|asistani|egeyi|uygulamayi) kapat|kapan|kapat|uygulamadan cik)(?: lutfen)?$',
  ).hasMatch(foldTr(text).replaceAll(RegExp(r'\s+'), ' '));

  /// Finds the best matching installed app by (fuzzy) name or package.
  static DeviceAppInfo? findApp(List<DeviceAppInfo> apps, String query) {
    final q = foldTr(query);
    if (q.isEmpty || apps.isEmpty) return null;
    DeviceAppInfo? best;
    var bestScore = 0;
    for (final a in apps) {
      final n = foldTr(a.name);
      final p = a.packageName.toLowerCase();
      var score = 0;
      if (n == q) {
        score = 100;
      } else if (n.startsWith(q)) {
        score = 80;
      } else if (n.contains(q)) {
        score = 60;
      } else if (p.contains(q.replaceAll(' ', ''))) {
        score = 40;
      }
      if (score > bestScore ||
          (score == bestScore && score > 0 && !a.isSystem)) {
        bestScore = score;
        best = a;
      }
    }
    return bestScore > 0 ? best : null;
  }

  /// Normalizes a phone number for wa.me (Turkish local numbers -> 90...).
  static String waNumber(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (d.startsWith('+')) d = d.substring(1);
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('0') && d.length == 11) d = '90${d.substring(1)}';
    if (d.length == 10 && d.startsWith('5')) d = '90$d';
    return d;
  }

  /// Strips Turkish accusative/dative suffixes to get contact name candidates.
  static List<String> nameCandidates(String word) {
    final w = word.trim();
    final out = <String>{w};
    final apo = w.indexOf(RegExp("['’]"));
    if (apo > 0) out.add(w.substring(0, apo));
    for (final suf in const [
      'yı',
      'yi',
      'yu',
      'yü',
      'ya',
      'ye',
      'ı',
      'i',
      'u',
      'ü',
      'a',
      'e',
    ]) {
      if (w.length > suf.length + 2 && w.endsWith(suf)) {
        out.add(w.substring(0, w.length - suf.length));
      }
    }
    return out.where((e) => e.length >= 2).toList();
  }

  /// Büyük şehirler: "istanbulda" gibi apostrofsuz yer-bulunma ekini ayıklamak için.
  static const _knownCities = {
    'istanbul', 'ankara', 'izmir', 'bursa', 'antalya', 'adana', 'konya',
    'gaziantep', 'kayseri', 'mersin', 'eskişehir', 'trabzon', 'samsun',
    'diyarbakır', 'denizli', 'malatya', 'erzurum', 'van', 'sakarya',
    'muğla', 'bodrum', 'marmaris', 'kocaeli', 'tekirdağ', 'balıkesir',
    'manisa', 'aydın', 'hatay', 'şanlıurfa', 'sivas', 'rize', 'ordu',
    'edirne', 'çanakkale', 'berlin', 'paris', 'londra', 'roma', 'madrid',
  };

  static const _weatherStop = {
    'hava', 'durumu', 'durumunu', 'nasıl', 'kaç', 'derece', 'ne', 'durumda',
    'raporu', 'bugün', 'bugünkü', 'yarın', 'yarınki', 'şu', 'an', 'şimdi',
    'bu', 'hafta', 'haftalık', 'için', 'nedir', 'olacak', 'göster', 'söyle',
    'de', 'da', 'te', 'ta', 'acaba', 'peki', 'oralar', 'orada', 'sonu', 've',
    'günaydın', 'saat', 'piknik',
  };

  /// Hava durumu cümlesinden şehir çıkarır. '' = şehir yok (konum kullanılır),
  /// null = cümle şehir sorusu değil (LLM'e bırak).
  static String? weatherCity(String stripped) {
    final toks = stripped
        .replaceAll(RegExp(r'[?.!,]'), ' ')
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    final kept = <String>[];
    for (var t in toks) {
      final apo = RegExp(r"['’](?:da|de|ta|te|nın|nin|un|ün|ın|in)$");
      if (apo.hasMatch(t)) {
        t = t.replaceAll(apo, '');
      } else {
        for (final suf in const ['da', 'de', 'ta', 'te']) {
          if (t.length > 3 && t.endsWith(suf)) {
            final stem = t.substring(0, t.length - 2);
            if (_knownCities.contains(stem)) {
              t = stem;
              break;
            }
          }
        }
      }
      if (t.isEmpty || _weatherStop.contains(t)) continue;
      kept.add(t);
    }
    if (kept.length > 2) return null;
    return kept.join(' ').trim();
  }

  /// Apostrof/ek soyma adaylarıyla uygulama bulur ("Telegram'ı" -> Telegram).
  static DeviceAppInfo? _findAppByCandidates(
    List<DeviceAppInfo> apps,
    String phrase,
  ) {
    final exact = findApp(apps, phrase);
    if (exact != null) return exact;
    final cands = nameCandidates(phrase).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final c in cands) {
      final a = findApp(apps, c);
      if (a != null) return a;
    }
    return null;
  }

  static num? _asNum(Object? v) {
    if (v is num) return v;
    if (v == null) return null;
    return num.tryParse(v.toString().trim().replaceAll(',', '.'));
  }

  static final _newsBadTopics = {
    'ne', 'iyi', 'kötü', 'şu', 'bu', 'sana', 'bana', 'ona', 'nasıl',
  };

  static Future<LocalCommandOutcome?> _tryInfoAndWebCommands(
    String raw,
    String stripped,
    MobileStateDelegate delegate,
  ) async {
    // --- URL driven: downloads ---
    final urls = WebTools.extractUrls(raw);
    if (urls.isNotEmpty) {
      final url = urls.first;
      final wantsDownload = RegExp(
        r'\b(indir|download|kaydet|telefona al|yükle)\b',
      ).hasMatch(stripped);
      if (wantsDownload &&
          RegExp(r'\b(resim\w*|görsel\w*|fotoğraf\w*)\b').hasMatch(stripped)) {
        return null; // The agent resolves the actual image and checks its MIME type.
      }
      if (wantsDownload) {
        final isVideo =
            RegExp(r'\b(video|videoyu|videosunu|film|klip|mp4|reels?)\b')
                .hasMatch(stripped) &&
            !WebTools.looksLikeDirectMedia(url);
        final msg = isVideo
            ? await delegate.downloadVideo(url)
            : await delegate.downloadFile(url);
        return LocalCommandOutcome(
          handled: true,
          reply: msg,
          actionBanner: isVideo ? '🎬 Video indirme' : '⬇️ Dosya indirme',
        );
      }
      return null; // other URL requests go to the AI with page content.
    }

    // --- Deep research ---
    final research =
        RegExp(r'^(?:derin\s+)?araştır(?:ma)?(?:\s+yap(?![a-zA-ZçğıöşüÇĞİÖŞÜ])\s*[:,-]?|\s*[:])\s*(.{4,})$')
            .firstMatch(stripped) ??
        RegExp(
          r'^(.{4,}?)\s+(?:hakkında|konusunda|ile ilgili)\s+(?:derin\s+)?araştırma\s+yap$',
        ).firstMatch(stripped);
    if (research != null &&
        !RegExp(r'ödev|öner|konu').hasMatch(research.group(1)!)) {
      final q = research.group(1)!.trim();
      final msg = await delegate.startDeepResearch(q);
      return LocalCommandOutcome(
        handled: true,
        reply: msg,
        actionBanner: '🔬 Derin araştırma: $q',
      );
    }

    // --- Weather ---
    final weatherQ =
        ((RegExp(r'\bhava\s*(durumu|nasıl|kaç derece|ne durumda|raporu)\b')
                    .hasMatch(stripped) ||
                stripped == 'hava' ||
                RegExp(r'^[^ ]+ hava$').hasMatch(stripped)) &&
            !stripped.endsWith(' aç') &&
            !stripped.contains('uygulama'))
        ? weatherCity(stripped)
        : null;
    if (weatherQ != null) {
      final city = weatherQ;
      WeatherReport? report;
      if (city.isNotEmpty) {
        report = await WebTools.weather(city: city);
      } else {
        final loc = await DeviceBridge.getCurrentLocation();
        if (loc != null) {
          report = await WebTools.weather(lat: loc.lat, lon: loc.lon);
        } else {
          report = await WebTools.weather(city: 'İstanbul');
        }
      }
      if (report == null) {
        return LocalCommandOutcome(
          handled: true,
          reply: city.isEmpty
              ? 'Hava durumu alınamadı. İnternet bağlantısını ve konum iznini kontrol edin.'
              : '"$city" için hava durumu bulunamadı.',
        );
      }
      return LocalCommandOutcome(
        handled: true,
        reply: '🌤️ ${report.toTurkishSummary()}',
        actionBanner: '🌡️ ${report.place}: ${report.temperatureC.round()}°C',
      );
    }

    // --- Currency ---
    final cur = RegExp(
      r'^(\d+(?:[.,]\d+)?)?\s*(dolar|euro|avro|sterlin|pound|yen|frank|ruble|riyal|yuan)\s*(?:kuru|kur|kaç\s*(?:tl|lira|para)?|ne kadar|kaç lira|tl)?\s*(?:oldu|ediyor|eder)?\??$',
    ).firstMatch(stripped);
    if (cur != null &&
        (stripped.contains('kaç') ||
            stripped.contains('kur') ||
            stripped.contains('ne kadar') ||
            stripped.contains('tl') ||
            stripped.contains('eder'))) {
      final amount =
          double.tryParse((cur.group(1) ?? '1').replaceAll(',', '.')) ?? 1;
      final code = WebTools.currencyCodeFromTurkish(cur.group(2)!);
      if (code != null) {
        final q = await WebTools.convertCurrency(
          amount: amount,
          from: code,
          to: 'TRY',
        );
        if (q == null) {
          return const LocalCommandOutcome(
            handled: true,
            reply: 'Döviz kuru alınamadı. İnternet bağlantısını kontrol edin.',
          );
        }
        final amt = amount == amount.roundToDouble()
            ? amount.toInt().toString()
            : amount.toString();
        return LocalCommandOutcome(
          handled: true,
          reply:
              '💱 $amt ${q.from} = **${q.converted.toStringAsFixed(2)} TL** (1 ${q.from} = ${q.rate.toStringAsFixed(4)} TL)${q.date != null ? ' • ${q.date!.day}.${q.date!.month}.${q.date!.year}' : ''}',
          actionBanner: '💱 1 ${q.from} = ${q.rate.toStringAsFixed(2)} TL',
        );
      }
    }

    // --- News ---
    final news = RegExp(
      r'^(?:son\s+|güncel\s+|bugünkü\s+|günün\s+)?(?:(.{2,40}?)\s+)?(?:haber(?:ler|leri|lerini)?|manşetler(?:i)?)(?:\s+(?:oku|göster|neler|ver|nedir|getir))?\??$',
    ).firstMatch(stripped);
    if (news != null) {
      var topic = (news.group(1) ?? '').trim();
      if (_newsBadTopics.contains(topic) ||
          RegExp(r'(?:ime|ıma|uma|üme|ama|eme)$').hasMatch(topic) ||
          (topic.isNotEmpty && RegExp(r'haber\s+ver$').hasMatch(stripped))) {
        topic = '';
        if (!RegExp(r'^(?:son |güncel |bugünkü |günün )?haberler?(?: oku| göster| neler| ver| nedir| getir)?\??$')
            .hasMatch(stripped)) {
          // konu cümlesi değil ("Ne haber?", "Anneme haber ver"): haber araması yapma.
          return null;
        }
      }
      if (const [
        'son',
        'güncel',
        'bugünkü',
        'günün',
        'bugün',
      ].contains(topic)) {
        topic = '';
      }
      final items = await WebTools.news(
        topic: topic.isEmpty ? null : topic,
        limit: 8,
      );
      if (items.isEmpty) {
        return const LocalCommandOutcome(
          handled: true,
          reply: 'Haberler alınamadı. İnternet bağlantısını kontrol edin.',
        );
      }
      final lines = <String>[
        '📰 **${topic.isEmpty ? 'Güncel Haberler' : '${topic[0].toUpperCase()}${topic.substring(1)} Haberleri'}**',
        '',
        for (var i = 0; i < items.length; i++)
          '${i + 1}. [${items[i].title}](${items[i].link})${items[i].source.isNotEmpty ? ' — *${items[i].source}*' : ''}',
      ];
      return LocalCommandOutcome(
        handled: true,
        reply: lines.join('\n'),
        actionBanner: '📰 ${items.length} haber',
      );
    }

    // --- Wikipedia ---
    final wiki =
        RegExp(
          r"^(?:vikipedi|wikipedia)(?:['’]?(?:de|da|den|dan))?\s+(.{2,80}?)(?:\s+(?:ara|bul|nedir|kimdir|oku))?$",
        ).firstMatch(stripped) ??
        RegExp(
          r"^(.{2,80}?)\s+(?:vikipedi|wikipedia)(?:['’]?(?:de|da))?(?:\s+(?:ara|bul))?$",
        ).firstMatch(stripped);
    if (wiki != null) {
      final q = wiki.group(1)!.trim();
      final sum = await WebTools.wikipediaSummary(q);
      if (sum == null) {
        return LocalCommandOutcome(
          handled: true,
          reply: 'Vikipedi\'de "$q" bulunamadı.',
        );
      }
      return LocalCommandOutcome(
        handled: true,
        reply:
            '📚 **${sum.title}**\n\n${sum.extract}\n\n[Vikipedi\'de aç](${sum.url})',
        actionBanner: '📚 Vikipedi: ${sum.title}',
      );
    }

    // --- Location ---
    if (const [
      'konumum',
      'konumum nerede',
      'neredeyim',
      'konumumu göster',
      'şu an neredeyim',
      'konum',
    ].contains(stripped.replaceAll('?', '').trim())) {
      final loc = await DeviceBridge.getCurrentLocation();
      if (loc == null) {
        return const LocalCommandOutcome(
          handled: true,
          reply: '📍 Konum alınamadı. Konum iznini verip GPS\'i açtıktan sonra tekrar deneyin.',
        );
      }
      final lat = loc.lat.toStringAsFixed(5);
      final lon = loc.lon.toStringAsFixed(5);
      return LocalCommandOutcome(
        handled: true,
        reply:
            '📍 Konumunuz: **$lat, $lon** (±${loc.accuracy.round()} m)\n\n[Haritada aç](https://www.google.com/maps/search/?api=1&query=$lat,$lon)',
        actionBanner: '📍 $lat, $lon',
      );
    }
    return null;
  }

  static Future<LocalCommandOutcome?> _tryPhoneManagementCommands(
    String raw,
    String stripped,
    MobileStateDelegate delegate, {
    String? original,
  }) async {
    final orig = original ?? raw;
    // --- Quick settings panels (Android forbids silent toggles; open panels) ---
    const panels = <String, String>{
      'wifi aç': 'wifi',
      'wifiyi aç': 'wifi',
      'wi-fi aç': 'wifi',
      'wifi kapat': 'wifi',
      'wifiyi kapat': 'wifi',
      'wi-fi kapat': 'wifi',
      'wifi paneli': 'wifi',
      'interneti aç': 'internet',
      'interneti kapat': 'internet',
      'mobil veriyi aç': 'internet',
      'mobil veriyi kapat': 'internet',
      'internet paneli': 'internet',
      'bluetooth aç': 'bluetooth',
      'bluetoothu aç': 'bluetooth',
      'bluetooth kapat': 'bluetooth',
      'bluetoothu kapat': 'bluetooth',
      'nfc aç': 'nfc',
      'nfc kapat': 'nfc',
      'uçak modunu aç': 'airplane',
      'uçak modunu kapat': 'airplane',
      'uçak modu': 'airplane',
      'rahatsız etmeyin': 'dnd',
      'rahatsız etmeyin modunu aç': 'dnd',
      'hotspot aç': 'hotspot',
      'erişim noktasını aç': 'hotspot',
      'hotspotu aç': 'hotspot',
      'pil tasarrufunu aç': 'battery_saver',
      'güç tasarrufunu aç': 'battery_saver',
      'depolama alanını aç': 'storage',
      'depolama ayarları': 'storage',
      'bildirim ayarları': 'notifications',
      'bildirim ayarlarını aç': 'notifications',
      'ses paneli': 'volume',
      'ses panelini aç': 'volume',
      'geliştirici seçenekleri': 'developer',
      'geliştirici seçeneklerini aç': 'developer',
      'erişilebilirlik ayarları': 'accessibility',
      'dil ayarları': 'language',
      'tarih ayarları': 'date',
      'güvenlik ayarları': 'security',
    };
    final panel = panels[stripped];
    if (panel != null) {
      final ok = await DeviceBridge.openSettingsPanel(panel);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '⚙️ $panel paneli açıldı. Android güvenlik kuralları nedeniyle anahtarı panelden siz değiştirmelisiniz.'
            : 'Panel açılamadı.',
        actionBanner: ok ? '⚙️ Panel: $panel' : null,
      );
    }

    // --- Ringer modes ---
    const ringer = <String, String>{
      'sessiz moda al': 'silent',
      'telefonu sessize al': 'silent',
      'sessiz mod': 'silent',
      'zili kapat': 'silent',
      'titreşime al': 'vibrate',
      'titreşim moduna al': 'vibrate',
      'telefonu titreşime al': 'vibrate',
      'normal moda al': 'normal',
      'zili aç': 'normal',
      'zil sesini aç': 'normal',
      'sessiz modu kapat': 'normal',
    };
    final mode = ringer[stripped];
    if (mode != null) {
      final res = await DeviceBridge.setRingerMode(mode);
      final label = {
        'silent': 'Sessiz',
        'vibrate': 'Titreşim',
        'normal': 'Normal',
      }[mode];
      return LocalCommandOutcome(
        handled: true,
        reply: res == 'OK'
            ? '🔔 Zil modu: **$label**'
            : res == 'PERMISSION_NEEDED'
            ? '🔔 Zil modunu değiştirmek için "Rahatsız Etmeyin erişimi" izni gerekiyor; ayar ekranını açtım, Ege\'e izin verip tekrar deneyin.'
            : 'Zil modu değiştirilemedi.',
        actionBanner: res == 'OK' ? '🔔 $label mod' : null,
      );
    }

    // --- Brightness ---
    final bright = RegExp(
      r"^(?:ekran\s+)?parlaklı(?:ğı|k)(?:nı)?\s+%?(\d{1,3})(?:['’]?(?:e|a|ye|ya))?\s*(?:yap|ayarla|getir|çek)?$",
    ).firstMatch(stripped);
    int? targetBright;
    if (bright != null) {
      targetBright = int.parse(bright.group(1)!).clamp(0, 100);
    } else if (const [
      'parlaklığı artır',
      'ekranı aydınlat',
      'parlaklığı yükselt',
    ].contains(stripped)) {
      targetBright = ((await DeviceBridge.getBrightness()) + 25).clamp(0, 100);
    } else if (const [
      'parlaklığı azalt',
      'ekranı karart',
      'parlaklığı düşür',
    ].contains(stripped)) {
      targetBright = ((await DeviceBridge.getBrightness()) - 25).clamp(5, 100);
    } else if (const [
      'parlaklığı fulle',
      'parlaklığı sonuna kadar aç',
    ].contains(stripped)) {
      targetBright = 100;
    }
    if (targetBright != null) {
      final res = await DeviceBridge.setBrightness(targetBright);
      return LocalCommandOutcome(
        handled: true,
        reply: res == 'OK'
            ? '🔆 Ekran parlaklığı %$targetBright yapıldı.'
            : res == 'PERMISSION_NEEDED'
            ? '🔆 Parlaklık şimdilik bu uygulamada %$targetBright yapıldı. Sistem genelinde değiştirmek için açılan ekranda "Sistem ayarlarını değiştir" iznini verin.'
            : 'Parlaklık ayarlanamadı.',
        actionBanner: '🔆 Parlaklık %$targetBright',
      );
    }

    // --- Screen / vibration ---
    if (const [
      'ekranı açık tut',
      'ekran kapanmasın',
      'ekranı uyanık tut',
    ].contains(stripped)) {
      await DeviceBridge.keepScreenOn(true);
      return const LocalCommandOutcome(
        handled: true,
        reply: '💡 Ege açıkken ekran kapanmayacak.',
        actionBanner: '💡 Ekran açık',
      );
    }
    if (const ['ekranı normale al', 'ekran kapanabilir'].contains(stripped)) {
      await DeviceBridge.keepScreenOn(false);
      return const LocalCommandOutcome(
        handled: true,
        reply: '💡 Ekran zaman aşımı normale döndü.',
      );
    }
    if (const ['titreş', 'telefonu titret', 'titret'].contains(stripped)) {
      await DeviceBridge.vibrate(ms: 500);
      return const LocalCommandOutcome(
        handled: true,
        reply: '📳 Bzzzt!',
        actionBanner: '📳 Titreşim',
      );
    }

    // --- Clipboard ---
    final clipRe = RegExp(
      r'^panoya(?:\s+kopyala)?\s*[:,-]?\s+(.+)$',
      caseSensitive: false,
    );
    final clip =
        clipRe.firstMatch(orig) ??
        clipRe.firstMatch(
          raw.trim().replaceFirst(
            RegExp(r'^(?:hey\s+)?jarvis\s*[,،]?\s*', caseSensitive: false),
            '',
          ),
        );
    if (clip != null && stripped.startsWith('panoya')) {
      final text = clip.group(1)!.trim();
      await Clipboard.setData(ClipboardData(text: text));
      return LocalCommandOutcome(
        handled: true,
        reply: '📋 Panoya kopyalandı: "$text"',
        actionBanner: '📋 Kopyalandı',
      );
    }
    if (const [
      'panoyu oku',
      'panoda ne var',
      'panodakini oku',
      'panoyu göster',
    ].contains(stripped)) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      return LocalCommandOutcome(
        handled: true,
        reply: text.isEmpty ? '📋 Pano boş.' : '📋 Panodaki metin:\n\n$text',
      );
    }

    // --- WhatsApp with number ---
    final waNum = RegExp(
      r"^whatsapp(?:['’]?(?:tan|dan))?\s+(\+?\d[\d\s]{8,16})\s*(?:numarasına|['’]?(?:e|a|ye|ya))?\s*(?:yaz|mesaj gönder|mesaj at|gönder)?\s*[:,-]\s*(.+)$",
    ).firstMatch(stripped);
    if (waNum != null) {
      final num = waNumber(waNum.group(1)!);
      final text = waNum.group(2)!.trim();
      final ok = await DeviceBridge.openUrl(
        'https://wa.me/$num?text=${Uri.encodeComponent(text)}',
      );
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '💬 WhatsApp mesajı hazırlandı (+$num). Göndermek için WhatsApp\'ta onaylayın.'
            : 'WhatsApp açılamadı.',
        actionBanner: ok ? '💬 WhatsApp: +$num' : null,
      );
    }
    // --- WhatsApp with contact name ("ahmet'e whatsapp'tan yaz: selam") ---
    final waName = RegExp(
      r"^(.{2,30}?)\s+whatsapp(?:['’]?(?:tan|dan))?\s+(?:yaz|mesaj at|mesaj gönder|gönder)\s*[:,-]?\s+(.+)$",
    ).firstMatch(stripped);
    if (waName != null) {
      final who = waName.group(1)!.trim();
      final text = waName.group(2)!.trim();
      for (final cand in nameCandidates(who)) {
        final contacts = await DeviceBridge.searchContacts(cand, limit: 3);
        if (contacts.isNotEmpty) {
          final c = contacts.first;
          final num = waNumber(c.phone);
          final ok = await DeviceBridge.openUrl(
            'https://wa.me/$num?text=${Uri.encodeComponent(text)}',
          );
          return LocalCommandOutcome(
            handled: true,
            reply: ok
                ? '💬 **${c.name}** için WhatsApp mesajı hazırlandı. Göndermek için onaylayın.'
                : 'WhatsApp açılamadı.',
            actionBanner: ok ? '💬 WhatsApp: ${c.name}' : null,
          );
        }
      }
      return LocalCommandOutcome(
        handled: true,
        reply: 'Rehberde "$who" bulunamadı (rehber izni gerekli olabilir).',
      );
    }

    // --- Call a contact ("annemi ara", "ahmet'i ara", "ara ahmet") ---
    final callMatch =
        RegExp(r"^(.{2,30}?)\s+(?:kişisini\s+)?ara$").firstMatch(stripped) ??
        RegExp(r'^(?:ara|arama yap)\s+(.{2,30})$').firstMatch(stripped);
    if (callMatch != null &&
        !stripped.contains('youtube') &&
        !stripped.contains('google')) {
      final who = callMatch.group(1)!.trim();
      final digits = who.replaceAll(RegExp(r'[^0-9+]'), '');
      if (digits.length >= 7 &&
          digits.length >= who.replaceAll(' ', '').length - 1) {
        await DeviceBridge.dialNumber(digits);
        return LocalCommandOutcome(
          handled: true,
          reply: '📞 $digits aranıyor (arama ekranı).',
          actionBanner: '📞 $digits',
        );
      }
      final endsAcc =
          RegExp(r"(?:['’][a-zçğıöşü]+|ı|i|u|ü|yı|yi|yu|yü)$").hasMatch(who) ||
          stripped.startsWith('ara ') ||
          stripped.contains('kişisini');
      if (endsAcc) {
        for (final cand in nameCandidates(who)) {
          final contacts = await DeviceBridge.searchContacts(cand, limit: 3);
          if (contacts.isNotEmpty) {
            final c = contacts.first;
            await DeviceBridge.dialNumber(c.phone);
            final others = contacts.length > 1
                ? '\n\nDiğer eşleşmeler: ${contacts.skip(1).map((e) => '${e.name} (${e.phone})').join(', ')}'
                : '';
            return LocalCommandOutcome(
              handled: true,
              reply:
                  '📞 **${c.name}** (${c.phone}) aranıyor — arama ekranında yeşil tuşa basın.$others',
              actionBanner: '📞 ${c.name}',
            );
          }
        }
      }
    }

    // --- Contacts lookup ---
    final findContact = RegExp(r'^rehberde\s+(.{2,30}?)\s*(?:ara|bul|göster)?$')
        .firstMatch(stripped);
    if (findContact != null) {
      final q = findContact.group(1)!.trim();
      final contacts = await DeviceBridge.searchContacts(q, limit: 8);
      return LocalCommandOutcome(
        handled: true,
        reply: contacts.isEmpty
            ? 'Rehberde "$q" bulunamadı (rehber izni verilmemiş olabilir).'
            : '👥 **Rehber sonuçları:**\n\n${contacts.map((c) => '- ${c.name}: `${c.phone}`').join('\n')}',
      );
    }

    // --- App management ---
    final uninstall = RegExp(
      r'^(.{2,40}?)\s+(?:uygulamasını\s+)?(?:kaldır|sil)$',
    ).firstMatch(stripped);
    if (uninstall != null &&
        !RegExp(r'(?<![\p{L}\p{N}])(?:not|notlar|not defteri)(?![\p{L}])',
                unicode: true)
            .hasMatch(stripped) &&
        !stripped.contains('zamanlayıcı')) {
      final app = _findAppByCandidates(
        delegate.installedApps,
        uninstall.group(1)!,
      );
      if (app != null) {
        final ok = await DeviceBridge.uninstallApp(app.packageName);
        return LocalCommandOutcome(
          handled: true,
          reply: ok
              ? '🗑️ **${app.name}** için kaldırma onay ekranı açıldı.'
              : '${app.name} kaldırılamadı.',
          actionBanner: ok ? '🗑️ ${app.name}' : null,
        );
      }
    }
    final appInfo = RegExp(
      r'^(.{2,40}?)\s+(?:uygulama\s+)?(?:bilgisi(?:ni)?|bilgilerini|izinlerini|ayarlarını)\s*(?:aç|göster)?$',
    ).firstMatch(stripped);
    if (appInfo != null) {
      final app = _findAppByCandidates(
        delegate.installedApps,
        appInfo.group(1)!,
      );
      if (app != null) {
        final ok = await DeviceBridge.openAppInfo(app.packageName);
        return LocalCommandOutcome(
          handled: true,
          reply: ok
              ? 'ℹ️ **${app.name}** uygulama bilgileri açıldı (sürüm ${app.versionName.isEmpty ? '-' : app.versionName}).'
              : 'Uygulama bilgisi açılamadı.',
          actionBanner: ok ? 'ℹ️ ${app.name}' : null,
        );
      }
    }
    final storeMatch =
        RegExp(r"^(.{2,40}?)\s+uygulamasını\s+(?:indir|yükle)$")
            .firstMatch(stripped) ??
        RegExp(
          r"^play\s*store(?:['’]?(?:da|dan))?\s+(.{2,40}?)\s*(?:ara|bul|aç|indir)?$",
        ).firstMatch(stripped);
    if (storeMatch != null) {
      final q = storeMatch.group(1)!.trim();
      final ok = await DeviceBridge.openPlayStore(q);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '🛒 Play Store\'da **$q** açılıyor.'
            : 'Play Store açılamadı.',
        actionBanner: ok ? '🛒 Play Store: $q' : null,
      );
    }
    if (const [
      'uygulamaları listele',
      'yüklü uygulamalar',
      'uygulamalarımı göster',
      'hangi uygulamalar yüklü',
    ].contains(stripped)) {
      final apps = delegate.installedApps;
      delegate.openTab(2, toolsSubTab: 3);
      return LocalCommandOutcome(
        handled: true,
        reply: apps.isEmpty
            ? 'Uygulama listesi alınamadı.'
            : '📱 **${apps.length} uygulama yüklü.** İlk 40:\n\n${apps.take(40).map((a) => a.name).join(', ')}',
        actionBanner: '📱 ${apps.length} uygulama',
        switchTabIndex: 2,
        switchToolsSubTab: 3,
      );
    }
    if (const [
      'en çok kullandığım uygulamalar',
      'ekran süresi',
      'uygulama kullanımım',
      'bugün telefonu ne kadar kullandım',
    ].contains(stripped)) {
      if (!await DeviceBridge.hasUsageAccess()) {
        await DeviceBridge.openUsageAccessSettings();
        return const LocalCommandOutcome(
          handled: true,
          reply: '📊 Kullanım istatistikleri için "Kullanım erişimi" izni gerekiyor. Açılan ekranda Ege\'i etkinleştirip tekrar sorun.',
        );
      }
      final usage = await DeviceBridge.getAppUsageStats(days: 1);
      if (usage.isEmpty) {
        return const LocalCommandOutcome(
          handled: true,
          reply: '📊 Bugün için kullanım verisi bulunamadı.',
        );
      }
      final total = usage.fold<int>(0, (s, u) => s + u.foregroundMs);
      String fmt(int ms) => formatDurationTr(ms ~/ 1000);
      return LocalCommandOutcome(
        handled: true,
        reply:
            '📊 **Bugünkü ekran süresi: ${fmt(total)}**\n\n${usage.take(10).map((u) => '- ${u.name}: ${fmt(u.foregroundMs)}').join('\n')}',
        actionBanner: '📊 Ekran süresi ${fmt(total)}',
      );
    }
    return null;
  }

  static String normalizeTr(String input) {
    return input
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .replaceAll('\u0307', '')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String formatDurationTr(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final parts = <String>[];
    if (h > 0) parts.add('$h saat');
    if (m > 0) parts.add('$m dakika');
    if (sec > 0 || parts.isEmpty) parts.add('$sec saniye');
    return parts.join(' ');
  }

  /// Whisper her cümleyi büyük harf + nokta ile yazar ("El fenerini aç.").
  /// Sondaki noktalama ve tırnaklar komut eşleşmesini bozmasın diye silinir;
  /// cümle içindeki ":" gibi ayırıcılar korunur ("not al: süt al").
  static String stripEndPunct(String input) => input
      .trim()
      .replaceAll(
        RegExp(
          '^[\\u0022\\u201C\\u201D\\u0027\\u2018\\u2019\\u00AB\\u00BB]+|[\\u0022\\u201C\\u201D\\u0027\\u2018\\u2019\\u00AB\\u00BB]+\$',
        ),
        '',
      )
      .replaceAll(RegExp(r'[\s.!?…,;:。]+$'), '')
      .trim();

  /// "devam et" yalnızca bir müzik/medya etkinken medya komutudur.
  static bool _mediaActive(MobileStateDelegate delegate) {
    try {
      return (delegate as dynamic).musicActive == true;
    } catch (_) {
      return false;
    }
  }

  static Future<LocalCommandOutcome> tryHandle(
    String rawInput,
    MobileStateDelegate delegate, {
    String? original,
  }) async {
    final raw = stripEndPunct(rawInput);
    if (raw.isEmpty) return const LocalCommandOutcome(handled: false);
    // Harf büyüklüğü korunmuş metin (not / pano içeriği için).
    final orig = stripEndPunct(stripWake(original ?? rawInput));

    final norm = normalizeTr(raw);
    final stripped = norm
        .replaceFirst(
          RegExp(r'^(?:(?:hey|hi|ey)\s+)?(?:ege|jarvis)(?=\s|[,،.!?:;\-]|$)\s*[,،.!?:;\-]?\s*'),
          '',
        )
        .replaceAll(RegExp(r'\blütfen\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Read-only info / web commands are safe even when phrased as questions.
    final info = await _tryInfoAndWebCommands(raw, stripped, delegate);
    if (info != null) return info;

    // Do not accidentally execute questions ("nasıl", "nedir") or negations ("kurma", "açma")
    if (RegExp(r'\b(nasıl|nedir|ne demek|yapılır|kurma|başlatma|açma|arama)\b')
        .hasMatch(norm)) {
      return const LocalCommandOutcome(handled: false);
    }

    // 1. Timer listing / cancelling
    if (const [
      'zamanlayıcıları göster',
      'zamanlayıcıları listele',
      'hatırlatıcıları göster',
      'hatırlatıcıları listele',
      'zamanlayıcılar neler',
      'hatırlatıcılar neler',
    ].contains(stripped)) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final active = delegate.timers.where((t) => !t.fired).toList();
      if (active.isEmpty) {
        return const LocalCommandOutcome(
          handled: true,
          reply: 'Şu anda etkin bir zamanlayıcı yok.',
          actionBanner: '⏱️ Etkin zamanlayıcı bulunamadı',
        );
      }
      final lines = active
          .map(
            (t) =>
                '${t.label} (${formatDurationTr(t.remainingSec(now))} kaldı)',
          )
          .join(' • ');
      return LocalCommandOutcome(
        handled: true,
        reply: 'Etkin zamanlayıcılar: $lines',
        actionBanner: '⏱️ ${active.length} etkin zamanlayıcı',
      );
    }

    if (const [
      'tüm zamanlayıcıları iptal et',
      'bütün zamanlayıcıları iptal et',
      'tüm hatırlatıcıları iptal et',
      'tüm alarmları iptal et',
    ].contains(stripped)) {
      final removed = await delegate.cancelTimers(all: true);
      final msg = removed > 0
          ? '$removed etkin zamanlayıcı iptal edildi.'
          : 'İptal edilecek etkin zamanlayıcı yok.';
      return LocalCommandOutcome(
        handled: true,
        reply: msg,
        actionBanner: '⏱️ Zamanlayıcı temizlendi',
      );
    }

    if (const [
      'son zamanlayıcıyı iptal et',
      'zamanlayıcıyı iptal et',
      'son hatırlatıcıyı iptal et',
      'ilk hatırlatıcıyı iptal et',
      'alarmı iptal et',
    ].contains(stripped)) {
      final earliest = stripped.startsWith('ilk ');
      final removed = await delegate.cancelTimers(
        all: false,
        earliest: earliest,
      );
      final msg = removed > 0
          ? 'Zamanlayıcı iptal edildi.'
          : 'İptal edilecek etkin zamanlayıcı bulunamadı.';
      return LocalCommandOutcome(
        handled: true,
        reply: msg,
        actionBanner: '⏱️ Zamanlayıcı iptal',
      );
    }

    // 2. Clock timer ("saat 21:30'da toplantı hatırlat")
    final clockRe = RegExp(
      r'^(?:saat\s+)?(\d{1,2})[:.](\d{2})(?:[\u0027]?(?:a|e|da|de|ta|te))?\s*(?:için\s+)?(?:(?:alarm|hatırlatıcı|zamanlayıcı)\s+)?(?:kur|ayarla|ekle|hatırlat)\s*[:،,-]?\s*(.*)$',
    );
    var cm = clockRe.firstMatch(stripped);
    cm ??= RegExp(
      r'^(?:saat\s+)?(\d{1,2})[:.](\d{2})(?:[\u0027]?(?:a|e|da|de|ta|te))?\s+(.+?)\s*(?:hatırlat|alarm kur|zamanlayıcı kur)$',
    ).firstMatch(stripped);
    if (cm != null) {
      final hour = int.parse(cm.group(1)!);
      final min = int.parse(cm.group(2)!);
      if (hour >= 0 && hour <= 23 && min >= 0 && min <= 59) {
        final now = DateTime.now();
        var target = DateTime(now.year, now.month, now.day, hour, min);
        if (!target.isAfter(now)) {
          target = target.add(const Duration(days: 1));
        }
        final sec = target.difference(now).inSeconds.clamp(1, 7 * 24 * 3600);
        final hh = hour.toString().padLeft(2, '0');
        final mm = min.toString().padLeft(2, '0');
        final rawLabel = (cm.group(3) ?? '').trim();
        final label = rawLabel.isEmpty ? 'Saat $hh:$mm hatırlatması' : rawLabel;
        final timer = await delegate.addTimer(sec, label);
        return LocalCommandOutcome(
          handled: true,
          reply:
              'Saat $hh:$mm için hatırlatıcı kuruldu: **${timer.label}** (${formatDurationTr(sec)} sonra).',
          actionBanner: '⏰ ${timer.label} ($hh:$mm)',
        );
      }
    }

    // 3. Relative duration timer ("5 dakika sonra kahve hatırlat", "5 dk çay sayacı kur")
    // Alarm erteleme desteklenmez; "ertele" etiketli sayaç kurma.
    if (RegExp(r'\bertele').hasMatch(stripped) &&
        RegExp(r'(?:^|\s)(?:alarm|zamanlayıcı|sayaç|hatırlatıcı)[a-zçğıöşü]*')
            .hasMatch(stripped)) {
      return const LocalCommandOutcome(
        handled: true,
        reply:
            'Alarm erteleme henüz desteklenmiyor. İstersen yeni bir zamanlayıcı kurabilirim.',
        actionBanner: '⏱️ Erteleme desteklenmiyor',
      );
    }
    // "bir buçuk saat", "yarım saat", "2 buçuk dakika" → ondalık sayı.
    var durText = stripped;
    if (durText.contains('buçuk')) {
      durText = TrNumbers.normalize(durText).replaceAllMapped(
        RegExp(r'(?<![\d.,])(\d+)\s+buçuk\s+(saat|dakika|dk)'),
        (m) => '${m.group(1)},5 ${m.group(2)}',
      );
    }
    durText = durText
        .replaceAllMapped(
          RegExp(r'\byarım\s+(saat|dakika)'),
          (m) => '0,5 ${m.group(1)}',
        )
        .replaceAllMapped(
          RegExp(r'\bçeyrek\s+(saat|dakika)'),
          (m) => '0,25 ${m.group(1)}',
        );
    final timerWords = durText.split(' ').length;
    if (timerWords <= 8 &&
        !RegExp(r'ertele|öner|plan|hazırla|etkinlik|ders').hasMatch(durText) &&
        RegExp(
          r'(?:^|\s)(?:zamanlayıcı|sayaç|sayac|alarm|hatırlat|hatırlatıcı)[a-zçğıöşü]*',
        ).hasMatch(durText) &&
        RegExp(
          r'(?:kur|başlat|ayarla|hatırlat|çalsın|ekle|ver|zamanlayıcı|sayaç|sayac|hatırlatıcı)[a-zçğıöşü]*$',
        ).hasMatch(durText)) {
      final durMatches = RegExp(
        r'(?<![\d.,])(\d+(?:[.,]\d+)?)\s*(saat|dk|dakika|sn|saniye)(?:lik|lık|luk|lük)?(?:$|[\s,.;:!?])',
      ).allMatches(durText);
      if (durMatches.isNotEmpty) {
        var totalSec = 0;
        for (final m in durMatches) {
          final n = double.parse(m.group(1)!.replaceAll(',', '.'));
          final unit = m.group(2)!;
          if (unit == 'saat') {
            totalSec += (n * 3600).round();
          } else if (unit == 'dk' || unit == 'dakika') {
            totalSec += (n * 60).round();
          } else {
            totalSec += n.round();
          }
        }
        if (totalSec >= 1 && totalSec <= 7 * 24 * 3600) {
          var label = durText
              .replaceAll(
                RegExp(
                  r'(?<![\d.,])\d+(?:[.,]\d+)?\s*(?:saat|dk|dakika|sn|saniye)(?:lik|lık|luk|lük)?(?=$|[\s,.;:!?])',
                ),
                ' ',
              )
              .replaceAll(
                RegExp(
                  r'(?:^|\s)(?:sonra|için|zamanlayıcı[a-zçğıöşü]*|sayac[a-zçğıöşü]*|sayaç[a-zçğıöşü]*|alarm[a-zçğıöşü]*|hatırlat[a-zçğıöşü]*|kur|başlat|ayarla|ekle|ver)(?=$|[\s,.;:!?])',
                ),
                ' ',
              )
              .replaceAll(RegExp(r'^[\s:،,-]+|[\s:،,-]+$'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (label.isEmpty) {
            label = '${formatDurationTr(totalSec)} sayacı';
          }
          final timer = await delegate.addTimer(totalSec, label);
          return LocalCommandOutcome(
            handled: true,
            reply:
                '⏱️ **${timer.label}** için **${formatDurationTr(totalSec)}** zamanlayıcı başlatıldı.',
            actionBanner: '⏰ ${timer.label} (${formatDurationTr(totalSec)})',
          );
        }
      }
    }

    // 4. Quick note append
    final noteRe = RegExp(
      r'^(?:notuma|notlarıma|notlara|not)\s+(?:ekle|al)\s*[:،,-]?\s+(.+)$',
      caseSensitive: false,
    );
    final noteMatch = noteRe.firstMatch(orig) ?? noteRe.firstMatch(raw);
    if (noteMatch != null) {
      final text = noteMatch.group(1)!.trim();
      await delegate.appendToActiveNote(text);
      return LocalCommandOutcome(
        handled: true,
        reply: '📝 Not defterine eklendi:\n> $text',
        actionBanner: '📝 Not eklendi',
      );
    }

    // 5. Panel navigation shortcuts
    if (const [
      'notları aç',
      'not defterini aç',
      'notlarımı aç',
    ].contains(stripped)) {
      delegate.openTab(2, toolsSubTab: 1);
      return const LocalCommandOutcome(
        handled: true,
        reply: '📝 Not Defteri açıldı.',
        actionBanner: '📝 Not Defteri',
        switchTabIndex: 2,
        switchToolsSubTab: 1,
      );
    }
    if (const ['hesap makinesini aç', 'hesap makinesi'].contains(stripped)) {
      delegate.openTab(2, toolsSubTab: 2);
      return const LocalCommandOutcome(
        handled: true,
        reply: '🧮 Hesap Makinesi açıldı.',
        actionBanner: '🧮 Hesap Makinesi',
        switchTabIndex: 2,
        switchToolsSubTab: 2,
      );
    }
    if (const [
      'cihaz durumu',
      'telefon durumu',
      'sistem izleyicisini aç',
      'pil durumu',
      'depolama ne kadar',
    ].contains(stripped)) {
      final metrics = await DeviceBridge.getDeviceMetrics();
      final batTxt = metrics.batteryPct >= 0
          ? '%${metrics.batteryPct}${metrics.charging ? ' (Şarjda)' : ''}'
          : 'Bilinmiyor';
      final ramPct = metrics.totalRamMb > 0
          ? ((metrics.usedRamMb * 100) / metrics.totalRamMb).round()
          : 0;
      delegate.openTab(2, toolsSubTab: 3);
      return LocalCommandOutcome(
        handled: true,
        reply:
            '📱 **${metrics.manufacturer} ${metrics.model}** (Android ${metrics.androidVersion})\n'
            '- 🔋 **Pil:** $batTxt\n'
            '- 🧠 **RAM:** ${metrics.usedRamMb} / ${metrics.totalRamMb} MB (%$ramPct)\n'
            '- 💾 **Depolama Boş:** ${metrics.freeStorageGb} / ${metrics.totalStorageGb} GB\n'
            '- 🌐 **Ağ:** ${metrics.networkType}',
        actionBanner: '📱 Cihaz Özeti ($batTxt)',
      );
    }

    // 6. Quick calculator expression ("hesapla 25*48" or direct math like "125 * 4")
    final calcMatch = RegExp(r'^(?:hesapla|kaç\s+eder)\s*[:،]?\s*(.+)$')
        .firstMatch(stripped);
    if (calcMatch != null) {
      try {
        final expr = calcMatch.group(1)!;
        final val = MathEvaluator.formatResult(MathEvaluator.evaluate(expr));
        return LocalCommandOutcome(
          handled: true,
          reply: '🧮 `$expr` = **$val**',
          actionBanner: '🧮 Sonuç: $val',
        );
      } catch (_) {}
    }

    // 7. External browser / map / dial intents
    final ytMatch = RegExp(
      r'^(?:youtube[\u0027]?(?:da|de|ta|te)?\s+)(.+?)\s+(?:ara|bul|aç|çal)$',
    ).firstMatch(stripped);
    if (ytMatch != null) {
      final q = ytMatch.group(1)!.trim();
      final url =
          'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(q)}';
      final ok = await DeviceBridge.openUrl(url);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '🎬 YouTube\'da **"$q"** araması açılıyor.'
            : 'YouTube bağlantısı açılamadı.',
        actionBanner: '🎬 YouTube: $q',
      );
    }

    final gMatch = RegExp(
      r'^(?:google[\u0027]?(?:da|de)?\s+|web[\u0027]?de\s+)(.+?)\s+(?:ara|bul)$',
    ).firstMatch(stripped);
    if (gMatch != null) {
      final q = gMatch.group(1)!.trim();
      final url =
          'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}';
      final ok = await DeviceBridge.openUrl(url);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '🔍 Google\'da **"$q"** araması açılıyor.'
            : 'Google araması açılamadı.',
        actionBanner: '🔍 Google: $q',
      );
    }

    final mapMatch = RegExp(
      r'^(?:haritada|haritalarda|konumda)\s+(.+?)\s+(?:ara|bul|göster)$',
    ).firstMatch(stripped);
    if (mapMatch != null) {
      final q = mapMatch.group(1)!.trim();
      final url =
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(q)}';
      final ok = await DeviceBridge.openUrl(url);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '🗺️ Haritada **"$q"** açılıyor.'
            : 'Harita uygulaması açılamadı.',
        actionBanner: '🗺️ Harita: $q',
      );
    }

    // 8. Full Android Phone Hardware & System Controls
    final flashMatch = RegExp(
      r'^(?:el\s+)?fener(?:i|ini)?\s+(aç|yak|açar mısın|açsana|kapat|söndür|kapatır mısın|kapatsana)$',
    ).firstMatch(stripped);
    if (flashMatch != null) {
      final on = const {'aç', 'yak', 'açar mısın', 'açsana'}.contains(
        flashMatch.group(1),
      );
      final ok = await DeviceBridge.setFlashlight(on);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? (on ? '🔦 El feneri açıldı.' : '🔦 El feneri kapatıldı.')
            : (on
                  ? 'El feneri bu cihazda veya mevcut durumda açılamadı.'
                  : 'El feneri kapatılamadı.'),
        actionBanner: ok ? (on ? '🔦 El feneri açık' : '🔦 El feneri kapalı') : null,
      );
    }
    if (const [
      'feneri aç',
      'el fenerini aç',
      'flaşı aç',
      'ışığı aç',
    ].contains(stripped)) {
      final ok = await DeviceBridge.setFlashlight(true);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '🔦 El feneri açıldı.'
            : 'El feneri bu cihazda veya mevcut durumda açılamadı.',
        actionBanner: ok ? '🔦 El feneri açık' : null,
      );
    }
    if (const [
      'feneri kapat',
      'el fenerini kapat',
      'flaşı kapat',
      'ışığı kapat',
    ].contains(stripped)) {
      final ok = await DeviceBridge.setFlashlight(false);
      return LocalCommandOutcome(
        handled: true,
        reply: ok ? '🔦 El feneri kapatıldı.' : 'El feneri kapatılamadı.',
        actionBanner: ok ? '🔦 El feneri kapalı' : null,
      );
    }

    // Volume shortcuts
    if (const ['sesi kapat', 'sessize al', 'sesi sıfırla'].contains(stripped)) {
      final ok = await DeviceBridge.setVolumeLevel(stream: 'media', percent: 0);
      return LocalCommandOutcome(
        handled: true,
        reply: ok ? '🔇 Medya sesi kapatıldı.' : 'Ses seviyesi ayarlanamadı.',
        actionBanner: ok ? '🔇 Medya sesi %0' : null,
      );
    }
    if (const [
      'sesi fulle',
      'sesi sonuna kadar aç',
      'sesi en yükseğe al',
    ].contains(stripped)) {
      final ok = await DeviceBridge.setVolumeLevel(
        stream: 'media',
        percent: 100,
      );
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '🔊 Medya sesi %100 yapıldı.'
            : 'Ses seviyesi ayarlanamadı.',
        actionBanner: ok ? '🔊 Medya sesi %100' : null,
      );
    }
    final volMatch = RegExp(
      r'^(?:medya\s+|zil\s+|alarm\s+)?sesi(?:ni)?\s+%?(\d{1,3})[\u0027]?(?:e|a|ye|ya)?\s*(?:yap|ayarla|getir|çek|aç)$',
    ).firstMatch(stripped);
    if (volMatch != null) {
      final pct = int.parse(volMatch.group(1)!).clamp(0, 100);
      final stream = stripped.startsWith('zil ')
          ? 'ring'
          : stripped.startsWith('alarm ')
          ? 'alarm'
          : 'media';
      final ok = await DeviceBridge.setVolumeLevel(
        stream: stream,
        percent: pct,
      );
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '🔊 ${stream == 'ring'
                  ? 'Zil'
                  : stream == 'alarm'
                  ? 'Alarm'
                  : 'Medya'} sesi %$pct olarak ayarlandı.'
            : 'Ses ayarlanamadı.',
        actionBanner: ok ? '🔊 Ses: %$pct' : null,
      );
    }

    // Media control shortcuts
    if (const [
      'müziği durdur',
      'müziği duraklat',
      'şarkıyı durdur',
      'oynatmayı durdur',
    ].contains(stripped)) {
      final ok = await DeviceBridge.controlMedia('play_pause');
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '⏯️ Medya oynatma/duraklatma komutu gönderildi.'
            : 'Medya denetimi başarısız.',
        actionBanner: ok ? '⏯️ Medya Duraklat/Oynat' : null,
      );
    }
    if (const [
      'müziği başlat',
      'müziği oynat',
      'şarkıyı oynat',
    ].contains(stripped) || (stripped == 'devam et' && _mediaActive(delegate))) {
      final ok = await DeviceBridge.controlMedia('play');
      return LocalCommandOutcome(
        handled: true,
        reply: ok ? '▶️ Medya oynatılıyor.' : 'Medya denetimi başarısız.',
        actionBanner: ok ? '▶️ Oynat' : null,
      );
    }
    if (const [
      'sonraki şarkı',
      'şarkıyı geç',
      'sonraki parça',
    ].contains(stripped)) {
      final ok = await DeviceBridge.controlMedia('next');
      return LocalCommandOutcome(
        handled: true,
        reply: ok ? '⏭️ Sonraki parçaya geçildi.' : 'Medya denetimi başarısız.',
        actionBanner: ok ? '⏭️ Sonraki' : null,
      );
    }
    if (const ['önceki şarkı', 'önceki parça'].contains(stripped)) {
      final ok = await DeviceBridge.controlMedia('previous');
      return LocalCommandOutcome(
        handled: true,
        reply: ok ? '⏮️ Önceki parçaya dönüldü.' : 'Medya denetimi başarısız.',
        actionBanner: ok ? '⏮️ Önceki' : null,
      );
    }

    // System Settings Panels
    final settingsTargets = <String, String>{
      'wifi ayarlarını aç': 'wifi',
      'wi-fi ayarlarını aç': 'wifi',
      'internet ayarlarını aç': 'wifi',
      'bluetooth ayarlarını aç': 'bluetooth',
      'konum ayarlarını aç': 'location',
      'gps ayarlarını aç': 'location',
      'ekran ayarlarını aç': 'display',
      'parlaklık ayarlarını aç': 'display',
      'ses ayarlarını aç': 'sound',
      'pil ayarlarını aç': 'battery',
      'batarya ayarlarını aç': 'battery',
      'uygulama ayarlarını aç': 'apps',
      'telefon ayarlarını aç': 'general',
      'sistem ayarlarını aç': 'general',
    };
    if (settingsTargets.containsKey(stripped)) {
      final target = settingsTargets[stripped]!;
      final ok = await DeviceBridge.openSystemSettings(target);
      return LocalCommandOutcome(
        handled: true,
        reply: ok
            ? '⚙️ Sistem ayarları ($target) açılıyor.'
            : 'Ayarlar açılamadı.',
        actionBanner: ok ? '⚙️ Ayarlar: $target' : null,
      );
    }

    // Panels, ringer, brightness, contacts, WhatsApp, clipboard, app management
    final phone = await _tryPhoneManagementCommands(
      raw,
      stripped,
      delegate,
      original: orig,
    );
    if (phone != null) return phone;

    final control = RegExp(
      r'^(.+?) uygulamasında (.+?) (?:düğmesine bas|düğmesine dokun)$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (control != null) {
      final query = foldTr(control.group(1)!.trim());
      final apps = delegate.installedApps.isEmpty
          ? await DeviceBridge.listInstalledApps()
          : delegate.installedApps;
      final matches = apps
          .where((a) => foldTr(a.name) == query || a.packageName == query)
          .toList();
      if (matches.length != 1) {
        return const LocalCommandOutcome(
          handled: true,
          reply: 'Uygulama adı bulunamadı veya belirsiz. Ayarlar → Uygulama kontrolünden seçebilirsin.',
        );
      }
      final result = await DeviceBridge.controlApp(
        packageName: matches.single.packageName,
        action: 'click',
        target: control.group(2)!.trim(),
      );
      return LocalCommandOutcome(handled: true, reply: result);
    }

    // Launch installed Android app ("whatsapp aç", "youtube aç", "instagram uygulamasını aç")
    final appMatch = RegExp(
      r'^([a-z0-9çğıöşü .+-]{2,100}?)(?:\s+uygulamasını)?\s+(?:aç|başlat)$',
    ).firstMatch(stripped);
    if (appMatch != null) {
      final appQuery = appMatch.group(1)!.trim();
      final launched = await DeviceBridge.launchApp(appQuery);
      if (launched != null && launched.isNotEmpty) {
        return LocalCommandOutcome(
          handled: true,
          reply: '🚀 **$launched** açılıyor.',
          actionBanner: '🚀 $launched',
        );
      }
    }

    return const LocalCommandOutcome(handled: false);
  }

  static Future<String?> executeStructuredAction(
    Map<String, dynamic> action,
    MobileStateDelegate delegate,
  ) async {
    final type = action['type']?.toString() ?? '';
    switch (type) {
      case 'flashlight':
        final enabled = action['enabled'] == true || action['on'] == true;
        final ok = await DeviceBridge.setFlashlight(enabled);
        if (!ok) return null;
        return enabled ? '🔦 El feneri açıldı' : '🔦 El feneri kapatıldı';
      case 'launch_app':
        final q = (action['app'] ?? action['query'] ?? '').toString().trim();
        if (q.isEmpty) return null;
        final launched = await DeviceBridge.launchApp(q);
        return launched != null ? '🚀 $launched açıldı' : null;
      case 'open_settings':
        final target = action['target']?.toString() ?? 'general';
        final ok = await DeviceBridge.openSystemSettings(target);
        return ok ? '⚙️ Ayarlar açıldı ($target)' : null;
      case 'set_volume':
        final stream = action['stream']?.toString() ?? 'media';
        final pct = _asNum(action['percent'])?.toInt() ?? 50;
        final ok = await DeviceBridge.setVolumeLevel(
          stream: stream,
          percent: pct.clamp(0, 100),
        );
        return ok ? '🔊 Ses %${pct.clamp(0, 100)} ($stream)' : null;
      case 'control_media':
        final act = action['action']?.toString() ?? 'play_pause';
        final ok = await DeviceBridge.controlMedia(act);
        return ok ? '⏯️ Medya komutu: $act' : null;
      case 'set_alarm':
        final hNum = _asNum(action['hour'])?.toInt();
        if (hNum == null || hNum < 0 || hNum > 23) {
          return 'Alarm saatini anlayamadım.';
        }
        final h = hNum;
        final m = (_asNum(action['minute'])?.toInt() ?? 0).clamp(0, 59);
        final msg = action['message']?.toString().trim() ?? 'Ege Alarm';
        final ok = await DeviceBridge.setSystemAlarm(
          hour: h,
          minute: m,
          message: msg,
        );
        final hh = h.toString().padLeft(2, '0');
        final mm = m.toString().padLeft(2, '0');
        return ok ? '⏰ Sistem alarmı: $hh:$mm ($msg)' : null;
      case 'add_calendar_event':
        final title = action['title']?.toString().trim() ?? 'Etkinlik';
        final desc = action['description']?.toString() ?? '';
        final iso = action['startIso']?.toString();
        final start =
            (iso != null ? DateTime.tryParse(iso) : null) ??
            DateTime.now().add(const Duration(hours: 1));
        final ok = await DeviceBridge.addCalendarEvent(
          title: title,
          description: desc,
          start: start,
        );
        return ok ? '📅 Takvim: $title' : null;
      case 'send_sms':
        final numStr = (action['number']?.toString() ?? '').replaceAll(
          RegExp(r'[^0-9+*#]'),
          '',
        );
        if (numStr.isEmpty) return null;
        final body = action['body']?.toString() ?? '';
        final uri = body.isEmpty
            ? 'smsto:$numStr'
            : 'smsto:$numStr?body=${Uri.encodeQueryComponent(body)}';
        final okSms = await DeviceBridge.openUrl(uri);
        return okSms
            ? '💬 SMS hazırlandı: $numStr'
            : 'SMS ekranı açılamadı.';
      case 'send_email':
        final to = action['to']?.toString().trim() ?? '';
        final sub = action['subject']?.toString() ?? '';
        final body = action['body']?.toString() ?? '';
        final q = <String, String>{
          if (sub.isNotEmpty) 'subject': sub,
          if (body.isNotEmpty) 'body': body,
        };
        final mailUri = Uri(
          scheme: 'mailto',
          path: to,
          queryParameters: q.isEmpty ? null : q,
        ).toString();
        final okMail = await DeviceBridge.openUrl(mailUri);
        return okMail
            ? '📧 E-posta açıldı${to.isNotEmpty ? ': $to' : ''}'
            : 'E-posta uygulaması açılamadı.';
      case 'show_notification':
        final title = action['title']?.toString() ?? 'Ege';
        final body = action['body']?.toString() ?? '';
        final ok = await DeviceBridge.showNotification(
          title: title,
          body: body,
        );
        return ok ? '🔔 Bildirim: $title' : null;
      case 'open_url':
        final url = action['url']?.toString() ?? '';
        final ok = await DeviceBridge.openUrl(url);
        return ok ? '🌐 Bağlantı açıldı: $url' : null;
      case 'youtube_search':
        final q = action['query']?.toString() ?? '';
        if (q.isEmpty) return null;
        final result = await DeviceBridge.openYouTube(query: q);
        return result == 'unavailable'
            ? 'YouTube araması açılamadı.'
            : 'YouTube araması açılıyor: $q';
      case 'google_search':
        final q = action['query']?.toString() ?? '';
        if (q.isEmpty) return null;
        final okG = await DeviceBridge.openUrl(
          'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}',
        );
        return okG ? '🔍 Google araması: $q' : 'Google araması açılamadı.';
      case 'map_search':
        final q = action['query']?.toString() ?? '';
        if (q.isEmpty) return null;
        final okM = await DeviceBridge.openUrl(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(q)}',
        );
        return okM ? '🗺️ Harita: $q' : 'Harita açılamadı.';
      case 'create_timer':
        final sec = _asNum(action['seconds'])?.toInt() ?? 0;
        final label = action['label']?.toString().trim() ?? 'Zamanlayıcı';
        if (sec < 1 || sec > 7 * 24 * 3600) return null;
        final t = await delegate.addTimer(sec, label);
        return '⏰ Zamanlayıcı kuruldu: ${t.label} (${formatDurationTr(sec)})';
      case 'add_note':
        final text = action['content']?.toString().trim() ?? '';
        if (text.isEmpty) return null;
        await delegate.appendToActiveNote(text);
        return '📝 Not defterine kaydedildi.';
      case 'dial_phone':
        final numStr = (action['number']?.toString() ?? '').replaceAll(
          RegExp(r'[^0-9+*#]'),
          '',
        );
        if (numStr.isEmpty) return null;
        final okTel = await DeviceBridge.openUrl('tel:$numStr');
        return okTel
            ? '📞 Arama ekranı açıldı: $numStr'
            : 'Arama ekranı açılamadı.';
      case 'call_contact':
        final who = action['name']?.toString().trim() ?? '';
        if (who.isEmpty) return null;
        for (final cand in nameCandidates(normalizeTr(who))) {
          final contacts = await DeviceBridge.searchContacts(cand, limit: 1);
          if (contacts.isNotEmpty) {
            await DeviceBridge.dialNumber(contacts.first.phone);
            return '📞 ${contacts.first.name} aranıyor';
          }
        }
        return '📞 Rehberde "$who" bulunamadı';
      case 'whatsapp_message':
        final text =
            action['text']?.toString() ?? action['body']?.toString() ?? '';
        var number = action['number']?.toString() ?? '';
        final name = action['name']?.toString() ?? '';
        if (number.isEmpty && name.isNotEmpty) {
          final contacts = await DeviceBridge.searchContacts(name, limit: 1);
          if (contacts.isNotEmpty) number = contacts.first.phone;
        }
        final waUrl = number.isEmpty
            ? 'https://wa.me/?text=${Uri.encodeComponent(text)}'
            : 'https://wa.me/${waNumber(number)}?text=${Uri.encodeComponent(text)}';
        final ok = await DeviceBridge.openUrl(waUrl);
        return ok ? '💬 WhatsApp mesajı hazırlandı' : null;
      case 'share_text':
        final text = action['text']?.toString() ?? '';
        if (text.isEmpty) return null;
        final ok = await DeviceBridge.shareText(text);
        return ok ? '📤 Paylaşım ekranı açıldı' : null;
      case 'clipboard_copy':
        final text = action['text']?.toString() ?? '';
        if (text.isEmpty) return null;
        await Clipboard.setData(ClipboardData(text: text));
        return '📋 Panoya kopyalandı';
      case 'vibrate':
        final ms = _asNum(action['ms'])?.toInt() ?? 400;
        await DeviceBridge.vibrate(ms: ms.clamp(50, 3000));
        return '📳 Titreşim';
      case 'open_panel':
        final panel = action['panel']?.toString() ?? 'internet';
        final ok = await DeviceBridge.openSettingsPanel(panel);
        return ok ? '⚙️ Panel açıldı ($panel)' : null;
      case 'set_brightness':
        final pct = (_asNum(action['percent'])?.toInt() ?? 50).clamp(0, 100);
        final res = await DeviceBridge.setBrightness(pct);
        return res == 'OK'
            ? '🔆 Parlaklık %$pct'
            : res == 'PERMISSION_NEEDED'
            ? '🔆 Parlaklık izni gerekiyor (ayar ekranı açıldı)'
            : null;
      case 'ringer_mode':
        final mode = action['mode']?.toString() ?? 'normal';
        final res = await DeviceBridge.setRingerMode(mode);
        return res == 'OK'
            ? '🔔 Zil modu: $mode'
            : res == 'PERMISSION_NEEDED'
            ? '🔔 Rahatsız Etmeyin erişimi gerekiyor (ayar ekranı açıldı)'
            : null;
      case 'app_info':
      case 'uninstall_app':
        final q = (action['app'] ?? action['package'] ?? '').toString();
        final app = findApp(delegate.installedApps, q);
        final pkg = app?.packageName ?? (q.contains('.') ? q : '');
        if (pkg.isEmpty) return null;
        final ok = type == 'app_info'
            ? await DeviceBridge.openAppInfo(pkg)
            : await DeviceBridge.uninstallApp(pkg);
        final label = app?.name ?? pkg;
        return ok
            ? (type == 'app_info'
                  ? 'ℹ️ $label bilgileri'
                  : '🗑️ $label kaldırma ekranı')
            : null;
      case 'play_store':
        final q = (action['query'] ?? action['app'] ?? '').toString().trim();
        if (q.isEmpty) return null;
        final ok = await DeviceBridge.openPlayStore(q);
        return ok ? '🛒 Play Store: $q' : null;
      case 'download_file':
        final url = action['url']?.toString() ?? '';
        if (url.isEmpty) return null;
        return await delegate.downloadFile(
          url,
          fileName: action['fileName']?.toString(),
        );
      case 'download_video':
        final url = action['url']?.toString() ?? '';
        if (url.isEmpty) return null;
        return await delegate.downloadVideo(url);
      case 'deep_research':
        final q = (action['question'] ?? action['query'] ?? '')
            .toString()
            .trim();
        if (q.isEmpty) return null;
        return await delegate.startDeepResearch(q);
      default:
        return null;
    }
  }

  /// Son extractActions çağrısında çözülemeyen MOBILE_ACTION gövdeleri için hata metinleri.
  static List<String> lastActionParseErrors = <String>[];

  /// JSON dizelerindeki geçersiz kaçışları ve ham satır sonlarını onarır.
  static String _repairJson(String src) {
    const bs = r'\';
    final sb = StringBuffer();
    var inStr = false;
    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      if (!inStr) {
        if (c == '"') inStr = true;
        sb.write(c);
        continue;
      }
      if (c == '"') {
        inStr = false;
        sb.write(c);
      } else if (c == bs) {
        final n = i + 1 < src.length ? src[i + 1] : '';
        if (n.isNotEmpty && '"\\/bfnrt'.contains(n)) {
          sb.write(c);
          sb.write(n);
          i++;
        } else if (n == 'u' &&
            i + 6 <= src.length &&
            RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(src.substring(i + 2, i + 6))) {
          sb.write(src.substring(i, i + 6));
          i += 5;
        } else {
          sb.write(bs);
          sb.write(bs);
        }
      } else if (c == '\n') {
        sb.write(bs);
        sb.write('n');
      } else if (c == '\r') {
        sb.write(bs);
        sb.write('r');
      } else if (c == '\t') {
        sb.write(bs);
        sb.write('t');
      } else {
        sb.write(c);
      }
    }
    return sb.toString();
  }

  static final _projectTag = RegExp(
    r'<(create_?project)>([\s\S]*?)</\1>', caseSensitive: false,
  );

  static List<Map<String, dynamic>> extractActions(String raw) =>
      extractActionsDetailed(raw).actions;

  static ({List<Map<String, dynamic>> actions, List<String> errors})
  extractActionsDetailed(String raw) {
    raw = raw.replaceAllMapped(_projectTag, (match) {
      try {
        final fields = jsonDecode(match.group(2)!);
        if (fields is Map<String, dynamic>) {
          return '<MOBILE_ACTION>${jsonEncode({...fields, 'type': 'create_project'})}</MOBILE_ACTION>';
        }
      } on FormatException {
        // Keep malformed payloads visible to the caller.
      }
      return match.group(0)!;
    });
    final matches = RegExp(
      r'<MOBILE_ACTION>([\s\S]*?)</MOBILE_ACTION>',
      caseSensitive: false,
    ).allMatches(raw);
    final out = <Map<String, dynamic>>[];
    final errors = <String>[];
    for (final m in matches) {
      final body = m.group(1)!.trim();
      Object? decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        try {
          decoded = jsonDecode(_repairJson(body));
        } catch (e) {
          final short = body.length > 80 ? '${body.substring(0, 80)}…' : body;
          errors.add('MOBILE_ACTION JSON çözülemedi: $short');
          continue;
        }
      }
      if (decoded is Map<String, dynamic>) {
        out.add(decoded);
      } else {
        errors.add('MOBILE_ACTION bir JSON nesnesi değil.');
      }
    }
    final lastOpen = raw.toUpperCase().lastIndexOf('<MOBILE_ACTION>');
    final lastClose = raw.toUpperCase().lastIndexOf('</MOBILE_ACTION>');
    if (lastOpen >= 0 && lastClose < lastOpen) {
      errors.add('MOBILE_ACTION etiketi kapatılmamış.');
    }
    lastActionParseErrors = errors;
    return (actions: out, errors: errors);
  }

  static String stripActionTags(String raw) {
    return raw.replaceAll(_projectTag, '')
        .replaceAll(
          RegExp(
            r'<MOBILE_ACTION>[\s\S]*?</MOBILE_ACTION>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'<MOBILE_ACTION>[\s\S]*$', caseSensitive: false),
          '',
        )
        .trim();
  }

  static String newId() => _uuid.v4();
}

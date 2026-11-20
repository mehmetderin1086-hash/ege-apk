import 'dart:math' as math;

import '../models/jarvis_models.dart';
import 'device_bridge.dart';
import 'local_command_engine.dart';

/// Sesli komut katmanı (Ege 3.0).
///
/// Whisper komutları "Saat yedi buçuğa alarm kur." gibi yazıyla, noktalı ve
/// büyük harfle verir. Eski motor yalnız rakamlı ve noktasız kalıpları
/// tanıdığı için en sık kullanılan telefon komutları (alarm, ses, arama,
/// uygulama açma, saat...) yapay zekâya gidiyordu. Bu katman Türkçe sayı /
/// saat sözcüklerini çözer ve bu komutları doğrudan, internetsiz yürütür.

// ============================================================ SAYILAR

class TrNumbers {
  static const _units = {
    'sıfır': 0,
    'bir': 1,
    'iki': 2,
    'üç': 3,
    'dört': 4,
    'dörd': 4,
    'beş': 5,
    'altı': 6,
    'yedi': 7,
    'sekiz': 8,
    'dokuz': 9,
  };
  static const _tens = {
    'on': 10,
    'yirmi': 20,
    'otuz': 30,
    'kırk': 40,
    'elli': 50,
    'altmış': 60,
    'yetmiş': 70,
    'seksen': 80,
    'doksan': 90,
  };
  static const _suffixes = [
    '',
    'e',
    'a',
    'ye',
    'ya',
    'de',
    'da',
    'te',
    'ta',
    'den',
    'dan',
    'ten',
    'tan',
    'i',
    'ı',
    'u',
    'ü',
    'yi',
    'yı',
    'yu',
    'yü',
    'lık',
    'lik',
    'luk',
    'lük',
    'er',
    'ar',
    'şer',
    'şar',
    'ncı',
    'nci',
    'ncu',
    'ncü',
    'inci',
    'ıncı',
    'uncu',
    'üncü',
  ];
  static const _unitWords = {
    'saniye',
    'saniyelik',
    'dakika',
    'dakikalık',
    'saat',
    'saatlik',
    'gün',
    'günlük',
    'hafta',
    'haftalık',
    'ay',
    'yıl',
    'kere',
    'kez',
    'buçuk',
    'tane',
    'adet',
    'kişi',
  };

  /// (değer, ek) ya da null. "yediye" → (7, "ye"), "dörde" → (4, "e").
  static (int, String, bool isTen, bool isHundred, bool isThousand)? _word(
    String token,
  ) {
    for (final entry in [
      ..._units.entries,
      ..._tens.entries,
      const MapEntry('yüz', 100),
      const MapEntry('bin', 1000),
    ]) {
      final stem = entry.key;
      if (!token.startsWith(stem)) continue;
      final rest = token.substring(stem.length);
      if (!_suffixes.contains(rest)) continue;
      // "yüzü/yüzünü" (yüz = surat) ve "on" + ünlü ekleri riskli; yalnız güvenli ekler.
      if (stem == 'yüz' &&
          const ['i', 'ı', 'u', 'ü', 'de', 'den'].contains(rest)) {
        continue;
      }
      if (stem == 'on' &&
          const ['u', 'ü', 'i', 'ı', 'ar', 'er', 'a', 'e'].contains(rest)) {
        continue;
      }
      if (stem == 'altı' &&
          rest.isNotEmpty &&
          !const ['ya', 'da', 'dan', 'yı', 'lık', 'şar', 'ncı'].contains(rest)) {
        continue;
      }
      return (
        entry.value,
        rest,
        _tens.containsKey(stem),
        stem == 'yüz',
        stem == 'bin',
      );
    }
    return null;
  }

  /// [start]'tan başlayan dakika (10-59: onluk + isteğe bağlı birlik) →
  /// (dakika, ek, sonraki indeks) ya da null.
  static (int, String, int)? _minuteAt(List<String> tokens, int start) {
    if (start >= tokens.length) return null;
    final a = _word(tokens[start]);
    if (a == null || !a.$3 || a.$1 > 50) return null;
    if (a.$2.isNotEmpty) return (a.$1, a.$2, start + 1);
    if (start + 1 < tokens.length) {
      final b = _word(tokens[start + 1]);
      if (b != null && !b.$3 && !b.$4 && !b.$5 && b.$1 >= 1 && b.$1 <= 9) {
        return (a.$1 + b.$1, b.$2, start + 2);
      }
    }
    return (a.$1, '', start + 1);
  }

  /// Metindeki Türkçe sayı sözcüklerini rakama çevirir ("yirmi beşe" →
  /// "25'e", "yüzde elli" → "%50", "yedi buçuk" → "7:30").
  static String normalize(String input) {
    final tokens = input.split(' ');
    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      final first = _word(tokens[i]);
      if (first == null) {
        out.add(tokens[i]);
        i++;
        continue;
      }
      // "bir" çoğu zaman belirsiz tanımlıktır ("bir şarkı çal"): yalnız birim
      // sözcüğünden önce ya da bileşik sayının parçasıyken sayı say.
      if (tokens[i] == 'bir') {
        final next = i + 1 < tokens.length ? tokens[i + 1] : '';
        if (!_unitWords.contains(next) &&
            !_unitWords.any((u) => next.startsWith(u))) {
          out.add(tokens[i]);
          i++;
          continue;
        }
      }
      var total = 0;
      var current = 0;
      var suffix = '';
      var j = i;
      var brokeInvalid = false;
      while (j < tokens.length) {
        final w = _word(tokens[j]);
        if (w == null) break;
        final (v, suf, isTen, isHundred, isThousand) = w;
        if (isHundred) {
          current = (current == 0 ? 1 : current) * 100;
        } else if (isThousand) {
          total += (current == 0 ? 1 : current) * 1000;
          current = 0;
        } else {
          // Onluk/birlik yalnız boş basamağa eklenir: "yirmi beş" → 25,
          // "yedi otuz" / "beş beş" → ayrı sayılar.
          final validAdd = isTen
              ? current % 100 == 0
              : (current % 10 == 0 && (current % 100 == 0 || current % 100 >= 10));
          if (!validAdd) {
            brokeInvalid = true;
            break;
          }
          current += v;
        }
        j++;
        if (suf.isNotEmpty) {
          suffix = suf;
          break;
        }
      }
      final value = total + current;
      var text = '$value';
      // "yedi otuz(da)" / "saat sekiz kırk beş(te)" → saat 7:30 / 8:45
      if (brokeInvalid && total == 0 && value >= 1 && value <= 24) {
        final min = _minuteAt(tokens, j);
        if (min != null) {
          final prevSaat = i > 0 && tokens[i - 1] == 'saat';
          final hasTimeSuffix = const [
            'e', 'a', 'ye', 'ya', 'de', 'da', 'te', 'ta',
          ].contains(min.$2);
          if (prevSaat || hasTimeSuffix) {
            final mm = min.$1.toString().padLeft(2, '0');
            final t = '$value:$mm';
            out.add(min.$2.isEmpty ? t : "$t'${min.$2}");
            i = min.$3;
            continue;
          }
        }
      }
      // "buçuk" ekle: "yedi buçuk" → 7:30, "yedi buçukta" → 7:30'da;
      // süre/işlem bağlamında ondalık: "bir buçuk saat" → 1,5
      if (j < tokens.length && tokens[j].startsWith('buçu') && suffix.isEmpty) {
        final b = tokens[j];
        final bSuf = b.startsWith('buçuk')
            ? b.substring(5)
            : (b.startsWith('buçuğ') ? b.substring(5) : '');
        final next = j + 1 < tokens.length ? tokens[j + 1] : '';
        final decimalCtx = bSuf.isEmpty &&
            (RegExp(r'^(?:saat|dakika|gün|hafta)').hasMatch(next) ||
                const ['çarpı', 'artı', 'eksi', 'bölü', 'kere', 'kez']
                    .contains(next));
        final prevSaat = i > 0 && tokens[i - 1] == 'saat';
        if (decimalCtx && !prevSaat) {
          text = '$value,5';
        } else {
          text = value <= 24 ? '$value:30' : '$value,5';
        }
        suffix = bSuf;
        j++;
      }
      out.add(suffix.isEmpty ? text : "$text'$suffix");
      i = j;
    }
    return out
        .join(' ')
        .replaceAllMapped(RegExp(r"\byüzde\s+(\d+)"), (m) => '%${m.group(1)}')
        .replaceAllMapped(RegExp(r'%\s+(\d+)'), (m) => '%${m.group(1)}');
  }
}

// ============================================================ SAAT

class TrClock {
  /// Alarm cümlesinden saat çıkarır: "yarın sabah 7:30'da", "akşam 8'de",
  /// "7'yi çeyrek geçe", "8'e çeyrek var", "saat 6". Sayılar önceden
  /// [TrNumbers.normalize] ile rakama çevrilmiş olmalı.
  static ({int hour, int minute})? parse(String t) {
    int? h;
    var m = 0;
    final hm = RegExp(r"(\d{1,2})[:.](\d{2})").firstMatch(t);
    final quarterPast = RegExp(
      r"(\d{1,2})['’]?(?:i|ı|u|ü|yi|yı|yu|yü)?\s+çeyrek\s+geçe",
    ).firstMatch(t);
    final quarterTo = RegExp(r"(\d{1,2})['’]?(?:e|a|ye|ya)?\s+çeyrek\s+(?:var|kala)")
        .firstMatch(t);
    final minPast = RegExp(
      r"(\d{1,2})['’]?(?:i|ı|u|ü|yi|yı|yu|yü)\s+(\d{1,2})\s+geçe",
    ).firstMatch(t);
    final minTo = RegExp(r"(\d{1,2})['’]?(?:e|a|ye|ya)\s+(\d{1,2})\s+(?:var|kala)")
        .firstMatch(t);
    final halfPast = RegExp(r"(\d{1,2})\s+buçu[kğ]").firstMatch(t);
    if (hm != null) {
      h = int.parse(hm.group(1)!);
      m = int.parse(hm.group(2)!);
    } else if (halfPast != null) {
      h = int.parse(halfPast.group(1)!);
      m = 30;
    } else if (quarterPast != null) {
      h = int.parse(quarterPast.group(1)!);
      m = 15;
    } else if (quarterTo != null) {
      h = (int.parse(quarterTo.group(1)!) + 23) % 24;
      m = 45;
    } else if (minPast != null) {
      h = int.parse(minPast.group(1)!);
      m = int.parse(minPast.group(2)!);
    } else if (minTo != null) {
      h = (int.parse(minTo.group(1)!) + 23) % 24;
      m = 60 - int.parse(minTo.group(2)!);
    } else {
      final bare =
          RegExp(
                r"(?:saat\s+)?(\d{1,2})(?:['’]?(?:e|a|ye|ya|de|da|te|ta|i|ı|u|ü|yi|yı))?(?=\s|$)",
              )
              .allMatches(t)
              .where(
                (x) =>
                    !RegExp(r'^\d+\s+(?:dakika|saniye|saat\s+sonra)')
                        .hasMatch(t.substring(x.start)),
              )
              .toList();
      if (bare.isNotEmpty) h = int.parse(bare.first.group(1)!);
    }
    if (h == null || h < 0 || h > 24 || m < 0 || m > 59) return null;
    if (h == 24) h = 0;
    final pm = RegExp(r'(?<![a-zçğıöşüâîû0-9])(akşam|öğleden sonra|ikindi)')
        .hasMatch(t);
    final night = RegExp(r'\bgece\b').hasMatch(t);
    final noon = RegExp(
      r'(?<![a-zçğıöşüâîû0-9])öğle(?:n|yin)?(?![a-zçğıöşüâîû0-9])',
    ).hasMatch(t);
    if (pm && h < 12) h += 12;
    if (night && h >= 8 && h < 12) h += 12;
    if (night && h == 12) h = 0;
    if (noon && h < 6) h += 12;
    return (hour: h, minute: m);
  }

  /// Tekrar sözcükleri → Calendar gün numaraları (1=Pazar … 7=Cumartesi).
  /// Tekrar yoksa boş liste.
  static List<int> recurrenceDays(String t) {
    if (RegExp(r'\bher\s*gün\b').hasMatch(t)) {
      return const [1, 2, 3, 4, 5, 6, 7];
    }
    if (RegExp(r'\bhafta\s*içi\b').hasMatch(t)) return const [2, 3, 4, 5, 6];
    if (RegExp(r'\bhafta\s*sonu\b').hasMatch(t)) return const [7, 1];
    final days = <int>{};
    if (RegExp(r'\bher\b').hasMatch(t)) {
      final names = <String, int>{
        r'pazartesi': 2,
        r'salı': 3,
        r'çarşamba': 4,
        r'perşembe': 5,
        r'cuma(?!rtesi)': 6,
        r'cumartesi': 7,
        r'pazar(?!tesi)': 1,
      };
      names.forEach((pat, d) {
        if (RegExp('(?<![a-zçğıöşüâîû])$pat').hasMatch(t)) days.add(d);
      });
    }
    final list = days.toList()..sort();
    return list;
  }

  static String fmt(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

// ============================================================ HESAP

class TrCalc {
  /// "245 çarpı 18", "100 bölü 4 artı 3", "144'ün karekökü" → sonuç.
  static double? evaluate(String t) {
    var e = t
        .replaceAll(
          RegExp(
            r'(?<![a-zçğıöşüâîû0-9])(hesapla|kaç eder|kaçtır|kaç|sonucu|nedir|eşittir|ne eder)(?![a-zçğıöşüâîû0-9])',
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'(?<![a-zçğıöşüâîû0-9])artı(?![a-zçğıöşüâîû0-9])'),
          '+',
        )
        .replaceAll(
          RegExp(r'(?<![a-zçğıöşüâîû0-9])eksi(?![a-zçğıöşüâîû0-9])'),
          '-',
        )
        .replaceAll(
          RegExp(
            r'(?<![a-zçğıöşüâîû0-9])(çarpı|kere|kez|x)(?![a-zçğıöşüâîû0-9])',
          ),
          '*',
        )
        .replaceAll(
          RegExp(r'(?<![a-zçğıöşüâîû0-9])(bölü|bölünür)(?![a-zçğıöşüâîû0-9])'),
          '/',
        )
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAllMapped(
          RegExp(r"(\d+(?:[.,]\d+)?)['’]?[a-zçğıöşü]*\s+karekökü"),
          (m) => 'sqrt(${m.group(1)})',
        )
        .replaceAllMapped(
          RegExp(r"(\d+(?:[.,]\d+)?)['’]?[a-zçğıöşü]*\s+karesi"),
          (m) => '(${m.group(1)})^2',
        )
        .replaceAll(
          RegExp(r'(?<![a-zçğıöşüâîû0-9])üzeri(?![a-zçğıöşüâîû0-9])'),
          '^',
        )
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'\s+'), '');
    if (e.isEmpty || !RegExp(r'^[0-9+\-*/^().sqrt]+$').hasMatch(e)) return null;
    if (!RegExp(r'[+\-*/^]|sqrt').hasMatch(e)) return null;
    try {
      final p = _Parser(e);
      final v = p.expr();
      if (p.pos != e.length || v.isNaN || v.isInfinite) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  static String format(double v) {
    // Kayan nokta artığını at: 434.99999999999994 → 435
    if (v.isFinite && v != 0) {
      v = double.parse(v.toStringAsPrecision(10));
    }
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      final s = v.toInt().toString();
      return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    }
    return v
        .toStringAsFixed(4)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'[.,]$'), '')
        .replaceAll('.', ',');
  }
}

class _Parser {
  _Parser(this.s);
  final String s;
  int pos = 0;

  double expr() {
    var v = term();
    while (pos < s.length && (s[pos] == '+' || s[pos] == '-')) {
      final op = s[pos++];
      final r = term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double term() {
    var v = power();
    while (pos < s.length && (s[pos] == '*' || s[pos] == '/')) {
      final op = s[pos++];
      final r = power();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double power() {
    final b = unary();
    if (pos < s.length && s[pos] == '^') {
      pos++;
      return math.pow(b, power()).toDouble();
    }
    return b;
  }

  double unary() {
    if (pos < s.length && s[pos] == '-') {
      pos++;
      return -unary();
    }
    return atom();
  }

  double atom() {
    if (s.startsWith('sqrt(', pos)) {
      pos += 5;
      final v = expr();
      if (pos >= s.length || s[pos] != ')') throw const FormatException();
      pos++;
      return math.sqrt(v);
    }
    if (pos < s.length && s[pos] == '(') {
      pos++;
      final v = expr();
      if (pos >= s.length || s[pos] != ')') throw const FormatException();
      pos++;
      return v;
    }
    final start = pos;
    while (pos < s.length && RegExp(r'[0-9.]').hasMatch(s[pos])) {
      pos++;
    }
    if (start == pos) throw const FormatException();
    return double.parse(s.substring(start, pos));
  }
}

// ============================================================ KOMUTLAR

/// Komutların ihtiyaç duyduğu uygulama durumu (JarvisController uygular).
abstract class VoiceCommandHost {
  List<DeviceAppInfo> get installedApps;
  Future<String> runDailyBriefing({bool speak});
  Future<String> askAboutScreen(String question);
  Future<String> readNotifications();
}

class VoiceCommands {
  static Future<LocalCommandOutcome> endCall() async {
    final result = await DeviceBridge.endCall();
    final reply = switch (result) {
      'ENDED' => 'Telefon araması sonlandırıldı; kapandığı doğrulandı.',
      'NO_ACTIVE_CALL' => 'Android telefon sisteminde etkin arama görünmüyor. Uygulama içi görüşmelerde çağrı ekranındaki kapatma kontrolünü kullanabilirim.',
      'PERMISSION_NEEDED' => 'Aramayı kapatmak için telefon durumu ve arama yönetimi izni gerekiyor. Açılan izin penceresini tamamlayıp komutu tekrar söyle.',
      'UNVERIFIED' => 'Kapatma isteği iletildi ancak aramanın sona erdiği doğrulanamadı. Tekrar kapatma işlemi yapmadım.',
      'BUSY' => 'Önceki kapatma isteğinin sonucu kontrol ediliyor.',
      'REJECTED' => 'Android aramayı kapatma isteğini kabul etmedi. Uygulama içi aramalar kendi çağrı ekranından kapatılmalı.',
      _ => 'Arama kapatılamadı; işlemin tamamlandığını doğrulayamadım.',
    };
    return _ok(reply);
  }

  static Future<LocalCommandOutcome> callContact(String who) =>
      _callContact(who);
  static LocalCommandOutcome _ok(String reply, [String? banner]) =>
      LocalCommandOutcome(handled: true, reply: reply, actionBanner: banner);

  /// Komut metnini karşılaştırmaya hazırlar: noktalama, "jarvis" hitabı,
  /// "lütfen", sayı sözcükleri.
  static String prepare(String raw) {
    var t = LocalCommandEngine.normalizeTr(
      LocalCommandEngine.stripEndPunct(raw),
    );
    t = t
        .replaceFirst(RegExp(r'^(?:(?:hey|hi)\s+)?(?:ege|jarvis)(?=\s|[,،]|$)\s*[,،]?\s*'), '')
        .replaceAll(RegExp(r'\blütfen\b|\bacaba\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return TrNumbers.normalize(t);
  }

  static Future<LocalCommandOutcome?> tryHandle(
    String raw,
    VoiceCommandHost host,
  ) async {
    final t = prepare(raw);
    if (t.isEmpty) return null;

    // Olumsuz ya da soru biçimli "nasıl kurulur" türü cümleler yürütülmez.
    if (RegExp(r'\b(nasıl kurulur|nasıl yapılır|ne demek|nedir)\b').hasMatch(t)) {
      return null;
    }

    // ---------------- sabah özeti
    if (RegExp(
      r'^(günaydın|günaydın jarvis|sabah özeti|günün özeti|bugün neler var|güne başlayalım|brifing|günlük özet)$',
    ).hasMatch(t)) {
      return _ok(await host.runDailyBriefing(speak: false), '🌅 Sabah özeti');
    }

    // ---------------- ekran
    if (RegExp(
      r'^(?:ekranda ne var|ekranı (?:açıkla|oku|anlat|özetle)|bu ekranı (?:açıkla|oku|anlat|özetle)|ekrandakini (?:açıkla|oku|anlat|özetle)|ekranda(?:ki)? (?:ne yazıyor|yazanı oku))',
    ).hasMatch(t)) {
      return _ok(await host.askAboutScreen(t), '🖼 Ekran');
    }

    // ---------------- bildirimler
    if (RegExp(
      r'^(?:son\s+)?bildirim(?:ler)?(?:imi|i)?\s+(?:oku|göster|söyle|neler)$|^bildirimlerimde ne var$|^bildirimlerim neler$|^yeni mesaj(?:lar)?ım var mı$',
    ).hasMatch(t)) {
      return _ok(await host.readNotifications(), '🔔 Bildirimler');
    }

    // ---------------- takvim
    final calM = RegExp(
      r'^(?:bugün|yarın|bu hafta)?\s*(?:takvim(?:im)?(?:de|e)?|ajandam(?:da)?|programım(?:da)?)\s*(?:ne var|neler var|nedir|göster|oku)?$|^(?:bugün|yarın)\s+(?:neler var|ne var|programım ne)$',
    ).firstMatch(t);
    if (calM != null &&
        RegExp(r'takvim|ajanda|program|neler var|ne var').hasMatch(t)) {
      final days = t.contains('hafta') ? 7 : (t.contains('yarın') ? 2 : 1);
      final ev = await DeviceBridge.calendarEvents(days: days);
      if (ev == null) {
        return _ok(
          'Takvimini okuyabilmem için izin penceresinde izin ver ve tekrar söyle.',
          '📅',
        );
      }
      final now = DateTime.now();
      final pick = t.contains('yarın')
          ? ev
                .where(
                  (e) =>
                      DateTime.fromMillisecondsSinceEpoch(
                        (e['begin'] as num?)?.toInt() ?? 0,
                      ).day !=
                      now.day,
                )
                .toList()
          : ev;
      if (pick.isEmpty) {
        return _ok(
          t.contains('yarın')
              ? 'Yarın takviminde etkinlik yok.'
              : 'Takviminde etkinlik yok.',
          '📅',
        );
      }
      final lines = pick
          .take(8)
          .map((e) {
            final b = DateTime.fromMillisecondsSinceEpoch(
              (e['begin'] as num?)?.toInt() ?? 0,
            );
            final base = e['allDay'] == true
                ? 'tüm gün'
                : TrClock.fmt(b.hour, b.minute);
            final when = days > 1
                ? '${const ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'][b.weekday - 1]} $base'
                : base;
            return '$when ${e['title']}';
          })
          .join(', ');
      return _ok('${pick.length} etkinlik: $lines.', '📅 Takvim');
    }

    // ---------------- saat / tarih / pil
    if (RegExp(r'^(?:saat kaç|şu an saat kaç|saati söyle|saat kaç oldu)$')
        .hasMatch(t)) {
      final n = DateTime.now();
      return _ok('Saat ${TrClock.fmt(n.hour, n.minute)}.', '🕒');
    }
    if (RegExp(
      r'^(?:bugün (?:günlerden ne|ayın kaçı|hangi gün|tarih ne)|tarih ne|bugünün tarihi|bugün ne günü)$',
    ).hasMatch(t)) {
      return _ok('Bugün ${trDate(DateTime.now())}.', '📅');
    }
    if (RegExp(
      r'^(?:şarjım kaç|şarj kaç|pil kaç|pil yüzde kaç|şarj durumu|şarjım ne kadar|batarya kaç)$',
    ).hasMatch(t)) {
      final m = await DeviceBridge.getDeviceMetrics();
      return _ok(
        m.batteryPct > 0
            ? 'Pil %${m.batteryPct}${m.charging ? ', şarj oluyor' : ''}.'
            : 'Pil durumu okunamadı.',
        '🔋',
      );
    }

    // ---------------- alarm / uyandırma (sistem Saat uygulaması: Ege kapalıyken de çalar)
    final alarmIntent =
        RegExp(
          r'(?:\balarm(?:ı|ını)?\s+(?:kur|ayarla|koy|ekle)|\b(?:beni\s+)?uyandır\b|^alarm\b|\balarm$)',
        ).hasMatch(t) &&
        !RegExp(r'\b(iptal|sil|kapat|durdur|kurma|listele|göster)\b')
            .hasMatch(t) &&
        !RegExp(r'\bm[ıiuü]\b|ne zaman|çaldı').hasMatch(t) &&
        !t.trimRight().endsWith('?');
    if (alarmIntent) {
      final clock = TrClock.parse(t);
      if (clock != null) {
        final label = _alarmLabel(t);
        final ok = await DeviceBridge.setSystemAlarm(
          hour: clock.hour,
          minute: clock.minute,
          message: label,
          days: TrClock.recurrenceDays(t),
        );
        final when =
            '${RegExp(r'\byarın\b').hasMatch(t) ? 'yarın ' : ''}${TrClock.fmt(clock.hour, clock.minute)}';
        return _ok(
          ok
              ? 'Alarm $when için kuruldu.'
              : 'Alarm kurulamadı; Saat uygulaması açılamadı.',
          ok ? '⏰ $when' : null,
        );
      }
    }

    // ---------------- ses düzeyi
    final volRel = RegExp(
      r'^(?:medya\s+)?ses(?:i|in|ini)?\s+(?:(biraz|çok)\s+)?(aç|artır|yükselt|kıs|azalt|düşür|alçalt)(?:\s*(?:(?:ar|er|ır|ir|ur|ür)\s*m[ıiuü]s[ıiuü]n|m[ıiuü]s[ıiuü]n|sana|sene))?$',
    ).firstMatch(t);
    if (volRel != null) {
      final up = const ['aç', 'artır', 'yükselt'].contains(volRel.group(2));
      final step = volRel.group(1) == 'biraz'
          ? 10
          : (volRel.group(1) == 'çok' ? 35 : 20);
      final st = await DeviceBridge.getVolumeState();
      final cur = (st['mediaPct'] as num?)?.toInt() ?? 50;
      final next = (cur + (up ? step : -step)).clamp(0, 100);
      final ok = await DeviceBridge.setVolumeLevel(
        stream: 'media',
        percent: next,
      );
      return _ok(
        ok ? 'Ses %$next.' : 'Ses değiştirilemedi.',
        ok ? '🔊 %$next' : null,
      );
    }
    final volAbs = RegExp(
      r"^(?:medya\s+)?ses(?:i|ini)?\s+%(\d{1,3})(?:['’][a-zçğıöşü]+)?\s*(?:yap|ayarla|getir|çek|aç|olsun)?$",
    ).firstMatch(t);
    if (volAbs != null) {
      final pct = int.parse(volAbs.group(1)!).clamp(0, 100);
      final ok = await DeviceBridge.setVolumeLevel(
        stream: 'media',
        percent: pct,
      );
      return _ok(
        ok ? 'Ses %$pct.' : 'Ses değiştirilemedi.',
        ok ? '🔊 %$pct' : null,
      );
    }

    // ---------------- parlaklık
    final bright = RegExp(
      r"^(?:ekran\s+)?parlaklı(?:k|ğı|ğını)\s+%(\d{1,3})(?:['’][a-zçğıöşü]+)?\s*(?:yap|ayarla|getir|olsun)?$",
    ).firstMatch(t);
    if (bright != null) {
      final pct = int.parse(bright.group(1)!).clamp(0, 100);
      final r = await DeviceBridge.setBrightness(pct);
      return _ok(
        r == 'OK'
            ? 'Parlaklık %$pct.'
            : r == 'PERMISSION_NEEDED'
            ? 'Parlaklık bu ekran için %$pct yapıldı; kalıcı olması için açılan ayarda Ege\'e izin ver.'
            : 'Parlaklık değiştirilemedi.',
        '☀️ %$pct',
      );
    }

    // ---------------- medya
    if (RegExp(r'^(?:müziği|şarkıyı|videoyu)\s+(?:kapat|durdur)$')
        .hasMatch(t)) {
      final ok = await DeviceBridge.controlMedia('pause');
      return _ok(ok ? 'Durduruldu.' : 'Medya durdurulamadı.', '⏸');
    }

    // ---------------- Bluetooth / Wi-Fi / konum / uçak modu (Android doğrudan açtırmaz)
    final radio = RegExp(
      r"^(bluetooth|wi-?fi|wifi|kablosuz|internet|mobil veri|konum|gps|uçak modu|nfc|hotspot|erişim noktası)(?:['’]?[a-zçğıöşü]*)?\s+(?:aç|kapat|açar mısın|kapatır mısın)$",
    ).firstMatch(t);
    if (radio != null) {
      final k = radio.group(1)!;
      final panel = switch (k) {
        'bluetooth' => 'bluetooth',
        'konum' || 'gps' => 'location',
        'uçak modu' => 'airplane',
        'nfc' => 'nfc',
        'hotspot' || 'erişim noktası' => 'hotspot',
        'mobil veri' || 'internet' => 'internet',
        _ => 'wifi',
      };
      final ok = await DeviceBridge.openSettingsPanel(panel);
      return _ok(
        ok
            ? 'Android, uygulamaların bunu doğrudan değiştirmesine izin vermiyor; ayar panelini açtım, tek dokunuşla değiştirebilirsin.'
            : 'Ayar paneli açılamadı.',
        '⚙️ $k',
      );
    }

    // ---------------- telefon ayarları
    if (RegExp(r'^(?:telefon(?:un)?\s+)?ayarlar(?:ı|ını)?\s+(?:aç|göster)$')
        .hasMatch(t)) {
      final ok = await DeviceBridge.openSystemSettings('general');
      return _ok(ok ? 'Ayarlar açıldı.' : 'Ayarlar açılamadı.', '⚙️ Ayarlar');
    }

    // ---------------- yol tarifi / yakındaki yerler
    final nav = RegExp(
      r"^(?:beni\s+)?(.{2,60}?)['’]?(?:e|a|ye|ya|na|ne)?\s+(?:yol tarifi(?: ver)?|nasıl giderim|götür|navigasyon(?:u başlat)?)$",
    ).firstMatch(t);
    final navWhat = nav?.group(1)?.trim() ?? '';
    final navPlaceLike =
        nav != null &&
        navWhat.split(' ').length <= 4 &&
        !RegExp(
          r'(?:^|\s)(?:bu|şu|bunu|şunu|daha|konu|konuyu|ileri|ben|beni|sen|ona|onu|bana|şimdi|biraz)(?:\s|$)',
        ).hasMatch(navWhat);
    if (nav != null &&
            navPlaceLike &&
            !RegExp(r'^(?:eve|işe)$').hasMatch(navWhat) ||
        RegExp(r'^(?:eve|işe) (?:yol tarifi|nasıl giderim|götür)')
            .hasMatch(t)) {
      final dest = navPlaceLike && !RegExp(r'^(?:eve|işe) ').hasMatch(t)
          ? navWhat
          : (t.startsWith('eve') ? 'Ev' : 'İş');
      final ok = await DeviceBridge.openUrl(
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(dest)}&travelmode=driving',
      );
      return _ok(
        ok ? '$dest için yol tarifi açıldı.' : 'Harita açılamadı.',
        '🧭 $dest',
      );
    }
    final near = RegExp(
      r"^(?:bana\s+)?en yakın\s+(eczane|hastane|market|bakkal|benzinci|benzin istasyonu|akaryakıt istasyonu|atm|banka|fırın|okul|cami|restoran|kafe|otopark|polis(?: karakolu)?|noter|postane|acil servis|pastane|kuaför|avm|park|durak|metro(?: istasyonu)?)(?:['’]?(?:yi|yı|i|ı|u|ü|yu|yü|ni|nı|si|sı|su|sü))?\s+(?:nerede|bul|göster|hangisi|neresi)$",
    ).firstMatch(t);
    if (near != null) {
      final what = near.group(1)!.trim();
      final ok = await DeviceBridge.openUrl(
        'geo:0,0?q=${Uri.encodeComponent(what)}',
      );
      return _ok(
        ok ? 'Yakındaki $what yerleri haritada.' : 'Harita açılamadı.',
        '📍 $what',
      );
    }

    // ---------------- hesap makinesi
    if (RegExp(
          r'(?<![a-zçğıöşüâîû0-9])(çarpı|bölü|artı|eksi|karekök|karekökü|karekökünü|kökü|karesi|üzeri|hesapla)(?![a-zçğıöşüâîû0-9])',
        ).hasMatch(t) &&
        RegExp(r'\d').hasMatch(t)) {
      final v = TrCalc.evaluate(t);
      if (v != null) {
        return _ok('Sonuç ${TrCalc.format(v)}.', '🧮 ${TrCalc.format(v)}');
      }
    }

    // ---------------- telefonla arama
    final call =
        RegExp(
          r"^(.{2,40}?)\s+(?:ara|arar mısın|arayabilir misin|telefon et|telefonla ara|ile görüştür|aramayı başlat)$",
        ).firstMatch(t) ??
        RegExp(r'^(?:ara|telefon et)\s+(.{2,40})$').firstMatch(t);
    if (call != null &&
        !RegExp(r'\b(youtube|google|internette|webde|haritada|rehberde)\b')
            .hasMatch(t)) {
      final who = call.group(1)!.trim();
      // Web/şarkı/tarif araması telefon araması sayılmaz; LCE/LLM ele alsın.
      if (_looksLikeCall(who)) return await _callContact(who);
    }

    // ---------------- SMS
    final smsRe1 = RegExp(
      r"^(.{2,30}?)['’]?(?:e|a|ye|ya|ne|na)?\s+(?:sms|mesaj|kısa mesaj)\s+(?:at|gönder|yaz|yolla)\s*[:,-]?\s+(.+)$",
    );
    final smsRe2 = RegExp(
      r"^(.{2,30}?)['’]?(?:e|a|ye|ya|ne|na)\s+(.+?)\s+diye\s+(?:sms|mesaj|kısa mesaj)\s+(?:at|gönder|yaz|yolla)$",
    );
    final waRe = RegExp(
      r"^(.{2,30}?)['’]?(?:e|a|ye|ya|ne|na)\s+whatsapp(?:['’]?(?:tan|dan))?\s+(.+?)\s+diye\s+(?:yaz|mesaj at|gönder)$",
    );
    final sms = smsRe1.firstMatch(t) ?? smsRe2.firstMatch(t);
    if (sms != null && !t.contains('whatsapp')) {
      final body = _rawBody(raw, [smsRe1, smsRe2], sms.group(2)!.trim());
      final r = await _sms(sms.group(1)!.trim(), body);
      if (r != null) return r;
      return null;
    }
    final wa = waRe.firstMatch(t);
    if (wa != null) {
      final body = _rawBody(raw, [waRe], wa.group(2)!.trim());
      final r = await _whatsApp(wa.group(1)!.trim(), body);
      if (r != null) return r;
      return null;
    }

    // ---------------- uygulama aç
    final open = RegExp(
      r"^(.{2,40}?)(?:['’](?:yı|yi|yu|yü|ı|i|u|ü|nı|ni|nu|nü))?(?:\s+uygulamasını)?\s+(?:aç|başlat|çalıştır|açar mısın)$",
    ).firstMatch(t);
    if (open != null) {
      final name = open.group(1)!.trim();
      if (!RegExp(
        r'\b(ses|sesi|fener|feneri|el feneri|el fenerini|ayar|ayarları|ayarlarını|panel)\b',
      ).hasMatch(name)) {
        final launched = await _launchApp(name, host);
        if (launched != null) return _ok('$launched açıldı.', '📱 $launched');
      }
    }
    return null;
  }

  /// Mesaj gövdesini küçük harfe çevrilmemiş ham metinden alır (İstanbul,
  /// rakamlar korunur); eşleşmezse normalleştirilmiş gövdeye döner.
  static String _rawBody(String raw, List<RegExp> res, String fallback) {
    final r = LocalCommandEngine.stripEndPunct(raw)
        .replaceFirst(
          RegExp(
            r'^(?:(?:hey|hi)\s+)?(?:ege|jarvis)(?=\s|[,،]|$)\s*[,،]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    for (final re in res) {
      final m = RegExp(re.pattern, caseSensitive: false).firstMatch(r);
      final g = m?.group(2)?.trim();
      if (g != null && g.isNotEmpty) return g;
    }
    return fallback;
  }

  static const _searchSource =
      r'(?:vikipedi|wikipedia|internet\w*|web\w*|google|youtube|play store|spotify|harita\w*|rehberde)';

  /// Bulunma eki gibi görünen ama gerçek ilk ad olan sözcükler.
  static final _locativeLikeName = RegExp(
    r'^(?:hande|seda|sevda|sevde|ayten|sude|gonca|funda|derya|aytan|nurten|sedat|ferhat|serdar|mete|belgin|nilgun|gulten|bilten|nuten|renda|ceyda|yagmurda)$',
  );

  /// "x ara" cümlesi gerçekten telefon araması mı (kişi/numara/ilişki)
  /// yoksa arama (web, şarkı, tarif) mi?
  static bool _looksLikeCall(String who) {
    final w = who.trim();
    final noSuffix = w.replaceAll(RegExp(r"['’][a-zçğıöşü]+$"), '');
    if (RegExp(r'^[\d\s+\-()]+$').hasMatch(noSuffix)) return true;
    if (RegExp('(?:^|\\s)$_searchSource(?:\\s|\$|[\'’])').hasMatch(w)) {
      return false;
    }
    final words = w.split(' ');
    if (words.length > 3) return false;
    if (words.length > 1 &&
        RegExp(r"^\S+?['’]?(?:de|da|te|ta|den|dan|ten|tan)$")
            .hasMatch(words.first) &&
        !_locativeLikeName.hasMatch(
          LocalCommandEngine.foldTr(words.first),
        )) {
      return false;
    }
    if (RegExp(r'tarifi|şarkı|sını|sini|sunu|sünü').hasMatch(w)) return false;
    return true;
  }

  static final _groupWord = RegExp(
    r'^(?:veli|ogrenci|arkadas|sinif|herkes|ona|on|bana|ban|sana|san|onlar|onlara|bize|size|hepsi|grup|o)$',
  );
  static bool _isGroupWord(String who) {
    final f = LocalCommandEngine.foldTr(who);
    if (_groupWord.hasMatch(f)) return true;
    final stripped = f.replaceAll(
      RegExp(r'(?:lara|lere|lar|ler|ya|ye|a|e)$'),
      '',
    );
    return _groupWord.hasMatch(stripped);
  }

  /// Saat/komut sözcükleri atılınca kalan kısım alarm etiketi olur.
  static String _alarmLabel(String t) {
    final rest = t
        .replaceAll(
          RegExp(
            r"(?<![a-zçğıöşüâîû0-9])(yarın|bugün|sabah|akşam|öğleden sonra|öğlen|gece|saat|beni|alarm(?:ı|ını)?|kur|ayarla|koy|ekle|uyandır|için|çeyrek|geçe|var|kala|buçu[kğ][a-zçğıöşü]*|her|gün|hafta içi|hafta sonu|pazartesi|salı|çarşamba|perşembe|cuma|cumartesi|pazar)(?![a-zçğıöşüâîû0-9])",
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r"\d{1,2}[:.]\d{2}(?:['’][a-zçğıöşü]+)?|\d{1,2}(?:['’][a-zçğıöşü]+)?",
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return rest.length >= 3 ? rest : 'Ege alarmı';
  }

  static String trDate(DateTime d) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, ${days[d.weekday - 1]}';
  }

  /// Kişi adı adayları: "annemi" → annem, anne; "ahmet'i" → ahmet.
  static List<String> nameCandidates(String who) {
    final out = <String>{...LocalCommandEngine.nameCandidates(who)};
    for (final c in out.toList()) {
      for (final poss in const ['ım', 'im', 'um', 'üm', 'm']) {
        if (c.length > poss.length + 2 && c.endsWith(poss)) {
          out.add(c.substring(0, c.length - poss.length));
        }
      }
    }
    return out.where((e) => e.length >= 2).toList();
  }

  static Future<({ContactInfo? contact, bool permission, bool ambiguous})>
  _findContact(String who) async {
    final raw = who.trim();
    // Soyulmuş biçimler önce, ekli ham biçim ("ali'yi") en sona.
    final all = nameCandidates(who);
    // Ham biçim önce: "Emre" tam adı, soyulmuş "emr" ile belirsiz kalmasın.
    // Ekli ham biçim ("ali'yi") rehberde eşleşmez, zararsızca sonraki adaya geçer.
    final ordered = [
      ...all.where((e) => e == raw),
      ...all.where((e) => e != raw),
    ];
    bool nameMatches(ContactInfo c, String cand) {
      final fc = LocalCommandEngine.foldTr(cand);
      if (fc.isEmpty) return false;
      return ' ${LocalCommandEngine.foldTr(c.name)}'.contains(' $fc');
    }

    for (final cand in ordered) {
      final listAll = await DeviceBridge.searchContacts(cand, limit: 12);
      final list = listAll.where((c) => nameMatches(c, cand)).toList();
      final exact = list
          .where(
            (c) =>
                LocalCommandEngine.foldTr(c.name) ==
                LocalCommandEngine.foldTr(cand),
          )
          .toList();
      final candidates = exact.isNotEmpty ? exact : list;
      final byNumber = {
        for (final c in candidates)
          c.phone.replaceAll(RegExp(r'[^0-9+]'), ''): c,
      };
      if (byNumber.length == 1) {
        return (
          contact: byNumber.values.single,
          permission: true,
          ambiguous: false,
        );
      }
      if (byNumber.length > 1) {
        return (contact: null, permission: true, ambiguous: true);
      }
    }
    return (
      contact: null,
      permission: await DeviceBridge.contactsPermissionGranted(),
      ambiguous: false,
    );
  }

  static Future<LocalCommandOutcome> _callContact(String who) async {
    final stripped = who
        .trim()
        .replaceAll(RegExp(r"['’]?(?:yi|yı|yu|yü|i|ı|u|ü|y?e|y?a)$"), '');
    var digits = stripped.replaceAll(RegExp(r'[^0-9+]'), '');
    final spoken = LocalCommandEngine.foldTr(who);
    final emergencyWord = RegExp(
      r'^(polis|ambulans|itfaiye|jandarma)(?:i|yi|u|yu|si)?$',
    ).firstMatch(spoken);
    if (emergencyWord != null) {
      digits = const {
        'polis': '155',
        'ambulans': '112',
        'itfaiye': '110',
        'jandarma': '156',
      }[emergencyWord.group(1)]!;
    }
    const emergency = ['112', '110', '155', '156', '177', '183', '184'];
    final isEmergency =
        emergency.contains(digits) &&
        (emergencyWord != null || stripped.replaceAll(' ', '') == digits);
    if (isEmergency ||
        (digits.length >= 7 &&
            digits.length >= stripped.replaceAll(' ', '').length - 2)) {

      final r = await DeviceBridge.callNumber(digits);
      return _ok(
        r == 'CALLING'
            ? '$digits için arama başlatıldı.'
            : r == 'DIALER'
            ? '$digits çevirici ekranında; yeşil tuşa bas.'
            : 'Arama başlatılamadı.',
        '📞 $digits',
      );
    }
    final f = await _findContact(who);
    final c = f.contact;
    if (f.ambiguous) {
      return _ok(
        'Birden fazla kişi veya numara eşleşiyor. Tam kişi adını ya da numarayı belirt; henüz arama yapmadım.',
      );
    }
    if (c == null) {
      return _ok(
        f.permission ? 'Rehberde "$who" adında biri bulunamadı.' : 'Rehberine erişim izni gerekiyor; izin penceresinden izin verip tekrar söyle.',
        '📞 ?',
      );
    }
    final r = await DeviceBridge.callNumber(c.phone);
    return _ok(
      r == 'CALLING'
          ? '${c.name} için arama başlatıldı.'
          : r == 'DIALER'
          ? '${c.name} (${c.phone}) çevirici ekranında; aramak için yeşil tuşa bas.'
          : 'Arama başlatılamadı.',
      '📞 ${c.name}',
    );
  }

  static Future<LocalCommandOutcome?> _sms(String who, String body) async {
    var number = who.replaceAll(RegExp(r'[^0-9+]'), '');
    var name = number;
    if (number.length < 7) {
      final f = await _findContact(who);
      if (f.ambiguous) {
        return _ok(
          'Birden fazla alıcı veya numara eşleşiyor. Tam adı ya da numarayı belirt; mesaj hazırlanmadı.',
        );
      }
      if (f.contact == null) {
        if (_isGroupWord(who)) return null;
        return _ok(
          f.permission
              ? 'Rehberde "$who" bulunamadı.'
              : 'Rehber izni gerekiyor; izin verip tekrar söyle.',
        );
      }
      number = f.contact!.phone;
      name = f.contact!.name;
    }
    final ok = await DeviceBridge.openUrl(
      'smsto:${number.replaceAll(' ', '')}?body=${Uri.encodeComponent(body)}',
    );
    return _ok(
      ok
          ? '$name için mesaj hazır; göndermek için gönder tuşuna bas.'
          : 'Mesaj uygulaması açılamadı.',
      '✉️ $name',
    );
  }

  static Future<LocalCommandOutcome?> _whatsApp(String who, String text) async {
    final f = await _findContact(who);
    if (f.ambiguous) {
      return _ok(
        'Birden fazla alıcı veya numara eşleşiyor. Tam adı ya da numarayı belirt; mesaj hazırlanmadı.',
      );
    }
    if (f.contact == null) {
      if (_isGroupWord(who)) return null;
      return _ok(
        f.permission
            ? 'Rehberde "$who" bulunamadı.'
            : 'Rehber izni gerekiyor; izin verip tekrar söyle.',
      );
    }
    final n = LocalCommandEngine.waNumber(f.contact!.phone);
    final ok = await DeviceBridge.openUrl(
      'https://wa.me/$n?text=${Uri.encodeComponent(text)}',
    );
    return _ok(
      ok
          ? '${f.contact!.name} için WhatsApp mesajı hazır; göndermek için onayla.'
          : 'WhatsApp açılamadı.',
      '💬 ${f.contact!.name}',
    );
  }

  static const _appAliases = {
    'kamera': 'Kamera',
    'kamerayı': 'Kamera',
    'ayarlar': 'Ayarlar',
    'galeri': 'Fotoğraflar',
    'fotoğraflar': 'Fotoğraflar',
    'saat': 'Saat',
    'takvim': 'Takvim',
    'hesap makinesi': 'Hesap Makinesi',
    'harita': 'Haritalar',
    'haritalar': 'Haritalar',
    'mesajlar': 'Mesajlar',
    'rehber': 'Kişiler',
    'kişiler': 'Kişiler',
    'telefon': 'Telefon',
    'müzik': 'Müzik',
    'dosyalar': 'Dosyalar',
    'play store': 'Play Store',
    'chrome': 'Chrome',
    'tarayıcı': 'Chrome',
    'gmail': 'Gmail',
    'e-posta': 'Gmail',
  };

  static Future<String?> _launchApp(
    String spoken,
    VoiceCommandHost host,
  ) async {
    final cands = <String>{
      spoken,
      ...LocalCommandEngine.nameCandidates(spoken),
    };
    final alias =
        _appAliases[spoken] ??
        _appAliases[cands.firstWhere(
          _appAliases.containsKey,
          orElse: () => '',
        )];
    if (alias != null) cands.add(alias);
    // Yüklü uygulamalar arasında Türkçe-duyarsız eşleşme (WhatsApp, Instagram…).
    final folded = cands.map(LocalCommandEngine.foldTr).toSet();
    for (final app in host.installedApps) {
      final f = LocalCommandEngine.foldTr(app.name);
      if (folded.contains(f) ||
          folded.any((c) => c.length >= 4 && f.startsWith(c))) {
        final r = await DeviceBridge.launchApp(app.name);
        if (r != null) return app.name;
      }
    }
    for (final c in [?alias, ...cands]) {
      final r = await DeviceBridge.launchApp(c);
      if (r != null && r.isNotEmpty) return r;
    }
    return null;
  }
}

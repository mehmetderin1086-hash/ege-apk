// Lise metin ailelerinin her vakasını açıp biçim, anahtar, çeldirici ve
// teklik denetiminden geçirir. Alan testleri bu işlevi çağırır.
import 'package:bilgili_flutter/data/advanced/lise_metin/ortak.dart';
import 'package:flutter_test/flutter_test.dart';

final _anahtarBicimi = RegExp(r'^lm_[a-z0-9]+(?:_[a-z0-9]+)*$');
final _ondalikNokta = RegExp(r'\d\.\d');
final _sayiyaEk = RegExp("\\d['’][a-zçğıöşü]", caseSensitive: false);
final _bosluklar = RegExp(r'\s+');
final _sayiDegil = RegExp(r'\bNaN\b|\bnull\b|\bInfinity\b');
final _eksiSifir = RegExp(r'(?<![\d,])[-−]0(?![\d,])');
const _yasakParcalar = ['Instance of', '  ', '--', '+-', '+ -'];

String _norm(String s) => s.trim().replaceAll(_bosluklar, ' ').toLowerCase();

/// Metindeki biçim kusurunu döndürür; kusur yoksa null.
String? _metinKusuru(String s) {
  if (s != s.trim()) return 'baş/son boşluk';
  for (final p in _yasakParcalar) {
    if (s.contains(p)) return 'yasak parça “$p”';
  }
  if (_sayiDegil.hasMatch(s)) return 'sayı olmayan değer (NaN/null/Infinity)';
  if (_eksiSifir.hasMatch(s)) return 'eksi sıfır';
  if (_ondalikNokta.hasMatch(s)) return 'ondalık nokta (virgül kullanın)';
  if (_sayiyaEk.hasMatch(s)) return 'sayıya kesme işaretiyle ek getirilmiş';
  return null;
}

void liseMetinDenetle(
  String alan,
  List<AdvancedFamily> families, {
  int beklenenAile = 20,
  bool ornekYaz = true,
}) {
  test('$alan: ${families.length} aile, her vaka denetlenir', () {
    expect(families.length, beklenenAile, reason: 'Aile sayısı');
    final keys = <String>{};
    final kokler = <String, String>{};
    var toplam = 0;
    for (final f in families) {
      void aileKosulu(bool ok, String neden) {
        if (!ok) fail('${f.key} [${f.title}] $neden');
      }

      aileKosulu(_anahtarBicimi.hasMatch(f.key), 'anahtar biçimi');
      aileKosulu(keys.add(f.key), 'yinelenen anahtar');
      aileKosulu(f.count == lmAileBoyu, 'vaka sayısı ${f.count}');
      aileKosulu(f.level == StudyLevel.lise, 'düzey lise olmalı');
      aileKosulu(
        f.visualKind == null &&
            f.activityKind == null &&
            f.creation == null &&
            f.multiSelect == null,
        'yalnız metin olmalı',
      );
      aileKosulu(f.bloom != BloomLevel.yaratma, 'yaratma basamağı kullanılamaz');
      aileKosulu(
        f.title.trim().length >= 8 && f.title.length <= 60,
        'başlık uzunluğu',
      );
      aileKosulu(f.lesson != null && f.lesson!.trim().isNotEmpty, 'ders adı');
      if (f.exam != null) {
        aileKosulu(
          f.exam!.lessons.contains(f.lesson),
          'ders “${f.lesson}” ${f.exam!.label} listesinde yok: ${f.exam!.lessons}',
        );
      }
      for (var i = 0; i < f.count; i++) {
        late final AdvancedItem raw;
        try {
          raw = f.build(i);
        } catch (e) {
          fail('${f.key}_$i üretilemedi: $e');
        }
        void kosul(bool ok, String neden) {
          if (!ok) {
            fail(
              '${f.key}_$i [${f.title}] $neden\n'
              '  Kök: ${raw.prompt}\n  Doğru: ${raw.correct}\n'
              '  Yanlış: ${raw.wrong}\n  Açıklama: ${raw.explanation}',
            );
          }
        }

        final secenekler = [raw.correct, ...raw.wrong];
        kosul(raw.wrong.length == 3, 'üç çeldirici gerekli');
        kosul(
          raw.prompt.length >= 25 && raw.prompt.length <= 700,
          'kök uzunluğu ${raw.prompt.length}',
        );
        kosul(
          raw.explanation.trim().length >= 12 && raw.explanation.length <= 600,
          'açıklama uzunluğu ${raw.explanation.length}',
        );
        for (final s in [raw.prompt, raw.explanation, ...secenekler]) {
          final kusur = _metinKusuru(s);
          kosul(kusur == null, 'metin kusuru: $kusur → “$s”');
        }
        kosul(
          secenekler.every((s) => s.isNotEmpty && s.length <= 140),
          'seçenek uzunluğu',
        );
        for (var x = 0; x < 4; x++) {
          for (var y = x + 1; y < 4; y++) {
            kosul(
              !ayniSecenek(secenekler[x], secenekler[y]),
              'eşdeğer seçenekler: “${secenekler[x]}” = “${secenekler[y]}”',
            );
          }
        }
        if (f.shortAnswer) {
          kosul(
            raw.correct.length <= 24,
            'yazılı yanıt için anahtar çok uzun (shortAnswer: false yapın)',
          );
          final yazili = Question(
            id: 'denetim',
            text: raw.prompt,
            options: secenekler,
            answer: 0,
            explanation: raw.explanation,
            category: f.topic,
            difficulty: f.difficulty,
            responseType: ResponseType.fill,
          );
          kosul(
            yazili.acceptsWritten(raw.correct) &&
                raw.wrong.every((s) => !yazili.acceptsWritten(s)),
            'yazılı yanıt eşdeğerliği',
          );
        }
        final q = f.questionAt(i);
        kosul(
          q.id == 'ak38_${f.key}_$i' &&
              q.answer >= 0 &&
              q.answer < q.options.length &&
              q.options.map(_norm).toSet().length == q.options.length &&
              q.visual == null &&
              q.activity == null,
          'soru kaydı',
        );
        if (q.responseType == ResponseType.trueFalse) {
          kosul(
            q.options.length == 2 &&
                (q.answer == 0) ==
                    q.text.contains('“${raw.correct}”. Bu yanıt doğru mu?'),
            'doğru/yanlış önermesi',
          );
        } else {
          kosul(q.options[q.answer] == raw.correct, 'cevap indeksi');
        }
        final kok = _norm(raw.prompt);
        final onceki = kokler[kok];
        kosul(onceki == null, 'yinelenen soru kökü (ilk görüldüğü yer: $onceki)');
        kokler[kok] = '${f.key}_$i';
        toplam++;
      }
      if (ornekYaz) {
        // ignore: avoid_print
        print(
          '\n### ${f.key} | ${f.title} | ${f.topic.label} | ${f.bloom.label} | '
          '${f.difficulty.label} | sınav=${f.exam?.label ?? '-'} | '
          'ders=${f.lesson} | yazılı=${f.shortAnswer}',
        );
        for (final i in const [3, 1281, 2507, 4996]) {
          final r = f.build(i);
          // ignore: avoid_print
          print(
            '[$i] ${r.prompt.replaceAll('\n', ' ⏎ ')}\n'
            '     ✓ ${r.correct}   ✗ ${r.wrong.join(' | ')}\n'
            '     → ${r.explanation}',
          );
        }
      }
    }
    expect(toplam, beklenenAile * lmAileBoyu);
    // ignore: avoid_print
    print('\n$alan: $toplam vaka, ${kokler.length} farklı kök — denetim tamam.');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

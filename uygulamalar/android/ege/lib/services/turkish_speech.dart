/// Conservative Turkish pronunciation for typed numerical expressions.
/// Keeps unknown/invalid values unchanged instead of inventing a correction.
class TurkishSpeech {
  static const _ones = [
    '',
    'bir',
    'iki',
    'üç',
    'dört',
    'beş',
    'altı',
    'yedi',
    'sekiz',
    'dokuz',
  ];
  static const _tens = [
    '',
    'on',
    'yirmi',
    'otuz',
    'kırk',
    'elli',
    'altmış',
    'yetmiş',
    'seksen',
    'doksan',
  ];
  static String number(int n) {
    if (n == 0) return 'sıfır';
    if (n < 0) return 'eksi ${number(-n)}';
    if (n >= 1000000000000) return n.toString();
    final out = <String>[];
    for (final unit in [
      (1000000000, 'milyar'),
      (1000000, 'milyon'),
      (1000, 'bin'),
    ]) {
      if (n >= unit.$1) {
        final q = n ~/ unit.$1;
        out.add(q == 1 && unit.$1 == 1000 ? 'bin' : '${number(q)} ${unit.$2}');
        n %= unit.$1;
      }
    }
    if (n >= 100) {
      out.add(n ~/ 100 == 1 ? 'yüz' : '${_ones[n ~/ 100]} yüz');
      n %= 100;
    }
    if (n >= 10) out.add(_tens[n ~/ 10]);
    if (n % 10 != 0) out.add(_ones[n % 10]);
    return out.join(' ');
  }

  static String decimal(String text) {
    final parts = text.replaceAll('.', '').split(',');
    final main = number(int.parse(parts.first));
    if (parts.length == 1) return main;
    final fraction = parts[1].startsWith('0')
        ? parts[1].split('').map((d) => number(int.parse(d))).join(' ')
        : number(int.parse(parts[1]));
    return '$main virgül $fraction';
  }

  static String normalize(String input) {
    var text = input;
    const months = [
      '',
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
    text = text.replaceAllMapped(
      RegExp(
        r'(?<![\d./])([0-3]?\d)[./]([01]?\d)[./]((?:19|20)\d{2})(?![\d./])',
      ),
      (m) {
        final d = int.parse(m[1]!),
            month = int.parse(m[2]!),
            y = int.parse(m[3]!);
        final date = DateTime(y, month, d);
        if (date.day != d || date.month != month) return m[0]!;
        return '${number(d)} ${months[month]} ${number(y)}';
      },
    );
    text = text.replaceAllMapped(
      RegExp(
        r'(?<![\d.,])(?:₺\s*)(\d{1,9}(?:\.\d{3})*(?:,\d{1,2})?)(?![\d.,])',
      ),
      (m) => _money(m[1]!),
    );
    text = text.replaceAllMapped(
      RegExp(
        r'(?<![\d.,])(\d{1,9}(?:\.\d{3})*(?:,\d{1,2})?)\s*(?:TL\b|₺|TRY\b)',
        caseSensitive: false,
      ),
      (m) => _money(m[1]!),
    );
    text = text.replaceAllMapped(
      RegExp(r'%\s*(\d{1,3}(?:,\d{1,3})?)(?!\d)'),
      (m) => 'yüzde ${decimal(m[1]!)}',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'(?<![\d:])(\d{1,3}):([0-5]\d)\s*(?:dk|dakika)\b',
        caseSensitive: false,
      ),
      (m) =>
          '${number(int.parse(m[1]!))} dakika ${number(int.parse(m[2]!))} saniye',
    );
    final beforeClock = text;
    text = text.replaceAllMapped(
      RegExp(
        r'(?<![\d:])(?:saat\s+)?([01]\d|2[0-3]):([0-5]\d)(?![:\d])',
        caseSensitive: false,
      ),
      (m) {
        final h = int.parse(m[1]!), minute = int.parse(m[2]!);
        final previous = beforeClock
            .substring((m.start - 24).clamp(0, beforeClock.length), m.start)
            .toLowerCase();
        if (RegExp(r'(?:süre|suresi|süresi|video konumu)\s*:?\s*$')
            .hasMatch(previous)) {
          return '${number(h)} dakika ${number(minute)} saniye';
        }
        return minute == 0
            ? 'saat ${number(h)}'
            : 'saat ${number(h)} ${minute < 10 ? "sıfır " : ""}${number(minute)}';
      },
    );
    text = text.replaceAllMapped(
      RegExp(
        r'(?<![\d.])saat\s+([01]?\d|2[0-3])\.([0-5]\d)(?![\d.])',
        caseSensitive: false,
      ),
      (m) => normalize('saat ${m[1]!.padLeft(2, '0')}:${m[2]}'),
    );
    text = text.replaceAllMapped(
      RegExp(
        r'\b(\d{1,6}(?:,\d{1,3})?)\s*(dk|sn|km|kg|sa)(?=\s|[.,;!?]|$)',
        caseSensitive: false,
      ),
      (m) =>
          '${decimal(m[1]!)} ${const {'dk': 'dakika', 'sn': 'saniye', 'km': 'kilometre', 'kg': 'kilogram', 'sa': 'saat'}[m[2]!.toLowerCase()]}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(\d{1,4})\s+(numaralı hat|numaralı otobüs|hattı)\b'),
      (m) => '${number(int.parse(m[1]!))} ${m[2]}',
    );
    return text;
  }

  static String _money(String raw) {
    final p = raw.replaceAll('.', '').split(',');
    final amount = number(int.parse(p.first));
    final cents = p.length > 1 ? int.parse(p[1].padRight(2, '0')) : 0;
    return '$amount lira${cents == 0 ? "" : " ${number(cents)} kuruş"}';
  }
}

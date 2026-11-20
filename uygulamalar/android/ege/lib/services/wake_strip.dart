/// Ortak uyandırma kelimesi / dolgu sözcüğü temizleyici.
///
/// Baştaki "(hey|hi|ey)? (ege|jarvis)" + ayraç, sondaki ", ege" / " jarvis" ve
/// baştaki dolgular (hadi, şimdi, bir, bi, hemen, artık, yani) atılır.
/// "bir/bi" sayı olduğunda (bir dakika, bir saatlik...) atılmaz.
/// Geri kalan metnin harf büyüklüğü korunur.
String stripWake(String text) {
  var t = text.trim();
  if (t.isEmpty) return t;
  final lead = RegExp(
    r'^(?:(?:hey|hi|ey)\s+)?(?:asistan|ege|jarvis)(?:\s*[.,!?:;\-،]+\s*|\s+|$)',
    caseSensitive: false,
    unicode: true,
  );
  // "ege" yalnızca ayraçla ya da sözcük sınırıyla biten hâliyle atılır.
  t = t.replaceFirst(lead, '').trim();
  final filler = RegExp(
    r'^(?:hadi|şimdi|simdi|hemen|artık|artik|yani|(?:bir|bi)(?!\s+(?:dakika|dk|saat|saniye|sn|gün|gun|hafta|ay|yıl|yil|buçuk|bucuk|kere|defa|kez)))(?:\s*[,]\s*|\s+)',
    caseSensitive: false,
    unicode: true,
  );
  var guard = 0;
  while (guard++ < 8 && filler.hasMatch(t)) {
    t = t.replaceFirst(filler, '').trim();
  }
  final trail = RegExp(
    r'(?:\s*,\s*|\s+)(?:asistan|ege|jarvis)(?=[\s.!?]*$)',
    caseSensitive: false,
    unicode: true,
  );
  t = t.replaceFirst(trail, '').trim();
  return t;
}

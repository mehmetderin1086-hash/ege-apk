/// Strips separators and invisible directional marks around ISBN strings.
String cleanIsbnInput(String value) => value
    .toUpperCase()
    .replaceAll(RegExp(r'^ISBN(?:-1[03])?\s*[:：]?\s*', caseSensitive: false), '')
    .replaceAll(RegExp(r'[\s\-\u200E\u200F\u202A-\u202E]'), '');

/// Checks ISBN-10 or ISBN-13, allowing spaces and hyphens as separators.
bool isValidIsbn(String value) {
  final clean = cleanIsbnInput(value);
  if (clean.isEmpty) return true; // ISBN is optional.
  if (RegExp(r'^\d{9}[\dX]$').hasMatch(clean)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      final n = clean[i] == 'X' ? 10 : int.parse(clean[i]);
      sum += n * (10 - i);
    }
    return sum % 11 == 0;
  }
  if (RegExp(r'^(978|979)\d{10}$').hasMatch(clean)) {
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(clean[i]) * (i.isEven ? 1 : 3);
    }
    return sum % 10 == 0;
  }
  return false;
}

/// Existing unverified ISBN values can remain unchanged while other fields are edited.
bool isAcceptableIsbnEdit(String value, String? original) =>
    isValidIsbn(value) || (original != null && value.trim() == original.trim());

/// ISBN-10 and corresponding 978 ISBN-13 identify the same edition.
String? canonicalIsbn(String value) {
  final clean = cleanIsbnInput(value);
  if (clean.isEmpty || !isValidIsbn(clean)) return null;
  if (clean.length == 13) return clean;
  final base = '978${clean.substring(0, 9)}';
  var sum = 0;
  for (var i = 0; i < base.length; i++) {
    sum += int.parse(base[i]) * (i.isEven ? 1 : 3);
  }
  return '$base${(10 - sum % 10) % 10}';
}

/// Returns the 10-character ISBN-10 (used as Amazon ASIN for 978 editions).
/// 979-prefixed ISBN-13s have no ISBN-10 equivalent and return null.
String? isbn10Of(String value) {
  final clean = cleanIsbnInput(value);
  if (clean.isEmpty || !isValidIsbn(clean)) return null;
  if (clean.length == 10) return clean;
  if (!clean.startsWith('978')) return null;
  final core = clean.substring(3, 12);
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(core[i]) * (10 - i);
  }
  final check = (11 - (sum % 11)) % 11;
  return '$core${check == 10 ? 'X' : check}';
}

/// Bounded, literal spreadsheet data. Sources must be pages read in this task.
class SpreadsheetSpec {
  static Map<String, dynamic> validate(
    Map<String, dynamic> input, {
    required Set<String> readUrls,
    required DateTime checkedAt,
  }) {
    final headers = input['headers'];
    final rows = input['rows'];
    if (headers is! List ||
        headers.isEmpty ||
        headers.length > 40 ||
        headers.any(
          (v) => v is! String || v.trim().isEmpty || v.length > 200,
        )) {
      throw const FormatException('1–40 geçerli sütun başlığı gerekli.');
    }
    if (rows is! List || rows.isEmpty || rows.length > 2000) {
      throw const FormatException('1–2000 veri satırı gerekli.');
    }
    for (final row in rows) {
      if (row is! List ||
          row.length != headers.length ||
          row.any(
            (v) => v != null && v is! String && v is! num && v is! bool,
          ) ||
          row.any(
            (v) => v is num && !v.isFinite || v is String && v.length > 4000,
          )) {
        throw const FormatException(
          'Her satır başlıklarla aynı sayıda, geçerli hücre içermeli.',
        );
      }
    }
    final sources = input['sources'] ?? const [];
    if (sources is! List ||
        sources.length > 20 ||
        sources.any((s) => s is! String || !readUrls.contains(s))) {
      throw const FormatException(
        'Kaynak URL önce fetch_url ile başarıyla okunmalı.',
      );
    }
    final sourceText = sources.join('\n');
    return {
      'sheet': input['sheet']?.toString() ?? 'Veriler',
      'headers': [
        ...headers,
        if (sources.isNotEmpty) ...['Kaynak URL', 'Kontrol tarihi'],
      ],
      'rows': [
        for (final row in rows)
          [
            ...row as List,
            if (sources.isNotEmpty) ...[
              sourceText,
              checkedAt.toIso8601String(),
            ],
          ],
      ],
    };
  }
}

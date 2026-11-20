import 'dart:convert';

import 'spreadsheet_spec.dart';

class DocumentSpec {
  static Map<String, dynamic> validate(
    Map<String, dynamic> input, {
    required Set<String> readUrls,
    required DateTime checkedAt,
  }) {
    if (jsonEncode(input).length > 200000)
      throw const FormatException('Belge çok büyük.');
    List<String> strings(dynamic value) {
      if (value == null) return [];
      if (value is! List ||
          value.length > 500 ||
          value.any((v) => v is! String || v.length > 10000)) {
        throw const FormatException(
          'Paragraflar ve maddeler metin dizisi olmalı.',
        );
      }
      return value.cast<String>();
    }

    final title = input['title'];
    if (title is! String || title.trim().isEmpty || title.length > 300)
      throw const FormatException('Belge başlığı gerekli.');
    final sections = input['sections'] ?? [];
    final tables = input['tables'] ?? [];
    if (sections is! List ||
        sections.length > 50 ||
        tables is! List ||
        tables.length > 20)
      throw const FormatException('Belge yapısı geçersiz.');
    final result = <String, dynamic>{
      'title': title,
      'paragraphs': strings(input['paragraphs']),
      'sections': [
        for (final section in sections)
          if (section is Map)
            {
              'heading': section['heading']?.toString() ?? '',
              'paragraphs': strings(section['paragraphs']),
              'bullets': strings(section['bullets']),
            }
          else
            throw const FormatException('Bölüm yapısı geçersiz.'),
      ],
      'tables': [
        for (final table in tables)
          if (table is Map)
            SpreadsheetSpec.validate(
              Map<String, dynamic>.from(table),
              readUrls: readUrls,
              checkedAt: checkedAt,
            )
          else
            throw const FormatException('Tablo yapısı geçersiz.'),
      ],
    };
    final sources = input['sources'] ?? [];
    if (sources is! List ||
        sources.length > 20 ||
        sources.any((s) => s is! String || !readUrls.contains(s)))
      throw const FormatException('Kaynak URL önce fetch_url ile okunmalı.');
    if (sources.isNotEmpty)
      (result['sections'] as List).add({
        'heading': 'Kaynaklar',
        'paragraphs': [
          ...sources,
          'Kontrol tarihi: ${checkedAt.toIso8601String()}',
        ],
      });
    if ((result['paragraphs'] as List).isEmpty &&
        sections.isEmpty &&
        tables.isEmpty)
      throw const FormatException('Belge içeriği boş.');
    return result;
  }
}

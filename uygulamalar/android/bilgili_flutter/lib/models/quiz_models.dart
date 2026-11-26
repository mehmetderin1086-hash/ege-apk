import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

enum Topic {
  mixed('Karışık', 'Her alandan keşif', Icons.auto_awesome_rounded, Color(0xFF4CE0D2)),
  science('Bilim', 'Merakının peşinden', Icons.science_rounded, Color(0xFF5AB2FF)),
  history('Tarih', 'Zamanda bir yolculuk', Icons.account_balance_rounded, Color(0xFFF6C453)),
  geography('Coğrafya', 'Dünyayı keşfet', Icons.public_rounded, Color(0xFF5CE09B)),
  art('Sanat', 'İlhamını bul', Icons.palette_rounded, Color(0xFFF27BB8)),
  sport('Spor', 'Bilginle sahaya çık', Icons.emoji_events_rounded, Color(0xFFFF9559)),
  culture('Genel Kültür', 'Yeni şeyler öğren', Icons.lightbulb_rounded, Color(0xFFC5A3FF)),
  cinema('Sinema ve TV', 'Perdenin ötesine geç', Icons.movie_filter_rounded, Color(0xFFA99CFF)),
  language('Yabancı Dil', 'Kelimelerle keşfet', Icons.translate_rounded, Color(0xFF58D5E3)),
  technology('Teknoloji', 'Geleceği yakala', Icons.memory_rounded, Color(0xFF4DD0E1)),
  literature('Edebiyat', 'Satırların izinde', Icons.menu_book_rounded, Color(0xFFFFB076)),
  music('Müzik', 'Ritmi ve ezgiyi tanı', Icons.music_note_rounded, Color(0xFFFF7BAC)),
  nature('Doğa', 'Yaşamın dengesini gör', Icons.eco_rounded, Color(0xFF7BE495)),
  exam('Sınav Hazırlık', 'Hedefine bir adım', Icons.school_rounded, Color(0xFFF7B955)),
  mathematics('Matematik ve Geometri', 'Yapılar, uzay ve değişim', Icons.functions, Color(0xFF79B9FF)),
  physics('Fizik ve Astronomi', 'Madde, enerji ve evren', Icons.public, Color(0xFF8AB7FF)),
  chemistry('Kimya ve Malzeme', 'Maddenin yapısı ve dönüşümü', Icons.science, Color(0xFF69DCC4)),
  biology('Biyoloji ve Yaşam Bilimleri', 'Canlı sistemler ve kalıtım', Icons.eco, Color(0xFF72D989)),
  engineering('Mühendislik ve Tasarım', 'Tasarımları modelle ve sına', Icons.engineering, Color(0xFF76D7E5)),
  computing('Bilişim ve Algoritmalar', 'Veriyi işle ve algoritma kur', Icons.computer, Color(0xFF8EC8FF)),
  statistics('İstatistik ve Veri Bilimi', 'Belirsizliği ölç ve veriyi yorumla', Icons.query_stats, Color(0xFFA9C6FF)),
  economics('Ekonomi ve Finans', 'Kaynaklar, fiyatlar ve kararlar', Icons.trending_up, Color(0xFFF2BA76)),
  socialScience('Toplum ve Sosyal Bilimler', 'Toplumları ve kurumları incele', Icons.groups, Color(0xFFC7A6E7)),
  research('Araştırma Yöntemleri', 'Kanıtı değerlendir ve çalışma tasarla', Icons.biotech, Color(0xFF9CDBC8)),
  custom('Özel Konu', 'Konuyu sen belirle', Icons.edit_note_rounded, Color(0xFF93B5FF));

  final String label;
  final String invitation;
  final IconData icon;
  final Color accent;
  const Topic(this.label, this.invitation, this.icon, this.accent);

  String get _artName => switch (this) {
    Topic.mathematics || Topic.statistics => 'exam',
    Topic.physics || Topic.chemistry || Topic.research => 'science',
    Topic.biology => 'nature',
    Topic.computing || Topic.engineering => 'technology',
    Topic.economics || Topic.socialScience => 'culture',
    _ => name,
  };
  String get coverImage => 'assets/images/topic_${_artName}_cover.webp';
  String get detailImage => 'assets/images/topic_${_artName}_detail.webp';

  static List<Topic> get poolCategories => values
      .where((t) => t != Topic.mixed && t != Topic.custom)
      .toList(growable: false);

  static Topic fromLabel(String? raw) {
    if (raw == null || raw.trim().isEmpty) return Topic.culture;
    final clean = raw.trim().toLowerCase();
    for (final t in Topic.values) {
      if (t.label.toLowerCase() == clean || t.name.toLowerCase() == clean) {
        return t;
      }
    }
    if (clean.contains('sinema')) return Topic.cinema;
    if (clean.contains('kültür') || clean.contains('kultur')) return Topic.culture;
    if (clean.contains('coğraf') || clean.contains('cograf')) return Topic.geography;
    if (clean.contains('yabancı') || clean.contains('dil')) return Topic.language;
    if (clean.contains('sınav') || clean.contains('sinav')) return Topic.exam;
    if (clean.contains('doğa') || clean.contains('doga')) return Topic.nature;
    if (clean.contains('müzik') || clean.contains('muzik')) return Topic.music;
    if (clean.contains('özel') || clean.contains('ozel')) return Topic.custom;
    return Topic.culture;
  }
}

enum Difficulty {
  easy('Kolay', 100, Color(0xFF5CE09B)),
  medium('Orta', 150, Color(0xFFF6C453)),
  hard('Zor', 220, Color(0xFFFF7B89));

  final String label;
  final int basePoints;
  final Color color;
  const Difficulty(this.label, this.basePoints, this.color);

  static Difficulty fromLabel(String? raw) {
    if (raw == null) return Difficulty.medium;
    final clean = raw.trim().toLowerCase();
    if (clean == 'kolay' || clean == 'easy') return Difficulty.easy;
    if (clean == 'zor' || clean == 'hard') return Difficulty.hard;
    return Difficulty.medium;
  }
}

enum GameMode {
  classic('Klasik', '15 sn süre · 3 joker hakkı', Icons.bolt_rounded, 15, true),
  training('Öğren', 'Süresiz · Anında açıklama & pekiştirme', Icons.psychology_rounded, 0, false),
  sprint('Hız Turu', '8 sn yüksek tempo refleks turu', Icons.speed_rounded, 8, true),
  timed('Dakika Turu', 'Ortak tur sayacında en çok doğru', Icons.timer_rounded, 0, true),
  stages('Etaplı Tur', 'Isınma 20sn → Odak 15sn → Final 10sn', Icons.stairs_rounded, 20, true);

  final String label;
  final String subtitle;
  final IconData icon;
  final int defaultQuestionSeconds;
  final bool allowsJokers;
  const GameMode(
    this.label,
    this.subtitle,
    this.icon,
    this.defaultQuestionSeconds,
    this.allowsJokers,
  );
}

enum QuestionFormat {
  mixed('Karışık', Icons.dashboard_customize_rounded),
  visual('Görselli', Icons.bar_chart_rounded),
  text('Metin', Icons.notes_rounded),
  multipleChoice('Çoktan seçmeli', Icons.list_rounded),
  multiSelect('Çoklu seçim', Icons.checklist_rounded),
  trueFalse('Doğru / yanlış', Icons.rule_rounded),
  fill('Boşluk doldurma', Icons.edit_rounded),
  creation('Açık uçlu tasarım', Icons.design_services_rounded),
  listening('Sesli Dinleme', Icons.headphones_rounded),
  dictation('Sesli Dikte', Icons.hearing_rounded),
  ordering('Sıralama', Icons.swap_vert_rounded),
  matching('Eşleştirme', Icons.compare_arrows_rounded),
  pronunciation('Telaffuz', Icons.record_voice_over_rounded),
  slider('Tahmin Sürgüsü', Icons.tune_rounded),
  anagram('Harf Dizme', Icons.spellcheck_rounded);

  final String label;
  final IconData icon;
  const QuestionFormat(this.label, this.icon);

  /// Arayüzde sunulan tüm oynanabilir soru biçimleri.
  static const sunulan = [
    mixed,
    visual,
    listening,
    dictation,
    pronunciation,
    slider,
    anagram,
    matching,
    ordering,
    multiSelect,
    trueFalse,
    fill,
    text,
  ];
}

enum ExamKind {
  tyt('TYT', 'Temel Yeterlilik Testi'),
  ayt('AYT', 'Alan Yeterlilik Testleri'),
  kpss('KPSS', 'Kamu Personel Seçme Sınavı'),
  lgs('LGS', 'Liselere Geçiş Sistemi');

  final String label;
  final String subtitle;
  const ExamKind(this.label, this.subtitle);

  List<String> get lessons {
    switch (this) {
      case ExamKind.tyt:
        return const ['Türkçe', 'Temel Matematik', 'Fizik', 'Kimya', 'Biyoloji', 'Tarih', 'Coğrafya', 'Felsefe'];
      case ExamKind.ayt:
        return const ['Matematik', 'Fizik', 'Kimya', 'Biyoloji', 'Edebiyat', 'Tarih-1', 'Coğrafya-1'];
      case ExamKind.kpss:
        return const ['Genel Yetenek Türkçe', 'Genel Yetenek Matematik', 'Tarih', 'Coğrafya', 'Vatandaşlık', 'Güncel Bilgiler'];
      case ExamKind.lgs:
        return const ['Türkçe', 'Matematik', 'Fen Bilimleri', 'T.C. İnkılap Tarihi', 'İngilizce'];
    }
  }

  static ExamKind? fromLabel(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final up = raw.trim().toUpperCase();
    for (final e in ExamKind.values) {
      if (e.label == up || e.name.toUpperCase() == up) return e;
    }
    return null;
  }
}

class StudyProfile {
  final String id;
  final String title;
  final ExamKind exam;
  final String lesson;
  final Difficulty difficulty;
  final int questionCount;

  const StudyProfile({
    required this.id,
    required this.title,
    required this.exam,
    required this.lesson,
    this.difficulty = Difficulty.medium,
    this.questionCount = 10,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'exam': exam.label,
        'lesson': lesson,
        'difficulty': difficulty.label,
        'questionCount': questionCount,
      };

  factory StudyProfile.fromJson(Map<String, dynamic> json) {
    final exam = ExamKind.fromLabel(json['exam']?.toString()) ?? ExamKind.tyt;
    return StudyProfile(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? '${exam.label} Çalışma',
      exam: exam,
      lesson: json['lesson']?.toString() ?? exam.lessons.first,
      difficulty: Difficulty.fromLabel(json['difficulty']?.toString()),
      questionCount: (json['questionCount'] as num?)?.toInt() ?? 10,
    );
  }
}

enum VisualKind {
  table,
  barChart,
  lineChart,
  diagram,
  image,
  pieChart,
  clock,
  flag,
  musicStaff,
  coordPlane,
  atom,
  matrix,
  circuit,
  venn,
  compass,
  colorLab,
  piano;

  static VisualKind? fromString(String? raw) {
    if (raw == null) return null;
    for (final k in VisualKind.values) {
      if (k.name.toLowerCase() == raw.trim().toLowerCase()) return k;
    }
    return null;
  }
}

class DiagramElement {
  final String shape; // circle, rectangle, triangle, point, line, arrow, text
  final double x;
  final double y;
  final double? width;
  final double? height;
  final double? endX;
  final double? endY;
  final String? label;
  final String? color;

  const DiagramElement({
    required this.shape,
    required this.x,
    required this.y,
    this.width,
    this.height,
    this.endX,
    this.endY,
    this.label,
    this.color,
  });

  factory DiagramElement.fromJson(Map<String, dynamic> json) => DiagramElement(
        shape: json['shape']?.toString() ?? 'circle',
        x: (json['x'] as num?)?.toDouble() ?? 50,
        y: (json['y'] as num?)?.toDouble() ?? 50,
        width: (json['width'] as num?)?.toDouble(),
        height: (json['height'] as num?)?.toDouble(),
        endX: (json['endX'] as num?)?.toDouble(),
        endY: (json['endY'] as num?)?.toDouble(),
        label: json['label']?.toString(),
        color: json['color']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'shape': shape,
        'x': x,
        'y': y,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (endX != null) 'endX': endX,
        if (endY != null) 'endY': endY,
        if (label != null) 'label': label,
        if (color != null) 'color': color,
      };
}

class QuestionVisual {
  final VisualKind kind;
  final String title;
  final String summary;
  final List<String> columns;
  final List<List<String>> rows;
  final List<String> labels;
  final List<double> values;
  final String? unit;
  final List<DiagramElement> elements;
  final String? imageID;

  const QuestionVisual({
    required this.kind,
    required this.title,
    required this.summary,
    this.columns = const [],
    this.rows = const [],
    this.labels = const [],
    this.values = const [],
    this.unit,
    this.elements = const [],
    this.imageID,
  });

  String? get assetPath {
    final name = imageID?.toLowerCase();
    if (name != null && RegExp(r'^plate(0[1-9]|1[0-9]|2[0-4])$').hasMatch(name)) {
      return 'assets/photos/$name.webp';
    }
    switch (name) {
      case 'bicycle':
        return 'assets/photos/QuestionBicycle.png';
      case 'leaf':
        return 'assets/photos/QuestionLeaf.png';
      case 'violin':
        return 'assets/photos/QuestionViolin.png';
      default:
        return null;
    }
  }

  factory QuestionVisual.fromJson(Map<String, dynamic> json) {
    final kind = VisualKind.fromString(json['kind']?.toString() ?? json['type']?.toString()) ??
        VisualKind.table;
    final cols = (json['columns'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final parsedRows = (json['rows'] as List?)
            ?.map((r) => (r as List).map((c) => c.toString()).toList())
            .toList() ??
        const [];
    final lbls = (json['labels'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final vals = (json['values'] as List?)
            ?.map((v) => (v as num?)?.toDouble() ?? 0.0)
            .toList() ??
        const [];
    final elems = (json['elements'] as List?)
            ?.whereType<Map>()
            .map((m) => DiagramElement.fromJson(Map<String, dynamic>.from(m)))
            .toList() ??
        const [];
    return QuestionVisual(
      kind: kind,
      title: json['title']?.toString() ?? 'Görsel Veri',
      summary: json['summary']?.toString() ?? '',
      columns: cols,
      rows: parsedRows,
      labels: lbls,
      values: vals,
      unit: json['unit']?.toString(),
      elements: elems,
      imageID: json['imageID']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        'summary': summary,
        if (columns.isNotEmpty) 'columns': columns,
        if (rows.isNotEmpty) 'rows': rows,
        if (labels.isNotEmpty) 'labels': labels,
        if (values.isNotEmpty) 'values': values,
        if (unit != null) 'unit': unit,
        if (elements.isNotEmpty) 'elements': elements.map((e) => e.toJson()).toList(),
        if (imageID != null) 'imageID': imageID,
      };
}

enum ActivityKind {
  listening,
  dictation,
  ordering,
  matching,
  pronunciation,
  slider,
  anagram;

  static ActivityKind? fromString(String? raw) {
    if (raw == null) return null;
    for (final k in ActivityKind.values) {
      if (k.name.toLowerCase() == raw.trim().toLowerCase()) return k;
    }
    return null;
  }

  String get badgeLabel {
    switch (this) {
      case ActivityKind.listening:
        return 'Dinleme';
      case ActivityKind.dictation:
        return 'Sesli Dikte';
      case ActivityKind.ordering:
        return 'Sıralama';
      case ActivityKind.matching:
        return 'Eşleştirme';
      case ActivityKind.pronunciation:
        return 'Telaffuz';
      case ActivityKind.slider:
        return 'Tahmin Sürgüsü';
      case ActivityKind.anagram:
        return 'Harf Dizme';
    }
  }
}

class QuestionActivity {
  final ActivityKind kind;
  final String title;
  final String? transcript;
  final String? language;
  final List<String> items;
  final List<String> left;
  final List<String> right;
  final List<int> solution;

  const QuestionActivity({
    required this.kind,
    required this.title,
    this.transcript,
    this.language,
    this.items = const [],
    this.left = const [],
    this.right = const [],
    this.solution = const [],
  });

  bool matchesSequence(List<int> attempt) {
    if (solution.isEmpty || attempt.length != solution.length) return false;
    for (var i = 0; i < solution.length; i++) {
      if (attempt[i] != solution[i]) return false;
    }
    return true;
  }

  double get sliderMin => items.isNotEmpty ? (double.tryParse(items[0]) ?? 0) : 0;
  double get sliderMax => items.length > 1 ? (double.tryParse(items[1]) ?? 100) : 100;
  double get sliderStep => items.length > 2 ? (double.tryParse(items[2]) ?? 1) : 1;
  double get sliderTolerance => items.length > 3 ? (double.tryParse(items[3]) ?? 0) : 0;
  String get sliderUnit => items.length > 4 ? items[4] : '';
  int get sliderTarget => solution.isNotEmpty ? solution.first : 0;

  bool matchesSlider(int estimate) => (estimate - sliderTarget).abs() <= sliderTolerance;

  String get anagramTarget => left.isNotEmpty ? left.first : '';

  bool matchesAnagram(String built) {
    String fold(String s) => s
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '');
    final exp = anagramTarget;
    if (exp.isEmpty) return false;
    if (language != null && language!.startsWith('en')) {
      return built.trim().toLowerCase().replaceAll(' ', '') ==
          exp.trim().toLowerCase().replaceAll(' ', '');
    }
    return fold(built) == fold(exp);
  }

  String describeSequence(List<int> seq) {
    if (kind == ActivityKind.ordering && items.isNotEmpty) {
      return seq
          .where((idx) => idx >= 0 && idx < items.length)
          .map((idx) => items[idx])
          .join(' → ');
    }
    if (kind == ActivityKind.matching && left.isNotEmpty && right.isNotEmpty) {
      final parts = <String>[];
      for (var i = 0; i < seq.length && i < left.length; i++) {
        final rIdx = seq[i];
        final rText = (rIdx >= 0 && rIdx < right.length) ? right[rIdx] : '?';
        parts.add('${left[i]} → $rText');
      }
      return parts.join(' · ');
    }
    if (kind == ActivityKind.slider && solution.isNotEmpty) {
      return '${solution.first}${sliderUnit.isNotEmpty ? ' $sliderUnit' : ''}';
    }
    if (kind == ActivityKind.anagram && left.isNotEmpty) {
      return left.first;
    }
    return seq.map((e) => '${e + 1}').join(' - ');
  }

  factory QuestionActivity.fromJson(Map<String, dynamic> json) {
    final kind = ActivityKind.fromString(json['kind']?.toString() ?? json['type']?.toString()) ??
        ActivityKind.listening;
    return QuestionActivity(
      kind: kind,
      title: json['title']?.toString() ?? kind.badgeLabel,
      transcript: json['transcript']?.toString(),
      language: json['language']?.toString(),
      items: (json['items'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      left: (json['left'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      right: (json['right'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      solution: (json['solution'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'title': title,
        if (transcript != null) 'transcript': transcript,
        if (language != null) 'language': language,
        if (items.isNotEmpty) 'items': items,
        if (left.isNotEmpty) 'left': left,
        if (right.isNotEmpty) 'right': right,
        if (solution.isNotEmpty) 'solution': solution,
      };
}

enum BloomLevel {
  hatirlama('Hatırlama'), anlama('Anlama'), uygulama('Uygulama'),
  analiz('Analiz'), degerlendirme('Değerlendirme'), yaratma('Yaratma');
  const BloomLevel(this.label);
  final String label;
}

enum ResponseType {
  choice('Çoktan seçmeli'), multiSelect('Çoklu seçim'), trueFalse('Doğru / yanlış'),
  fill('Boşluk doldurma'), creation('Açık uçlu tasarım'),
  ordering('Sıralama'), matching('Eşleştirme'), listening('Dinleme'),
  pronunciation('Telaffuz'), slider('Tahmin sürgüsü'), anagram('Harf dizme');
  const ResponseType(this.label);
  final String label;
}

class MultiSelectTask {
  final String prompt;
  final List<String> options;
  final List<int> correct;
  final String explanation;
  const MultiSelectTask(this.prompt, this.options, this.correct, this.explanation);

  bool matches(Set<int> selection) =>
      selection.length == correct.length && correct.every(selection.contains);

  Map<String, dynamic> toJson() =>
      {'prompt': prompt, 'options': options, 'correct': correct, 'explanation': explanation};
  factory MultiSelectTask.fromJson(Map<String, dynamic> json) => MultiSelectTask(
      json['prompt'] as String, List<String>.from(json['options'] as List),
      List<int>.from(json['correct'] as List), json['explanation'] as String);
}

class CreationTask {
  final String brief;
  final List<String> criteria;
  const CreationTask(this.brief, this.criteria);

  Map<String, dynamic> toJson() => {'brief': brief, 'criteria': criteria};
  factory CreationTask.fromJson(Map<String, dynamic> json) => CreationTask(
        json['brief'] as String, List<String>.from(json['criteria'] as List));
}

class Question {
  final String id;
  final String? contentID;
  final String text;
  final List<String> options;
  final int answer;
  final String explanation;
  final List<String> optionExplanations;
  final Topic category;
  final Difficulty difficulty;
  final ExamKind? exam;
  final String? lesson;
  final QuestionVisual? visual;
  final QuestionActivity? activity;
  final String? sourceModel;
  final String? verifiedByModel;
  final BloomLevel? bloom;
  final String? studyLevel;
  final CreationTask? creation;
  final MultiSelectTask? multiSelect;
  final ResponseType _answerMode;

  const Question({
    required this.id,
    this.contentID,
    required this.text,
    required this.options,
    required this.answer,
    required this.explanation,
    this.optionExplanations = const [],
    required this.category,
    required this.difficulty,
    this.exam,
    this.lesson,
    this.visual,
    this.activity,
    this.sourceModel,
    this.verifiedByModel,
    this.bloom,
    this.studyLevel,
    this.creation,
    this.multiSelect,
    ResponseType responseType = ResponseType.choice,
  }) : _answerMode = responseType;

  ResponseType get responseType {
    if (creation != null) return ResponseType.creation;
    if (multiSelect != null) return ResponseType.multiSelect;
    return switch (activity?.kind) {
      ActivityKind.ordering => ResponseType.ordering,
      ActivityKind.matching => ResponseType.matching,
      ActivityKind.listening => ResponseType.listening,
      ActivityKind.dictation => ResponseType.fill,
      ActivityKind.pronunciation => ResponseType.pronunciation,
      ActivityKind.slider => ResponseType.slider,
      ActivityKind.anagram => ResponseType.anagram,
      null => _answerMode,
    };
  }

  /// Match exact academic terms or equivalent numeric fractions/decimals.
  /// Preserve SI unit case, operation signs and inequality symbols.
  bool acceptsWritten(String value) {
    String clean(String s) => s
        .trim()
        .replaceAll('−', '-')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    final expected = clean(correctAnswerText), given = clean(value);
    if (given.isEmpty) return false;
    if (given == expected) return true;
    if (given.length > 2048) return false;
    final number = RegExp(r'^([+-]?\d+(?:[,.]\d+)?(?:[eE][+-]?\d+)?(?:/[+-]?\d+)?)\s*(.*)$');
    String percent(String s) => s.startsWith('%') || s.startsWith('‰')
        ? '${s.substring(1).trim()}${s[0]}' : s;
    final a = number.firstMatch(percent(expected));
    final b = number.firstMatch(percent(given));
    if (a == null || b == null) {
      if (a != null || b != null) return false;
      String stripEndPunct(String s) => s.replaceAll(RegExp(r'[.!?]+$'), '').trim();
      final expTrim = stripEndPunct(expected);
      final givTrim = stripEndPunct(given);
      if (category == Topic.language && expTrim.toLowerCase() == givTrim.toLowerCase()) {
        return true;
      }
      String fold(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
      return fold(expTrim) == fold(givTrim);
    }
    const optionalUnits = {
      '%', '‰', '°', '°C', 'K', 'm', 'km', 'cm', 'mm', 'nm', 'µm',
      'm²', 'cm²', 'km²', 'm³', 'cm³', 'L', 'mL', 'kg', 'g', 'mg',
      's', 'ms', 'dk', 'sa', 'saat', 'dakika', 'saniye', 'gün', 'yıl',
      'm/s', 'm/s²', 'km/sa', 'km/saat', 'N', 'kN', 'J', 'kJ', 'W',
      'kW', 'MW', 'mW', 'Wh', 'kWh', 'Pa', 'kPa', 'MPa', 'Hz', 'kHz', 'MHz',
      'mol', 'mmol', 'mol/L', 'g/L', 'kg/m³', 'V', 'mV', 'A', 'mA', 'Ω',
      'C', 'F', 'TL', 'puan', 'kişi', 'adet', 'bit', 'bayt', 'MB', 'GB',
      'N·s', 'N·m', 'µmol/L', 'kişi/km²', 'g/mol', 'mg/L', 'mmol/L',
    };
    final expectedUnit = a.group(2)!, enteredUnit = b.group(2)!;
    if (expectedUnit != enteredUnit &&
        !(enteredUnit.isEmpty && optionalUnits.contains(expectedUnit))) {
      return false;
    }
    (BigInt, BigInt)? ratio(String s) {
      final fraction = s.toLowerCase().replaceAll(',', '.').split('/');
      final scientific = fraction.first.split('e');
      final places = scientific.first.contains('.') ? scientific.first.split('.').last.length : 0;
      final exponent = scientific.length == 2 ? int.tryParse(scientific.last) : 0;
      if (exponent == null || exponent.abs() > 308) return null;
      final shift = exponent - places;
      final coefficient = BigInt.parse(scientific.first.replaceAll('.', ''));
      final divisor = fraction.length == 2 ? BigInt.parse(fraction.last) : BigInt.one;
      if (divisor == BigInt.zero) return null;
      return (coefficient * BigInt.from(10).pow(max(0, shift)),
          divisor * BigInt.from(10).pow(max(0, -shift)));
    }
    final x = ratio(a.group(1)!), y = ratio(b.group(1)!);
    return x != null && y != null && x.$1 * y.$2 == y.$1 * x.$2;
  }

  String get correctAnswerText {
    if (multiSelect != null) {
      return multiSelect!.correct.map((i) => multiSelect!.options[i]).join(' · ');
    }
    if (activity != null) {
      if (activity!.kind == ActivityKind.ordering ||
          activity!.kind == ActivityKind.matching ||
          activity!.kind == ActivityKind.slider ||
          activity!.kind == ActivityKind.anagram) {
        if (activity!.solution.isNotEmpty || activity!.left.isNotEmpty) {
          return activity!.describeSequence(activity!.solution);
        }
      }
      if (activity!.kind == ActivityKind.pronunciation) {
        return activity!.transcript ?? options.first;
      }
    }
    if (answer >= 0 && answer < options.length) {
      return options[answer];
    }
    return options.isNotEmpty ? options.first : '';
  }

  bool get isInteractiveSequence =>
      activity?.kind == ActivityKind.ordering || activity?.kind == ActivityKind.matching;

  bool get isSlider => activity?.kind == ActivityKind.slider;
  bool get isAnagram => activity?.kind == ActivityKind.anagram;
  bool get isCustomInteractive => isInteractiveSequence || isSlider || isAnagram;

  bool get isPronunciation => activity?.kind == ActivityKind.pronunciation;

  bool get isDictation => activity?.kind == ActivityKind.dictation;

  bool matchesFormat(QuestionFormat format) {
    switch (format) {
      case QuestionFormat.mixed:
        return true;
      case QuestionFormat.visual:
        return visual != null;
      case QuestionFormat.text:
        return visual == null && activity == null && responseType == ResponseType.choice;
      case QuestionFormat.multiSelect:
        return responseType == ResponseType.multiSelect;
      case QuestionFormat.multipleChoice:
        return responseType == ResponseType.choice;
      case QuestionFormat.trueFalse:
        return responseType == ResponseType.trueFalse;
      case QuestionFormat.fill:
        return responseType == ResponseType.fill && activity?.kind != ActivityKind.dictation;
      case QuestionFormat.creation:
        return responseType == ResponseType.creation;
      case QuestionFormat.listening:
        return activity?.kind == ActivityKind.listening;
      case QuestionFormat.dictation:
        return activity?.kind == ActivityKind.dictation;
      case QuestionFormat.ordering:
        return activity?.kind == ActivityKind.ordering;
      case QuestionFormat.matching:
        return activity?.kind == ActivityKind.matching;
      case QuestionFormat.pronunciation:
        return activity?.kind == ActivityKind.pronunciation;
      case QuestionFormat.slider:
        return activity?.kind == ActivityKind.slider;
      case QuestionFormat.anagram:
        return activity?.kind == ActivityKind.anagram;
    }
  }

  // Graph and table questions can share a stem while presenting different evidence.
  String get poolKey => id.startsWith('ak38_') ? id : normalizePoolKey(text);

  static String normalizePoolKey(String raw) {
    final lower = raw
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return lower;
  }

  Question shuffled(Random rng) {
    if (isCustomInteractive || isPronunciation || multiSelect != null || options.length != 4) {
      return this;
    }
    final indices = [0, 1, 2, 3]..shuffle(rng);
    final newOptions = [for (final idx in indices) options[idx]];
    final newAnswer = indices.indexOf(answer);
    final newOptExp = optionExplanations.length == 4
        ? [for (final idx in indices) optionExplanations[idx]]
        : optionExplanations;
    return Question(
      id: id,
      contentID: contentID,
      text: text,
      options: newOptions,
      answer: newAnswer < 0 ? 0 : newAnswer,
      explanation: explanation,
      optionExplanations: newOptExp,
      category: category,
      difficulty: difficulty,
      exam: exam,
      lesson: lesson,
      visual: visual,
      activity: activity,
      sourceModel: sourceModel,
      verifiedByModel: verifiedByModel,
      bloom: bloom, studyLevel: studyLevel, creation: creation, multiSelect: multiSelect, responseType: _answerMode,
    );
  }

  factory Question.fromJson(Map<String, dynamic> json, {int fallbackIndex = 0}) {
    final rawOpts = (json['options'] as List?)?.map((e) => e.toString()).toList() ??
        const ['A', 'B', 'C', 'D'];
    final mode = ResponseType.values.where((v) => v.name == json['responseType']).firstOrNull
        ?? ResponseType.choice;
    final opts = mode == ResponseType.trueFalse && rawOpts.length == 2 ? rawOpts : rawOpts.length >= 4
        ? rawOpts.sublist(0, 4)
        : [...rawOpts, ...List.filled(4 - rawOpts.length, '-')];
    final ans = ((json['answer'] as num?)?.toInt() ?? 0).clamp(0, opts.length - 1);
    final contentId = json['contentID']?.toString();
    final id = json['id']?.toString() ??
        contentId ??
        'q_${fallbackIndex}_${json['text'].hashCode.abs()}';
    return Question(
      id: id,
      contentID: contentId,
      text: json['text']?.toString() ?? '',
      options: opts,
      answer: ans,
      explanation: json['explanation']?.toString() ?? '',
      optionExplanations:
          (json['optionExplanations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      category: Topic.fromLabel(json['category']?.toString() ?? json['topic']?.toString()),
      difficulty: Difficulty.fromLabel(json['difficulty']?.toString()),
      exam: ExamKind.fromLabel(json['exam']?.toString()),
      lesson: json['lesson']?.toString(),
      visual: json['visual'] is Map
          ? QuestionVisual.fromJson(Map<String, dynamic>.from(json['visual'] as Map))
          : null,
      activity: json['activity'] is Map
          ? QuestionActivity.fromJson(Map<String, dynamic>.from(json['activity'] as Map))
          : null,
      sourceModel: json['sourceModel']?.toString(),
      verifiedByModel: json['verifiedByModel']?.toString(),
      bloom: BloomLevel.values.where((b) => b.name == json['bloom']).firstOrNull,
      studyLevel: json['studyLevel'] as String?,
      creation: json['creation'] is Map
          ? CreationTask.fromJson(Map<String, dynamic>.from(json['creation'])) : null,
      multiSelect: json['multiSelect'] is Map
          ? MultiSelectTask.fromJson(Map<String, dynamic>.from(json['multiSelect'])) : null,
      responseType: mode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (contentID != null) 'contentID': contentID,
        'text': text,
        'options': options,
        'answer': answer,
        'explanation': explanation,
        if (optionExplanations.isNotEmpty) 'optionExplanations': optionExplanations,
        'category': category.label,
        'difficulty': difficulty.label,
        if (exam != null) 'exam': exam!.label,
        if (lesson != null) 'lesson': lesson,
        if (visual != null) 'visual': visual!.toJson(),
        if (activity != null) 'activity': activity!.toJson(),
        if (sourceModel != null) 'sourceModel': sourceModel,
        if (verifiedByModel != null) 'verifiedByModel': verifiedByModel,
        if (bloom != null) 'bloom': bloom!.name,
        if (studyLevel != null) 'studyLevel': studyLevel,
        if (creation != null) 'creation': creation!.toJson(),
        if (multiSelect != null) 'multiSelect': multiSelect!.toJson(),
        if (responseType != ResponseType.choice) 'responseType': responseType.name,
      };
}

class AnswerRecord {
  final Question question;
  final int? selectedOption;
  final List<int>? submittedSequence;
  final String? spokenTranscript;
  final bool correct;
  final int earnedPoints;
  final int elapsedSeconds;
  final int? duelPlayerIndex;
  final String? writtenResponse;

  const AnswerRecord({
    required this.question,
    this.selectedOption,
    this.submittedSequence,
    this.spokenTranscript,
    required this.correct,
    required this.earnedPoints,
    required this.elapsedSeconds,
    this.duelPlayerIndex,
    this.writtenResponse,
  });
}

class RoundSetup {
  final Topic topic;
  /// Birden fazla kategori seçildiğinde kullanılır; boşsa [topic] esas alınır.
  final Set<Topic> selectedTopics;
  final Difficulty? difficulty; // null = mixed difficulty
  final GameMode mode;
  final QuestionFormat format;
  final int questionCount;
  final int timedMinutes; // for GameMode.timed (1..30)
  final ExamKind exam;
  final String? lesson;
  final String customTopicPrompt;
  final bool liveVoiceHost;
  final List<String> duelPlayerNames; // empty = solo, 2..10 = sırayla oynayan oyuncular
  /// Klasik modda soru başına süre (sn); boşsa varsayılan 15 sn.
  final int? secondsPerQuestion;
  /// Bilgisayar rakipleri (Bire Bir, Çoklu); her soruda kendi hızlarıyla cevaplar.
  final List<String> rivalNames;

  const RoundSetup({
    this.topic = Topic.mixed,
    this.selectedTopics = const {},
    this.difficulty,
    this.mode = GameMode.classic,
    this.format = QuestionFormat.mixed,
    this.questionCount = 10,
    this.timedMinutes = 3,
    this.exam = ExamKind.tyt,
    this.lesson,
    this.customTopicPrompt = '',
    this.liveVoiceHost = false,
    this.duelPlayerNames = const [],
    this.secondsPerQuestion,
    this.rivalNames = const [],
  });

  /// Etkin seçili kategori kümesi. Boş küme "tüm kategoriler / karışık" demektir.
  Set<Topic> get effectiveTopics {
    if (selectedTopics.isNotEmpty) {
      return selectedTopics
          .where((t) => t != Topic.mixed && t != Topic.custom)
          .toSet();
    }
    if (topic != Topic.mixed && topic != Topic.custom) {
      return {topic};
    }
    return const {};
  }

  bool get isMultiTopic => effectiveTopics.length > 1;

  bool isTopicSelected(Topic t) {
    final active = effectiveTopics;
    if (t == Topic.mixed) return active.isEmpty && topic != Topic.custom;
    if (t == Topic.custom) return active.isEmpty && topic == Topic.custom;
    return active.contains(t);
  }

  String get topicsLabel {
    final active = effectiveTopics;
    if (active.isEmpty) {
      return topic == Topic.custom ? Topic.custom.label : Topic.mixed.label;
    }
    final ordered = Topic.poolCategories.where(active.contains).toList();
    if (ordered.length == 1) return ordered.first.label;
    if (ordered.length == 2) return '${ordered[0].label} + ${ordered[1].label}';
    return '${ordered[0].label}, ${ordered[1].label} +${ordered.length - 2}';
  }

  RoundSetup copyWith({
    Topic? topic,
    Set<Topic>? selectedTopics,
    Difficulty? Function()? difficulty,
    GameMode? mode,
    QuestionFormat? format,
    int? questionCount,
    int? timedMinutes,
    ExamKind? exam,
    String? Function()? lesson,
    String? customTopicPrompt,
    bool? liveVoiceHost,
    List<String>? duelPlayerNames,
    int? secondsPerQuestion,
    List<String>? rivalNames,
  }) {
    final nextTopic = topic ?? this.topic;
    final Set<Topic> nextSelected;
    if (selectedTopics != null) {
      nextSelected = Set<Topic>.unmodifiable(
        selectedTopics.where((t) => t != Topic.mixed && t != Topic.custom),
      );
    } else if (topic != null) {
      nextSelected = (topic == Topic.mixed || topic == Topic.custom)
          ? const {}
          : Set<Topic>.unmodifiable({topic});
    } else {
      nextSelected = this.selectedTopics;
    }
    return RoundSetup(
      topic: nextTopic,
      selectedTopics: nextSelected,
      difficulty: difficulty != null ? difficulty() : this.difficulty,
      mode: mode ?? this.mode,
      format: format ?? this.format,
      questionCount: questionCount ?? this.questionCount,
      timedMinutes: timedMinutes ?? this.timedMinutes,
      exam: exam ?? this.exam,
      lesson: lesson != null ? lesson() : this.lesson,
      customTopicPrompt: customTopicPrompt ?? this.customTopicPrompt,
      liveVoiceHost: liveVoiceHost ?? this.liveVoiceHost,
      duelPlayerNames: duelPlayerNames ?? this.duelPlayerNames,
      secondsPerQuestion: secondsPerQuestion ?? this.secondsPerQuestion,
      rivalNames: rivalNames ?? this.rivalNames,
    );
  }
}

class RoundSummary {
  final String id;
  final DateTime playedAt;
  final String title;
  final Topic topic;
  final GameMode mode;
  final int totalQuestions;
  final int correctCount;
  final int totalScore;
  final int xpGained;
  final int maxStreak;
  final bool wasLiveVoice;
  final List<Map<String, dynamic>> duelStandings;

  const RoundSummary({
    required this.id,
    required this.playedAt,
    required this.title,
    required this.topic,
    required this.mode,
    required this.totalQuestions,
    required this.correctCount,
    required this.totalScore,
    required this.xpGained,
    required this.maxStreak,
    this.wasLiveVoice = false,
    this.duelStandings = const [],
  });

  double get accuracy => totalQuestions == 0 ? 0 : correctCount / totalQuestions;

  Map<String, dynamic> toJson() => {
        'id': id,
        'playedAt': playedAt.toIso8601String(),
        'title': title,
        'topic': topic.label,
        'mode': mode.name,
        'totalQuestions': totalQuestions,
        'correctCount': correctCount,
        'totalScore': totalScore,
        'xpGained': xpGained,
        'maxStreak': maxStreak,
        'wasLiveVoice': wasLiveVoice,
        if (duelStandings.isNotEmpty) 'duelStandings': duelStandings,
      };

  factory RoundSummary.fromJson(Map<String, dynamic> json) => RoundSummary(
        id: json['id']?.toString() ?? '',
        playedAt: DateTime.tryParse(json['playedAt']?.toString() ?? '') ?? DateTime.now(),
        title: json['title']?.toString() ?? 'Bilgi Turu',
        topic: Topic.fromLabel(json['topic']?.toString()),
        mode: GameMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => GameMode.classic,
        ),
        totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 10,
        correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
        totalScore: (json['totalScore'] as num?)?.toInt() ?? 0,
        xpGained: (json['xpGained'] as num?)?.toInt() ?? 0,
        maxStreak: (json['maxStreak'] as num?)?.toInt() ?? 0,
        wasLiveVoice: json['wasLiveVoice'] == true,
        duelStandings: (json['duelStandings'] as List?)
                ?.whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            const [],
      );
}

class ReviewCard {
  final Question question;
  final int box; // Leitner box 0..5
  final int attempts;
  final int correct;
  final DateTime due;

  const ReviewCard({
    required this.question,
    this.box = 0,
    this.attempts = 1,
    this.correct = 0,
    required this.due,
  });

  ReviewCard recordOutcome(bool wasCorrect, DateTime now) {
    if (wasCorrect) {
      final nextBox = (box + 1).clamp(1, 5);
      final durations = [
        const Duration(minutes: 10),
        const Duration(days: 1),
        const Duration(days: 3),
        const Duration(days: 7),
        const Duration(days: 14),
        const Duration(days: 30),
      ];
      return ReviewCard(
        question: question,
        box: nextBox,
        attempts: attempts + 1,
        correct: correct + 1,
        due: now.add(durations[nextBox]),
      );
    } else {
      return ReviewCard(
        question: question,
        box: 0,
        attempts: attempts + 1,
        correct: correct,
        due: now.add(const Duration(minutes: 5)),
      );
    }
  }

  Map<String, dynamic> toJson() => {
        'question': question.toJson(),
        'box': box,
        'attempts': attempts,
        'correct': correct,
        'due': due.toIso8601String(),
      };

  factory ReviewCard.fromJson(Map<String, dynamic> json) => ReviewCard(
        question: Question.fromJson(
          Map<String, dynamic>.from((json['question'] as Map?) ?? const {}),
        ),
        box: (json['box'] as num?)?.toInt() ?? 0,
        attempts: (json['attempts'] as num?)?.toInt() ?? 1,
        correct: (json['correct'] as num?)?.toInt() ?? 0,
        due: DateTime.tryParse(json['due']?.toString() ?? '') ?? DateTime.now(),
      );
}

class QuestionPack {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<String> models;
  final List<Question> questions;

  const QuestionPack({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.models,
    required this.questions,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'models': models,
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  factory QuestionPack.fromJson(Map<String, dynamic> json) {
    final rawQuestions = (json['questions'] as List?) ?? const [];
    final parsed = <Question>[];
    for (var i = 0; i < rawQuestions.length; i++) {
      final item = rawQuestions[i];
      if (item is Map) {
        parsed.add(Question.fromJson(Map<String, dynamic>.from(item), fallbackIndex: i));
      }
    }
    return QuestionPack(
      id: json['id']?.toString() ??
          json['packID']?.toString() ??
          'pack_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? 'Soru Paketi (${parsed.length})',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      models: (json['models'] as List?)?.map((e) => e.toString()).toList() ?? const ['Yerel Paket'],
      questions: parsed,
    );
  }

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

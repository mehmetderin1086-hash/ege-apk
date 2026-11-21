import 'dart:collection';

import 'applied.dart';
import 'common.dart';
import 'math.dart';
import 'physics.dart';
import 'plates.dart';
import 'renewed.dart';
import 'social.dart';

enum PoolCollection {
  all('Tümü'),
  personal('Kişisel'),
  highSchool('Lise'),
  university('Üniversite');

  final String label;
  const PoolCollection(this.label);

  StudyLevel? get level => switch (this) {
    highSchool => StudyLevel.lise,
    university => StudyLevel.universite,
    _ => null,
  };
}

class AdvancedCatalog {
  static final families = List<AdvancedFamily>.unmodifiable([
    ...mathFamilies,
    ...physicsFamilies,
    ...socialFamilies,
    ...appliedFamilies,
    ...plateFamilies,
    ...renewedFamilies,
  ]);
  static final _byKey = {for (final f in families) f.key: f};
  static final all = FamilyQuestions(families);
  static final visuals = select(format: QuestionFormat.visual);
  static final activityCount = [
    QuestionFormat.listening,
    QuestionFormat.pronunciation,
    QuestionFormat.ordering,
    QuestionFormat.matching,
  ].fold<int>(0, (n, format) => n + select(format: format).length);

  static ({AdvancedFamily family, int index})? _locate(String id) {
    if (!id.startsWith('ak38_')) return null;
    final split = id.lastIndexOf('_');
    if (split <= 5) return null;
    final family = _byKey[id.substring(5, split)];
    final tail = id.substring(split + 1);
    final index = int.tryParse(tail);
    if (family == null || index == null || index < 0 || index >= family.count ||
        index.toString() != tail) {
      return null;
    }
    return (family: family, index: index);
  }

  static bool hasId(String id) => _locate(id) != null;

  static Question? questionById(String id) {
    final location = _locate(id);
    return location?.family.questionAt(location.index);
  }

  static FamilyQuestions select({
    Topic topic = Topic.mixed,
    QuestionFormat format = QuestionFormat.mixed,
    StudyLevel? level,
    BloomLevel? bloom,
    Difficulty? difficulty,
    ExamKind? exam,
    String? lesson,
    VisualKind? visualKind,
    bool? requireVisual,
  }) {
    return FamilyQuestions(
      families.where((f) {
        if (topic == Topic.exam) {
          if (f.exam == null && f.topic != Topic.exam) return false;
        } else if (topic != Topic.mixed &&
            topic != Topic.custom &&
            topic != f.topic) {
          return false;
        }
        if (level != null && f.level != level) return false;
        if (bloom != null && f.bloom != bloom) return false;
        if (difficulty != null && f.difficulty != difficulty) return false;
        if (exam != null && f.exam != exam) return false;
        if (lesson != null && lesson.isNotEmpty && f.lesson != lesson) {
          return false;
        }
        if (requireVisual != null && (f.visualKind != null) != requireVisual) {
          return false;
        }
        return visualKind == null || f.visualKind == visualKind;
      }),
      format: format,
    );
  }

  static final Map<Topic, int> topicCounts = {
    for (final t in Topic.values) t: select(topic: t).length,
  };
}

abstract class _ReadOnlyQuestions extends ListBase<Question> {
  @override
  set length(int value) => throw UnsupportedError('Salt okunur soru bankası');

  @override
  void operator []=(int index, Question value) =>
      throw UnsupportedError('Salt okunur soru bankası');
}

// Rows alternate families. A family of six images is browsable alongside a
// family of 5,000 problems, without creating any of those questions upfront.
class FamilyQuestions extends _ReadOnlyQuestions {
  final List<({int end, int firstRow, List<AdvancedFamily> families})> _bands =
      [];

  final QuestionFormat format;

  FamilyQuestions(
    Iterable<AdvancedFamily> source, {
    this.format = QuestionFormat.mixed,
  }) {
    final counts = {for (final f in source) f: f.countForFormat(format)};
    final sizes = counts.values.where((n) => n > 0).toSet().toList()..sort();
    var first = 0;
    var end = 0;
    for (final size in sizes) {
      final active = [
        for (final f in counts.keys)
          if (counts[f]! >= size) f,
      ];
      end += active.length * (size - first);
      _bands.add((end: end, firstRow: first, families: active));
      first = size;
    }
  }

  @override
  int get length => _bands.isEmpty ? 0 : _bands.last.end;

  @override
  Question operator [](int index) {
    RangeError.checkValidIndex(index, this);
    var start = 0;
    for (final band in _bands) {
      if (index < band.end) {
        final offset = index - start;
        final width = band.families.length;
        final family = band.families[offset % width];
        final local = family.indexForFormat(
          format,
          band.firstRow + offset ~/ width,
        );
        return family.questionAt(local);
      }
      start = band.end;
    }
    throw RangeError.index(index, this);
  }
}

class JoinedQuestions extends _ReadOnlyQuestions {
  final List<Question> left;
  final List<Question> right;

  JoinedQuestions(this.left, this.right);

  @override
  int get length => left.length + right.length;

  @override
  Question operator [](int index) =>
      index < left.length ? left[index] : right[index - left.length];
}

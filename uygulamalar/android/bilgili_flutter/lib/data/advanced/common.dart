import '../../models/quiz_models.dart';
export '../../models/quiz_models.dart';

enum StudyLevel {
  lise('Lise'),
  universite('Üniversite');

  final String label;
  const StudyLevel(this.label);
}

/// One question specification. Distractors and the key are kept separate
/// until a final, reproducible option order is selected.
class AdvancedItem {
  final String prompt;
  final String correct;
  final List<String> wrong;
  final String explanation;
  final QuestionVisual? visual;
  final QuestionActivity? activity;

  const AdvancedItem(this.prompt, this.correct, this.wrong, this.explanation,
      {this.visual, this.activity});
}

class AdvancedFamily {
  final String key;
  final String title;
  final Topic topic;
  final StudyLevel level;
  final int count;
  final Difficulty difficulty;
  final VisualKind? visualKind;
  final ExamKind? exam;
  final String? lesson;
  final AdvancedItem Function(int) build;
  final BloomLevel bloom;
  final bool shortAnswer;
  final ActivityKind? activityKind;
  final CreationTask Function(AdvancedItem, int)? creation;
  final MultiSelectTask Function(AdvancedItem, int)? multiSelect;


  const AdvancedFamily({
    required this.key,
    required this.title,
    required this.topic,
    required this.level,
    required this.count,
    required this.difficulty,
    required this.build,
    this.visualKind,
    this.bloom = BloomLevel.uygulama,
    this.shortAnswer = false,
    this.activityKind,
    this.creation,
    this.multiSelect,
    this.exam,
    this.lesson,
  });

  ResponseType responseAt(int index) {
    if (creation != null) return ResponseType.creation;
    if (multiSelect != null) return ResponseType.multiSelect;
    if (activityKind != null) {
      return switch (activityKind!) {
        ActivityKind.ordering => ResponseType.ordering,
        ActivityKind.matching => ResponseType.matching,
        ActivityKind.listening => ResponseType.listening,
        ActivityKind.pronunciation => ResponseType.pronunciation,
      };
    }
    // Stable response modes for each distinct case; formats do not multiply the count.
    return switch ((index + _salt) % 8) {
      1 || 5 => ResponseType.trueFalse,
      2 || 6 || 7 when shortAnswer => ResponseType.fill,
      _ => ResponseType.choice,
    };
  }

  int get _salt => key.codeUnits.fold<int>(0, (a, b) => a + b);

  bool _matches(QuestionFormat format, int i) => switch (format) {
        QuestionFormat.mixed => true,
        QuestionFormat.visual => visualKind != null,
        QuestionFormat.text => visualKind == null && activityKind == null,
        QuestionFormat.multiSelect => responseAt(i) == ResponseType.multiSelect,
        QuestionFormat.multipleChoice => responseAt(i) == ResponseType.choice,
        QuestionFormat.trueFalse => responseAt(i) == ResponseType.trueFalse,
        QuestionFormat.fill => responseAt(i) == ResponseType.fill,
        QuestionFormat.creation => responseAt(i) == ResponseType.creation,
        QuestionFormat.listening => activityKind == ActivityKind.listening,
        QuestionFormat.ordering => activityKind == ActivityKind.ordering,
        QuestionFormat.matching => activityKind == ActivityKind.matching,
        QuestionFormat.pronunciation => activityKind == ActivityKind.pronunciation,
      };

  List<int> _offsets(QuestionFormat format) =>
      [for (var i = 0; i < 8; i++) if (_matches(format, i)) i];

  int countForFormat(QuestionFormat format) {
    if (format == QuestionFormat.mixed) return count;
    final offsets = _offsets(format);
    return count ~/ 8 * offsets.length + offsets.where((i) => i < count % 8).length;
  }

  int indexForFormat(QuestionFormat format, int offset) {
    if (format == QuestionFormat.mixed) return offset;
    final offsets = _offsets(format);
    return offset ~/ offsets.length * 8 + offsets[offset % offsets.length];
  }

  Question questionAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', count);
    final item = build(index);
    final mode = responseAt(index);
    final design = creation?.call(item, index);
    final multiple = multiSelect?.call(item, index);
    // Mix consecutive variants without storing per-question option orders.
    // Every group of four uses each correct position once.
    final block = index ~/ 4;
    final phase = (key.codeUnits.fold(0, (a, b) => a + b) + block * 37 +
            (block ~/ 13) * 17) & 3;
    final answer = ((index & 3) + phase) & 3;
    final offset = (block + index) % 3;
    final options = List.generate(3, (j) => item.wrong[(j + offset) % 3])
      ..insert(answer, item.correct);
    final isBinary = mode == ResponseType.trueFalse;
    final statementCorrect = ((index ~/ 8 + index ~/ 4 + _salt ~/ 8) % 2) == 0;
    final proposed = statementCorrect ? item.correct : item.wrong[(index ~/ 2) % 3];
    final id = 'ak38_${key}_$index';
    return Question(
      id: id,
      contentID: id,
      text: multiple?.prompt ?? (isBinary
          ? '${item.prompt}\nÖnerilen yanıt: “$proposed”. Bu yanıt doğru mu?'
          : item.prompt),
      options: multiple?.options ?? (isBinary ? const ['Doğru', 'Yanlış'] : options),
      answer: multiple?.correct.first ?? (isBinary ? (statementCorrect ? 0 : 1) : answer),
      explanation: multiple?.explanation ?? (isBinary
          ? 'Doğru yanıt: ${item.correct}. ${item.explanation}'
          : item.explanation),
      bloom: bloom,
      studyLevel: level.label,
      responseType: mode,
      creation: design,
      multiSelect: multiple,
      activity: item.activity,
      category: topic,
      difficulty: difficulty,
      exam: exam,
      lesson: lesson ?? title,
      visual: item.visual,
      sourceModel: 'GPT-6.2 Astra · Akademik Banka',
    );
  }
}

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
  final ResponseType? fixedResponseType;
  final CreationTask Function(AdvancedItem, int)? creation;
  final MultiSelectTask Function(AdvancedItem, int)? multiSelect;

  /// Sorunun kaynak etiketi; verilmezse akademik bankanın etiketi kullanılır.
  final String? sourceLabel;

  /// Seçkiyle daraltılmış ailelerde her yerel sıranın özgün vaka numarası.
  /// Soru kimlikleri özgün numarayı taşır; böylece kayıtlı istatistikler
  /// seçkiden sonra da aynı soruya bağlı kalır.
  final List<int>? ozgunSira;

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
    this.fixedResponseType,
    this.creation,
    this.multiSelect,
    this.exam,
    this.lesson,
    this.sourceLabel,
    this.ozgunSira,
  });

  /// Yalnız [secki] içindeki özgün vakaları sunan aile.
  AdvancedFamily secili(List<int> secki) => AdvancedFamily(
        key: key,
        title: title,
        topic: topic,
        level: level,
        count: secki.length,
        difficulty: difficulty,
        build: (j) => build(secki[j]),
        visualKind: visualKind,
        bloom: bloom,
        shortAnswer: shortAnswer,
        activityKind: activityKind,
        fixedResponseType: fixedResponseType,
        creation: creation,
        multiSelect: multiSelect,
        exam: exam,
        lesson: lesson,
        sourceLabel: sourceLabel,
        ozgunSira: List.unmodifiable(secki),
      );

  static final _yerelSiralar = Expando<Map<int, int>>();

  /// Soru kimliğindeki özgün numaranın bu ailedeki yerel sırası.
  int? yerelSira(int ozgun) {
    final secki = ozgunSira;
    if (secki == null) return ozgun >= 0 && ozgun < count ? ozgun : null;
    final harita = _yerelSiralar[secki] ??=
        {for (var j = 0; j < secki.length; j++) secki[j]: j};
    return harita[ozgun];
  }

  int ozgunNumara(int yerel) => ozgunSira?[yerel] ?? yerel;

  ResponseType responseAt(int index) {
    if (creation != null) return ResponseType.creation;
    if (multiSelect != null) return ResponseType.multiSelect;
    if (activityKind != null) {
      return switch (activityKind!) {
        ActivityKind.ordering => ResponseType.ordering,
        ActivityKind.matching => ResponseType.matching,
        ActivityKind.listening => ResponseType.listening,
        ActivityKind.dictation => ResponseType.fill,
        ActivityKind.pronunciation => ResponseType.pronunciation,
      };
    }
    if (fixedResponseType != null) return fixedResponseType!;
    return ResponseType.choice;
  }

  int get _salt => key.codeUnits.fold<int>(0, (a, b) => a + b);

  bool _matches(QuestionFormat format, int i) => switch (format) {
        QuestionFormat.mixed => true,
        QuestionFormat.visual => visualKind != null,
        QuestionFormat.text =>
            visualKind == null && activityKind == null && responseAt(i) == ResponseType.choice,
        QuestionFormat.multiSelect => responseAt(i) == ResponseType.multiSelect,
        QuestionFormat.multipleChoice => responseAt(i) == ResponseType.choice,
        QuestionFormat.trueFalse => responseAt(i) == ResponseType.trueFalse,
        QuestionFormat.fill =>
            responseAt(i) == ResponseType.fill && activityKind != ActivityKind.dictation,
        QuestionFormat.creation => responseAt(i) == ResponseType.creation,
        QuestionFormat.listening => activityKind == ActivityKind.listening,
        QuestionFormat.dictation => activityKind == ActivityKind.dictation,
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
    final id = 'ak38_${key}_${ozgunNumara(index)}';

    final isBinary = mode == ResponseType.trueFalse;
    final isNativeBinary = isBinary &&
        (item.correct == 'Doğru' || item.correct == 'Yanlış');

    late final String qText;
    late final List<String> qOptions;
    late final int qAnswer;
    late final String qExplanation;

    if (multiple != null) {
      qText = multiple.prompt;
      qOptions = multiple.options;
      qAnswer = multiple.correct.first;
      qExplanation = multiple.explanation;
    } else if (isNativeBinary) {
      qText = item.prompt;
      qOptions = const ['Doğru', 'Yanlış'];
      qAnswer = item.correct == 'Doğru' ? 0 : 1;
      qExplanation = item.explanation;
    } else if (isBinary) {
      final statementCorrect = ((index ~/ 8 + index ~/ 4 + _salt ~/ 8) % 2) == 0;
      final proposed = statementCorrect
          ? item.correct
          : item.wrong[(index ~/ 2) % item.wrong.length];
      qText = '${item.prompt}\nÖnerilen yanıt: “$proposed”. Bu yanıt doğru mu?';
      qOptions = const ['Doğru', 'Yanlış'];
      qAnswer = statementCorrect ? 0 : 1;
      qExplanation = 'Doğru yanıt: ${item.correct}. ${item.explanation}';
    } else if (mode == ResponseType.fill) {
      qText = item.prompt;
      qOptions = [item.correct, ...item.wrong];
      qAnswer = 0;
      qExplanation = item.explanation;
    } else {
      // Mix consecutive variants without storing per-question option orders.
      // Every group of four uses each correct position once.
      final block = index ~/ 4;
      final phase = (key.codeUnits.fold(0, (a, b) => a + b) + block * 37 +
              (block ~/ 13) * 17) & 3;
      final answer = ((index & 3) + phase) & 3;
      final offset = (block + index) % 3;
      final options = List.generate(3, (j) => item.wrong[(j + offset) % item.wrong.length])
        ..insert(answer, item.correct);
      qText = item.prompt;
      qOptions = options;
      qAnswer = answer;
      qExplanation = item.explanation;
    }

    return Question(
      id: id,
      contentID: id,
      text: qText,
      options: qOptions,
      answer: qAnswer,
      explanation: qExplanation,
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
      sourceModel: sourceLabel ?? 'GPT-6.2 Astra · Akademik Banka',
    );
  }
}

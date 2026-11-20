import 'dart:math';
import '../models/quiz_models.dart';

enum SpokenVoiceCommand { pause, repeatQuestion, skip }

class ResolvedSpokenAnswer {
  final int? choiceIndex;
  final List<int>? sequence;
  final double confidence;

  const ResolvedSpokenAnswer.choice(this.choiceIndex, {this.confidence = 1.0})
      : sequence = null;

  const ResolvedSpokenAnswer.sequence(this.sequence, {this.confidence = 1.0})
      : choiceIndex = null;
}

class VoiceAnswerResolver {
  static String clean(String input) {
    final folded = input
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('i̇', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll('ä', 'a')
        .replaceAll('ß', 'ss')
        .replaceAll('ñ', 'n')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return folded;
  }

  static SpokenVoiceCommand? detectCommand(String raw) {
    final c = clean(raw);
    const pauseSet = {
      'dur',
      'duraklat',
      'durdur',
      'mola',
      'bekle',
      'mola ver',
    };
    const repeatSet = {
      'tekrar',
      'tekrar oku',
      'soruyu tekrar oku',
      'tekrar et',
      'yeniden oku',
      'bir daha oku',
      'bir daha',
      'soruyu tekrarla',
      'tekrarla',
    };
    const skipSet = {
      'gec',
      'soruyu gec',
      'pas',
      'pas gec',
      'atla',
      'soruyu atla',
      'sonraki',
      'sonraki soru',
    };
    if (pauseSet.contains(c)) return SpokenVoiceCommand.pause;
    if (repeatSet.contains(c)) return SpokenVoiceCommand.repeatQuestion;
    if (skipSet.contains(c)) return SpokenVoiceCommand.skip;
    return null;
  }

  static String stripFillers(String raw) {
    var tokens = clean(raw).split(' ').where((t) => t.isNotEmpty).toList();
    const leadingFillers = {
      'bence',
      'sanirim',
      'galiba',
      'kesinlikle',
      'cevap',
      'cevabim',
      'yanit',
      'yanitim',
      'dogru',
      'secenek',
      'sik',
      'sikki',
      'ben',
    };
    const trailingFillers = {
      'sikki',
      'sik',
      'secenegi',
      'secenek',
      'olsun',
      'diyorum',
      'eminim',
      'olabilir',
      'olmali',
      'dir',
      'tir',
    };
    while (tokens.length > 1 && leadingFillers.contains(tokens.first)) {
      tokens.removeAt(0);
    }
    while (tokens.length > 1 && trailingFillers.contains(tokens.last)) {
      tokens.removeLast();
    }
    return tokens.join(' ').trim();
  }

  static ResolvedSpokenAnswer? resolve(
    String rawTranscript,
    Question question, {
    List<String> alternatives = const [],
  }) {
    final candidates = <String>[
      rawTranscript,
      ...alternatives.where((a) => a.trim().isNotEmpty && a != rawTranscript),
    ];
    for (final candidate in candidates) {
      final result = _resolveSingle(candidate, question);
      if (result != null) return result;
    }
    return null;
  }

  static ResolvedSpokenAnswer? _resolveSingle(String raw, Question question) {
    final stripped = stripFillers(raw);
    if (stripped.isEmpty) return null;

    // 1. Pronunciation target phrase check
    if (question.isPronunciation) {
      final target = clean(question.activity?.transcript ?? question.options.first);
      final spoken = clean(raw);
      if (target.isEmpty || spoken.isEmpty) return null;
      final sim = similarity(spoken, target);
      if (spoken.contains(target) || target.contains(spoken) && spoken.length >= target.length * 0.7 || sim >= 0.68) {
        return ResolvedSpokenAnswer.choice(0, confidence: sim);
      }
      return null;
    }

    // 2. Interactive 4-item sequence (ordering / matching)
    if (question.isInteractiveSequence) {
      final seq = parseFourIndices(stripped);
      if (seq != null) {
        return ResolvedSpokenAnswer.sequence(seq);
      }
    }

    // 3. Direct single-letter / ordinal / letter-name match
    final direct = _matchLetterOrOrdinal(stripped);
    if (direct != null && direct < question.options.length) {
      return ResolvedSpokenAnswer.choice(direct);
    }

    // Check patterns like "c sikki" or "ikinci secenek" inside raw
    final rawTokens = clean(raw).split(' ').where((e) => e.isNotEmpty).toList();
    if (rawTokens.length <= 4) {
      for (var i = 0; i < rawTokens.length; i++) {
        final t = rawTokens[i];
        if (i + 1 < rawTokens.length &&
            const {'sik', 'sikki', 'secenek', 'secenegi'}.contains(rawTokens[i + 1])) {
          final idx = _matchLetterOrOrdinal(t);
          if (idx != null && idx < question.options.length) {
            return ResolvedSpokenAnswer.choice(idx);
          }
        }
      }
    }

    // 4. Exact or normalized option text match
    final normOptions = question.options.map(clean).toList();
    final exactMatches = <int>[];
    for (var i = 0; i < normOptions.length; i++) {
      if (normOptions[i].isNotEmpty && normOptions[i] == stripped) {
        exactMatches.add(i);
      }
    }
    if (exactMatches.length == 1) {
      return ResolvedSpokenAnswer.choice(exactMatches.first);
    }

    // 5. Substring containment if unambiguous
    if (stripped.length >= 3) {
      final containsMatches = <int>[];
      for (var i = 0; i < normOptions.length; i++) {
        final opt = normOptions[i];
        if (opt.isEmpty) continue;
        if (opt.contains(stripped) || stripped.contains(opt)) {
          containsMatches.add(i);
        }
      }
      if (containsMatches.length == 1) {
        return ResolvedSpokenAnswer.choice(containsMatches.first, confidence: 0.86);
      }
    }

    // 6. Unique closest fuzzy Levenshtein match
    var bestIdx = -1;
    var bestScore = 0.0;
    var secondBest = 0.0;
    for (var i = 0; i < normOptions.length; i++) {
      final opt = normOptions[i];
      if (opt.isEmpty) continue;
      final s = similarity(stripped, opt);
      if (s > bestScore) {
        secondBest = bestScore;
        bestScore = s;
        bestIdx = i;
      } else if (s > secondBest) {
        secondBest = s;
      }
    }
    if (bestIdx >= 0 && bestScore >= 0.66 && (bestScore - secondBest) >= 0.10) {
      return ResolvedSpokenAnswer.choice(bestIdx, confidence: bestScore);
    }

    return null;
  }

  static int? _matchLetterOrOrdinal(String token) {
    switch (token) {
      case 'a':
      case 'aa':
      case '1':
      case 'bir':
      case 'birinci':
      case 'ilk':
        return 0;
      case 'b':
      case 'be':
      case 'bee':
      case '2':
      case 'iki':
      case 'ikinci':
        return 1;
      case 'c':
      case 'ce':
      case 'cee':
      case '3':
      case 'uc':
      case 'ucuncu':
        return 2;
      case 'd':
      case 'de':
      case 'dee':
      case '4':
      case 'dort':
      case 'dorduncu':
      case 'son':
      case 'sonuncu':
        return 3;
      default:
        return null;
    }
  }

  static List<int>? parseFourIndices(String text) {
    final compactDigits = text.replaceAll(' ', '');
    if (RegExp(r'^[1-4]{4}$').hasMatch(compactDigits)) {
      final vals = compactDigits.split('').map((c) => int.parse(c) - 1).toList();
      if (vals.toSet().length == 4) return vals;
    }
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    final mapped = <int>[];
    for (final t in tokens) {
      switch (t) {
        case '1':
        case 'bir':
        case 'birinci':
          mapped.add(0);
          break;
        case '2':
        case 'iki':
        case 'ikinci':
          mapped.add(1);
          break;
        case '3':
        case 'uc':
        case 'ucuncu':
          mapped.add(2);
          break;
        case '4':
        case 'dort':
        case 'dorduncu':
          mapped.add(3);
          break;
      }
    }
    if (mapped.length == 4 && mapped.toSet().length == 4) {
      return mapped;
    }
    return null;
  }

  static double similarity(String a, String b) {
    if (a == b) return 1.0;
    final maxLen = max(a.length, b.length);
    if (maxLen == 0) return 1.0;
    final dist = levenshtein(a, b);
    return (1.0 - dist / maxLen).clamp(0.0, 1.0);
  }

  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    var prev = List<int>.generate(t.length + 1, (i) => i);
    var curr = List<int>.filled(t.length + 1, 0);
    for (var i = 0; i < s.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = s.codeUnitAt(i) == t.codeUnitAt(j) ? 0 : 1;
        curr[j + 1] = min(min(curr[j] + 1, prev[j + 1] + 1), prev[j] + cost);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[t.length];
  }
}

import 'dart:convert';
import 'dart:math';
import 'catalog_search.dart';
import 'loan_model.dart';
import 'member_store.dart';

String newGradeRuleId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class GradeLoanRule {
  const GradeLoanRule({
    required this.id,
    required this.prefix,
    required this.maximum,
    required this.days,
  });
  final String id, prefix;
  final int maximum, days;

  Map<String, dynamic> toJson() => {
    'id': id,
    'gradePrefix': prefix,
    'maxConcurrentLoans': maximum,
    'loanDurationDays': days,
  };
}

class MemberLoanRule {
  const MemberLoanRule({
    required this.kind,
    required this.days,
    required this.maximum,
  });
  final String kind;
  final int days, maximum;
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'durationDays': days,
    'maximumLoans': maximum,
  };
}

class LoanSettings {
  const LoanSettings({
    this.days = 15,
    this.maximum = 0,
    this.blockOverdue = false,
    this.gradeRules = const [],
    this.memberRules = const [],
  });
  final int days;
  final int maximum;
  final bool blockOverdue;
  final List<GradeLoanRule> gradeRules;
  final List<MemberLoanRule> memberRules;

  static LoanSettings fromSupplement(Map<String, dynamic>? supplement) {
    final settings = supplement?['ayarlar.json'];
    dynamic read(String key) {
      if (settings is! Map || settings[key] == null) return null;
      try {
        return jsonDecode(utf8.decode(base64Decode(settings[key] as String)));
      } catch (_) {
        throw FormatException('iPhone ödünç ayarı okunamadı: $key');
      }
    }

    final days = read('loanDurationDays');
    final maximum = read('maxLoansPerPerson');
    final block = read('blockOverdueBorrowers');
    final rawMemberRules = read('memberLoanRules');
    final memberRules = <MemberLoanRule>[];
    if (rawMemberRules != null) {
      dynamic decoded;
      try {
        if (rawMemberRules is! Map || rawMemberRules['archiveData'] is! String)
          throw const FormatException('Üye kuralları geçersiz');
        decoded = jsonDecode(
          utf8.decode(base64Decode(rawMemberRules['archiveData'] as String)),
        );
      } catch (_) {
        throw const FormatException('Üye kuralları okunamadı');
      }
      if (decoded is! List)
        throw const FormatException('Üye kuralları geçersiz');
      final kinds = <String>{};
      for (final item in decoded) {
        if (item is! Map ||
            item['kind'] is! String ||
            !memberKinds.containsKey(item['kind']) ||
            !kinds.add(item['kind'] as String) ||
            item['durationDays'] is! int ||
            (item['durationDays'] as int) < 1 ||
            (item['durationDays'] as int) > 365 ||
            item['maximumLoans'] is! int ||
            (item['maximumLoans'] as int) < 0 ||
            (item['maximumLoans'] as int) > 99)
          throw const FormatException('Üye kuralı geçersiz');
        memberRules.add(
          MemberLoanRule(
            kind: item['kind'] as String,
            days: item['durationDays'] as int,
            maximum: item['maximumLoans'] as int,
          ),
        );
      }
    }
    final supporting = supplement?['destek-dosyalari.json'];
    final encodedRules = supporting is Map
        ? supporting['KademeKurallari.json']
        : null;
    final rules = <GradeLoanRule>[];
    if (encodedRules != null) {
      dynamic parsed;
      try {
        parsed = jsonDecode(utf8.decode(base64Decode(encodedRules as String)));
      } catch (_) {
        throw const FormatException('Kademe kuralları okunamadı');
      }
      if (parsed is! List)
        throw const FormatException('Kademe kuralları geçersiz');
      final prefixes = <String>{};
      for (final entry in parsed) {
        if (entry is! Map ||
            entry['id'] is! String ||
            (entry['id'] as String).isEmpty ||
            entry['gradePrefix'] is! String ||
            entry['maxConcurrentLoans'] is! int ||
            entry['loanDurationDays'] is! int)
          throw const FormatException('Kademe kuralı geçersiz');
        final prefix = (entry['gradePrefix'] as String).trim();
        final maximum = entry['maxConcurrentLoans'] as int;
        final duration = entry['loanDurationDays'] as int;
        if (prefix.isEmpty ||
            !prefixes.add(prefix) ||
            maximum < 0 ||
            maximum > 99 ||
            duration < 1 ||
            duration > 365)
          throw const FormatException('Kademe kuralı geçersiz');
        rules.add(
          GradeLoanRule(
            id: entry['id'] as String,
            prefix: prefix,
            maximum: maximum,
            days: duration,
          ),
        );
      }
    }
    if (days != null && (days is! int || days < 1 || days > 180) ||
        maximum != null && (maximum is! int || maximum < 0 || maximum > 20) ||
        block != null && block is! bool) {
      throw const FormatException('Ödünç ayarları geçersiz');
    }
    return LoanSettings(
      days: days ?? 15,
      maximum: maximum ?? 0,
      blockOverdue: block ?? false,
      gradeRules: rules,
      memberRules: memberRules,
    );
  }

  Map<String, dynamic> writeTo(Map<String, dynamic>? original) {
    final result = Map<String, dynamic>.from(original ?? {});
    final settings = Map<String, dynamic>.from(
      result['ayarlar.json'] as Map? ?? {},
    );
    String encode(Object value) => base64Encode(utf8.encode(jsonEncode(value)));
    settings['loanDurationDays'] = encode(days);
    settings['maxLoansPerPerson'] = encode(maximum);
    settings['blockOverdueBorrowers'] = encode(blockOverdue);
    if (memberRules.isNotEmpty || settings.containsKey('memberLoanRules')) {
      settings['memberLoanRules'] = encode({
        'archiveData': encode(
          memberRules.map((rule) => rule.toJson()).toList(),
        ),
      });
    }
    result['ayarlar.json'] = settings;
    final supporting = Map<String, dynamic>.from(
      result['destek-dosyalari.json'] as Map? ?? {},
    );
    if (gradeRules.isNotEmpty ||
        supporting.containsKey('KademeKurallari.json')) {
      supporting['KademeKurallari.json'] = encode(
        gradeRules.map((rule) => rule.toJson()).toList(),
      );
      result['destek-dosyalari.json'] = supporting;
    }
    return result;
  }

  GradeLoanRule? ruleFor(String studentClass) {
    GradeLoanRule? best;
    for (final rule in gradeRules) {
      if (!studentClass.startsWith(rule.prefix)) continue;
      if (studentClass.length > rule.prefix.length &&
          RegExp(
            r'[0-9]',
          ).hasMatch(rule.prefix.substring(rule.prefix.length - 1)) &&
          RegExp(r'[0-9]').hasMatch(
            studentClass.substring(rule.prefix.length, rule.prefix.length + 1),
          ))
        continue;
      if (best == null || rule.prefix.length > best.prefix.length) best = rule;
    }
    return best;
  }

  int durationFor(String studentClass) => ruleFor(studentClass)?.days ?? days;

  MemberLoanRule? memberRuleFor(String? kind) {
    for (final rule in memberRules) {
      if (rule.kind == kind) return rule;
    }
    return null;
  }
}

String? loanPolicyViolation(
  List<Map<String, dynamic>> books,
  Map<String, dynamic> borrower,
  LoanSettings settings, {
  DateTime? now,
  String? memberKind,
}) {
  final id = borrower['studentId'] as String?;
  final memberId = borrower['memberId'] as String?;
  final name = foldTurkish((borrower['name'] as String).trim());
  final studentClass = foldTurkish(
    (borrower['studentClass'] ?? '').toString().trim(),
  );
  final matches = <Map<String, dynamic>>[];
  for (final book in books) {
    for (final loan in activeLoans(book)) {
      if (loan['kind'] == 'textbook') continue;
      final otherId = loan['studentId'] as String?;
      final otherMember = loan['memberId'] as String?;
      if (memberId != null) {
        if (otherMember != null &&
            memberId.toUpperCase() == otherMember.toUpperCase())
          matches.add(loan);
        continue;
      }
      if (otherMember != null) continue;
      final sameId =
          id != null &&
          otherId != null &&
          id.toUpperCase() == otherId.toUpperCase();
      final fallback =
          otherId == null &&
          (id == null ||
              (loan['identitySource'] != 'manual' &&
                  loan['needsIdentityReview'] != true)) &&
          foldTurkish((loan['name'] ?? '').toString().trim()) == name &&
          (studentClass.isEmpty ||
              foldTurkish((loan['studentClass'] ?? '').toString().trim()) ==
                  studentClass);
      if (sameId || fallback) matches.add(loan);
    }
  }
  if (settings.blockOverdue &&
      matches.any((loan) => isOverdue(loan, now: now))) {
    return 'Önce gecikmiş kitapları iade alın.';
  }
  final maximum = memberId != null
      ? (settings.memberRuleFor(memberKind)?.maximum ?? settings.maximum)
      : (settings
                .ruleFor((borrower['studentClass'] ?? '').toString())
                ?.maximum ??
            settings.maximum);
  if (maximum > 0 && matches.length >= maximum) {
    return 'Kişi başı $maximum kitap sınırına ulaşıldı.';
  }
  return null;
}

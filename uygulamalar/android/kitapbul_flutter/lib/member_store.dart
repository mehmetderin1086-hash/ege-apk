import 'dart:convert';

const memberKinds = {
  'teacher': 'Öğretmen',
  'guardian': 'Veli',
  'staff': 'Personel',
  'other': 'Diğer üye',
};

class Member {
  const Member({
    required this.id,
    required this.name,
    this.number = '',
    this.note = '',
    this.kind,
  });
  final String id, name, number, note;
  final String? kind;
  String get kindTitle => memberKinds[kind] ?? 'Türü belirtilmemiş';

  factory Member.fromJson(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        (value['id'] as String).trim().isEmpty ||
        value['name'] is! String ||
        (value['name'] as String).trim().isEmpty ||
        (value['memberNumber'] != null && value['memberNumber'] is! String) ||
        (value['note'] != null && value['note'] is! String) ||
        (value['kind'] != null &&
            (value['kind'] is! String ||
                !memberKinds.containsKey(value['kind'])))) {
      throw const FormatException('Geçersiz üye kaydı');
    }
    return Member(
      id: value['id'] as String,
      name: value['name'] as String,
      number: value['memberNumber'] as String? ?? '',
      note: value['note'] as String? ?? '',
      kind: value['kind'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'memberNumber': number,
    'note': note,
    if (kind != null) 'kind': kind,
  };
}

List<Member> decodeMembers(String raw) {
  final data = jsonDecode(raw);
  if (data is! List) throw const FormatException('Üye listesi geçersiz');
  final ids = <String>{};
  return data.map((entry) {
    final member = Member.fromJson(entry);
    if (!ids.add(member.id.toUpperCase()))
      throw const FormatException('Tekrarlanan üye kimliği');
    return member;
  }).toList();
}

/// Current loans and open reservations must point to one known member.
void validateMemberLinks(List<dynamic> books, List<Member> members) {
  final ids = members.map((member) => member.id.toUpperCase()).toSet();
  for (final book in books) {
    if (book is! Map) throw const FormatException('Kitap kaydı geçersiz');
    for (final section in ['loans', 'reservations']) {
      final entries = book[section] ?? [];
      if (entries is! List)
        throw const FormatException('Ödünç veya rezervasyon listesi geçersiz');
      for (final entry in entries) {
        if (entry is! Map)
          throw const FormatException('Ödünç veya rezervasyon kaydı geçersiz');
        final memberId = entry['memberId'];
        if (memberId == null) continue;
        if (memberId is! String ||
            memberId.trim().isEmpty ||
            entry['studentId'] != null ||
            (section == 'loans' || entry['isClosed'] != true) &&
                !ids.contains(memberId.toUpperCase())) {
          throw const FormatException('Üye kimliği veya bağlantısı geçersiz');
        }
      }
    }
  }
}

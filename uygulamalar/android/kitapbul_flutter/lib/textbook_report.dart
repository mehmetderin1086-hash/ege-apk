import 'catalog_csv.dart';
import 'catalog_search.dart';
import 'loan_model.dart';

class TextbookReportFilter {
  const TextbookReportFilter({
    required this.start,
    required this.end,
    this.period = '',
    this.className = '',
    this.query = '',
  });
  final DateTime start, end;
  final String period, className, query;
}

class TextbookReportRow {
  const TextbookReportRow({
    required this.loanId,
    required this.book,
    required this.person,
    required this.number,
    required this.className,
    required this.period,
    required this.copy,
    required this.delivered,
    required this.due,
    required this.returned,
    required this.condition,
    required this.status,
    required this.note,
  });
  final String loanId,
      book,
      person,
      number,
      className,
      period,
      copy,
      delivered,
      due,
      returned,
      condition,
      status,
      note;
  List<String> get fields => [
    period,
    className,
    number,
    person,
    book,
    copy,
    loanId,
    delivered,
    due,
    returned,
    condition,
    status,
    note,
  ];
}

const textbookReportHeaders = [
  'Dağıtım dönemi',
  'Teslim sınıfı',
  'Okul numarası',
  'Öğrenci / okur',
  'Kitap',
  'Nüsha / demirbaş',
  'Ödünç kimliği',
  'Teslim tarihi',
  'Son teslim tarihi',
  'İade tarihi',
  'İade durumu',
  'İşlem durumu',
  'Doğrulama notu',
];

/// Never joins history on a person's name. Conflicting or anonymous records are
/// retained as review rows instead of being silently counted as verified.
List<TextbookReportRow> textbookReport(
  List<Map<String, dynamic>> books,
  TextbookReportFilter filter,
) {
  final from = DateTime(
    filter.start.year,
    filter.start.month,
    filter.start.day,
  );
  final until = DateTime(
    filter.end.year,
    filter.end.month,
    filter.end.day,
  ).add(const Duration(days: 1));
  if (!from.isBefore(until)) return [];
  final groups =
      <
        String,
        List<({Map<String, dynamic> book, Map<String, dynamic> event})>
      >{};
  final live =
      <
        String,
        List<({Map<String, dynamic> book, Map<String, dynamic> loan})>
      >{};
  final anonymous =
      <({Map<String, dynamic> book, Map<String, dynamic> event})>[];
  DateTime? date(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
  bool inRange(DateTime d) => !d.isBefore(from) && d.isBefore(until);
  for (final book in books) {
    for (final event in loanHistory(book)) {
      final at = date(event['date']);
      if (event['loanKind'] != 'textbook' || at == null || !at.isBefore(until))
        continue;
      final id = event['loanId'];
      if (id is String && id.isNotEmpty) {
        groups.putIfAbsent(id.toUpperCase(), () => []).add((
          book: book,
          event: event,
        ));
      } else if (inRange(at) &&
          ['lent', 'returned', 'lost'].contains(event['kind'])) {
        anonymous.add((book: book, event: event));
      }
    }
    for (final loan in activeLoans(
      book,
    ).where((l) => l['kind'] == 'textbook')) {
      final id = loan['id'];
      final at = date(
        loan['loanedAt'] ??
            (loan['iphoneOriginal'] is Map
                ? loan['iphoneOriginal']['loanedAt']
                : null),
      );
      if (id is String && id.isNotEmpty && (at == null || at.isBefore(until))) {
        live.putIfAbsent(id.toUpperCase(), () => []).add((
          book: book,
          loan: loan,
        ));
      }
    }
  }
  String value(dynamic x) => x?.toString() ?? '';
  String dateText(dynamic x) => value(x).split('T').first;
  String copyText(Map book, dynamic id) {
    if (id is! String || id.isEmpty) return 'Tekil nüsha belirtilmemiş';
    for (final copy in ((book['copies'] as List?) ?? []).whereType<Map>()) {
      if (value(copy['id']).toUpperCase() == id.toUpperCase()) {
        final code = value(copy['accessionCode']);
        return code.isEmpty ? id : code;
      }
    }
    return id;
  }

  final rows = <TextbookReportRow>[];
  for (final id in {...groups.keys, ...live.keys}) {
    final entries = groups[id] ?? [];
    entries.sort(
      (a, b) => date(a.event['date'])!.compareTo(date(b.event['date'])!),
    );
    final lives = live[id] ?? [];
    final deliveries = entries.where((e) => e.event['kind'] == 'lent').toList();
    final endings = entries
        .where(
          (e) => e.event['kind'] == 'returned' || e.event['kind'] == 'lost',
        )
        .toList();
    final corrections = entries
        .where((e) => e.event['kind'] == 'identityCorrected')
        .toList();
    final delivery = deliveries.firstOrNull;
    final terminal = endings.lastOrNull;
    final current = lives.firstOrNull;
    final booksSeen = {
      for (final e in entries) value(e.book['id']).toUpperCase(),
      for (final e in lives) value(e.book['id']).toUpperCase(),
    };
    final eventInRange = entries.any(
      (e) =>
          ['lent', 'returned', 'lost'].contains(e.event['kind']) &&
          inRange(date(e.event['date'])!),
    );
    if (!eventInRange && terminal != null) continue;
    if (entries.isEmpty && current == null) continue;
    final anchor =
        delivery?.event ?? entries.firstOrNull?.event ?? current!.loan;
    final book = delivery?.book ?? entries.firstOrNull?.book ?? current!.book;
    bool valid =
        booksSeen.length == 1 &&
        deliveries.length <= 1 &&
        endings.length <= 1 &&
        lives.length <= 1 &&
        (delivery != null || current != null) &&
        corrections.isEmpty;
    final identity = <String>{};
    for (final entry in entries) {
      final e = entry.event;
      if (e['studentId'] != null && e['memberId'] != null) valid = false;
      final key = e['studentId'] != null
          ? 's:${value(e['studentId']).toUpperCase()}'
          : e['memberId'] != null
          ? 'm:${value(e['memberId']).toUpperCase()}'
          : 'n:${value(e['person'])}\u0000${value(e['studentClass'])}';
      identity.add(key);
    }
    if (current != null) {
      final loan = current.loan;
      if (loan['studentId'] != null && loan['memberId'] != null) valid = false;
      final key = loan['studentId'] != null
          ? 's:${value(loan['studentId']).toUpperCase()}'
          : loan['memberId'] != null
          ? 'm:${value(loan['memberId']).toUpperCase()}'
          : 'n:${value(loan['name'])}\u0000${value(loan['studentClass'])}';
      identity.add(key);
    }
    if (identity.length > 1) valid = false;
    final copyIds = <String>{
      for (final entry in entries)
        if (entry.event['copyId'] is String &&
            (entry.event['copyId'] as String).isNotEmpty)
          (entry.event['copyId'] as String).toUpperCase(),
      if (current?.loan['copyId'] is String &&
          (current!.loan['copyId'] as String).isNotEmpty)
        (current.loan['copyId'] as String).toUpperCase(),
    };
    if (copyIds.length > 1 || (terminal != null && entries.last != terminal))
      valid = false;
    if (current != null && terminal != null) valid = false;
    final status = !valid
        ? 'Eşleştirme gerekli'
        : terminal?.event['kind'] == 'returned'
        ? 'İade alındı'
        : terminal?.event['kind'] == 'lost'
        ? 'Kayıp bildirildi'
        : 'Henüz iade edilmedi';
    final loan = current?.loan;
    final copy =
        anchor['copyId'] ?? loan?['copyId'] ?? terminal?.event['copyId'];
    rows.add(
      TextbookReportRow(
        loanId: id,
        book: value(book['title']),
        person: value(anchor['person'] ?? anchor['name']),
        number: value(
          anchor['studentNumberSnapshot'] ?? loan?['studentNumberSnapshot'],
        ),
        className: value(anchor['studentClass'] ?? loan?['studentClass']),
        period: value(anchor['periodSnapshot'] ?? loan?['periodSnapshot']),
        copy: copyText(book, copy),
        delivered: dateText(delivery?.event['date'] ?? loan?['loanedAt']),
        due: dateText(
          entries.reversed
                  .where((e) => e.event['due'] != null)
                  .firstOrNull
                  ?.event['due'] ??
              loan?['due'],
        ),
        returned: valid && terminal?.event['kind'] == 'returned'
            ? dateText(terminal?.event['date'])
            : '',
        condition: valid && terminal?.event['kind'] == 'returned'
            ? value(terminal?.event['returnedCondition'] ?? 'Belirtilmemiş')
            : '',
        status: status,
        note: !valid
            ? 'Ödünç zinciri doğrulanmalı.'
            : delivery == null
            ? 'Teslim hareketi bulunamadı; etkin kayıt kullanıldı.'
            : '',
      ),
    );
  }
  for (final entry in anonymous) {
    final e = entry.event;
    rows.add(
      TextbookReportRow(
        loanId: '',
        book: value(entry.book['title']),
        person: value(e['person']),
        number: value(e['studentNumberSnapshot']),
        className: value(e['studentClass']),
        period: value(e['periodSnapshot']),
        copy: copyText(entry.book, e['copyId']),
        delivered: e['kind'] == 'lent' ? dateText(e['date']) : '',
        due: dateText(e['due']),
        returned: e['kind'] == 'returned' ? dateText(e['date']) : '',
        condition: value(e['returnedCondition']),
        status: 'Eşleştirme gerekli',
        note: 'Ödünç kimliği yok; başka hareketle birleştirilmedi.',
      ),
    );
  }
  final query = foldTurkish(filter.query.trim());
  final filtered = rows
      .where(
        (r) =>
            (filter.period.isEmpty || r.period == filter.period) &&
            (filter.className.isEmpty || r.className == filter.className) &&
            (query.isEmpty ||
                foldTurkish(
                  '${r.person} ${r.number} ${r.book} ${r.copy}',
                ).contains(query)),
      )
      .toList();
  filtered.sort(
    (
      a,
      b,
    ) => '${a.period}|${a.className}|${a.number}|${a.person}|${a.book}|${a.loanId}'
        .compareTo(
          '${b.period}|${b.className}|${b.number}|${b.person}|${b.book}|${b.loanId}',
        ),
  );
  return filtered;
}

String textbookReportCsv(List<TextbookReportRow> rows) =>
    '\uFEFF${[textbookReportHeaders, ...rows.map((r) => r.fields)].map((line) => line.map(csvCell).join(';')).join('\r\n')}\r\n';

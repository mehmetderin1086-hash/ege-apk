import 'dart:convert';
import 'package:flutter/services.dart';
import 'loan_model.dart';

/// One reminder per active loan at 09:00 on its local calendar due date.
List<Map<String, Object>> loanReminders(List<Map<String, dynamic>> books) {
  final items = <Map<String, Object>>[];
  for (final book in books) {
    for (final loan in activeLoans(book)) {
      if (loan['kind'] == 'textbook') continue;
      final due = DateTime.tryParse((loan['due'] ?? '').toString())?.toLocal();
      final bookId = book['id'];
      final loanId = loan['id'];
      if (due == null ||
          bookId is! String ||
          loanId is! String ||
          bookId.isEmpty ||
          loanId.isEmpty)
        continue;
      final fire = DateTime(due.year, due.month, due.day, 9);
      if (fire.millisecondsSinceEpoch <= 0) continue;
      items.add({
        'id': jsonEncode([bookId, loanId]),
        'title': (book['title'] ?? 'Kitap').toString(),
        'person': (loan['name'] ?? '').toString(),
        'due': fire.millisecondsSinceEpoch,
      });
    }
  }
  return items;
}

class LoanReminderService {
  static const channel = MethodChannel('kitapbul/loan_reminders');
  Future<void> synchronize(List<Map<String, dynamic>> books) async {
    await channel.invokeMethod<bool>('replace', {
      'items': loanReminders(books),
    });
  }
}

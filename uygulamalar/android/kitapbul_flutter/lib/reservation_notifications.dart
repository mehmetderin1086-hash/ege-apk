import 'package:flutter/services.dart';
import 'reservation_model.dart';

class ReadyNotice {
  const ReadyNotice(this.id, this.title, this.person, this.expiresAtMillis);
  final String id, title, person;
  final int? expiresAtMillis;
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'person': person,
    if (expiresAtMillis != null) 'expiresAtMillis': expiresAtMillis!,
  };
}

Map<String, ReadyNotice> readyNotices(
  List<Map<String, dynamic>> books, {
  bool includeExpired = false,
}) {
  final result = <String, ReadyNotice>{};
  for (final book in books) {
    if (book['isWithdrawn'] == true) continue;
    for (final reservation in reservationsOf(book)) {
      if (isReadyReservation(reservation) ||
          (includeExpired &&
              isActiveReservation(reservation) &&
              reservation['notifiedAt'] != null)) {
        final id = '${book['id']}/${reservation['id']}';
        result[id] = ReadyNotice(
          id,
          (book['title'] ?? '').toString(),
          (reservation['name'] ?? '').toString(),
          reservation['expiresAt'] == null
              ? null
              : DateTime.parse(
                  reservation['expiresAt'] as String,
                ).millisecondsSinceEpoch,
        );
      }
    }
  }
  return result;
}

class ReservationNotifications {
  static const channel = MethodChannel('kitapbul/notifications');
  Future<bool> request() async =>
      await channel.invokeMethod<bool>('request') ?? false;
  Future<void> synchronize(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after, {
    bool force = false,
  }) async {
    final old = readyNotices(before, includeExpired: true),
        current = readyNotices(after);
    for (final id in old.keys.where((id) => !current.containsKey(id))) {
      await channel.invokeMethod<bool>('cancel', {'id': id});
    }
    for (final entry in current.entries) {
      final previous = old[entry.key];
      if (force ||
          previous == null ||
          previous.title != entry.value.title ||
          previous.person != entry.value.person ||
          previous.expiresAtMillis != entry.value.expiresAtMillis) {
        await channel.invokeMethod<bool>('ready', entry.value.toJson());
      }
    }
  }
}

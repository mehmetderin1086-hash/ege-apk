import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fixed Google endpoints only. OAuth tokens never enter chat, memory or settings.
class GoogleWorkspace {
  GoogleWorkspace({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _channel = MethodChannel('com.jarvis.assistant/device');
  final _sent = <String, Map<String, dynamic>>{};
  static const services = ['gmail', 'drive', 'calendar'];
  Future<bool> connected(String service) async =>
      (await SharedPreferences.getInstance()).getBool(
        'google_connected_$service',
      ) ??
      false;
  Future<void> disconnect(String service) async {
    await (await SharedPreferences.getInstance()).remove(
      'google_connected_$service',
    );
  }

  static Uri _path(
    String host,
    List<String> segments, [
    Map<String, String>? query,
  ]) => Uri(
    scheme: 'https',
    host: host,
    pathSegments: segments,
    queryParameters: query,
  );
  Future<String> _token(String service, {bool interactive = false}) async {
    if (!services.contains(service))
      throw StateError('Bilinmeyen Google hizmeti.');
    if (!interactive && !await connected(service))
      throw StateError(
        'Ayarlar → Bağlı hesaplar bölümünden $service bağlantısını aç.',
      );
    final auth = await _channel.invokeMapMethod<String, dynamic>(
      'googleAuthorize',
      {'service': service, 'interactive': interactive},
    );
    if (auth?['status'] != 'OK' || auth?['token'] is! String)
      throw StateError(
        auth?['message']?.toString() ??
            'Google izni tamamlanmadı. Ayarlardan yeniden bağlan.',
      );
    return auth!['token'] as String;
  }

  Future<void> connect(String service) async {
    final token = await _token(service, interactive: true);
    final uri = switch (service) {
      'gmail' => Uri.https(
        'gmail.googleapis.com',
        '/gmail/v1/users/me/profile',
      ),
      'drive' => Uri.https('www.googleapis.com', '/drive/v3/about', {
        'fields': 'user(displayName,emailAddress)',
      }),
      _ => Uri.https(
        'www.googleapis.com',
        '/calendar/v3/users/me/calendarList',
        {'maxResults': '1'},
      ),
    };
    await _request(service, 'GET', uri, token: token);
    await (await SharedPreferences.getInstance()).setBool(
      'google_connected_$service',
      true,
    );
  }

  Future<http.Response> _request(
    String service,
    String method,
    Uri uri, {
    Object? body,
    String? token,
    String contentType = 'application/json; charset=utf-8',
  }) async {
    final access = token ?? await _token(service);
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $access',
      'Content-Type': contentType,
    });
    if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body != null) {
      request.body = jsonEncode(body);
    }
    // Never retry writes automatically: a timeout can follow a successful send.
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Google $service HTTP ${response.statusCode}. İzinleri ve Google Cloud API etkinleştirmesini kontrol et. İşlem tamamlandı sayılmadı.',
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _json(
    String service,
    String method,
    Uri uri, {
    Object? body,
  }) async => Map<String, dynamic>.from(
    jsonDecode((await _request(service, method, uri, body: body)).body) as Map,
  );
  Future<Map<String, dynamic>> mailSearch(String query, {String? pageToken}) =>
      _json(
        'gmail',
        'GET',
        Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages', {
          'q': query,
          'maxResults': '20',
          if (pageToken?.isNotEmpty == true) 'pageToken': pageToken!,
        }),
      );
  Future<Map<String, dynamic>> mailRead(String id) async {
    final message = await _json(
      'gmail',
      'GET',
      _path(
        'gmail.googleapis.com',
        ['gmail', 'v1', 'users', 'me', 'messages', id],
        {'format': 'full'},
      ),
    );
    final payload = message['payload'] as Map? ?? {};
    final headers = <String, String>{};
    for (final h in (payload['headers'] as List? ?? [])) {
      if (h is Map &&
          [
            'from',
            'to',
            'subject',
            'date',
          ].contains(h['name']?.toString().toLowerCase()))
        headers[h['name'].toString()] = h['value'].toString();
    }
    final parts = <String>[];
    void read(Map part) {
      if (part['mimeType'] == 'text/plain') {
        final data = (part['body'] as Map?)?['data'];
        if (data is String) {
          try {
            parts.add(
              utf8.decode(
                base64Url.decode(base64Url.normalize(data)),
                allowMalformed: true,
              ),
            );
          } catch (_) {}
        }
      }
      for (final child in (part['parts'] as List? ?? [])) {
        if (child is Map) read(child);
      }
    }

    read(payload);
    final text = parts.isEmpty
        ? message['snippet']?.toString() ?? ''
        : parts.join('\n');
    return {
      'id': message['id'],
      'threadId': message['threadId'],
      'headers': headers,
      'text': text.length > 24000 ? text.substring(0, 24000) : text,
      'truncated': text.length > 24000 || parts.isEmpty,
    };
  }

  static String encodeMail(String to, String subject, String body) {
    if (!RegExp(r'^[^\s@<>;,\r\n]+@[^\s@<>;,\r\n]+\.[^\s@<>;,\r\n]+$')
            .hasMatch(to) ||
        subject.contains(RegExp(r'[\r\n]')) ||
        subject.length > 500 ||
        body.length > 100000)
      throw const FormatException(
        'Tek, geçerli alıcı adresi, konu ve uygun uzunlukta mesaj gerekli.',
      );
    return base64Url
        .encode(
          utf8.encode(
            'To: $to\r\nSubject: =?UTF-8?B?${base64Encode(utf8.encode(subject))}?=\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${base64Encode(utf8.encode(body))}',
          ),
        )
        .replaceAll('=', '');
  }

  Future<Map<String, dynamic>> mailSend(
    String to,
    String subject,
    String body,
  ) async {
    final raw = encodeMail(to, subject, body);
    if (_sent.containsKey(raw))
      return {..._sent[raw]!, 'duplicatePrevented': true};
    final result = await _json(
      'gmail',
      'POST',
      Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages/send'),
      body: {'raw': raw},
    );
    if (result['id'] == null)
      throw StateError('Gönderim kimliği alınamadı; tekrar gönderme.');
    if (_sent.length >= 20) _sent.remove(_sent.keys.first);
    _sent[raw] = result;
    return result;
  }

  Future<Map<String, dynamic>> driveList(
    String query, {
    String? pageToken,
  }) => _json(
    'drive',
    'GET',
    Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': query.isEmpty ? 'trashed = false' : 'trashed = false and ($query)',
      'pageSize': '30',
      'fields':
          'nextPageToken,files(id,name,mimeType,modifiedTime,size,webViewLink)',
      if (pageToken?.isNotEmpty == true) 'pageToken': pageToken!,
    }),
  );
  Future<Map<String, dynamic>> driveRead(String id) => _json(
    'drive',
    'GET',
    _path(
      'www.googleapis.com',
      ['drive', 'v3', 'files', id],
      {'fields': 'id,name,mimeType,size,description,webViewLink,modifiedTime'},
    ),
  );
  Future<Map<String, dynamic>> driveUpload(
    String name,
    String mime,
    Uint8List bytes,
  ) async {
    if (bytes.length > 5 * 1024 * 1024)
      throw StateError(
        'Doğrudan Drive yüklemesi şu anda en fazla 5 MB. Büyük dosya için dosya kartından Paylaş → Drive kullan.',
      );
    final boundary = 'ege_${DateTime.now().microsecondsSinceEpoch}';
    final data = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode({'name': name})}\r\n--$boundary\r\nContent-Type: $mime\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    final result = await _request(
      'drive',
      'POST',
      Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'multipart',
        'fields': 'id,name,size,webViewLink',
      }),
      body: data.takeBytes(),
      contentType: 'multipart/related; boundary=$boundary',
    );
    return Map<String, dynamic>.from(jsonDecode(result.body) as Map);
  }

  Future<Map<String, dynamic>> calendars() => _json(
    'calendar',
    'GET',
    Uri.https('www.googleapis.com', '/calendar/v3/users/me/calendarList', {
      'maxResults': '100',
    }),
  );
  Future<Map<String, dynamic>> events(
    String calendarId,
    String start,
    String end,
  ) => _json(
    'calendar',
    'GET',
    _path(
      'www.googleapis.com',
      ['calendar', 'v3', 'calendars', calendarId, 'events'],
      {
        'timeMin': _instant(start),
        'timeMax': _instant(end),
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'maxResults': '100',
      },
    ),
  );
  static String _instant(String value) {
    if (!RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(value) ||
        DateTime.tryParse(value) == null)
      throw const FormatException(
        'Saat dilimi içeren ISO tarih gerekli (ör. 2026-11-17T14:00:00+03:00).',
      );
    return value;
  }

  static Map<String, dynamic> eventBody(
    String title,
    String start,
    String end,
    String description,
  ) {
    _instant(start);
    _instant(end);
    if (title.trim().isEmpty ||
        !DateTime.parse(end).isAfter(DateTime.parse(start)))
      throw const FormatException(
        'Başlık ve başlangıçtan sonra bitiş gerekli.',
      );
    return {
      'summary': title,
      'description': description,
      'start': {'dateTime': start},
      'end': {'dateTime': end},
    };
  }

  Future<Map<String, dynamic>> saveEvent({
    required String calendarId,
    String? eventId,
    required String title,
    required String start,
    required String end,
    String description = '',
  }) => _json(
    'calendar',
    eventId == null ? 'POST' : 'PATCH',
    _path('www.googleapis.com', [
      'calendar',
      'v3',
      'calendars',
      calendarId,
      'events',
      if (eventId != null) eventId,
    ]),
    body: eventBody(title, start, end, description),
  );
  void dispose() => _client.close();
}

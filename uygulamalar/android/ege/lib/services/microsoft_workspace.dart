import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'google_workspace.dart';

/// Delegated Microsoft Graph access. Remote content is data, never instructions.
class MicrosoftWorkspace {
  MicrosoftWorkspace({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _channel = MethodChannel('com.jarvis.assistant/device');
  static const services = ['outlook', 'onedrive', 'calendar'];
  final _sends = <String, Map<String, dynamic>>{};
  Future<bool> connected(String service) async =>
      (await SharedPreferences.getInstance()).getBool(
        'microsoft_connected_$service',
      ) ??
      false;
  Future<void> disconnect(String service) async {
    await (await SharedPreferences.getInstance()).remove(
      'microsoft_connected_$service',
    );
    await _channel.invokeMethod<bool>('microsoftDisconnect', {
      'service': service,
    });
  }

  static Uri path(List<String> segments, [Map<String, String>? query]) => Uri(
    scheme: 'https',
    host: 'graph.microsoft.com',
    pathSegments: ['v1.0', 'me', ...segments],
    queryParameters: query,
  );
  Future<String> _token(String service, {bool interactive = false}) async {
    if (!services.contains(service))
      throw StateError('Bilinmeyen Microsoft hizmeti.');
    if (!interactive && !await connected(service)) {
      throw StateError(
        'Ayarlar → Bağlı hesaplar bölümünden Microsoft hesabını bağla.',
      );
    }
    final auth = await _channel.invokeMapMethod<String, dynamic>(
      'microsoftAuthorize',
      {'service': service, 'interactive': interactive},
    );
    if (auth?['status'] != 'OK' || auth?['token'] is! String) {
      throw StateError(
        auth?['message']?.toString() ??
            'Microsoft izni tamamlanmadı; ayarlardan yeniden bağlan.',
      );
    }
    return auth!['token'] as String;
  }

  Future<void> connect(String service) async {
    final token = await _token(service, interactive: true);
    final uri = switch (service) {
      'outlook' => path(['messages'], {r'$top': '1', r'$select': 'id'}),
      'onedrive' => path(['drive', 'root'], {r'$select': 'id,name'}),
      _ => path(['calendars'], {r'$top': '1', r'$select': 'id,name'}),
    };
    await _request(service, 'GET', uri, token: token);
    await (await SharedPreferences.getInstance()).setBool(
      'microsoft_connected_$service',
      true,
    );
  }

  Future<http.Response> _request(
    String service,
    String method,
    Uri uri, {
    String? token,
    Object? body,
    String contentType = 'application/json; charset=utf-8',
  }) async {
    if (uri.scheme != 'https' ||
        uri.host != 'graph.microsoft.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Geçersiz Microsoft API adresi.');
    }
    final access = token ?? await _token(service);
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $access',
      'Content-Type': contentType,
      'Prefer': 'outlook.body-content-type="text"',
    });
    if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body != null) {
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        await (await SharedPreferences.getInstance()).remove(
          'microsoft_connected_$service',
        );
      }
      throw StateError(
        'Microsoft $service HTTP ${response.statusCode}. İşlem tamamlandı sayılmadı; gönderimi otomatik tekrarlama.',
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

  Future<Map<String, dynamic>> mailSearch(String query) => _json(
    'outlook',
    'GET',
    path(
      ['messages'],
      {
        r'$top': '20',
        r'$select': 'id,subject,from,receivedDateTime,isRead,webLink',
        if (query.trim().isNotEmpty) r'$search': jsonEncode(query.trim()),
      },
    ),
  );
  Future<Map<String, dynamic>> mailRead(String id) async {
    final data = await _json(
      'outlook',
      'GET',
      path(
        ['messages', id],
        {
          r'$select':
              'id,subject,from,toRecipients,receivedDateTime,body,webLink',
        },
      ),
    );
    final body = data['body'] as Map? ?? {};
    final text = body['content']?.toString() ?? '';
    return {
      ...data,
      'body': {
        'contentType': body['contentType'],
        'content': text.length > 24000 ? text.substring(0, 24000) : text,
      },
      'truncated': text.length > 24000,
    };
  }

  Future<Map<String, dynamic>> mailSend(
    String to,
    String subject,
    String body,
  ) async {
    // Same strict recipient/header limits as Gmail; JSON is used on the wire.
    GoogleWorkspace.encodeMail(to, subject, body);
    if (!await connected('outlook'))
      throw StateError('Önce Outlook hesabını bağla.');
    final key = sha256
        .convert(utf8.encode(jsonEncode([to, subject, body])))
        .toString();
    if (_sends.containsKey(key))
      return {..._sends[key]!, 'duplicatePrevented': true};
    // Keep ambiguous outcomes, too: a timeout may occur after Microsoft's acceptance.
    _sends[key] = {
      'status': 'unknown',
      'message': 'Önceki isteğin sonucu belirsiz. Gönderilmiş Öğeler kontrol edilmeden tekrar gönderilmedi.',
    };
    final response = await _request(
      'outlook',
      'POST',
      path(['sendMail']),
      body: {
        'message': {
          'subject': subject,
          'body': {'contentType': 'Text', 'content': body},
          'toRecipients': [
            {
              'emailAddress': {'address': to},
            },
          ],
        },
        'saveToSentItems': true,
      },
    );
    if (response.statusCode != 202)
      throw StateError(
        'Beklenen Microsoft kabul yanıtı alınamadı; tekrar gönderme.',
      );
    return _sends[key] = {
      'status': 'accepted',
      'deliveryConfirmed': false,
      'message': 'Microsoft gönderim isteğini kabul etti. Alıcıya teslim edildiği henüz doğrulanmadı.',
    };
  }

  Future<Map<String, dynamic>> driveList({String? folderId}) => _json(
    'onedrive',
    'GET',
    path(
      [
        'drive',
        if (folderId?.isNotEmpty == true) ...['items', folderId!] else 'root',
        'children',
      ],
      {
        r'$top': '50',
        r'$select': 'id,name,size,webUrl,file,folder,lastModifiedDateTime',
      },
    ),
  );
  Future<Map<String, dynamic>> driveRead(String id) => _json(
    'onedrive',
    'GET',
    path(
      ['drive', 'items', id],
      {r'$select': 'id,name,size,webUrl,file,folder,lastModifiedDateTime'},
    ),
  );
  Future<Map<String, dynamic>> driveUpload(
    String name,
    String mime,
    Uint8List bytes,
  ) async {
    if (name.isEmpty ||
        name.length > 180 ||
        name.contains(RegExp(r'[\\/:*?"<>|]')) ||
        name == '.' ||
        name == '..' ||
        bytes.length > 5 * 1024 * 1024) {
      throw const FormatException(
        'Geçerli dosya adı ve en fazla 5 MB dosya gerekli.',
      );
    }
    // Fail instead of silently replacing an existing user's document.
    final uri = Uri.https(
      'graph.microsoft.com',
      '/v1.0/me/drive/root:/$name:/content',
      {'@microsoft.graph.conflictBehavior': 'fail'},
    );
    final result = await _request(
      'onedrive',
      'PUT',
      uri,
      body: bytes,
      contentType: mime,
    );
    return Map<String, dynamic>.from(jsonDecode(result.body) as Map);
  }

  Future<Map<String, dynamic>> calendars() => _json(
    'calendar',
    'GET',
    path(['calendars'], {r'$top': '100', r'$select': 'id,name,canEdit,owner'}),
  );
  static void validateRange(String start, String end) {
    final zone = RegExp(r'(Z|[+-]\d{2}:\d{2})$');
    final a = DateTime.tryParse(start), b = DateTime.tryParse(end);
    if (!zone.hasMatch(start) ||
        !zone.hasMatch(end) ||
        a == null ||
        b == null ||
        !b.isAfter(a)) {
      throw const FormatException(
        'Başlangıç/bitiş açık saat dilimli olmalı; bitiş başlangıçtan sonra olmalı.',
      );
    }
  }

  Future<Map<String, dynamic>> events(
    String calendarId,
    String start,
    String end,
  ) {
    validateRange(start, end);
    return _json(
      'calendar',
      'GET',
      path(
        [
          if (calendarId.isNotEmpty) ...['calendars', calendarId],
          'calendarView',
        ],
        {
          'startDateTime': start,
          'endDateTime': end,
          r'$top': '50',
          r'$select': 'id,subject,start,end,location,webLink',
        },
      ),
    );
  }

  Future<Map<String, dynamic>> saveEvent({
    required String calendarId,
    String? eventId,
    required String title,
    required String start,
    required String end,
    String description = '',
  }) {
    validateRange(start, end);
    if (title.trim().isEmpty ||
        title.length > 500 ||
        description.length > 10000) {
      throw const FormatException(
        'Geçerli etkinlik başlığı ve açıklaması gerekli.',
      );
    }
    String utc(String value) =>
        DateTime.parse(value)
            .toUtc()
            .toIso8601String()
            .replaceFirst(RegExp(r'Z$'), '');
    return _json(
      'calendar',
      eventId == null ? 'POST' : 'PATCH',
      path([
        if (calendarId.isNotEmpty) ...['calendars', calendarId],
        'events',
        if (eventId != null) eventId,
      ]),
      body: {
        'subject': title,
        'body': {'contentType': 'Text', 'content': description},
        'start': {'dateTime': utc(start), 'timeZone': 'UTC'},
        'end': {'dateTime': utc(end), 'timeZone': 'UTC'},
      },
    );
  }

  void dispose() => _client.close();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/pc_models.dart';

class PcBridgeException implements Exception {
  final int status;
  final String message;

  const PcBridgeException(this.status, this.message);

  bool get unauthorized => status == 401;
  bool get conflict => status == 409;

  @override
  String toString() => message;
}

/// HTTP client for the JARVIS PC Bridge running on the user's Windows PC.
class PcBridgeClient {
  static const int defaultPort = 8765;

  final String baseUrl;
  final String token;
  final http.Client? _client;

  PcBridgeClient({
    required String baseUrl,
    required this.token,
    http.Client? client,
  })  : baseUrl = normalizeUrl(baseUrl),
        _client = client; // ignore: prefer_initializing_formals

  static String normalizeUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    u = u.replaceAll(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(u);
    if (parsed != null && !parsed.hasPort) {
      u = parsed.replace(port: defaultPort).toString();
    }
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  Future<T> _withClient<T>(Future<T> Function(http.Client c) body) async {
    final c = _client ?? http.Client();
    try {
      return await body(c);
    } on SocketException catch (e) {
      throw PcBridgeException(
        0,
        'PC Köprüsüne ulaşılamadı ($baseUrl). PC açık ve aynı ağda mı? '
        '(${e.osError?.message ?? e.message})',
      );
    } on TimeoutException {
      throw PcBridgeException(0, 'PC Köprüsü zaman aşımına uğradı ($baseUrl).');
    } on http.ClientException catch (e) {
      throw PcBridgeException(0, 'Bağlantı hatası: ${e.message}');
    } finally {
      if (_client == null) c.close();
    }
  }

  static dynamic _decode(http.Response r) {
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    dynamic data;
    try {
      data = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    } catch (_) {
      data = {'error': body.length > 200 ? body.substring(0, 200) : body};
    }
    if (r.statusCode >= 400) {
      final msg = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'HTTP ${r.statusCode}';
      throw PcBridgeException(r.statusCode, msg);
    }
    return data;
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  ]) {
    return _withClient((c) async {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
      final r = await c.get(uri, headers: _headers).timeout(timeout);
      final d = _decode(r);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    });
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _withClient((c) async {
      final r = await c
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      final d = _decode(r);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    });
  }

  Future<Uint8List> _getBytes(
    String path, [
    Map<String, String>? query,
    void Function(int received, int total)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  ]) {
    return _withClient((c) async {
      final req = http.Request(
        'GET',
        Uri.parse('$baseUrl$path').replace(queryParameters: query),
      )..headers.addAll(_headers);
      final res = await c.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode >= 400) {
        final body = await http.Response.fromStream(res);
        _decode(body);
      }
      final total = res.contentLength ?? -1;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in res.stream.timeout(timeout)) {
        builder.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      return builder.takeBytes();
    });
  }

  // ------------------------------------------------------------------ public

  static Future<({String host, String version, int devices})?> ping(
    String url, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(Uri.parse('${normalizeUrl(url)}/ping'))
          .timeout(timeout);
      if (r.statusCode != 200) return null;
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is! Map || d['service'] != 'jarvis-pc-bridge') return null;
      return (
        host: d['host']?.toString() ?? 'PC',
        version: d['version']?.toString() ?? '',
        devices: (d['devices'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  static Future<({String token, String host})> pair(
    String url,
    String pin, {
    String device = 'JARVIS Android',
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(
            Uri.parse('${normalizeUrl(url)}/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin.trim(), 'device': device}),
          )
          .timeout(const Duration(seconds: 12));
      final d = _decode(r);
      final token = d is Map ? d['token']?.toString() ?? '' : '';
      if (token.isEmpty) {
        throw const PcBridgeException(500, 'PC Köprüsü token döndürmedi.');
      }
      return (token: token, host: (d as Map)['host']?.toString() ?? 'PC');
    } on SocketException catch (e) {
      throw PcBridgeException(0, 'PC Köprüsüne ulaşılamadı: ${e.message}');
    } on TimeoutException {
      throw const PcBridgeException(0, 'PC Köprüsü yanıt vermedi.');
    } finally {
      if (client == null) c.close();
    }
  }

  /// Scans the phone's local /24 networks (Wi-Fi, hotspot, USB tethering) for
  /// a running PC Bridge. Mobile-data interfaces are skipped.
  static Future<List<PcDiscovered>> discover({
    int port = defaultPort,
    void Function(double progress)? onProgress,
    List<String> extraHosts = const [],
  }) async {
    final candidates = <String>{...extraHosts};
    final own = <String>{};
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in ifaces) {
        final name = iface.name.toLowerCase();
        if (RegExp(r'rmnet|ccmni|pdp|dummy|tun|ims|v4-|clat').hasMatch(name)) {
          continue;
        }
        for (final a in iface.addresses) {
          final parts = a.address.split('.');
          if (parts.length != 4) continue;
          own.add(a.address);
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          for (var i = 1; i < 255; i++) {
            candidates.add('$prefix.$i');
          }
        }
      }
    } catch (_) {}
    candidates.removeAll(own);
    final list = candidates.toList();
    final found = <PcDiscovered>[];
    const batch = 48;
    for (var i = 0; i < list.length; i += batch) {
      final slice = list.sublist(i, (i + batch).clamp(0, list.length));
      final open = await Future.wait(slice.map((ip) async {
        try {
          final s = await Socket.connect(
            ip,
            port,
            timeout: const Duration(milliseconds: 650),
          );
          s.destroy();
          return ip;
        } catch (_) {
          return null;
        }
      }));
      for (final ip in open.whereType<String>()) {
        final url = 'http://$ip:$port';
        final info = await ping(url);
        if (info != null) {
          found.add(PcDiscovered(
            url: url,
            host: info.host,
            version: info.version,
            devices: info.devices,
          ));
        }
      }
      onProgress?.call(((i + slice.length) / list.length).clamp(0.0, 1.0));
    }
    return found;
  }

  Future<PcHostInfo> info() async => PcHostInfo.fromJson(await _get('/api/info'));

  Future<PcKeyBundle> keys() async => PcKeyBundle.fromJson(await _get('/api/keys'));

  Future<List<PcRoot>> roots() async {
    final d = await _get('/api/roots');
    return (d['roots'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PcRoot.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PcDirListing> list(String path) async =>
      PcDirListing.fromJson(await _get('/api/list', {'path': path}));

  Future<PcFileContent> read(String path) async => PcFileContent.fromJson(
        await _get('/api/read', {'path': path}, const Duration(seconds: 40)),
      );

  Future<({String sha256, int size})> write({
    required String path,
    required String content,
    String? baseSha,
    String? encoding,
  }) async {
    final d = await _post('/api/write', {
      'path': path,
      'content': content,
      if (baseSha != null && baseSha.isNotEmpty) 'baseSha': baseSha,
      'encoding': ?encoding,
    });
    return (
      sha256: d['sha256']?.toString() ?? '',
      size: (d['size'] as num?)?.toInt() ?? 0,
    );
  }

  Future<String> create({
    required String dir,
    required String name,
    bool directory = false,
  }) async {
    final d = await _post('/api/create', {
      'dir': dir,
      'name': name,
      'type': directory ? 'dir' : 'file',
    });
    return d['path']?.toString() ?? '';
  }

  Future<String> upload({
    required String dir,
    required String name,
    required Uint8List bytes,
  }) {
    return _withClient((c) async {
      final r = await c
          .post(
            Uri.parse('$baseUrl/api/upload')
                .replace(queryParameters: {'dir': dir, 'name': name}),
            headers: {..._headers, 'Content-Type': 'application/octet-stream'},
            body: bytes,
          )
          .timeout(const Duration(minutes: 3));
      final d = _decode(r);
      return d is Map ? d['path']?.toString() ?? '' : '';
    });
  }

  Future<({List<PcSearchHit> hits, bool truncated})> search({
    required String root,
    required String query,
    bool byName = false,
    String? glob,
    bool regex = false,
    bool caseSensitive = false,
  }) async {
    final d = await _get(
      '/api/search',
      {
        'root': root,
        'q': query,
        if (byName) 'mode': 'name',
        if (glob != null && glob.trim().isNotEmpty) 'glob': glob.trim(),
        if (regex) 'regex': '1',
        if (caseSensitive) 'case': '1',
      },
      const Duration(seconds: 30),
    );
    return (
      hits: (d['hits'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PcSearchHit.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      truncated: d['truncated'] == true,
    );
  }

  Future<Map<String, dynamic>> git(String path, String op, {String? rev}) =>
      _get('/api/git', {'path': path, 'op': op, 'rev': ?rev},
          const Duration(seconds: 40));

  Future<({List<PcTask> tasks, bool claude, bool codex})> tasks() async {
    final d = await _get('/api/tasks');
    final agents = d['agents'] is Map ? d['agents'] as Map : const {};
    return (
      tasks: (d['tasks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PcTask(id: '${e['id']}', label: '${e['label']}'))
          .toList(),
      claude: agents['claude'] == true,
      codex: agents['codex'] == true,
    );
  }

  Future<PcJob> runTask(String id, String cwd) async =>
      PcJob.fromJson(await _post('/api/tasks/run', {'id': id, 'cwd': cwd}));

  Future<PcJob> startAgent({
    required String agent,
    required String prompt,
    required String cwd,
    String mode = 'edit',
  }) async =>
      PcJob.fromJson(await _post('/api/agent', {
        'agent': agent,
        'prompt': prompt,
        'cwd': cwd,
        'mode': mode,
      }));

  Future<List<PcJob>> jobs() async {
    final d = await _get('/api/jobs');
    return (d['jobs'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PcJob.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PcJob> job(String id, {int since = 0}) async =>
      PcJob.fromJson(await _get('/api/jobs/$id', {'since': '$since'}));

  Future<PcJob> cancelJob(String id) async =>
      PcJob.fromJson(await _post('/api/jobs/$id/cancel', const {}));

  Future<PcApkInfo> apkInfo() async => PcApkInfo.fromJson(await _get('/api/apk'));

  Future<Uint8List> downloadApk({
    void Function(int received, int total)? onProgress,
  }) =>
      _getBytes('/api/apk', {'download': '1'}, onProgress);

  Future<Uint8List> downloadFile(
    String path, {
    void Function(int received, int total)? onProgress,
  }) =>
      _getBytes('/api/download', {'path': path}, onProgress);

  Future<Uint8List> screenshot() =>
      _getBytes('/api/screenshot', null, null, const Duration(seconds: 40));

  Future<String> clipboard() async =>
      (await _get('/api/clipboard'))['text']?.toString() ?? '';

  Future<void> setClipboard(String text) async {
    await _post('/api/clipboard', {'text': text});
  }

  Future<void> unpair() async {
    await _post('/api/unpair', const {});
  }

  // ---- Terminal / arama / yama araçları ----

  /// Runs a shell command on the PC. A hardline-blocked command (HTTP 403)
  /// is returned as a result with [PcExecResult.blocked] set; a dangerous one
  /// returns [PcExecResult.needsApproval] without having run.
  Future<PcExecResult> exec(
    String cmd, {
    String? cwd,
    int timeout = 60,
    bool background = false,
    bool approved = false,
  }) async {
    try {
      final d = await _post(
        '/api/exec',
        {
          'cmd': cmd,
          'cwd': ?cwd,
          'timeout': timeout,
          'background': background,
          'approved': approved,
        },
        timeout: Duration(seconds: timeout + 15),
      );
      return PcExecResult.fromJson(d);
    } on PcBridgeException catch (e) {
      if (e.status == 403) {
        return PcExecResult(blocked: true, reason: e.message);
      }
      rethrow;
    }
  }

  Future<void> allowCommand(String cmd) async {
    await _post('/api/exec/allow', {'cmd': cmd});
  }

  Future<List<PcGrepHit>> searchFiles(
    String query, {
    String? path,
    String? glob,
    int max = 50,
  }) {
    return _withClient((c) async {
      final r = await c
          .post(
            Uri.parse('$baseUrl/api/search'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': query,
              'path': ?path,
              'glob': ?glob,
              'max': max,
            }),
          )
          .timeout(const Duration(seconds: 40));
      final d = _decode(r);
      if (d is! List) return <PcGrepHit>[];
      return [
        for (final e in d)
          if (e is Map) PcGrepHit.fromJson(Map<String, dynamic>.from(e)),
      ];
    });
  }

  /// Exact find/replace (`oldText` must occur exactly once). Returns the
  /// unified diff. Throws [PcBridgeException] (conflict == true) otherwise.
  Future<String> patchFile(String path, String oldText, String newText) async {
    final d = await _post('/api/patch', {
      'path': path,
      'old': oldText,
      'new': newText,
    });
    return d['diff']?.toString() ?? '';
  }
}

class PcExecResult {
  final int? exitCode;
  final String output;
  final bool truncated;
  final int durationMs;
  final bool needsApproval;
  final bool blocked;
  final String reason;
  final String? jobId;

  const PcExecResult({
    this.exitCode,
    this.output = '',
    this.truncated = false,
    this.durationMs = 0,
    this.needsApproval = false,
    this.blocked = false,
    this.reason = '',
    this.jobId,
  });

  factory PcExecResult.fromJson(Map<String, dynamic> j) => PcExecResult(
        exitCode: (j['exit_code'] as num?)?.toInt(),
        output: j['output']?.toString() ?? '',
        truncated: j['truncated'] == true,
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
        needsApproval: j['needs_approval'] == true,
        blocked: j['blocked'] == true,
        reason: j['reason']?.toString() ?? '',
        jobId: (j['job_id'] ?? j['jobId'])?.toString(),
      );
}

class PcGrepHit {
  final String path;
  final int line;
  final String text;

  const PcGrepHit({required this.path, required this.line, required this.text});

  factory PcGrepHit.fromJson(Map<String, dynamic> j) => PcGrepHit(
        path: j['path']?.toString() ?? '',
        line: (j['line'] as num?)?.toInt() ?? 0,
        text: j['text']?.toString() ?? '',
      );
}

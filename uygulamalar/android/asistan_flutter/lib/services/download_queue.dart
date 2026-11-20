import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum DownloadState {
  queued,
  scheduled,
  running,
  paused,
  completed,
  failed,
  canceled,
}

class DownloadJob {
  DownloadJob({
    required this.id,
    required this.url,
    required this.name,
    required this.category,
    this.scheduledAt,
  });
  final String id, url, name, category;
  DateTime? scheduledAt;
  DownloadState state = DownloadState.queued;
  int received = 0, total = 0, attempts = 0;
  double bytesPerSecond = 0;
  String? validator;
  String error = '', note = '', savedPath = '';
  bool stopRequested = false;
  http.Client? client;
  final List<http.Client> partClients = [];
  Future<void>? running;
  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'name': name,
    'category': category,
    'scheduled': scheduledAt?.toIso8601String(),
    'state': state.name,
    'received': received,
    'total': total,
    'attempts': attempts,
    'validator': validator,
    'error': error,
    'note': note,
    'savedPath': savedPath,
  };
  static DownloadJob fromJson(Map<String, dynamic> v) {
    final j = DownloadJob(
      id: v['id'] as String,
      url: v['url'] as String,
      name: v['name'] as String,
      category: v['category'] as String,
      scheduledAt: DateTime.tryParse(v['scheduled']?.toString() ?? ''),
    );
    j.state = DownloadState.values.firstWhere(
      (s) => s.name == v['state'],
      orElse: () => DownloadState.paused,
    );
    if (j.state == DownloadState.running) j.state = DownloadState.paused;
    j.received = (v['received'] as num?)?.toInt() ?? 0;
    j.total = (v['total'] as num?)?.toInt() ?? 0;
    j.attempts = (v['attempts'] as num?)?.toInt() ?? 0;
    j.validator = v['validator'] as String?;
    j.error = v['error']?.toString() ?? '';
    j.note = v['note']?.toString() ?? '';
    j.savedPath = v['savedPath']?.toString() ?? '';
    return j;
  }
}

/// Persistent foreground queue. Android's system queue remains available for
/// downloads that must outlive the Flutter process.
class DownloadQueue extends ChangeNotifier {
  DownloadQueue({
    http.Client Function()? clientFactory,
    this.multipartThreshold = 1024 * 1024,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final int multipartThreshold;
  int maxParts = 1;
  final List<DownloadJob> jobs = [];
  Directory? _directory;
  Timer? _ticker;
  bool _closed = false;
  int maxConcurrent = 2;
  int speedLimitKiB = 0;
  int maxRetries = 2;
  Future<void> _saveChain = Future.value();
  DateTime _lastNotice = DateTime.fromMillisecondsSinceEpoch(0);
  bool get ready => _directory != null;
  int get activeCount =>
      jobs.where((j) => j.state == DownloadState.running).length;
  File _partial(DownloadJob j) => File('${_directory!.path}/${j.id}.part');
  File _target(DownloadJob j) =>
      File('${_directory!.path}/${j.category}/${j.id}_${j.name}');

  Future<void> initialize({
    Directory? directory,
    bool startTimer = true,
  }) async {
    if (ready) return;
    _directory =
        directory ??
        Directory(
          '${(await getApplicationDocumentsDirectory()).path}/download_queue',
        );
    await _directory!.create(recursive: true);
    final state = File('${_directory!.path}/queue.json');
    if (await state.exists()) {
      try {
        final data = jsonDecode(await state.readAsString()) as Map;
        maxConcurrent = ((data['concurrency'] as num?)?.toInt() ?? 2).clamp(
          1,
          4,
        );
        maxParts = ((data['parts'] as num?)?.toInt() ?? 1).clamp(1, 4);
        speedLimitKiB = ((data['speedKiB'] as num?)?.toInt() ?? 0).clamp(
          0,
          10240,
        );
        for (final raw in (data['jobs'] as List? ?? [])) {
          final job = DownloadJob.fromJson(
            Map<String, dynamic>.from(raw as Map),
          );
          // Only generated identifiers and safe basenames may become local paths.
          if (!RegExp(r'^\d+_\d+$').hasMatch(job.id) ||
              job.name.contains('/') ||
              job.name.contains('\\') ||
              !categories.contains(job.category))
            continue;
          jobs.add(job);
        }
      } catch (_) {
        // Preserve a damaged state file for recovery instead of deleting it.
        await state.copy('${state.path}.recovery');
      }
    }
    if (startTimer)
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => pump());
    notifyListeners();
  }

  static const categories = [
    'Belgeler',
    'Gorseller',
    'Videolar',
    'Sesler',
    'Arsivler',
    'Diger',
  ];
  static String categoryFor(String name) {
    final ext = name.toLowerCase().split('.').last;
    if ([
      'pdf',
      'doc',
      'docx',
      'xlsx',
      'pptx',
      'txt',
      'csv',
      'epub',
    ].contains(ext))
      return 'Belgeler';
    if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) return 'Gorseller';
    if (['mp4', 'webm', 'mkv', 'mov'].contains(ext)) return 'Videolar';
    if (['mp3', 'wav', 'm4a', 'flac', 'ogg'].contains(ext)) return 'Sesler';
    if (['zip', '7z', 'rar', 'apk'].contains(ext)) return 'Arsivler';
    return 'Diger';
  }

  Future<DownloadJob> add(
    String url, {
    DateTime? scheduledAt,
    bool start = true,
  }) async {
    if (!ready) await initialize();
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty)
      throw const FormatException(
        'Geçerli HTTP/HTTPS dosya bağlantısı gerekli.',
      );
    var name = uri.pathSegments.isEmpty ? 'dosya' : uri.pathSegments.last;
    name = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'dosya';
    if (name.length > 100) name = name.substring(name.length - 100);
    final job = DownloadJob(
      id: '${DateTime.now().microsecondsSinceEpoch}_${jobs.length}',
      url: uri.toString(),
      name: name,
      category: categoryFor(name),
      scheduledAt: scheduledAt,
    );
    job.state = scheduledAt != null && scheduledAt.isAfter(DateTime.now())
        ? DownloadState.scheduled
        : DownloadState.queued;
    jobs.insert(0, job);
    await _save();
    notifyListeners();
    if (start) pump();
    return job;
  }

  void configure({int? concurrency, int? speedKiB, int? parts}) {
    if (parts != null) maxParts = parts.clamp(1, 4);
    if (concurrency != null) maxConcurrent = concurrency.clamp(1, 4);
    if (speedKiB != null) speedLimitKiB = speedKiB.clamp(0, 10240);
    unawaited(_save());
    notifyListeners();
    pump();
  }

  void pump() {
    if (_closed || !ready) return;
    for (final job in jobs.reversed) {
      if (activeCount >= maxConcurrent) break;
      if (job.running != null) continue;
      if (job.state != DownloadState.queued &&
          job.state != DownloadState.scheduled)
        continue;
      if (job.scheduledAt?.isAfter(DateTime.now()) == true) continue;
      job.state = DownloadState.running;
      job.stopRequested = false;
      job.error = '';
      job.running = _download(job).whenComplete(() {
        job.running = null;
        if (!_closed) {
          unawaited(_save());
          notifyListeners();
          pump();
        }
      });
      notifyListeners();
    }
  }

  Future<void> pause(DownloadJob job) async {
    if (job.state == DownloadState.completed ||
        job.state == DownloadState.canceled)
      return;
    job.stopRequested = true;
    job.state = DownloadState.paused;
    job.client?.close();
    for (final client in job.partClients) {
      client.close();
    }
    notifyListeners();
    await job.running;
    await _save();
  }

  Future<void> resume(DownloadJob job) async {
    if (job.state == DownloadState.completed ||
        job.state == DownloadState.running)
      return;
    await job.running;
    job.attempts = 0;
    job.scheduledAt = null;
    job.state = DownloadState.queued;
    await _save();
    pump();
  }

  Future<void> cancel(DownloadJob job) async {
    await pause(job);
    if (job.state == DownloadState.completed) return;
    job.state = DownloadState.canceled;
    final partial = _partial(job);
    if (await partial.exists()) await partial.delete();
    for (var i = 0; i < 4; i++) {
      final file = File('${_directory!.path}/${job.id}.p$i');
      if (await file.exists()) await file.delete();
    }
    job.received = 0;
    await _save();
    notifyListeners();
  }

  Future<void> reschedule(DownloadJob job, DateTime when) async {
    await pause(job);
    if (job.state == DownloadState.completed) return;
    job.scheduledAt = when;
    job.state = DownloadState.scheduled;
    await _save();
    notifyListeners();
    pump();
  }

  Future<void> _download(DownloadJob job) async {
    IOSink? sink;
    final client = _clientFactory();
    job.client = client;
    try {
      if (maxParts > 1 && await _tryMultipart(job, client)) return;
      final partial = _partial(job);
      var offset = await partial.exists() ? await partial.length() : 0;
      // Resuming without a validator could concatenate two different revisions.
      if (offset > 0 && job.validator == null) {
        offset = 0;
        job.note =
            'Sunucu doğrulayıcısı yok; güvenli biçimde baştan indiriliyor.';
      }
      final request = http.Request('GET', Uri.parse(job.url));
      request.headers['Accept-Encoding'] = 'identity';
      if (offset > 0) {
        request.headers['Range'] = 'bytes=$offset-';
        request.headers['If-Range'] = job.validator!;
      }
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (job.stopRequested || _closed) return;
      final contentEncoding = response.headers['content-encoding'];
      if (contentEncoding != null && contentEncoding != 'identity')
        throw const FormatException(
          'Sunucu sıkıştırılmış yanıt döndürdü; güvenli devam desteklenmiyor.',
        );
      if (response.statusCode == 206) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers['content-range'] ?? '');
        if (range == null ||
            int.parse(range.group(1)!) != offset ||
            int.parse(range.group(2)!) < offset)
          throw const FormatException(
            'Sunucunun dosya aralığı yanıtı geçersiz.',
          );
        final current =
            response.headers['etag'] ?? response.headers['last-modified'];
        if (offset > 0 && current != null && current != job.validator)
          throw const FormatException(
            'Dosya sunucuda değişti; mevcut parça korunarak indirme durduruldu.',
          );
        job.total = int.parse(range.group(3)!);
      } else if (response.statusCode == 200) {
        if (offset > 0)
          job.note =
              'Sunucu devam isteğini kabul etmedi; dosya baştan indiriliyor.';
        offset = 0;
        job.total = response.contentLength ?? 0;
      } else {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final etag = response.headers['etag'];
      job.validator = etag != null && !etag.startsWith('W/')
          ? etag
          : response.headers['last-modified'];
      job.received = offset;
      await _save();
      sink = partial.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      final clock = Stopwatch()..start();
      var transferred = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        if (job.stopRequested || _closed) break;
        sink.add(chunk);
        job.received += chunk.length;
        transferred += chunk.length;
        job.bytesPerSecond =
            transferred * 1000 / (clock.elapsedMilliseconds + 1);
        if (speedLimitKiB > 0) {
          final requiredMs = (transferred * 1000 / (speedLimitKiB * 1024))
              .round();
          while (!job.stopRequested &&
              !_closed &&
              clock.elapsedMilliseconds < requiredMs) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        if (DateTime.now().difference(_lastNotice).inMilliseconds >= 250) {
          _lastNotice = DateTime.now();
          if (!_closed) notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (job.stopRequested || _closed) return;
      if (job.total > 0 && job.received != job.total)
        throw const FormatException('Dosya eksik veya beklenenden uzun geldi.');
      final target = _target(job);
      await target.parent.create(recursive: true);
      await partial.rename(target.path);
      job.savedPath = target.path;
      job.state = DownloadState.completed;
      job.bytesPerSecond = 0;
    } catch (error) {
      if (!job.stopRequested && !_closed) {
        job.attempts++;
        job.error = error is HttpException
            ? error.message
            : error is FormatException
            ? error.message
            : 'Bağlantı kesildi veya zaman aşımı oluştu.';
        final retryable =
            error is! FormatException &&
            !(error is HttpException &&
                RegExp(r'HTTP 4\d\d').hasMatch(error.message));
        if (retryable && job.attempts <= maxRetries) {
          job.scheduledAt = DateTime.now().add(
            Duration(seconds: 2 * job.attempts),
          );
          job.state = DownloadState.scheduled;
        } else {
          job.state = DownloadState.failed;
        }
      }
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      client.close();
      job.client = null;
      job.bytesPerSecond = 0;
    }
  }

  Future<bool> _tryMultipart(DownloadJob job, http.Client headClient) async {
    http.Response head;
    try {
      head = await headClient
          .head(Uri.parse(job.url), headers: {'Accept-Encoding': 'identity'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return false;
    }
    final total = int.tryParse(head.headers['content-length'] ?? '') ?? 0;
    final tag = head.headers['etag'];
    if (head.statusCode != 200 ||
        total < multipartThreshold ||
        head.headers['accept-ranges'] != 'bytes' ||
        tag == null ||
        tag.startsWith('W/')) {
      job.note = 'Sunucu doğrulanabilir çok parçalı indirmeyi desteklemiyor; tek bağlantı kullanılıyor.';
      return false;
    }
    if (job.stopRequested || _closed) return true;
    final combined = _partial(job);
    if (await combined.exists()) await combined.delete();
    final count = maxParts;
    final metadata = File('${_directory!.path}/${job.id}.parts.json');
    final signature = '$tag:$total:$count';
    final previous = await metadata.exists()
        ? await metadata.readAsString()
        : '';
    if (previous != signature) {
      for (var i = 0; i < 4; i++) {
        final f = File('${_directory!.path}/${job.id}.p$i');
        if (await f.exists()) await f.delete();
      }
      await metadata.writeAsString(signature, flush: true);
    }
    final sizes = <int>[];
    for (var i = 0; i < count; i++) {
      final f = File('${_directory!.path}/${job.id}.p$i');
      sizes.add(await f.exists() ? await f.length() : 0);
    }
    job.total = total;
    job.validator = tag;
    job.received = sizes.fold(0, (a, b) => a + b);
    job.note = '$count doğrulanmış parça ile indiriliyor.';
    await _save();
    final clock = Stopwatch()..start();
    final originalReceived = job.received;
    Future<void> part(int i) async {
      final start = total * i ~/ count;
      final end = total * (i + 1) ~/ count - 1;
      final expected = end - start + 1;
      if (sizes[i] == expected) return;
      if (sizes[i] > expected)
        throw const FormatException('Yerel dosya parçası geçersiz.');
      final client = _clientFactory();
      job.partClients.add(client);
      IOSink? sink;
      try {
        final request = http.Request('GET', Uri.parse(job.url));
        request.headers.addAll({
          'Range': 'bytes=${start + sizes[i]}-$end',
          'If-Range': tag,
          'Accept-Encoding': 'identity',
        });
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 20));
        final expectedRange = 'bytes ${start + sizes[i]}-$end/$total';
        if (response.statusCode != 206 ||
            response.headers['content-range'] != expectedRange ||
            response.headers['etag'] != tag) {
          throw const FormatException(
            'Parçalı indirme yanıtı doğrulanamadı. Tek bağlantı seçip yeniden deneyin.',
          );
        }
        if (job.stopRequested || _closed) return;
        sink = File('${_directory!.path}/${job.id}.p$i')
            .openWrite(mode: FileMode.append);
        var transferred = 0;
        final partClock = Stopwatch()..start();
        await for (final bytes in response.stream.timeout(
          const Duration(seconds: 20),
        )) {
          if (job.stopRequested || _closed) break;
          if (sizes[i] + bytes.length > expected)
            throw const FormatException('Sunucu dosya parçası boyutunu aştı.');
          sink.add(bytes);
          sizes[i] += bytes.length;
          transferred += bytes.length;
          job.received = sizes.fold(0, (a, b) => a + b);
          job.bytesPerSecond =
              (job.received - originalReceived) *
              1000 /
              (clock.elapsedMilliseconds + 1);
          if (speedLimitKiB > 0) {
            final required =
                transferred * 1000 * count ~/ (speedLimitKiB * 1024);
            while (!job.stopRequested &&
                !_closed &&
                partClock.elapsedMilliseconds < required) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
          if (!_closed) notifyListeners();
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (!job.stopRequested && !_closed && sizes[i] != expected)
          throw const HttpException('Dosya parçası eksik kaldı.');
      } finally {
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {}
        }
        client.close();
        job.partClients.remove(client);
      }
    }

    // All workers finish/close before a pause, retry or merge can touch files.
    await Future.wait(List.generate(count, part));
    if (job.stopRequested || _closed) return true;
    final merged = _partial(job).openWrite();
    try {
      for (var i = 0; i < count; i++) {
        await merged.addStream(
          File('${_directory!.path}/${job.id}.p$i').openRead(),
        );
      }
      await merged.flush();
    } finally {
      await merged.close();
    }
    if (job.stopRequested || _closed) return true;
    if (await _partial(job).length() != total)
      throw const FormatException('Birleştirilmiş dosya boyutu geçersiz.');
    final target = _target(job);
    await target.parent.create(recursive: true);
    await _partial(job).rename(target.path);
    job.savedPath = target.path;
    job.state = DownloadState.completed;
    for (var i = 0; i < count; i++) {
      await File('${_directory!.path}/${job.id}.p$i').delete();
    }
    await metadata.delete();
    return true;
  }

  Future<void> _save() {
    if (!ready) return Future.value();
    final payload = jsonEncode({
      'concurrency': maxConcurrent,
      'parts': maxParts,
      'speedKiB': speedLimitKiB,
      'jobs': jobs.map((j) => j.toJson()).toList(),
    });
    _saveChain = _saveChain.catchError((_) {}).then((_) async {
      final file = File('${_directory!.path}/queue.json');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    });
    return _saveChain;
  }

  @override
  void dispose() {
    _closed = true;
    _ticker?.cancel();
    for (final job in jobs) {
      job.stopRequested = true;
      if (job.state == DownloadState.running) job.state = DownloadState.paused;
      job.client?.close();
      for (final client in job.partClients) {
        client.close();
      }
    }
    unawaited(_save());
    super.dispose();
  }
}

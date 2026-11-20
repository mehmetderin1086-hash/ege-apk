import 'package:flutter/material.dart';

import '../services/asistan_controller.dart';
import '../services/download_queue.dart';
import 'legacy_downloader_screen.dart';

class DownloaderScreen extends StatefulWidget {
  const DownloaderScreen({super.key, required this.controller});
  final AsistanController controller;
  @override
  State<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends State<DownloaderScreen> {
  final _url = TextEditingController();
  String _error = '', _filter = 'Tümü';
  DateTime? _scheduled;
  DownloadQueue get queue => widget.controller.downloadQueue;
  @override
  void initState() {
    super.initState();
    _takeSharedUrl();
  }

  @override
  void didUpdateWidget(covariant DownloaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _takeSharedUrl();
  }

  void _takeSharedUrl() {
    if (widget.controller.downloadDraftUrl.isNotEmpty) {
      _url.text = widget.controller.downloadDraftUrl;
      widget.controller.downloadDraftUrl = '';
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickSchedule() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _add() async {
    try {
      await queue.add(_url.text, scheduledAt: _scheduled);
      if (!mounted) return;
      setState(() {
        _error = '';
        _scheduled = null;
        _url.clear();
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'İndirme eklenemedi. Geçerli HTTP/HTTPS dosya bağlantısı girin.',
        );
    }
  }

  String _size(num bytes) => bytes >= 1048576
      ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';
  String _status(DownloadJob j) => switch (j.state) {
    DownloadState.queued => 'Kuyrukta',
    DownloadState.scheduled => 'Zamanlandı',
    DownloadState.running => 'İndiriliyor',
    DownloadState.paused => 'Duraklatıldı',
    DownloadState.completed => 'Tamamlandı',
    DownloadState.failed => 'Başarısız',
    DownloadState.canceled => 'İptal edildi',
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: queue,
    builder: (context, _) {
      final jobs = queue.jobs
          .where((j) => _filter == 'Tümü' || j.category == _filter)
          .toList();
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'İndirme yöneticisi',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Dosya bağlantısı',
              hintText: 'https://…/dosya.zip',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.download),
                label: const Text('Kuyruğa ekle'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final value = await _pickSchedule();
                  if (value != null && mounted)
                    setState(() => _scheduled = value);
                },
                icon: const Icon(Icons.schedule),
                label: Text(
                  _scheduled == null
                      ? 'Zamanla'
                      : '${_scheduled!.day}.${_scheduled!.month} ${_scheduled!.hour}:${_scheduled!.minute.toString().padLeft(2, '0')}',
                ),
              ),
              if (_scheduled != null)
                IconButton(
                  tooltip: 'Zamanlamayı kaldır',
                  onPressed: () => setState(() => _scheduled = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: Colors.amberAccent)),
          if (widget.controller.downloadQueueError.isNotEmpty)
            Text(widget.controller.downloadQueueError),
          const Text(
            'Bu kuyruk uygulama çalışırken indirmeleri ve zamanlamayı yönetir. Android uygulamayı kapatırsa yarım dosyalar korunur; tekrar açınca devam ettirebilirsiniz.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              title: const Text('Hız ve bağlantı ayarları'),
              children: [
                DropdownButtonFormField<int>(
                  initialValue: queue.maxConcurrent,
                  decoration: const InputDecoration(
                    labelText: 'Aynı anda indirilecek dosya',
                  ),
                  items: [1, 2, 3, 4]
                      .map(
                        (v) =>
                            DropdownMenuItem(value: v, child: Text('$v dosya')),
                      )
                      .toList(),
                  onChanged: (v) => queue.configure(concurrency: v),
                ),
                DropdownButtonFormField<int>(
                  initialValue: queue.speedLimitKiB,
                  decoration: const InputDecoration(
                    labelText: 'Dosya başına hız sınırı',
                  ),
                  items: [0, 128, 512, 1024, 4096]
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(v == 0 ? 'Sınırsız' : '$v KB/sn'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => queue.configure(speedKiB: v),
                ),
                DropdownButtonFormField<int>(
                  initialValue: queue.maxParts,
                  decoration: const InputDecoration(
                    labelText: 'Dosya başına bağlantı',
                  ),
                  items: [1, 2, 4]
                      .map(
                        (v) =>
                            DropdownMenuItem(value: v, child: Text('$v parça')),
                      )
                      .toList(),
                  onChanged: (v) => queue.configure(parts: v),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Çok parçalı indirme yalnızca dosya boyutu, aralık ve güçlü ETag doğrulaması sağlayan sunucularda kullanılır. Diğer sunucularda tek bağlantıya geçilir.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    title: const Text('Sistem indirmeleri ve web araçları'),
                  ),
                  body: LegacyDownloaderScreen(controller: widget.controller),
                ),
              ),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Android arka plan kuyruğu ve web araçları'),
          ),
          const Divider(),
          DropdownButton<String>(
            value: _filter,
            isExpanded: true,
            items: [
              'Tümü',
              ...DownloadQueue.categories,
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _filter = v!),
          ),
          if (jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Henüz indirme yok. Bir dosya bağlantısı ekleyin veya başka uygulamadan Asistan’a paylaşın.',
              ),
            ),
          for (final job in jobs)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_status(job)} · ${_size(job.received)}${job.total > 0 ? ' / ${_size(job.total)}' : ''}${job.bytesPerSecond > 0 ? ' · ${_size(job.bytesPerSecond)}/sn' : ''}',
                    ),
                    if (job.scheduledAt != null &&
                        job.state == DownloadState.scheduled)
                      Text(
                        'Başlangıç: ${job.scheduledAt!.toLocal().toString().substring(0, 16)}',
                      ),
                    if (job.state == DownloadState.running)
                      LinearProgressIndicator(
                        value: job.total > 0
                            ? (job.received / job.total).clamp(0, 1)
                            : null,
                      ),
                    if (job.note.isNotEmpty)
                      Text(job.note, style: const TextStyle(fontSize: 12)),
                    if (job.error.isNotEmpty)
                      Text(
                        job.error,
                        style: const TextStyle(color: Colors.amberAccent),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if ([
                          DownloadState.running,
                          DownloadState.queued,
                          DownloadState.scheduled,
                        ].contains(job.state))
                          TextButton(
                            onPressed: () => queue.pause(job),
                            child: const Text('Duraklat'),
                          ),
                        if ([
                          DownloadState.paused,
                          DownloadState.failed,
                          DownloadState.canceled,
                        ].contains(job.state))
                          TextButton(
                            onPressed: () => queue.resume(job),
                            child: Text(
                              job.state == DownloadState.paused
                                  ? 'Sürdür'
                                  : 'Yeniden dene',
                            ),
                          ),
                        if (job.state != DownloadState.completed &&
                            job.state != DownloadState.canceled)
                          TextButton(
                            onPressed: () => queue.cancel(job),
                            child: const Text('İptal'),
                          ),
                        if (job.state != DownloadState.completed)
                          TextButton(
                            onPressed: () async {
                              final when = await _pickSchedule();
                              if (when != null)
                                await queue.reschedule(job, when);
                            },
                            child: const Text('Zamanla'),
                          ),
                        if (job.state == DownloadState.completed) ...[
                          TextButton(
                            onPressed: () => widget.controller.invokeNative(
                              'openFile',
                              {'path': job.savedPath},
                            ),
                            child: const Text('Aç'),
                          ),
                          TextButton(
                            onPressed: () => widget.controller.invokeNative(
                              'shareFile',
                              {'path': job.savedPath, 'title': job.name},
                            ),
                            child: const Text('Paylaş'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final result = await widget.controller
                                  .invokeNative('publishDownload', {
                                    'path': job.savedPath,
                                    'name': job.name,
                                    'category': job.category,
                                  });
                              if (context.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      result is Map
                                          ? result['message'].toString()
                                          : 'Dosya dışa aktarılamadı.',
                                    ),
                                  ),
                                );
                            },
                            child: const Text('İndirilenlere kaydet'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

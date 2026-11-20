import 'dart:convert';
import 'textbook_report_xlsx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'textbook_report.dart';

class TextbookReportPage extends StatefulWidget {
  const TextbookReportPage({super.key, required this.books});
  final List<Map<String, dynamic>> books;
  @override
  State<TextbookReportPage> createState() => _TextbookReportPageState();
}

class _TextbookReportPageState extends State<TextbookReportPage> {
  DateTime end = DateTime.now();
  late DateTime start = DateTime(end.year - 1, end.month, end.day);
  String period = '', className = '', query = '';
  bool exporting = false;
  @override
  Widget build(BuildContext context) {
    final all = textbookReport(
      widget.books,
      TextbookReportFilter(start: DateTime(1900), end: DateTime(2100)),
    );
    final periods =
        all.map((r) => r.period).where((p) => p.isNotEmpty).toSet().toList()
          ..sort();
    final classes =
        all.map((r) => r.className).where((c) => c.isNotEmpty).toSet().toList()
          ..sort();
    final rows = textbookReport(
      widget.books,
      TextbookReportFilter(
        start: start,
        end: end,
        period: period,
        className: className,
        query: query,
      ),
    );
    String display(DateTime d) => '${d.day}.${d.month}.${d.year}';
    return Scaffold(
      appBar: AppBar(title: const Text('Ders kitabı çizelgesi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Dağıtım ve iadeler ödünç kimliğiyle eşleştirilir. Eksik veya çelişkili kayıtlar ayrıca gösterilir.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          for (final isStart in [true, false])
            TextButton(
              onPressed: () async {
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: isStart ? start : end,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                );
                if (chosen != null && mounted)
                  setState(() {
                    if (isStart) {
                      start = chosen;
                    } else {
                      end = chosen;
                    }
                  });
              },
              child: Text(
                '${isStart ? 'Başlangıç' : 'Bitiş'}: ${display(isStart ? start : end)}',
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: period,
            decoration: const InputDecoration(labelText: 'Dağıtım dönemi'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tüm dönemler')),
              for (final p in periods)
                DropdownMenuItem(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => period = v ?? ''),
          ),
          DropdownButtonFormField<String>(
            initialValue: className,
            decoration: const InputDecoration(labelText: 'Teslim sınıfı'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tüm sınıflar')),
              for (final c in classes)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => className = v ?? ''),
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Öğrenci, numara, kitap veya demirbaş ara',
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          if (start.isAfter(end))
            const Text('Başlangıç tarihi bitişten sonra olamaz.'),
          Text(
            '${rows.length} kayıt',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          FilledButton.icon(
            onPressed: exporting || start.isAfter(end)
                ? null
                : () async {
                    setState(() => exporting = true);
                    try {
                      final ok = await const MethodChannel('kitapbul/files')
                          .invokeMethod<bool>('exportCsv', {
                            'data': textbookReportCsv(rows),
                            'filename': 'DersKitabiCizelgesi.csv',
                          });
                      if (mounted && ok == true)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Çizelge kaydedildi.')),
                        );
                    } catch (_) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Çizelge kaydedilemedi.'),
                          ),
                        );
                    } finally {
                      if (mounted) setState(() => exporting = false);
                    }
                  },
            icon: const Icon(Icons.save_alt),
            label: const Text('CSV kaydet'),
          ),
          OutlinedButton.icon(
            onPressed: exporting || start.isAfter(end)
                ? null
                : () async {
                    setState(() => exporting = true);
                    try {
                      final payload = jsonEncode({
                        'headers': textbookReportHeaders,
                        'rows': rows.map((row) => row.fields).toList(),
                        'filters': [
                          'Tarih aralığı: ${display(start)} – ${display(end)}',
                          'Dönem: ${period.isEmpty ? 'Tüm dönemler' : period}',
                          'Sınıf: ${className.isEmpty ? 'Tüm sınıflar' : className}',
                          'Arama: ${query.isEmpty ? 'Tümü' : query}',
                        ],
                      });
                      final ok = await const MethodChannel('kitapbul/files')
                          .invokeMethod<bool>('exportTextbookPdf', {
                            'data': payload,
                            'filename': 'DersKitabiCizelgesi.pdf',
                          });
                      if (mounted && ok == true)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('PDF çizelgesi kaydedildi.'),
                          ),
                        );
                    } catch (_) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('PDF çizelgesi kaydedilemedi.'),
                          ),
                        );
                    } finally {
                      if (mounted) setState(() => exporting = false);
                    }
                  },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF kaydet'),
          ),
          OutlinedButton.icon(
            onPressed: exporting || start.isAfter(end)
                ? null
                : () async {
                    setState(() => exporting = true);
                    try {
                      final ok = await const MethodChannel('kitapbul/files')
                          .invokeMethod<bool>('exportXlsx', {
                            'bytes': textbookReportXlsx(rows),
                          });
                      if (mounted && ok == true)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Excel çizelgesi kaydedildi.'),
                          ),
                        );
                    } catch (_) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Excel çizelgesi kaydedilemedi.'),
                          ),
                        );
                    } finally {
                      if (mounted) setState(() => exporting = false);
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Excel kaydet'),
          ),
          for (final r in rows)
            Card(
              child: ListTile(
                title: Text('${r.person} · ${r.book}'),
                subtitle: Text(
                  '${r.className} · ${r.period}\n${r.status}${r.note.isEmpty ? '' : '\n${r.note}'}\nTeslim: ${r.delivered} · İade: ${r.returned}',
                ),
                isThreeLine: true,
              ),
            ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Bu kapsamda ders kitabı kaydı yok.'),
            ),
        ],
      ),
    );
  }
}

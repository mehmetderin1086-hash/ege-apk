import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme_settings.dart';
import 'book_visuals.dart';
import 'student_store.dart';

class DutyAssignment {
  const DutyAssignment({
    required this.studentId,
    required this.name,
    required this.className,
    required this.number,
    this.shift = 'Tam Gün',
  });

  final String studentId;
  final String name;
  final String className;
  final String number;
  final String shift;

  Map<String, dynamic> toJson() => {
    'studentId': studentId,
    'name': name,
    'className': className,
    'number': number,
    'shift': shift,
  };

  factory DutyAssignment.fromJson(Map<String, dynamic> json) {
    return DutyAssignment(
      studentId: (json['studentId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      className: (json['className'] ?? '').toString(),
      number: (json['number'] ?? '').toString(),
      shift: (json['shift'] ?? 'Tam Gün').toString(),
    );
  }
}

const weekdayNamesTr = <int, String>{
  1: 'Pazartesi',
  2: 'Salı',
  3: 'Çarşamba',
  4: 'Perşembe',
  5: 'Cuma',
};

/// Cumhuriyet Anadolu Lisesi — Cumhuriyet Kütüphanesi resmî güncel nöbet listesi.
Map<int, List<DutyAssignment>> defaultCumhuriyetDutySchedule() => {
  1: const [
    DutyAssignment(
      studentId: 'CAL-DUTY-13',
      name: 'Baraa Hamid Nsaif Karagholi',
      className: '9/C',
      number: '13',
    ),
    DutyAssignment(
      studentId: 'CAL-DUTY-176',
      name: 'Ayşenur Timofte',
      className: '9/C',
      number: '176',
    ),
  ],
  2: const [
    DutyAssignment(
      studentId: 'CAL-DUTY-186',
      name: 'Ahmet Eren Şimşak',
      className: '9/B',
      number: '186',
    ),
    DutyAssignment(
      studentId: 'CAL-DUTY-22',
      name: 'Seyid Ali Bahadır',
      className: '10/A',
      number: '22',
    ),
  ],
  3: const [
    DutyAssignment(
      studentId: 'CAL-DUTY-124',
      name: 'Buğlem Sezen',
      className: '10/B',
      number: '124',
    ),
    DutyAssignment(
      studentId: 'CAL-DUTY-18',
      name: 'Öykü Durmuş',
      className: '10/B',
      number: '18',
    ),
    DutyAssignment(
      studentId: 'CAL-DUTY-237',
      name: 'Sude Naz Paşalı',
      className: '11/B',
      number: '237',
    ),
  ],
  4: const [
    DutyAssignment(
      studentId: 'CAL-DUTY-128',
      name: 'Belinay Kibar',
      className: '10/A',
      number: '128',
    ),
    DutyAssignment(
      studentId: 'CAL-DUTY-20',
      name: 'Beyza Nur Yıldırım',
      className: '10/A',
      number: '20',
    ),
    DutyAssignment(
      studentId: 'CAL-DUTY-100',
      name: 'Ela Nur Uzun',
      className: '10/A',
      number: '100',
    ),
  ],
  5: const [
    DutyAssignment(
      studentId: 'CAL-DUTY-130',
      name: 'Ayaz Dikal',
      className: '9/B',
      number: '130',
    ),
    DutyAssignment(
      studentId: 'CAL-DUTY-226',
      name: 'Mustafa Mehdi Yurdakul',
      className: '9/C',
      number: '226',
    ),
  ],
};

class SchoolDutyRoster {
  const SchoolDutyRoster({
    required this.days,
    this.attendance = const {},
  });

  final Map<int, List<DutyAssignment>> days;
  final Map<String, Set<String>> attendance;

  List<DutyAssignment> forWeekday(int weekday) =>
      days[weekday] ?? const <DutyAssignment>[];

  int get totalAssigned =>
      days.values.fold<int>(0, (sum, list) => sum + list.length);

  static String dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  bool isPresent(DateTime date, DutyAssignment slot) {
    final key = dateKey(date);
    final token = '${slot.number}|${slot.name}';
    return attendance[key]?.contains(token) == true;
  }

  SchoolDutyRoster toggleAttendance(DateTime date, DutyAssignment slot) {
    final key = dateKey(date);
    final token = '${slot.number}|${slot.name}';
    final nextMap = <String, Set<String>>{
      for (final e in attendance.entries) e.key: {...e.value},
    };
    final set = nextMap.putIfAbsent(key, () => <String>{});
    if (!set.remove(token)) set.add(token);
    return SchoolDutyRoster(days: days, attendance: nextMap);
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'days': {
      for (var d = 1; d <= 5; d++)
        '$d': (days[d] ?? const []).map((e) => e.toJson()).toList(),
    },
    'attendance': {
      for (final e in attendance.entries)
        if (e.value.isNotEmpty) e.key: e.value.toList(),
    },
  };

  factory SchoolDutyRoster.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final parsedDays = <int, List<DutyAssignment>>{};
    if (rawDays is Map) {
      for (var d = 1; d <= 5; d++) {
        final list = rawDays['$d'];
        if (list is List) {
          parsedDays[d] = list
              .whereType<Map>()
              .map((m) => DutyAssignment.fromJson(Map<String, dynamic>.from(m)))
              .toList();
        } else {
          parsedDays[d] = const [];
        }
      }
    } else {
      return SchoolDutyRoster(days: defaultCumhuriyetDutySchedule());
    }
    final rawAtt = json['attendance'];
    final parsedAtt = <String, Set<String>>{};
    if (rawAtt is Map) {
      for (final e in rawAtt.entries) {
        if (e.key is String && e.value is List) {
          parsedAtt[e.key as String] =
              (e.value as List).map((x) => x.toString()).toSet();
        }
      }
    }
    return SchoolDutyRoster(days: parsedDays, attendance: parsedAtt);
  }
}

class SchoolDutyStore {
  SchoolDutyStore(this.directory);
  final Directory directory;

  File get file => File('${directory.path}/school_duty_roster.json');

  Future<SchoolDutyRoster> load() async {
    try {
      if (!await file.exists()) {
        return SchoolDutyRoster(days: defaultCumhuriyetDutySchedule());
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map<String, dynamic>) {
        final loaded = SchoolDutyRoster.fromJson(raw);
        if (loaded.totalAssigned > 0) return loaded;
      }
    } catch (_) {}
    return SchoolDutyRoster(days: defaultCumhuriyetDutySchedule());
  }

  Future<void> save(SchoolDutyRoster roster) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(roster.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

class SchoolDutyRosterPage extends StatefulWidget {
  const SchoolDutyRosterPage({
    super.key,
    required this.students,
    this.initialRoster,
    this.onChanged,
  });

  final List<Student> students;
  final SchoolDutyRoster? initialRoster;
  final ValueChanged<SchoolDutyRoster>? onChanged;

  @override
  State<SchoolDutyRosterPage> createState() => _SchoolDutyRosterPageState();
}

class _SchoolDutyRosterPageState extends State<SchoolDutyRosterPage> {
  late SchoolDutyRoster _roster =
      widget.initialRoster ??
      SchoolDutyRoster(days: defaultCumhuriyetDutySchedule());
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRoster == null) {
      _loadFromDisk();
    }
  }

  Future<void> _loadFromDisk() async {
    final docs = await getApplicationDocumentsDirectory();
    final loaded = await SchoolDutyStore(docs).load();
    if (mounted) setState(() => _roster = loaded);
  }

  Future<void> _persist(SchoolDutyRoster next) async {
    setState(() => _roster = next);
    widget.onChanged?.call(next);
    try {
      final docs = await getApplicationDocumentsDirectory();
      await SchoolDutyStore(docs).save(next);
    } catch (_) {}
  }

  Future<void> _addDutyDialog(int weekday) async {
    Student? selectedStudent;
    final nameCtrl = TextEditingController();
    final classCtrl = TextEditingController();
    final numCtrl = TextEditingController();
    var shift = 'Tam Gün';

    final activeStudents =
        widget.students.where((s) => s.graduatedAt == null).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final added = await showDialog<DutyAssignment>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text('${weekdayNamesTr[weekday]} Nöbetçisi Ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (activeStudents.isNotEmpty) ...[
                  DropdownButtonFormField<Student>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Kayıtlı Öğrenciden Seç',
                      isDense: true,
                    ),
                    items: [
                      for (final s in activeStudents)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            '${s.name} (${s.className} · No: ${s.number})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (s) {
                      refresh(() {
                        selectedStudent = s;
                        if (s != null) {
                          nameCtrl.text = s.name;
                          classCtrl.text = s.className;
                          numCtrl.text = s.number;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Öğrenci Adı Soyadı',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: classCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Sınıf (örn. 10/A)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: numCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Okul No',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: shift,
                  decoration: const InputDecoration(
                    labelText: 'Nöbet Vardiyası',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Tam Gün', child: Text('Tam Gün')),
                    DropdownMenuItem(
                      value: 'Öğleden Önce',
                      child: Text('Öğleden Önce'),
                    ),
                    DropdownMenuItem(
                      value: 'Öğle Arası',
                      child: Text('Öğle Arası'),
                    ),
                    DropdownMenuItem(
                      value: 'Öğleden Sonra',
                      child: Text('Öğleden Sonra'),
                    ),
                  ],
                  onChanged: (v) => refresh(() => shift = v ?? 'Tam Gün'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(
                  ctx,
                  DutyAssignment(
                    studentId:
                        selectedStudent?.id ??
                        'MANUAL-${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    className: classCtrl.text.trim(),
                    number: numCtrl.text.trim(),
                    shift: shift,
                  ),
                );
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );

    if (added == null) return;
    final nextDays = <int, List<DutyAssignment>>{
      for (final e in _roster.days.entries) e.key: [...e.value],
    };
    nextDays.putIfAbsent(weekday, () => []).add(added);
    await _persist(
      SchoolDutyRoster(days: nextDays, attendance: _roster.attendance),
    );
  }

  Future<void> _exportDutyPdf() async {
    setState(() => _exporting = true);
    try {
      final cfg = appThemeNotifier.value;
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
      final rows = <List<String>>[];
      for (var d = 1; d <= 5; d++) {
        final dayName = weekdayNamesTr[d]!;
        final list = _roster.forWeekday(d);
        if (list.isEmpty) {
          rows.add([dayName, '—', '—', '—', '—']);
        } else {
          for (final item in list) {
            rows.add([
              dayName,
              item.name,
              item.className,
              item.number,
              item.shift,
            ]);
          }
        }
      }

      final payload = jsonEncode({
        'schoolName': cfg.schoolName,
        'libraryName': cfg.libraryName,
        'reportTitle': 'ÖĞRENCİ KÜTÜPHANE NÖBET ÇİZELGESİ',
        'subtitle': 'Güncel Haftalık Nöbet Listesi · Tarih: $dateStr',
        'kpis': [
          {'label': 'Nöbet Günü', 'value': '5 Gün'},
          {'label': 'Toplam Nöbetçi', 'value': '${_roster.totalAssigned}'},
          {
            'label': 'Bugünkü Yoklama',
            'value':
                '${_roster.attendance[SchoolDutyRoster.dateKey(now)]?.length ?? 0} Öğrenci',
          },
        ],
        'sections': [
          {
            'heading': 'Haftalık Kütüphane Öğrenci Nöbet Listesi',
            'headers': ['Gün', 'Adı Soyadı', 'Sınıf', 'Okul No', 'Vardiya'],
            'weights': [1.2, 2.8, 0.9, 0.9, 1.2],
            'rows': rows,
          },
        ],
        'footerNote':
            'Nöbetçi öğrenciler kütüphane açılış-kapanış düzeni, raf yerleştirme ve banko ödünç-iade işlemlerinde görevlidir.',
        'leftSignerTitle': 'Kütüphane Sorumlusu',
        'leftSignerName': cfg.librarianName,
        'rightSignerTitle': 'Okul Müdürü',
        'rightSignerName': cfg.principalName,
      });

      final ok = await const MethodChannel('kitapbul/files')
          .invokeMethod<bool>('exportOfficialReportPdf', {
            'data': payload,
            'filename': 'Kutuphane_Nobet_Listesi.pdf',
          });
      if (mounted && ok == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resmî nöbet çizelgesi PDF kaydedildi.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nöbet çizelgesi PDF oluşturulamadı.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayWeekday = today.weekday.clamp(1, 5);
    final cfg = appThemeNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nöbetçi Öğrenci Çizelgesi'),
        actions: [
          IconButton(
            tooltip: 'Varsayılan Okul Listesini Yükle',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Resmî Nöbet Listesini Geri Yükle'),
                  content: const Text(
                    'Cumhuriyet Kütüphanesi güncel resmî öğrenci nöbet listesi yüklensin mi?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Vazgeç'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Yükle'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _persist(
                  SchoolDutyRoster(
                    days: defaultCumhuriyetDutySchedule(),
                    attendance: _roster.attendance,
                  ),
                );
              }
            },
            icon: const Icon(Icons.restore_rounded),
          ),
          IconButton(
            tooltip: 'Resmî PDF İndir',
            onPressed: _exporting ? null : _exportDutyPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          IllustratedBannerCard(
            imageAsset: 'assets/images/duty_roster_banner.jpg',
            title: '${cfg.libraryName} Nöbet Çizelgesi',
            subtitle:
                '${cfg.schoolName} · Pazartesi–Cuma öğrenci görev ve yoklama takibi',
            icon: Icons.badge_rounded,
            gradientColors: const [Color(0xFF7F1D1D), Color(0xFFBE123C)],
            pills: [
              AnimatedStatPill(
                label: 'Toplam Nöbetçi',
                value: _roster.totalAssigned,
                icon: Icons.groups_rounded,
                accentColor: const Color(0xFFFDE68A),
              ),
              AnimatedStatPill(
                label: 'Bugün Yoklama',
                value:
                    _roster.attendance[SchoolDutyRoster.dateKey(today)]
                        ?.length ??
                    0,
                icon: Icons.fact_check_rounded,
                accentColor: const Color(0xFF6EE7B7),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ShimmerActionButton(
            label: _exporting
                ? 'PDF Hazırlanıyor...'
                : 'Resmî İmzalı Nöbet Listesi PDF İndir',
            subtitle: 'A4 mühür ve müdür imzalı pano çıktısı',
            icon: Icons.picture_as_pdf_rounded,
            colors: const [Color(0xFFBE123C), Color(0xFFE11D48)],
            onTap: _exporting ? null : _exportDutyPdf,
          ),
          const SizedBox(height: 16),
          for (var day = 1; day <= 5; day++)
            StaggeredFadeSlide(
              index: day,
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: day == today.weekday
                    ? scheme.primaryContainer.withValues(alpha: 0.35)
                    : scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: day == today.weekday
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.45),
                    width: day == today.weekday ? 1.5 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: day == todayWeekday
                                  ? scheme.primary
                                  : scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              weekdayNamesTr[day]!,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: day == todayWeekday
                                    ? scheme.onPrimary
                                    : scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          if (day == today.weekday) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'BUGÜN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _addDutyDialog(day),
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                            label: const Text('Öğrenci Ekle'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_roster.forWeekday(day).isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Bu gün için atanmış nöbetçi öğrenci yok.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      else
                        for (
                          var i = 0;
                          i < _roster.forWeekday(day).length;
                          i++
                        ) ...[
                          Builder(
                            builder: (_) {
                              final item = _roster.forWeekday(day)[i];
                              final present = _roster.isPresent(today, item);
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: present
                                      ? const Color(0xFF059669)
                                      : scheme.primaryContainer,
                                  child: Text(
                                    item.className.isEmpty
                                        ? 'Ö'
                                        : item.className,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: present
                                          ? Colors.white
                                          : scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  'Sınıf: ${item.className} · Okul No: ${item.number} · ${item.shift}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilterChip(
                                      label: Text(
                                        present ? 'Görevde' : 'Yoklama',
                                        style: const TextStyle(fontSize: 11.5),
                                      ),
                                      selected: present,
                                      onSelected: (_) => _persist(
                                        _roster.toggleAttendance(today, item),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Listeden çıkar',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        final nextDays =
                                            <int, List<DutyAssignment>>{
                                              for (final e
                                                  in _roster.days.entries)
                                                e.key: [...e.value],
                                            };
                                        nextDays[day]?.removeAt(i);
                                        _persist(
                                          SchoolDutyRoster(
                                            days: nextDays,
                                            attendance: _roster.attendance,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

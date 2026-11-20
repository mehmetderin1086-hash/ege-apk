import 'package:flutter/material.dart';

import '../kagit_models.dart';
import '../kagit_store.dart';
import '../theme_kagit.dart';
import 'shared_kagit_widgets.dart';
import 'tool_runner_sheet.dart';

class KagitTeacherPage extends StatefulWidget {
  const KagitTeacherPage({super.key, required this.controller});

  final KagitController controller;

  @override
  State<KagitTeacherPage> createState() => _KagitTeacherPageState();
}

class _KagitTeacherPageState extends State<KagitTeacherPage> {
  Future<void> _addClassDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni Sınıf / Şube'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Sınıf Adı (ör. 11-B)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              widget.controller.addClassGroup(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _addStudentDialog(SinifGrubu sinif) async {
    final noCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${sinif.name} — Öğrenci Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: noCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Okul Numarası', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Ad Soyad', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                widget.controller.addStudent(sinif.id, noCtrl.text, nameCtrl.text);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    noCtrl.dispose();
    nameCtrl.dispose();
  }

  void _launchTool(KagitToolId id) {
    final tool = kagitToolsCatalog.firstWhere((t) => t.id == id);
    runKagitTool(context, widget.controller, tool);
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.controller.ayarlar.okulBasligi;
    final teacherTools = [
      (KagitToolId.sinavYiginiBol, 'Yığını Böl', 'Tek PDF’i öğrenci öğrenci ayır', Icons.folder_copy_rounded, KagitTema.altinMuhur),
      (KagitToolId.abKitapcik, 'A / B Kitapçığı', 'Soruları karıştır + anahtar', Icons.shuffle_rounded, KagitTema.vurgu),
      (KagitToolId.aiSoruUret, 'Soru Üret (AI)', 'Test ve yazılı kâğıdı oluştur', Icons.quiz_rounded, KagitTema.morOkuma),
      (KagitToolId.puanToplaVeExcel, 'Puan → Excel', 'Damgalı notları .xlsx yap', Icons.table_chart_rounded, KagitTema.yaprakYesili),
      (KagitToolId.okulBasligiEkle, 'Başlık Bas', 'İlk sayfaya resmî sınav bandı', Icons.school_rounded, KagitTema.murekkepMavi),
      (KagitToolId.kameraTara, 'Sınav Tara', 'Kâğıtları çek & netleştir', Icons.document_scanner_rounded, KagitTema.camYesili),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        KagitHeroBanner(
          imageAsset: 'assets/images/kagit_teacher_backdrop.jpg',
          badge: 'ÖĞRETMEN MERKEZİ',
          accent: KagitTema.altinMuhur,
          title: 'Sınav, Kitapçık ve Puanlama Stüdyosu',
          subtitle: '${header.okulAdi}\n${header.dersAdi} • ${header.sinavTuru} (${header.sure})',
          bottomWidget: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: KagitTema.altinMuhur,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onPressed: () => _launchTool(KagitToolId.abKitapcik),
                  icon: const Icon(Icons.shuffle_rounded, size: 17),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('A/B Kitapçık Üret', maxLines: 1),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    foregroundColor: KagitTema.koyuMurekkep,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onPressed: () => _launchTool(KagitToolId.puanToplaVeExcel),
                  icon: const Icon(Icons.table_chart_rounded, size: 17),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Excel Raporu', maxLines: 1),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        Text('Sınav ve Sınıf Eylemleri', style: kagitSerif(context, size: 19)),
        const SizedBox(height: 10),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 118,
          ),
          children: [
            for (final item in teacherTools)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _launchTool(item.$1),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: KagitTema.cardBg(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: KagitTema.border(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: item.$5.withValues(alpha: 0.14),
                        child: Icon(item.$4, size: 18, color: item.$5),
                      ),
                      const Spacer(),
                      Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(
                        item.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: KagitTema.inkSecondary(context)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: Text('Sınıflar ve Öğrenci Listeleri', style: kagitSerif(context, size: 19))),
            FilledButton.tonalIcon(
              onPressed: _addClassDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Sınıf Ekle'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (widget.controller.siniflar.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Henüz tanımlı sınıf yok. Sınav yığınlarını öğrenci adıyla bölmek için sınıf ekleyin.'),
          )
        else
          for (final sinif in widget.controller.siniflar)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              color: KagitTema.cardBg(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: KagitTema.border(context)),
              ),
              child: ExpansionTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22D98E26),
                  child: Icon(Icons.groups_rounded, color: KagitTema.altinMuhur),
                ),
                title: Text(sinif.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${sinif.students.length} öğrenci'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Öğrenci Ekle',
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                      onPressed: () => _addStudentDialog(sinif),
                    ),
                    IconButton(
                      tooltip: 'Sınıfı Sil',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      onPressed: () {
                        widget.controller.deleteClassGroup(sinif.id);
                        showKagitSnack(context, '${sinif.name} silindi.');
                      },
                    ),
                  ],
                ),
                children: [
                  for (final st in sinif.students)
                    ListTile(
                      dense: true,
                      leading: Text(st.no, style: const TextStyle(fontWeight: FontWeight.w700, color: KagitTema.vurgu)),
                      title: Text(st.adSoyad),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => widget.controller.removeStudent(sinif.id, st.id),
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

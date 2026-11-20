import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_book_vision_page.dart';
import 'ai_proxy_service.dart';
import 'app_theme_settings.dart';
import 'book_visuals.dart';
import 'bulk_isbn_importer_page.dart';
import 'catalog_search.dart';
import 'inventory_session.dart';
import 'isbn.dart';
import 'library_atmosphere_studio.dart';
import 'library_labels_page.dart';
import 'loan_model.dart';
import 'school_duty_roster.dart';
import 'shelf_photo_scanner_page.dart';
import 'student_cards_page.dart';
import 'student_store.dart';
import 'voice_assistant_page.dart';

/// Mevcut demirbaş kodlarındaki (`CAL-004057; CAL-004058`) en büyük sayıyı bulur.
int findHighestAccessionNumber(
  List<Map<String, dynamic>> books, {
  String prefix = 'CAL-',
}) {
  final upperPrefix = prefix.toUpperCase();
  var maxNum = 0;
  for (final b in books) {
    if (b['deletedAt'] != null) continue;
    for (final token in extractAccessionTokens(b)) {
      final upper = token.toUpperCase();
      if (upper.startsWith(upperPrefix)) {
        final tail = upper
            .substring(upperPrefix.length)
            .replaceAll(RegExp(r'[^0-9]'), '');
        final val = int.tryParse(tail);
        if (val != null && val > maxNum) maxNum = val;
      }
    }
  }
  return maxNum;
}

/// Demirbaş kodu eksik kitaplara sıralı `CAL-004061` kodu üretir.
({
  List<Map<String, dynamic>> updatedBooks,
  int assignedBooks,
  int assignedCodes,
  String firstCode,
  String lastCode,
})
assignMissingAccessionCodes(
  List<Map<String, dynamic>> books, {
  String prefix = 'CAL-',
  int digits = 6,
}) {
  var nextNum = findHighestAccessionNumber(books, prefix: prefix) + 1;
  var assignedBooks = 0;
  var assignedCodes = 0;
  String firstCode = '';
  String lastCode = '';

  String fmt(int n) => '$prefix${n.toString().padLeft(digits, '0')}';

  final updated = <Map<String, dynamic>>[];
  for (final b in books) {
    final active = b['deletedAt'] == null && b['isWithdrawn'] != true;
    final currentAcc = (b['accessionCode'] ?? '').toString().trim();
    if (!active || currentAcc.isNotEmpty) {
      updated.add(b);
      continue;
    }
    final qty = ((b['quantity'] as int?) ?? 1).clamp(1, 50);
    final generated = <String>[];
    for (var i = 0; i < qty; i++) {
      final code = fmt(nextNum++);
      if (firstCode.isEmpty) firstCode = code;
      lastCode = code;
      generated.add(code);
      assignedCodes++;
    }
    assignedBooks++;
    updated.add(
      normalizeBook({
        ...b,
        'accessionCode': generated.join('; '),
      }),
    );
  }

  return (
    updatedBooks: updated,
    assignedBooks: assignedBooks,
    assignedCodes: assignedCodes,
    firstCode: firstCode,
    lastCode: lastCode,
  );
}

/// Aynı ISBN veya normalize Başlık+Yazar paylaşan mükerrer kitap gruplarını bulur.
List<List<Map<String, dynamic>>> detectDuplicateBookGroups(
  List<Map<String, dynamic>> books,
) {
  final active = books.where((b) => b['deletedAt'] == null).toList();
  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final b in active) {
    final canon = canonicalIsbn((b['isbn'] ?? '').toString());
    final title = foldTurkish((b['title'] ?? '').toString().trim())
        .replaceAll(RegExp(r'\s+'), ' ');
    final author = foldTurkish((b['author'] ?? '').toString().trim())
        .replaceAll(RegExp(r'\s+'), ' ');
    final key = (canon != null && canon.isNotEmpty)
        ? 'ISBN:$canon|VOL:${b['volume'] ?? ''}'
        : 'TA:$title|$author|VOL:${b['volume'] ?? ''}';
    if (title.isEmpty) continue;
    byKey.putIfAbsent(key, () => []).add(b);
  }
  return byKey.values.where((g) => g.length >= 2).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
}

/// Mükerrer bir gruptaki kitapları veri kaybetmeden tek kayıtta birleştirir.
List<Map<String, dynamic>> mergeDuplicateGroup(
  List<Map<String, dynamic>> allBooks,
  List<Map<String, dynamic>> group,
) {
  if (group.length < 2) return allBooks;
  // Kapağı olan kaydı ana kayıt olarak seç
  final sorted = [...group]
    ..sort((a, b) {
      final aHas = hasStoredImage(a['coverBase64']) ? 1 : 0;
      final bHas = hasStoredImage(b['coverBase64']) ? 1 : 0;
      return bHas.compareTo(aHas);
    });
  final primary = Map<String, dynamic>.from(sorted.first);
  final secondaryIds = {
    for (final s in sorted.skip(1)) s['id'] as String,
  };

  var totalQty = (primary['quantity'] as int?) ?? 1;
  final accTokens = <String>[...extractAccessionTokens(primary)];
  final mergedLoans = <Map<String, dynamic>>[...activeLoans(primary)];
  final mergedHistory = <Map<String, dynamic>>[...loanHistory(primary)];

  for (final sec in sorted.skip(1)) {
    totalQty += (sec['quantity'] as int?) ?? 1;
    for (final t in extractAccessionTokens(sec)) {
      if (!accTokens.any((x) => x.toUpperCase() == t.toUpperCase())) {
        accTokens.add(t);
      }
    }
    mergedLoans.addAll(activeLoans(sec));
    mergedHistory.addAll(loanHistory(sec));
    for (final field in [
      'coverBase64',
      'backCoverBase64',
      'publisher',
      'category',
      'shelf',
      'publicationYear',
      'pageCount',
      'notes',
    ]) {
      if ((primary[field] == null ||
              primary[field].toString().trim().isEmpty) &&
          sec[field] != null &&
          sec[field].toString().trim().isNotEmpty) {
        primary[field] = sec[field];
      }
    }
  }

  primary['quantity'] = totalQty;
  if (accTokens.isNotEmpty) {
    primary['accessionCode'] = accTokens.join('; ');
  }
  primary['loans'] = mergedLoans;
  primary['history'] = mergedHistory;
  final normalizedPrimary = normalizeBook(primary);
  final nowIso = DateTime.now().toIso8601String();

  return [
    for (final b in allBooks)
      if (b['id'] == normalizedPrimary['id'])
        normalizedPrimary
      else if (secondaryIds.contains(b['id']))
        normalizeBook({
          ...b,
          'loans': <Map<String, dynamic>>[],
          'reservations': <Map<String, dynamic>>[],
          'copies': <Map<String, dynamic>>[],
          'deletedAt': nowIso,
        })
      else
        b,
  ];
}

class SchoolAutomationHubView extends StatelessWidget {
  const SchoolAutomationHubView({
    super.key,
    required this.books,
    required this.students,
    required this.dutyRoster,
    required this.busy,
    required this.onSaveBooks,
    required this.onDutyChanged,
    required this.onOpenInventory,
    required this.onOpenChampions,
    required this.onOpenTextbooks,
    required this.onOpenDataQuality,
    required this.onExportXlsx,
    required this.onResyncIPhoneSeed,
    this.onSaveInventorySession,
    this.onOpenDiscovery,
    this.onOpenSanctuary,
    this.onOpenThemeStudio,
  });

  final List<Map<String, dynamic>> books;
  final List<Student> students;
  final SchoolDutyRoster dutyRoster;
  final bool busy;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;
  final ValueChanged<SchoolDutyRoster> onDutyChanged;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenChampions;
  final VoidCallback onOpenTextbooks;
  final VoidCallback onOpenDataQuality;
  final VoidCallback onExportXlsx;
  final Future<void> Function() onResyncIPhoneSeed;
  final Future<bool> Function(InventorySession session)? onSaveInventorySession;
  final VoidCallback? onOpenDiscovery;
  final VoidCallback? onOpenSanctuary;
  final VoidCallback? onOpenThemeStudio;

  @override
  Widget build(BuildContext context) {
    final cfg = appThemeNotifier.value;
    final activeBooks = books
        .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
        .toList();
    final withAccession = activeBooks
        .where((b) => (b['accessionCode'] ?? '').toString().trim().isNotEmpty)
        .length;
    final missingAccession = activeBooks.length - withAccession;
    final shelfSet = {
      for (final b in activeBooks)
        if ((b['shelf'] ?? '').toString().trim().isNotEmpty)
          (b['shelf'] ?? '').toString().trim(),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        IllustratedBannerCard(
          imageAsset: 'assets/images/analytics_banner.jpg',
          title: 'Okul Kütüphane Kayıt Otomasyonu',
          subtitle: '${cfg.schoolName} · ${cfg.libraryName}',
          icon: Icons.account_balance_rounded,
          gradientColors: const [Color(0xFF1E3A8A), Color(0xFF4F46E5)],
          pills: [
            AnimatedStatPill(
              label: 'Kayıtlı Kitap',
              value: activeBooks.length,
              icon: Icons.auto_stories_rounded,
              accentColor: const Color(0xFFFDE68A),
            ),
            AnimatedStatPill(
              label: 'Demirbaşlı',
              value: withAccession,
              icon: Icons.qr_code_rounded,
              accentColor: const Color(0xFF6EE7B7),
            ),
            AnimatedStatPill(
              label: 'Dolap Sayısı',
              value: shelfSet.length,
              icon: Icons.shelves,
              accentColor: const Color(0xFFA5F3FC),
            ),
            AnimatedStatPill(
              label: 'Nöbetçi Öğrenci',
              value: dutyRoster.totalAssigned,
              icon: Icons.badge_rounded,
              accentColor: const Color(0xFFFBCFE8),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ShimmerActionButton(
                label: 'Sırt & Barkod Etiketi',
                subtitle: 'A4 Sırt · Barkod · QR Kart',
                icon: Icons.qr_code_2_rounded,
                colors: const [Color(0xFF7C3AED), Color(0xFF9333EA)],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LibraryLabelsPage(books: books),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ShimmerActionButton(
                label: 'Demirbaş Defteri',
                subtitle: missingAccession > 0
                    ? '$missingAccession kitaba kod ata'
                    : 'Tümü numaralı ($withAccession)',
                icon: Icons.menu_book_rounded,
                colors: const [Color(0xFF059669), Color(0xFF0D9488)],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AccessionRegisterPage(
                      books: books,
                      busy: busy,
                      onSaveBooks: onSaveBooks,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFF59E0B),
              size: 20,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Atölye Vitrin Kartları',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: onOpenThemeStudio ??
                  () => showThemeAndSchoolSettingsSheet(
                    context,
                    totalBooks: activeBooks.length,
                    onResyncIPhoneSeed: onResyncIPhoneSeed,
                  ),
              icon: const Icon(Icons.palette_outlined, size: 17),
              label: const Text('Stüdyo'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: IllustratedSquareMenuCard(
                title: 'Okuma Köşesi',
                subtitle: 'Huzurlu odak & sayaç',
                imageAsset: 'assets/images/card_okuma_modu.webp',
                icon: Icons.nightlight_round,
                accentColors: const [Color(0xFF312E81), Color(0xFF6366F1)],
                badge: 'HUZUR',
                height: 146,
                onTap: onOpenSanctuary ??
                    () => openReadingSanctuaryPage(context, books: books),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: IllustratedSquareMenuCard(
                title: 'Ne Okusam?',
                subtitle: 'Keşfet & rastgele öner',
                imageAsset: 'assets/images/card_kesfet.webp',
                icon: Icons.explore_rounded,
                accentColors: const [Color(0xFFDB2777), Color(0xFFF43F5E)],
                badge: 'KEŞİF',
                height: 146,
                onTap: onOpenDiscovery ?? onOpenChampions,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: IllustratedSquareMenuCard(
                title: 'Envanter & Raf',
                subtitle: '${shelfSet.length} dolap · stok sayım',
                imageAsset: 'assets/images/card_envanter.webp',
                icon: Icons.inventory_2_rounded,
                accentColors: const [Color(0xFF4338CA), Color(0xFF06B6D4)],
                badge: 'STOK',
                height: 146,
                onTap: onOpenInventory,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: IllustratedSquareMenuCard(
                title: 'Şampiyonlar',
                subtitle: '${students.length} öğrenci · sertifika',
                imageAsset: 'assets/images/card_sampiyonlar.webp',
                icon: Icons.emoji_events_rounded,
                accentColors: const [Color(0xFFD97706), Color(0xFFFBBF24)],
                badge: 'ÖDÜL',
                height: 146,
                onTap: onOpenChampions,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: IllustratedSquareMenuCard(
                title: 'Excel & Rapor',
                subtitle: '${activeBooks.length} kitap dışa aktar',
                imageAsset: 'assets/images/card_excel_rapor.webp',
                icon: Icons.grid_on_rounded,
                accentColors: const [Color(0xFF059669), Color(0xFF10B981)],
                badge: 'XLSX',
                height: 146,
                onTap: onExportXlsx,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: IllustratedSquareMenuCard(
                title: 'Atmosfer & Tema',
                subtitle: 'Canlı sahne & efekt',
                imageAsset: 'assets/images/bg_osmanli_kutuphane.webp',
                icon: Icons.auto_awesome_rounded,
                accentColors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
                badge: 'VİTRİN',
                height: 146,
                onTap: onOpenThemeStudio ??
                    () => showThemeAndSchoolSettingsSheet(
                      context,
                      totalBooks: activeBooks.length,
                      onResyncIPhoneSeed: onResyncIPhoneSeed,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Yapay Zekâ (CLIProxy), OCR & Toplu Kataloglama',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () => showAiProxySettingsSheet(context),
              icon: const Icon(Icons.hub_rounded, size: 18),
              label: const Text('CLIProxy Ayarları'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AutomationModuleTile(
          index: 0,
          title: 'Sesli Yapay Zekâ Kütüphane Asistanı (Türkçe STT + TTS)',
          subtitle:
              'Cep telefonu CLIProxyAPI ile konuşarak dolap/kitap sorgulama, gecikenleri öğrenme ve sesle kitap ekleme',
          icon: Icons.mic_rounded,
          imageAsset: 'assets/images/voice_assistant_banner.jpg',
          badge: 'AI SES',
          colors: const [Color(0xFF0284C7), Color(0xFF06B6D4)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VoiceLibraryAssistantPage(
                initialBooks: books,
                students: students,
                dutyRoster: dutyRoster,
                onSaveBooks: onSaveBooks,
              ),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 1,
          title: '100+ ISBN Amazon & Çoklu Kaynak Toplu Kitap Çekme',
          subtitle:
              'Yüzlerce ISBN yapıştırın, turbo kamerayla kuyruğa dizin veya iPhone bekleyen ISBN\'leri Amazon\'dan çekin',
          icon: Icons.rocket_launch_rounded,
          imageAsset: 'assets/images/ai_vision_banner.jpg',
          badge: 'TOPLU',
          colors: const [Color(0xFFEA580C), Color(0xFFF59E0B)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BulkIsbnImporterPage(
                initialBooks: books,
                onSaveBooks: onSaveBooks,
              ),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 2,
          title: '4-Sayfa Kitap Kapak, İç Künye & Son Sayfa Gemini OCR',
          subtitle:
              'Ön kapak + künye sayfası + son kapak öncesi yaprak + arka kapak fotoğraflarından tam otomatik künye girişi',
          icon: Icons.document_scanner_rounded,
          imageAsset: 'assets/images/scanner_banner.jpg',
          badge: 'AI OCR',
          colors: const [Color(0xFF9333EA), Color(0xFFEC4899)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FourPageBookScannerPage(
                initialBooks: books,
                onSaveBooks: onSaveBooks,
              ),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 3,
          title: 'Raf Fotoğrafından Toplu Kitap Sayma & Envanter Eşleştirme',
          subtitle:
              'Raf fotoğrafındaki tüm kitap sırtlarını kutulayarak sayar, yanlış dolaptakileri ve yeni kitapları ayırır',
          icon: Icons.collections_bookmark_rounded,
          imageAsset: 'assets/images/bg_sabah_ferah.webp',
          badge: 'GÖRÜNTÜ',
          colors: const [Color(0xFF1D4ED8), Color(0xFF6366F1)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ShelfPhotoScannerPage(
                initialBooks: books,
                onSaveBooks: onSaveBooks,
                onSaveInventorySession: onSaveInventorySession,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Okul Kütüphanesi Otomasyon Modülleri',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (onOpenDiscovery != null)
          _AutomationModuleTile(
            index: 0,
            title: 'Ne Okusam? · Seriler, Yazarlar & Popüler Kitaplar',
            subtitle:
                'Rastgele kitap önerici, seri takibi, yazar dizini, etiket bulutu ve en çok okunanlar',
            icon: Icons.explore_rounded,
            imageAsset: 'assets/images/card_kesfet.webp',
            badge: 'KEŞİF',
            colors: const [Color(0xFFDB2777), Color(0xFFF43F5E)],
            onTap: onOpenDiscovery!,
          ),
        _AutomationModuleTile(
          index: 0,
          title: 'İstatistikler, Grafikler & Resmî Dönem Raporu',
          subtitle:
              'Dolap/kategori grafikleri, hiç okunmayan kitaplar ve müdür imzalı A4 PDF rapor',
          icon: Icons.pie_chart_rounded,
          imageAsset: 'assets/images/analytics_banner.jpg',
          colors: const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SchoolAnalyticsReportPage(
                books: books,
                students: students,
                onExportXlsx: onExportXlsx,
              ),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 1,
          title: 'Nöbetçi Öğrenci Kütüphaneci Çizelgesi',
          subtitle:
              'Cumhuriyet Kütüphanesi Pazartesi–Cuma nöbet listesi, yoklama ve PDF çıktı',
          icon: Icons.assignment_ind_rounded,
          imageAsset: 'assets/images/duty_roster_banner.jpg',
          colors: const [Color(0xFFBE123C), Color(0xFFE11D48)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SchoolDutyRosterPage(
                students: students,
                initialRoster: dutyRoster,
                onChanged: onDutyChanged,
              ),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 2,
          title: 'Demirbaş Kayıt Defteri & Otomatik CAL- Kod Atama',
          subtitle:
              'Sıralı demirbaş numarası üretme (${cfg.accessionPrefix}000001) ve resmî demirbaş listesi',
          icon: Icons.format_list_numbered_rounded,
          imageAsset: 'assets/images/bg_gece_calisma.webp',
          colors: const [Color(0xFF047857), Color(0xFF10B981)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AccessionRegisterPage(
                books: books,
                busy: busy,
                onSaveBooks: onSaveBooks,
              ),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 3,
          title: 'Katalog Bakım: Mükerrer Birleştirme & Toplu Dolap Taşıma',
          subtitle:
              'Çift kayıtları birleştirin, yazar/yayınevi/dolap adlarını topluca düzenleyin',
          icon: Icons.build_circle_rounded,
          imageAsset: 'assets/images/bg_sonbahar_okuma.webp',
          colors: const [Color(0xFFB45309), Color(0xFFF59E0B)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CatalogMaintenancePage(
                books: books,
                busy: busy,
                onSaveBooks: onSaveBooks,
              ),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 4,
          title: 'Barkodlu Öğrenci Kütüphane Kartları (A4)',
          subtitle:
              'Sınıf bazlı Code128 barkodlu öğrenci kimlik kartlarını PDF olarak basın',
          icon: Icons.credit_card_rounded,
          imageAsset: 'assets/images/label_print_banner.jpg',
          colors: const [Color(0xFF0369A1), Color(0xFF0EA5E9)],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StudentCardsPage(students: students),
            ),
          ),
        ),
        _AutomationModuleTile(
          index: 5,
          title: 'Kameralı Envanter & Raf Stok Sayımı',
          subtitle:
              'Dolap bazlı barkod okutarak eksik/fazla nüsha tutanağı hazırlayın',
          icon: Icons.inventory_2_rounded,
          imageAsset: 'assets/images/card_envanter.webp',
          colors: const [Color(0xFF4338CA), Color(0xFF6366F1)],
          onTap: onOpenInventory,
        ),
        _AutomationModuleTile(
          index: 6,
          title: 'Okuma Şampiyonları & Başarı Sertifikası (PDF)',
          subtitle:
              'En çok kitap okuyan öğrencileri sıralayın ve resmî sertifika basın',
          icon: Icons.emoji_events_rounded,
          imageAsset: 'assets/images/card_sampiyonlar.webp',
          colors: const [Color(0xFFD97706), Color(0xFFFBBF24)],
          onTap: onOpenChampions,
        ),
        _AutomationModuleTile(
          index: 7,
          title: 'Ders Kitabı Dağıtım & Eksik Alan Tamamlama',
          subtitle:
              'Dönemlik ders kitabı tutanakları ve Amazon/Kitapyurdu otomatik kapak tamamlama',
          icon: Icons.auto_fix_high_rounded,
          imageAsset: 'assets/images/library_hero.jpg',
          colors: const [Color(0xFF6D28D9), Color(0xFFA855F7)],
          onTap: onOpenDataQuality,
        ),
        _AutomationModuleTile(
          index: 8,
          title: 'Görünüm, Arka Plan Resimleri, Tema & 2.892 iPhone Eşitleme',
          subtitle:
              'Renk teması, duvar kağıdı, ışık efektleri, okul müdür/sorumlu adı ve iPhone arşivi',
          icon: Icons.palette_rounded,
          imageAsset: 'assets/images/bg_osmanli_kutuphane.webp',
          badge: 'STÜDYO',
          colors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
          onTap: onOpenThemeStudio ??
              () => showThemeAndSchoolSettingsSheet(
                context,
                totalBooks: activeBooks.length,
                onResyncIPhoneSeed: onResyncIPhoneSeed,
              ),
        ),
      ],
    );
  }
}

class _AutomationModuleTile extends StatelessWidget {
  const _AutomationModuleTile({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.imageAsset,
    this.badge,
  });

  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final String? imageAsset;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = appThemeNotifier.value.glassCardsEnabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StaggeredFadeSlide(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: BouncyTap(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                color: glass
                    ? (isDark
                          ? scheme.surfaceContainerHigh.withValues(alpha: 0.72)
                          : scheme.surface.withValues(alpha: 0.78))
                    : scheme.surfaceContainerLow.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: glass
                      ? (isDark
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.56))
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                boxShadow: glass
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.20 : 0.06,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  if (imageAsset != null && imageAsset!.isNotEmpty)
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: 0.48,
                          child: ShaderMask(
                            shaderCallback: (rect) => LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.28),
                              ],
                            ).createShader(rect),
                            blendMode: BlendMode.dstIn,
                            child: Opacity(
                              opacity: isDark ? 0.42 : 0.28,
                              child: Image.asset(
                                imageAsset!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: colors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: colors.first.withValues(alpha: 0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(icon, color: Colors.white, size: 23),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (badge != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.first.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: colors.first.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        badge!,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? Colors.white
                                              : colors.first,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Demirbaş Kayıt Defteri & 1-Tıkla Sıralı Demirbaş Numaralandırma Ekranı.
class AccessionRegisterPage extends StatefulWidget {
  const AccessionRegisterPage({
    super.key,
    required this.books,
    required this.busy,
    required this.onSaveBooks,
  });

  final List<Map<String, dynamic>> books;
  final bool busy;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;

  @override
  State<AccessionRegisterPage> createState() => _AccessionRegisterPageState();
}

class _AccessionRegisterPageState extends State<AccessionRegisterPage> {
  late List<Map<String, dynamic>> _books = widget.books;
  String _selectedShelf = '';
  String _filterMode = 'all'; // all, assigned, missing
  String _query = '';
  bool _saving = false;

  Future<void> _autoAssignMissing() async {
    final cfg = appThemeNotifier.value;
    final preview = assignMissingAccessionCodes(
      _books,
      prefix: cfg.accessionPrefix,
      digits: cfg.accessionDigits,
    );
    if (preview.assignedBooks == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demirbaş kodu eksik kitap bulunmuyor.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otomatik Demirbaş Numarası Ata'),
        content: Text(
          'Demirbaş kodu bulunmayan ${preview.assignedBooks} kitaba (${preview.assignedCodes} nüsha) '
          'mevcut en yüksek numaradan devam ederek:\n\n'
          '${preview.firstCode}  →  ${preview.lastCode}\n\n'
          'aralığında sıralı demirbaş kodu atanacaktır. Mevcut demirbaş kodları kesinlikle değiştirilmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla ve Ata'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await widget.onSaveBooks(preview.updatedBooks);
      if (mounted) {
        setState(() => _books = preview.updatedBooks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${preview.assignedBooks} kitaba (${preview.firstCode} – ${preview.lastCode}) atandı.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportRegisterPdf(List<Map<String, dynamic>> filtered) async {
    setState(() => _saving = true);
    try {
      final cfg = appThemeNotifier.value;
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
      final rows = <List<String>>[];
      for (var i = 0; i < filtered.length; i++) {
        final b = filtered[i];
        rows.add([
          '${i + 1}',
          (b['accessionCode'] ?? '-').toString().isEmpty
              ? '-'
              : '${b['accessionCode']}',
          '${b['title'] ?? ''}',
          '${b['author'] ?? ''}',
          '${b['shelf'] ?? '-'}',
          '${b['quantity'] ?? 1}',
        ]);
      }

      final payload = jsonEncode({
        'schoolName': cfg.schoolName,
        'libraryName': cfg.libraryName,
        'reportTitle': 'KÜTÜPHANE DEMİRBAŞ KAYIT DEFTERİ',
        'subtitle':
            'Toplam ${filtered.length} Kayıt · Düzenleme Tarihi: $dateStr',
        'kpis': [
          {'label': 'Listelenen Çeşit', 'value': '${filtered.length}'},
          {
            'label': 'Toplam Nüsha',
            'value':
                '${filtered.fold<int>(0, (s, b) => s + ((b['quantity'] as int?) ?? 1))}',
          },
          {
            'label': 'En Son Numara',
            'value':
                '${cfg.accessionPrefix}${findHighestAccessionNumber(_books, prefix: cfg.accessionPrefix).toString().padLeft(cfg.accessionDigits, '0')}',
          },
        ],
        'sections': [
          {
            'heading': 'Demirbaş Envanter Listesi',
            'headers': [
              'Sıra',
              'Demirbaş No',
              'Kitap Adı',
              'Yazar',
              'Dolap',
              'Adet',
            ],
            'weights': [0.55, 1.35, 2.4, 1.5, 0.65, 0.55],
            'rows': rows,
          },
        ],
        'footerNote':
            'Yukarıda dökümü yapılan eserler okul kütüphanesi demirbaş envanterinde kayıtlıdır.',
        'leftSignerTitle': 'Kütüphane Sorumlusu',
        'leftSignerName': cfg.librarianName,
        'rightSignerTitle': 'Okul Müdürü',
        'rightSignerName': cfg.principalName,
      });

      final ok = await const MethodChannel('kitapbul/files')
          .invokeMethod<bool>('exportOfficialReportPdf', {
            'data': payload,
            'filename': 'Kutuphane_Demirbas_Defteri.pdf',
          });
      if (mounted && ok == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resmî demirbaş defteri PDF olarak kaydedildi.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demirbaş PDF kaydedilemedi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cfg = appThemeNotifier.value;
    final active = _books
        .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
        .toList();
    final missingCount = active
        .where((b) => (b['accessionCode'] ?? '').toString().trim().isEmpty)
        .length;
    final maxAcc = findHighestAccessionNumber(
      active,
      prefix: cfg.accessionPrefix,
    );

    final shelves = {
      for (final b in active)
        if ((b['shelf'] ?? '').toString().trim().isNotEmpty)
          (b['shelf'] ?? '').toString().trim(),
    }.toList()..sort();

    final filtered = active.where((b) {
      if (_selectedShelf.isNotEmpty &&
          (b['shelf'] ?? '').toString().trim() != _selectedShelf) {
        return false;
      }
      final hasAcc = (b['accessionCode'] ?? '').toString().trim().isNotEmpty;
      if (_filterMode == 'assigned' && !hasAcc) return false;
      if (_filterMode == 'missing' && hasAcc) return false;
      if (_query.trim().isNotEmpty && !matchesCatalog(b, _query)) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Demirbaş Kayıt Defteri'),
        actions: [
          IconButton(
            tooltip: 'Resmî Demirbaş PDF İndir',
            onPressed: _saving || filtered.isEmpty
                ? null
                : () => _exportRegisterPdf(filtered),
            icon: const Icon(Icons.picture_as_pdf_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    if (missingCount > 0)
                      Expanded(
                        child: ShimmerActionButton(
                          label: '$missingCount Kitaba Otomatik Kod Ata',
                          subtitle:
                              'Sıradaki kod: ${cfg.accessionPrefix}${(maxAcc + 1).toString().padLeft(cfg.accessionDigits, '0')}',
                          icon: Icons.onetwothree_rounded,
                          colors: const [Color(0xFF059669), Color(0xFF10B981)],
                          onTap: _saving ? null : _autoAssignMissing,
                        ),
                      )
                    else
                      Expanded(
                        child: ShimmerActionButton(
                          label: 'Resmî Demirbaş Defteri PDF İndir',
                          subtitle: '${filtered.length} kitap · İmzalı tutanak',
                          icon: Icons.picture_as_pdf_rounded,
                          colors: const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
                          onTap: _saving
                              ? null
                              : () => _exportRegisterPdf(filtered),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedShelf,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Dolap',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Tüm Dolaplar'),
                          ),
                          for (final s in shelves)
                            DropdownMenuItem(value: s, child: Text('Dolap $s')),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedShelf = v ?? ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _filterMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'Durum',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Tümü (${active.length})'),
                          ),
                          DropdownMenuItem(
                            value: 'assigned',
                            child: Text(
                              'Numaralı (${active.length - missingCount})',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'missing',
                            child: Text('Eksik ($missingCount)'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _filterMode = v ?? 'all'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Demirbaş no (CAL-...), başlık veya yazar ara...',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              itemCount: filtered.length,
              itemBuilder: (_, idx) {
                final b = filtered[idx];
                final acc = (b['accessionCode'] ?? '').toString().trim();
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: scheme.surfaceContainerLow,
                  child: ListTile(
                    dense: true,
                    leading: BookCoverWidget(book: b, width: 34, height: 48),
                    title: Text(
                      '${b['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${b['author'] ?? ''} · Dolap ${b['shelf'] ?? '-'} · ${b['quantity'] ?? 1} adet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: acc.isEmpty
                            ? scheme.errorContainer
                            : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        acc.isEmpty ? 'Kod Yok' : acc.split(';').first.trim(),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: acc.isEmpty
                              ? scheme.onErrorContainer
                              : scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// İstatistikler, Grafikler ve Resmî Dönem Faaliyet Raporu Sayfası.
class SchoolAnalyticsReportPage extends StatefulWidget {
  const SchoolAnalyticsReportPage({
    super.key,
    required this.books,
    required this.students,
    required this.onExportXlsx,
  });

  final List<Map<String, dynamic>> books;
  final List<Student> students;
  final VoidCallback onExportXlsx;

  @override
  State<SchoolAnalyticsReportPage> createState() =>
      _SchoolAnalyticsReportPageState();
}

class _SchoolAnalyticsReportPageState extends State<SchoolAnalyticsReportPage> {
  bool _exporting = false;

  Future<void> _exportOfficialPeriodPdf(
    List<MapEntry<String, int>> topCategories,
    List<MapEntry<String, int>> topShelves,
    List<MapEntry<String, int>> topAuthors,
    int activeCount,
    int totalCopies,
    int activeLoansCount,
    int neverLoanedCount,
  ) async {
    setState(() => _exporting = true);
    try {
      final cfg = appThemeNotifier.value;
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

      String pct(int n) => activeCount == 0
          ? '%0'
          : '%${((n / activeCount) * 100).toStringAsFixed(1)}';

      final payload = jsonEncode({
        'schoolName': cfg.schoolName,
        'libraryName': cfg.libraryName,
        'reportTitle': 'KÜTÜPHANE DÖNEM FAALİYET VE İSTATİSTİK RAPORU',
        'subtitle': 'Resmî Envanter ve Okuma Analizi · Tarih: $dateStr',
        'kpis': [
          {'label': 'Toplam Çeşit', 'value': '$activeCount'},
          {'label': 'Toplam Nüsha', 'value': '$totalCopies'},
          {'label': 'Aktif Ödünç', 'value': '$activeLoansCount'},
          {'label': 'Kayıtlı Öğrenci', 'value': '${widget.students.length}'},
        ],
        'sections': [
          {
            'heading': '1. Kategori / Tür Dağılımı (İlk 12)',
            'headers': ['Kategori / Konu', 'Kitap Çeşidi', 'Koleksiyon Oranı'],
            'weights': [3.0, 1.2, 1.2],
            'rows': [
              for (final e in topCategories.take(12))
                [e.key, '${e.value}', pct(e.value)],
            ],
          },
          {
            'heading': '2. Dolap ve Raf Yoğunluk Analizi',
            'headers': ['Dolap / Konum', 'Kitap Çeşidi', 'Oran'],
            'weights': [3.0, 1.2, 1.2],
            'rows': [
              for (final e in topShelves.take(18))
                [
                  e.key.length <= 2 ? 'Dolap ${e.key}' : e.key,
                  '${e.value}',
                  pct(e.value),
                ],
            ],
          },
          {
            'heading': '3. Koleksiyonda En Çok Eseri Bulunan Yazarlar',
            'headers': ['Yazar Adı', 'Eser Sayısı'],
            'weights': [3.8, 1.2],
            'rows': [
              for (final e in topAuthors.take(12)) [e.key, '${e.value}'],
            ],
          },
        ],
        'footerNote':
            'Koleksiyondaki $neverLoanedCount eser henüz ödünç dolaşımına girmemiş olup okuma teşvik panosunda sergilenmeye uygundur.',
        'leftSignerTitle': 'Kütüphane Sorumlusu',
        'leftSignerName': cfg.librarianName,
        'rightSignerTitle': 'Okul Müdürü',
        'rightSignerName': cfg.principalName,
      });

      final ok = await const MethodChannel('kitapbul/files')
          .invokeMethod<bool>('exportOfficialReportPdf', {
            'data': payload,
            'filename': 'Kutuphane_Donem_Faaliyet_Raporu.pdf',
          });
      if (mounted && ok == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resmî dönem faaliyet raporu PDF olarak kaydedildi.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dönem raporu PDF kaydedilemedi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.books
        .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
        .toList();

    var totalCopies = 0;
    var activeLoanCount = 0;
    var neverLoanedCount = 0;
    final catMap = <String, int>{};
    final shelfMap = <String, int>{};
    final authorMap = <String, int>{};

    for (final b in active) {
      totalCopies += (b['quantity'] as int?) ?? 1;
      final l = activeLoans(b);
      final h = loanHistory(b);
      activeLoanCount += l.length;
      if (l.isEmpty && h.isEmpty) neverLoanedCount++;

      final cat = (b['category'] ?? '').toString().trim();
      catMap[cat.isEmpty ? 'Diğer / Genel' : cat] =
          (catMap[cat.isEmpty ? 'Diğer / Genel' : cat] ?? 0) + 1;

      final sh = (b['shelf'] ?? '').toString().trim();
      if (sh.isNotEmpty) shelfMap[sh] = (shelfMap[sh] ?? 0) + 1;

      final au = (b['author'] ?? '').toString().trim();
      if (au.isNotEmpty) authorMap[au] = (authorMap[au] ?? 0) + 1;
    }

    final topCategories = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topShelves = shelfMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topAuthors = authorMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    const chartColors = [
      Color(0xFF4F46E5),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFFBE123C),
      Color(0xFF0284C7),
      Color(0xFF7C3AED),
      Color(0xFF475569),
    ];

    final donutSlices = <({String label, int count, Color color})>[];
    var otherCount = 0;
    for (var i = 0; i < topCategories.length; i++) {
      if (i < 6) {
        donutSlices.add((
          label: topCategories[i].key,
          count: topCategories[i].value,
          color: chartColors[i],
        ));
      } else {
        otherCount += topCategories[i].value;
      }
    }
    if (otherCount > 0) {
      donutSlices.add((
        label: 'Diğer Türler',
        count: otherCount,
        color: chartColors.last,
      ));
    }

    final maxShelf = topShelves.isEmpty ? 1 : topShelves.first.value;

    return Scaffold(
      appBar: AppBar(title: const Text('İstatistikler & Dönem Raporu')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          IllustratedBannerCard(
            imageAsset: 'assets/images/analytics_banner.jpg',
            title: 'Kütüphane Veri & Analiz Merkezi',
            subtitle:
                'Koleksiyon dağılımı, dolap yoğunluğu ve resmî dönem sonu raporu',
            icon: Icons.insights_rounded,
            gradientColors: const [Color(0xFF0F172A), Color(0xFF1D4ED8)],
            pills: [
              AnimatedStatPill(
                label: 'Toplam Çeşit',
                value: active.length,
                icon: Icons.menu_book_rounded,
              ),
              AnimatedStatPill(
                label: 'Toplam Nüsha',
                value: totalCopies,
                icon: Icons.layers_rounded,
                accentColor: const Color(0xFFFDE68A),
              ),
              AnimatedStatPill(
                label: 'Hiç Ödünç Verilmeyen',
                value: neverLoanedCount,
                icon: Icons.visibility_outlined,
                accentColor: const Color(0xFFA5F3FC),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ShimmerActionButton(
                  label: _exporting ? 'Hazırlanıyor...' : 'Resmî PDF Rapor',
                  subtitle: 'İmzalı dönem tutanağı',
                  icon: Icons.picture_as_pdf_rounded,
                  colors: const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
                  onTap: _exporting
                      ? null
                      : () => _exportOfficialPeriodPdf(
                          topCategories,
                          topShelves,
                          topAuthors,
                          active.length,
                          totalCopies,
                          activeLoanCount,
                          neverLoanedCount,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ShimmerActionButton(
                  label: 'Excel (.xlsx) Rapor',
                  subtitle: 'Çok sayfalı tablo',
                  icon: Icons.grid_on_rounded,
                  colors: const [Color(0xFF15803D), Color(0xFF22C55E)],
                  onTap: widget.onExportXlsx,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category Donut Card
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kategori ve Konu Dağılımı',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      AnimatedDonutChart(
                        slices: donutSlices,
                        centerValue: '${active.length}',
                        centerLabel: 'Kitap',
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final s in donutSlices)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3.5,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: s.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        s.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${s.count}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Cabinet / Shelf Bar Chart
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dolap Bazlı Kitap Yoğunluğu (Dolap A–N)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in topShelves.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                entry.key.length <= 2
                                    ? 'Dolap ${entry.key}'
                                    : entry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${entry.value} kitap',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: entry.value / maxShelf,
                            ),
                            duration: const Duration(milliseconds: 700),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, _) => ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: v,
                                minHeight: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Top Authors Card
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'En Çok Eseri Bulunan Yazarlar',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < topAuthors.take(10).length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 13,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      title: Text(
                        topAuthors[i].key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Text(
                        '${topAuthors[i].value} eser',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mükerrer Birleştirme & Toplu Yazar/Yayınevi/Dolap Düzenleme Ekranı.
class CatalogMaintenancePage extends StatefulWidget {
  const CatalogMaintenancePage({
    super.key,
    required this.books,
    required this.busy,
    required this.onSaveBooks,
  });

  final List<Map<String, dynamic>> books;
  final bool busy;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;

  @override
  State<CatalogMaintenancePage> createState() => _CatalogMaintenancePageState();
}

class _CatalogMaintenancePageState extends State<CatalogMaintenancePage> {
  late List<Map<String, dynamic>> _books = widget.books;
  String _fieldKey = 'shelf';
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyBulkReplace() async {
    final from = _findCtrl.text.trim();
    final to = _replaceCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) return;

    var count = 0;
    final next = <Map<String, dynamic>>[];
    for (final b in _books) {
      if (b['deletedAt'] == null &&
          foldTurkish((b[_fieldKey] ?? '').toString().trim()) ==
              foldTurkish(from)) {
        count++;
        next.add(normalizeBook({...b, _fieldKey: to}));
      } else {
        next.add(b);
      }
    }

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$from" değeriyle eşleşen kitap bulunamadı.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSaveBooks(next);
      if (mounted) {
        setState(() => _books = next);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count kitabın kaydı "$to" olarak güncellendi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duplicates = detectDuplicateBookGroups(_books);

    return Scaffold(
      appBar: AppBar(title: const Text('Katalog Bakım & Düzenleme')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Toplu Dolap / Yazar / Yayınevi / Kategori Değiştir',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _fieldKey,
                    decoration: const InputDecoration(
                      labelText: 'Düzenlenecek Alan',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'shelf',
                        child: Text('Dolap / Raf (örn. N → A)'),
                      ),
                      DropdownMenuItem(value: 'author', child: Text('Yazar Adı')),
                      DropdownMenuItem(
                        value: 'publisher',
                        child: Text('Yayınevi'),
                      ),
                      DropdownMenuItem(
                        value: 'category',
                        child: Text('Kategori / Tür'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _fieldKey = v ?? 'shelf'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _findCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Mevcut Değer',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _replaceCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Yeni Değer',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _applyBulkReplace,
                      icon: const Icon(Icons.find_replace_rounded),
                      label: const Text('Eşleşen Kayıtları Toplu Güncelle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Mükerrer Kitap Grupları (${duplicates.length} grup)',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (duplicates.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Harika! Katalogda mükerrer ISBN veya aynı başlık+yazar grubu bulunmuyor.',
              ),
            )
          else
            for (final group in duplicates.take(40))
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: scheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          BookCoverWidget(
                            book: group.first,
                            width: 42,
                            height: 60,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${group.first['title'] ?? ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${group.first['author'] ?? ''} · ${group.length} ayrı kayıt',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  'Demirbaşlar: ${group.map((b) => b['accessionCode'] ?? '-').join(' | ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: _saving
                                ? null
                                : () async {
                                    setState(() => _saving = true);
                                    try {
                                      final merged = mergeDuplicateGroup(
                                        _books,
                                        group,
                                      );
                                      await widget.onSaveBooks(merged);
                                      if (mounted) {
                                        setState(() => _books = merged);
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _saving = false);
                                      }
                                    }
                                  },
                            child: const Text('Birleştir'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Görünüm, Arka Plan Duvar Kağıdı, Efektler, Okul Kimliği ve iPhone Eşitleme Paneli.
Future<void> showThemeAndSchoolSettingsSheet(
  BuildContext context, {
  required int totalBooks,
  required Future<void> Function() onResyncIPhoneSeed,
}) {
  return openLibraryAtmosphereStudio(
    context,
    totalBooks: totalBooks,
    onResyncIPhoneSeed: onResyncIPhoneSeed,
  );
}

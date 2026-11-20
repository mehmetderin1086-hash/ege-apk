import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_settings.dart';
import 'book_visuals.dart';
import 'catalog_search.dart';
import 'loan_model.dart';
import 'reservation_model.dart';

enum CatalogViewMode {
  showcaseGrid('Vitrin', Icons.grid_view_rounded),
  largeCards('Büyük Kart', Icons.view_agenda_rounded),
  bookshelf('Raf', Icons.shelves),
  excelTable('Excel Tablo', Icons.table_chart_rounded);

  const CatalogViewMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class BookActionCallbacks {
  const BookActionCallbacks({
    required this.onEdit,
    required this.onLoan,
    required this.onReturn,
    required this.onExtend,
    required this.onMarkLost,
    required this.onResolveIdentity,
    required this.onCopies,
    required this.onReservations,
    required this.onHistory,
    required this.onWithdraw,
    required this.onTrash,
    required this.onOpenCover,
    this.onToggleFavorite,
    this.onRateBook,
    this.onQuickExtend,
    this.allBooks,
  });

  final void Function(Map<String, dynamic> book) onEdit;
  final void Function(Map<String, dynamic> book) onLoan;
  final void Function(Map<String, dynamic> book) onReturn;
  final void Function(Map<String, dynamic> book) onExtend;
  final void Function(Map<String, dynamic> book) onMarkLost;
  final void Function(Map<String, dynamic> book) onResolveIdentity;
  final void Function(Map<String, dynamic> book) onCopies;
  final void Function(Map<String, dynamic> book) onReservations;
  final void Function(Map<String, dynamic> book) onHistory;
  final void Function(Map<String, dynamic> book) onWithdraw;
  final void Function(Map<String, dynamic> book) onTrash;
  final void Function(Map<String, dynamic> book, String heroTag) onOpenCover;
  final void Function(Map<String, dynamic> book)? onToggleFavorite;
  final void Function(Map<String, dynamic> book, int rating)? onRateBook;
  final void Function(Map<String, dynamic> book, String loanId)? onQuickExtend;
  final List<Map<String, dynamic>>? allBooks;
}

/// Formats a clean, copy-ready Turkish bibliography card for sharing a book.
String formatBookBibliographyText(Map<String, dynamic> book) {
  final lines = <String>[];
  final title = (book['title'] ?? '').toString().trim();
  if (title.isNotEmpty) lines.add('Kitap: $title');
  void addField(String label, String key) {
    final val = (book[key] ?? '').toString().trim();
    if (val.isNotEmpty) lines.add('$label: $val');
  }

  addField('Yazar', 'author');
  addField('Yayınevi', 'publisher');
  addField('Kategori', 'category');
  addField('Seri', 'series');
  addField('Raf', 'shelf');
  addField('Demirbaş', 'accessionCode');
  addField('ISBN', 'isbn');
  addField('Yayın Yılı', 'publicationYear');
  addField('Sayfa', 'pageCount');
  addField('Dil', 'language');
  final tags = (book['tags'] ?? '').toString().trim();
  if (tags.isNotEmpty) lines.add('Etiketler: $tags');
  final notes = (book['notes'] ?? '').toString().trim();
  if (notes.isNotEmpty) lines.add('Not: $notes');
  return lines.join('\n');
}

/// Finds related books in the catalog by matching series, author, category, or shelf.
List<Map<String, dynamic>> findRelatedBooks(
  Map<String, dynamic> book,
  List<Map<String, dynamic>> catalog, {
  int limit = 10,
}) {
  final selfId = (book['id'] ?? '').toString();
  final series = foldTurkish((book['series'] ?? '').toString().trim());
  final author = foldTurkish((book['author'] ?? '').toString().trim());
  final category = foldTurkish((book['category'] ?? '').toString().trim());
  final shelf = foldTurkish((book['shelf'] ?? '').toString().trim());

  final scored = <({Map<String, dynamic> book, int score})>[];
  for (final candidate in catalog) {
    if ((candidate['id'] ?? '').toString() == selfId) continue;
    if (candidate['deletedAt'] != null || candidate['isWithdrawn'] == true) {
      continue;
    }
    var score = 0;
    final cSeries = foldTurkish((candidate['series'] ?? '').toString().trim());
    final cAuthor = foldTurkish((candidate['author'] ?? '').toString().trim());
    final cCat = foldTurkish((candidate['category'] ?? '').toString().trim());
    final cShelf = foldTurkish((candidate['shelf'] ?? '').toString().trim());
    if (series.isNotEmpty && cSeries == series) score += 8;
    if (author.isNotEmpty && cAuthor == author) score += 5;
    if (category.isNotEmpty && cCat == category) score += 2;
    if (shelf.isNotEmpty && cShelf == shelf) score += 1;
    if (score > 0) scored.add((book: candidate, score: score));
  }
  scored.sort((a, b) {
    final cmp = b.score.compareTo(a.score);
    if (cmp != 0) return cmp;
    return foldTurkish('${a.book['title'] ?? ''}')
        .compareTo(foldTurkish('${b.book['title'] ?? ''}'));
  });
  return scored.take(limit).map((e) => e.book).toList();
}

/// Generates a polite Turkish reminder message (WhatsApp/SMS) for a borrowed book.
String buildOverdueReminderMessage(
  Map<String, dynamic> book,
  Map<String, dynamic> loan, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final title = (book['title'] ?? 'Kitap').toString().trim();
  final name = (loan['name'] ?? 'Öğrencimiz').toString().trim();
  final cls = (loan['studentClass'] ?? '').toString().trim();
  final due = DateTime.tryParse('${loan['due'] ?? ''}');
  final clsPart = cls.isEmpty ? '' : ' ($cls)';
  if (due == null) {
    return 'Merhaba $name$clsPart, okul kütüphanemizden ödünç aldığınız "$title" adlı kitabı müsait olduğunuzda teslim etmenizi rica ederiz. İyi okumalar!';
  }
  final today = DateTime(current.year, current.month, current.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  final diffDays = today.difference(dueDay).inDays;
  final dateText =
      '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}.${due.year}';
  if (diffDays > 0) {
    return 'Merhaba $name$clsPart, okul kütüphanemizden aldığınız "$title" adlı kitabın teslim tarihi ($dateText) $diffDays gün geçmiştir. En kısa sürede kütüphaneye teslim etmenizi rica ederiz.';
  }
  return 'Merhaba $name$clsPart, okul kütüphanemizden aldığınız "$title" adlı kitabın teslim tarihi $dateText olup yakında dolmaktadır. Bilginize sunarız.';
}

/// Generates a clean multi-line summary of all overdue books for sharing/copying.
String buildBulkOverdueSummaryText(
  List<Map<String, dynamic>> books, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final rows = <String>[];
  for (final book in books) {
    if (book['deletedAt'] != null) continue;
    final title = (book['title'] ?? '').toString().trim();
    for (final loan in activeLoans(book)) {
      if (!isOverdue(loan, now: current)) continue;
      final due = DateTime.tryParse('${loan['due'] ?? ''}');
      final days = due == null
          ? 0
          : today.difference(DateTime(due.year, due.month, due.day)).inDays;
      final cls = (loan['studentClass'] ?? '').toString().trim();
      final clsText = cls.isEmpty ? '' : ' ($cls)';
      rows.add('• ${loan['name']}$clsText — $title ($days gün gecikmiş)');
    }
  }
  if (rows.isEmpty) return 'Geciken kitap ödüncü bulunmuyor.';
  return 'Geciken Kütüphane Kitapları (${rows.length}):\n${rows.join('\n')}';
}

/// Top smart library hero banner with generated 3D illustration, live animated counters,
/// and colorful horizontal quick-action cards.
class LibraryHeroHeader extends StatelessWidget {
  const LibraryHeroHeader({
    super.key,
    required this.books,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.busy,
    required this.onQuickRegister,
    required this.onKitapyurduSearch,
    required this.onInventory,
    required this.onExportXlsx,
    required this.onImportXlsx,
    required this.onDataQuality,
    this.libraryTitle = 'Akıllı Kütüphane Yönetimi',
    this.onOpenDesk,
    this.onOpenLabels,
    this.onVoiceAssistant,
    this.onBulkIsbnAmazon,
    this.onFourPageOcr,
    this.onShelfPhotoCount,
    this.onDiscover,
    this.onOpenSanctuary,
    this.onOpenThemeStudio,
    this.showQuickRibbon = true,
  });

  final List<Map<String, dynamic>> books;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final bool busy;
  final VoidCallback onQuickRegister;
  final VoidCallback onKitapyurduSearch;
  final VoidCallback onInventory;
  final VoidCallback onExportXlsx;
  final VoidCallback onImportXlsx;
  final VoidCallback onDataQuality;
  final String libraryTitle;
  final VoidCallback? onOpenDesk;
  final VoidCallback? onOpenLabels;
  final VoidCallback? onVoiceAssistant;
  final VoidCallback? onBulkIsbnAmazon;
  final VoidCallback? onFourPageOcr;
  final VoidCallback? onShelfPhotoCount;
  final VoidCallback? onDiscover;
  final VoidCallback? onOpenSanctuary;
  final VoidCallback? onOpenThemeStudio;
  final bool showQuickRibbon;

  @override
  Widget build(BuildContext context) {
    final active = books
        .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
        .toList();
    var totalCopies = 0;
    var shelfCopies = 0;
    var loanedCopies = 0;
    var overdueCount = 0;
    for (final b in active) {
      totalCopies += (b['quantity'] as int?) ?? 1;
      shelfCopies += availableCopies(b);
      final loans = activeLoans(b);
      loanedCopies += loans.length;
      overdueCount += loans.where(isOverdue).length;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF4338CA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ValueListenableBuilder<AppThemeSettings>(
                        valueListenable: appThemeNotifier,
                        builder: (context, cfg, _) {
                          final wp = cfg.effectiveWallpaperAsset;
                          final asset = wp.isNotEmpty
                              ? wp
                              : 'assets/images/bg_yildizli_kutuphane.webp';
                          return Image.asset(
                            asset,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            errorBuilder: (_, _, _) => Image.asset(
                              'assets/images/library_hero.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink(),
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF0F0D2E).withValues(alpha: 0.88),
                              const Color(0xFF1E1B4B).withValues(alpha: 0.66),
                              const Color(0xFF0F172A).withValues(alpha: 0.36),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: collapsed ? 10 : 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: Color(0xFFFBBF24),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  libraryTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: onToggleCollapsed,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        collapsed ? 'Paneli Aç' : 'Daralt',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        collapsed
                                            ? Icons.expand_more_rounded
                                            : Icons.expand_less_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (collapsed) ...[
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  CompactStatChip(
                                    icon: Icons.menu_book_rounded,
                                    label: '${active.length} kitap',
                                    color: const Color(0xFFA5B4FC),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.14,
                                    ),
                                    foregroundColor: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  CompactStatChip(
                                    icon: Icons.check_circle_outline_rounded,
                                    label: '$shelfCopies rafta',
                                    color: const Color(0xFF6EE7B7),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.14,
                                    ),
                                    foregroundColor: const Color(0xFFA7F3D0),
                                  ),
                                  const SizedBox(width: 6),
                                  CompactStatChip(
                                    icon: Icons.swap_horiz_rounded,
                                    label: '$loanedCopies ödünçte',
                                    color: const Color(0xFFFCA5A5),
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.14,
                                    ),
                                    foregroundColor: const Color(0xFFFEE2E2),
                                  ),
                                  if (overdueCount > 0) ...[
                                    const SizedBox(width: 6),
                                    CompactStatChip(
                                      icon: Icons.warning_amber_rounded,
                                      label: '$overdueCount gecikmiş',
                                      color: const Color(0xFFF87171),
                                      backgroundColor: const Color(
                                        0xFFEF4444,
                                      ).withValues(alpha: 0.28),
                                      foregroundColor: const Color(0xFFFECACA),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if (!collapsed) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                LibraryPulseDial(
                                  ratio: totalCopies > 0
                                      ? (shelfCopies / totalCopies)
                                            .clamp(0.0, 1.0)
                                      : 1.0,
                                  centerValue:
                                      '${totalCopies > 0 ? ((shelfCopies / totalCopies) * 100).round() : 100}%',
                                  centerCaption: 'rafta',
                                  size: 74,
                                  alert: overdueCount > 0,
                                  accent: overdueCount > 0
                                      ? const Color(0xFFF87171)
                                      : const Color(0xFFFBBF24),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        AnimatedStatPill(
                                          label: 'Çeşit Kitap',
                                          value: active.length,
                                          icon: Icons.menu_book_rounded,
                                          accentColor: const Color(0xFFA5B4FC),
                                        ),
                                        const SizedBox(width: 8),
                                        AnimatedStatPill(
                                          label: 'Toplam Nüsha',
                                          value: totalCopies,
                                          icon: Icons.layers_rounded,
                                          accentColor: const Color(0xFFFDE68A),
                                        ),
                                        const SizedBox(width: 8),
                                        AnimatedStatPill(
                                          label: 'Rafta Mevcut',
                                          value: shelfCopies,
                                          icon: Icons.check_circle_outline_rounded,
                                          accentColor: const Color(0xFF6EE7B7),
                                        ),
                                        const SizedBox(width: 8),
                                        AnimatedStatPill(
                                          label: 'Ödünçte',
                                          value: loanedCopies,
                                          icon: Icons.swap_horiz_rounded,
                                          accentColor: const Color(0xFFFCA5A5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed && showQuickRibbon)
            SizedBox(
              height: 118,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                children: [
                  if (onOpenSanctuary != null) ...[
                    GradientActionCard(
                      title: 'Okuma Köşesi',
                      subtitle: 'Huzurlu odak & sayaç',
                      icon: Icons.nightlight_round,
                      colors: const [Color(0xFF312E81), Color(0xFF6366F1)],
                      imageAsset: 'assets/images/card_okuma_modu.webp',
                      badgeText: 'HUZUR',
                      badgeColor: const Color(0xFFF59E0B),
                      width: 170,
                      onTap: busy ? null : onOpenSanctuary,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onDiscover != null) ...[
                    GradientActionCard(
                      title: 'Ne Okusam?',
                      subtitle: 'Keşfet & rastgele öner',
                      icon: Icons.explore_rounded,
                      colors: const [Color(0xFFDB2777), Color(0xFFF43F5E)],
                      imageAsset: 'assets/images/card_kesfet.webp',
                      badgeText: 'KEŞİF',
                      width: 168,
                      onTap: busy ? null : onDiscover,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onOpenThemeStudio != null) ...[
                    GradientActionCard(
                      title: 'Tema Stüdyosu',
                      subtitle: 'Canlı sahne & efekt',
                      icon: Icons.auto_awesome_rounded,
                      colors: const [Color(0xFF78350F), Color(0xFFD97706)],
                      imageAsset: 'assets/images/bg_osmanli_kutuphane.webp',
                      badgeText: 'VİTRİN',
                      width: 168,
                      onTap: busy ? null : onOpenThemeStudio,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onVoiceAssistant != null) ...[
                    GradientActionCard(
                      title: 'Sesli Asistan',
                      subtitle: 'CLIProxy Türkçe AI',
                      icon: Icons.mic_rounded,
                      colors: const [Color(0xFF0284C7), Color(0xFF06B6D4)],
                      imageAsset: 'assets/images/voice_assistant_banner.jpg',
                      badgeText: 'AI SES',
                      width: 168,
                      onTap: busy ? null : onVoiceAssistant,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onBulkIsbnAmazon != null) ...[
                    GradientActionCard(
                      title: '100+ ISBN Çek',
                      subtitle: 'Amazon toplu kayıt',
                      icon: Icons.rocket_launch_rounded,
                      colors: const [Color(0xFFEA580C), Color(0xFFF59E0B)],
                      imageAsset: 'assets/images/ai_vision_banner.jpg',
                      badgeText: 'TOPLU',
                      width: 168,
                      onTap: busy ? null : onBulkIsbnAmazon,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onFourPageOcr != null) ...[
                    GradientActionCard(
                      title: '4-Sayfa OCR',
                      subtitle: 'Kapak + iç künye AI',
                      icon: Icons.document_scanner_rounded,
                      colors: const [Color(0xFF9333EA), Color(0xFFEC4899)],
                      imageAsset: 'assets/images/scanner_banner.jpg',
                      badgeText: 'AI OCR',
                      width: 168,
                      onTap: busy ? null : onFourPageOcr,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onShelfPhotoCount != null) ...[
                    GradientActionCard(
                      title: 'Raf Foto Sayım',
                      subtitle: 'Fotoğraftan kitap say',
                      icon: Icons.collections_bookmark_rounded,
                      colors: const [Color(0xFF1D4ED8), Color(0xFF6366F1)],
                      imageAsset: 'assets/images/bg_sabah_ferah.webp',
                      badgeText: 'KAMERA',
                      width: 168,
                      onTap: busy ? null : onShelfPhotoCount,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onOpenDesk != null) ...[
                    GradientActionCard(
                      title: 'Akıllı Banko',
                      subtitle: 'Hızlı ödünç & iade',
                      icon: Icons.point_of_sale_rounded,
                      colors: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
                      imageAsset: 'assets/images/school_desk_banner.jpg',
                      badgeText: 'BANKO',
                      width: 168,
                      onTap: busy ? null : onOpenDesk,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onOpenLabels != null) ...[
                    GradientActionCard(
                      title: 'Sırt & Barkod',
                      subtitle: 'A4 etiket ve QR kart',
                      icon: Icons.qr_code_2_rounded,
                      colors: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
                      imageAsset: 'assets/images/label_print_banner.jpg',
                      badgeText: 'A4 PDF',
                      width: 168,
                      onTap: busy ? null : onOpenLabels,
                    ),
                    const SizedBox(width: 10),
                  ],
                  GradientActionCard(
                    title: 'Hızlı Kayıt',
                    subtitle: 'Seri barkod ve raf',
                    icon: Icons.bolt_rounded,
                    colors: const [Color(0xFF059669), Color(0xFF10B981)],
                    imageAsset: 'assets/images/bg_gece_calisma.webp',
                    badgeText: 'SERİ',
                    width: 166,
                    onTap: busy ? null : onQuickRegister,
                  ),
                  const SizedBox(width: 10),
                  GradientActionCard(
                    title: 'Kitapyurdu Ara',
                    subtitle: 'Başlık / yazar / yayın',
                    icon: Icons.travel_explore_rounded,
                    colors: const [Color(0xFFD97706), Color(0xFFF59E0B)],
                    imageAsset: 'assets/images/library_hero.jpg',
                    badgeText: 'WEB',
                    width: 166,
                    onTap: busy ? null : onKitapyurduSearch,
                  ),
                  const SizedBox(width: 10),
                  GradientActionCard(
                    title: 'Envanter Sayımı',
                    subtitle: 'Kamera ile stok say',
                    icon: Icons.inventory_2_rounded,
                    colors: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    imageAsset: 'assets/images/card_envanter.webp',
                    badgeText: 'STOK',
                    width: 166,
                    onTap: busy ? null : onInventory,
                  ),
                  const SizedBox(width: 10),
                  GradientActionCard(
                    title: 'Excel İndir (.xlsx)',
                    subtitle: 'Renkli kitap listesi',
                    icon: Icons.grid_on_rounded,
                    colors: const [Color(0xFF15803D), Color(0xFF22C55E)],
                    imageAsset: 'assets/images/card_excel_rapor.webp',
                    badgeText: 'XLSX',
                    width: 166,
                    onTap: busy ? null : onExportXlsx,
                  ),
                  const SizedBox(width: 10),
                  GradientActionCard(
                    title: 'Excel\'den Yükle',
                    subtitle: '.xlsx tablo içe aktar',
                    icon: Icons.upload_file_rounded,
                    colors: const [Color(0xFF0369A1), Color(0xFF0EA5E9)],
                    imageAsset: 'assets/images/analytics_banner.jpg',
                    badgeText: 'İÇE AKTAR',
                    width: 166,
                    onTap: busy ? null : onImportXlsx,
                  ),
                  const SizedBox(width: 10),
                  GradientActionCard(
                    title: 'Eksik Alanlar',
                    subtitle: 'Oto kapak ve künye',
                    icon: Icons.auto_fix_high_rounded,
                    colors: const [Color(0xFFBE123C), Color(0xFFF43F5E)],
                    imageAsset: 'assets/images/duty_roster_banner.jpg',
                    badgeText: 'DENETİM',
                    width: 166,
                    onTap: busy ? null : onDataQuality,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Illustrated empty state widget with gentle floating animation.
class EmptyCatalogArtwork extends StatelessWidget {
  const EmptyCatalogArtwork({
    super.key,
    required this.title,
    required this.subtitle,
    this.onAddBook,
    this.onQuickRegister,
    this.onImportXlsx,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onAddBook;
  final VoidCallback? onQuickRegister;
  final VoidCallback? onImportXlsx;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.92, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (_, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 156,
                height: 156,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.24),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/images/empty_shelf.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: scheme.primaryContainer,
                      child: Icon(
                        Icons.auto_stories_rounded,
                        size: 64,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onAddBook != null ||
                onQuickRegister != null ||
                onImportXlsx != null) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (onQuickRegister != null)
                    FilledButton.icon(
                      onPressed: onQuickRegister,
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text('Hızlı Barkod Kayıt'),
                    ),
                  if (onAddBook != null)
                    FilledButton.tonalIcon(
                      onPressed: onAddBook,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Kitap Ekle'),
                    ),
                  if (onImportXlsx != null)
                    OutlinedButton.icon(
                      onPressed: onImportXlsx,
                      icon: const Icon(Icons.grid_on_rounded),
                      label: const Text('Excel\'den Yükle'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

({Color bg, Color fg, String text}) _stockBadgeInfo(
  Map<String, dynamic> book,
  ColorScheme scheme,
) {
  if (book['isWithdrawn'] == true) {
    return (
      bg: Colors.grey.shade700,
      fg: Colors.white,
      text: 'Düşüldü',
    );
  }
  final loans = activeLoans(book);
  final qty = (book['quantity'] as int?) ?? 1;
  final avail = availableCopies(book);
  if (loans.any(isOverdue)) {
    return (
      bg: const Color(0xFFDC2626),
      fg: Colors.white,
      text: 'Gecikmiş ($avail/$qty)',
    );
  }
  if (avail <= 0) {
    return (
      bg: const Color(0xFFD97706),
      fg: Colors.white,
      text: 'Ödünçte (0/$qty)',
    );
  }
  return (
    bg: const Color(0xFF059669),
    fg: Colors.white,
    text: '$avail/$qty Rafta',
  );
}

PopupMenuButton<String> _buildBookPopupMenu(
  Map<String, dynamic> b,
  BookActionCallbacks actions,
) {
  final loans = activeLoans(b);
  return PopupMenuButton<String>(
    tooltip: 'Kitap işlemleri',
    icon: const Icon(Icons.more_vert_rounded),
    onSelected: (action) {
      switch (action) {
        case 'edit':
          actions.onEdit(b);
        case 'loan':
          actions.onLoan(b);
        case 'return':
          actions.onReturn(b);
        case 'extend':
          actions.onExtend(b);
        case 'lost':
          actions.onMarkLost(b);
        case 'identity':
          actions.onResolveIdentity(b);
        case 'copies':
          actions.onCopies(b);
        case 'reservations':
          actions.onReservations(b);
        case 'history':
          actions.onHistory(b);
        case 'withdraw':
          actions.onWithdraw(b);
        case 'trash':
          actions.onTrash(b);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(
        value: 'edit',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.edit_outlined),
          title: Text('Kitabı düzenle'),
        ),
      ),
      if (availableCopies(b) > 0)
        const PopupMenuItem(
          value: 'loan',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.outbound_outlined),
            title: Text('Ödünç ver'),
          ),
        ),
      if (loans.isNotEmpty) ...[
        const PopupMenuItem(
          value: 'return',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.assignment_returned_outlined),
            title: Text('İade al'),
          ),
        ),
        const PopupMenuItem(
          value: 'extend',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.update_rounded),
            title: Text('Süreyi uzat'),
          ),
        ),
        const PopupMenuItem(
          value: 'identity',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.badge_outlined),
            title: Text('Ödünç kimliğini düzelt'),
          ),
        ),
        const PopupMenuItem(
          value: 'lost',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.report_problem_outlined),
            title: Text('Kayıp bildir'),
          ),
        ),
      ],
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'copies',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.qr_code_2_rounded),
          title: Text('Fiziksel nüshalar'),
        ),
      ),
      const PopupMenuItem(
        value: 'reservations',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.bookmark_added_outlined),
          title: Text('Rezervasyonlar'),
        ),
      ),
      const PopupMenuItem(
        value: 'history',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.history_rounded),
          title: Text('Ödünç geçmişi'),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'withdraw',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_outlined),
          title: Text(
            b['isWithdrawn'] == true
                ? 'Koleksiyona geri al'
                : 'Koleksiyondan düş',
          ),
        ),
      ),
      const PopupMenuItem(
        value: 'trash',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_outline, color: Colors.red),
          title: Text('Çöp kutusuna taşı'),
        ),
      ),
    ],
  );
}

/// Opens a rich interactive detail & quick-action bottom sheet for a book.
Future<void> showRichBookDetailSheet(
  BuildContext context,
  Map<String, dynamic> book,
  BookActionCallbacks actions,
) async {
  final scheme = Theme.of(context).colorScheme;
  final loans = activeLoans(book);
  final avail = availableCopies(book);
  final heroTag = 'detail-cover-${book['id']}';
  final badge = _stockBadgeInfo(book, scheme);
  final activeRes = reservationsOf(book).where(isActiveReservation).length;
  final completedReads = loanHistory(
    book,
  ).where((e) => e['kind'] == 'returned').length;
  final relatedBooks = actions.allBooks == null
      ? const <Map<String, dynamic>>[]
      : findRelatedBooks(book, actions.allBooks!);
  var localFavorite = book['isFavorite'] == true;
  var localRating = (book['rating'] as int?) ?? 0;

  final tags = (book['tags'] ?? '')
      .toString()
      .split(RegExp(r'[,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final contentWarning = (book['contentWarning'] ?? '').toString().trim();

  Widget metaChip(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$label: $value',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (outerCtx) {
      return StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BookCoverWidget(
                        book: book,
                        width: 124,
                        height: 182,
                        heroTag: heroTag,
                        showZoomBadge: true,
                        onTap: () => actions.onOpenCover(book, heroTag),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badge.bg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      badge.text,
                                      style: TextStyle(
                                        color: badge.fg,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                if (actions.onToggleFavorite != null)
                                  IconButton(
                                    tooltip: localFavorite
                                        ? 'Favorilerden çıkar'
                                        : 'Favorilere ekle',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setSheetState(
                                        () => localFavorite = !localFavorite,
                                      );
                                      actions.onToggleFavorite!(book);
                                    },
                                    icon: Icon(
                                      localFavorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: localFavorite
                                          ? Colors.pinkAccent
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Künyeyi Kopyala',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(
                                        text: formatBookBibliographyText(book),
                                      ),
                                    );
                                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Kitap künyesi panoya kopyalandı.',
                                        ),
                                      ),
                                    );
                                  },
                                  icon: Icon(
                                    Icons.copy_all_rounded,
                                    size: 20,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${book['title'] ?? ''}',
                              style: Theme.of(sheetCtx).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                  ),
                            ),
                            if ((book['author'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${book['author']}',
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                            if ((book['publisher'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                '${book['publisher']}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                            if (actions.onRateBook != null ||
                                localRating > 0) ...[
                              const SizedBox(height: 8),
                              StarRatingRow(
                                rating: localRating,
                                size: 20,
                                showNumeric: true,
                                onChanged: actions.onRateBook == null
                                    ? null
                                    : (next) {
                                        setSheetState(() => localRating = next);
                                        actions.onRateBook!(book, next);
                                      },
                              ),
                            ],
                            if (completedReads > 0 ||
                                book['isTextbook'] == true) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (completedReads > 0)
                                    CompactStatChip(
                                      icon: Icons.auto_stories_rounded,
                                      label: '$completedReads kez okundu',
                                      color: scheme.secondary,
                                    ),
                                  if (book['isTextbook'] == true)
                                    CompactStatChip(
                                      icon: Icons.school_rounded,
                                      label: 'Ders Kitabı',
                                      color: scheme.tertiary,
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () =>
                                  actions.onOpenCover(book, heroTag),
                              icon: const Icon(
                                Icons.zoom_out_map_rounded,
                                size: 16,
                              ),
                              label: const Text('Kapağı Tam Ekran Gör'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (contentWarning.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'İçerik Notu: $contentWarning',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Primary Quick Action Buttons
                  Row(
                    children: [
                      if (avail > 0 && book['isWithdrawn'] != true)
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              actions.onLoan(book);
                            },
                            icon: const Icon(Icons.outbound_rounded),
                            label: const Text('Ödünç Ver'),
                          ),
                        ),
                      if (avail > 0 &&
                          book['isWithdrawn'] != true &&
                          loans.isNotEmpty)
                        const SizedBox(width: 10),
                      if (loans.isNotEmpty)
                        Expanded(
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              actions.onReturn(book);
                            },
                            icon: const Icon(Icons.assignment_returned_rounded),
                            label: Text('İade Al (${loans.length})'),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            actions.onEdit(book);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Düzenle'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      metaChip(
                        Icons.shelves,
                        'Raf',
                        '${book['shelf'] ?? ''}',
                      ),
                      metaChip(
                        Icons.category_outlined,
                        'Kategori',
                        '${book['category'] ?? ''}',
                      ),
                      metaChip(
                        Icons.qr_code_rounded,
                        'ISBN',
                        '${book['isbn'] ?? ''}',
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: '${book['isbn'] ?? ''}'),
                          );
                          ScaffoldMessenger.of(sheetCtx).showSnackBar(
                            const SnackBar(
                              content: Text('ISBN panoya kopyalandı.'),
                            ),
                          );
                        },
                      ),
                      metaChip(
                        Icons.tag_rounded,
                        'Demirbaş',
                        '${book['accessionCode'] ?? ''}',
                      ),
                      metaChip(
                        Icons.calendar_today_outlined,
                        'Yıl',
                        '${book['publicationYear'] ?? ''}',
                      ),
                      metaChip(
                        Icons.auto_stories_outlined,
                        'Sayfa',
                        '${book['pageCount'] ?? ''}',
                      ),
                      metaChip(
                        Icons.layers_outlined,
                        'Baskı',
                        '${book['edition'] ?? ''}',
                      ),
                      metaChip(
                        Icons.format_list_numbered_rounded,
                        'Cilt',
                        book['volume'] == null ? '' : '${book['volume']}',
                      ),
                      metaChip(
                        Icons.translate_rounded,
                        'Dil',
                        '${book['language'] ?? ''}',
                      ),
                      metaChip(
                        Icons.collections_bookmark_outlined,
                        'Seri',
                        '${book['series'] ?? ''}',
                      ),
                      metaChip(
                        Icons.school_outlined,
                        'Seviye',
                        '${book['readingLevel'] ?? ''}',
                      ),
                      metaChip(
                        Icons.bookmark_outline_rounded,
                        'Okuma Durumu',
                        '${book['readingStatus'] ?? ''}',
                      ),
                    ],
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if ((book['notes'] ?? '').toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${book['notes']}'),
                    ),
                  ],
                  if (loans.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Etkin Ödünçler (${loans.length})',
                      style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final l in loans)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: isOverdue(l)
                            ? scheme.errorContainer.withValues(alpha: 0.55)
                            : scheme.surfaceContainerLow,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            isOverdue(l)
                                ? Icons.warning_amber_rounded
                                : Icons.person_outline_rounded,
                            color: isOverdue(l) ? scheme.error : scheme.primary,
                          ),
                          title: Text(
                            '${l['name']}${(l['studentClass'] ?? '').toString().isEmpty ? '' : ' · ${l['studentClass']}'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Builder(
                            builder: (_) {
                              final due = DateTime.tryParse(
                                '${l['due'] ?? ''}',
                              );
                              if (due == null) {
                                return const Text('Süresiz ödünç');
                              }
                              return Text(
                                'Teslim: ${due.day}.${due.month}.${due.year}${isOverdue(l) ? ' · GECİKMİŞ' : ''}',
                              );
                            },
                          ),
                          trailing: IconButton(
                            tooltip: 'Hatırlatma Mesajı Kopyala',
                            icon: const Icon(Icons.sms_outlined, size: 19),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(
                                  text: buildOverdueReminderMessage(book, l),
                                ),
                              );
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Hatırlatma mesajı panoya kopyalandı.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                  const Divider(height: 28),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: const Text('Fiziksel Nüshalar'),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          actions.onCopies(book);
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.bookmark_added_outlined,
                          size: 18,
                        ),
                        label: Text(
                          activeRes > 0
                              ? 'Rezervasyonlar ($activeRes)'
                              : 'Rezervasyonlar',
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          actions.onReservations(book);
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('Ödünç Geçmişi'),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          actions.onHistory(book);
                        },
                      ),
                      if (loans.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.update_rounded, size: 18),
                          label: const Text('Süreyi Uzat'),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            actions.onExtend(book);
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.inventory_outlined, size: 18),
                        label: Text(
                          book['isWithdrawn'] == true
                              ? 'Koleksiyona Geri Al'
                              : 'Koleksiyondan Düş',
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          actions.onWithdraw(book);
                        },
                      ),
                      ActionChip(
                        avatar: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: scheme.error,
                        ),
                        label: Text(
                          'Çöp Kutusuna Taşı',
                          style: TextStyle(color: scheme.error),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          actions.onTrash(book);
                        },
                      ),
                    ],
                  ),
                  if (relatedBooks.isNotEmpty) ...[
                    const Divider(height: 28),
                    Text(
                      'Benzer / Aynı Yazar & Seri Kitapları',
                      style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 184,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: relatedBooks.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, idx) {
                          final rel = relatedBooks[idx];
                          final relTag = 'rel-${book['id']}-${rel['id']}';
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              showRichBookDetailSheet(context, rel, actions);
                            },
                            child: SizedBox(
                              width: 102,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BookCoverWidget(
                                    book: rel,
                                    width: 102,
                                    height: 132,
                                    heroTag: relTag,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${rel['title'] ?? ''}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      );
    },
  );
}

/// 1) 2-Column Showcase Grid with HUGE Book Covers (`CatalogViewMode.showcaseGrid`).
class CatalogShowcaseGridView extends StatelessWidget {
  const CatalogShowcaseGridView({
    super.key,
    required this.books,
    required this.actions,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.onToggleSelect,
  });

  final List<Map<String, dynamic>> books;
  final BookActionCallbacks actions;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<String>? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 900 ? 4 : (width >= 600 ? 3 : 2);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 348,
      ),
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final b = books[i];
        final id = '${b['id'] ?? ''}';
        final isSelected = selectedIds.contains(id);
        final isFavorite = b['isFavorite'] == true;
        final rating = (b['rating'] as int?) ?? 0;
        final heroTag = 'grid-cover-$id';
        final badge = _stockBadgeInfo(b, scheme);
        final avail = availableCopies(b);
        final loans = activeLoans(b);
        final shelf = (b['shelf'] ?? '').toString().trim();

        return StaggeredFadeSlide(
          index: i,
          child: BouncyTap(
            onTap: () {
              if (selectionMode && onToggleSelect != null) {
                onToggleSelect!(id);
              } else {
                showRichBookDetailSheet(ctx, b, actions);
              }
            },
            onLongPress: onToggleSelect == null
                ? null
                : () => onToggleSelect!(id),
            child: Container(
              decoration: () {
                final glass = appThemeNotifier.value.glassCardsEnabled;
                final isDark = Theme.of(ctx).brightness == Brightness.dark;
                return BoxDecoration(
                  color: isSelected
                      ? scheme.primaryContainer.withValues(
                          alpha: glass ? 0.52 : 0.35,
                        )
                      : glass
                      ? (isDark
                            ? scheme.surfaceContainerHigh.withValues(alpha: 0.70)
                            : scheme.surface.withValues(alpha: 0.76))
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? scheme.primary
                        : glass
                        ? (isDark
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.white.withValues(alpha: 0.58))
                        : scheme.outlineVariant.withValues(alpha: 0.45),
                    width: isSelected ? 2.2 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: glass ? (isDark ? 0.24 : 0.08) : 0.06,
                      ),
                      blurRadius: glass ? 16 : 12,
                      offset: Offset(0, glass ? 6 : 4),
                    ),
                  ],
                );
              }(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top large cover area
                  Container(
                    height: 204,
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primaryContainer.withValues(
                            alpha: appThemeNotifier.value.glassCardsEnabled
                                ? 0.34
                                : 0.42,
                          ),
                          scheme.surfaceContainerLow.withValues(
                            alpha: appThemeNotifier.value.glassCardsEnabled
                                ? 0.28
                                : 1.0,
                          ),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        BookCoverWidget(
                          book: b,
                          width: 126,
                          height: 180,
                          heroTag: heroTag,
                          showZoomBadge: !selectionMode,
                          onTap: () {
                            if (selectionMode && onToggleSelect != null) {
                              onToggleSelect!(id);
                            } else {
                              actions.onOpenCover(b, heroTag);
                            }
                          },
                        ),
                        Positioned(
                          top: 0,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3.5,
                            ),
                            decoration: BoxDecoration(
                              color: badge.bg,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              badge.text,
                              style: TextStyle(
                                color: badge.fg,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        if (selectionMode || isSelected)
                          Positioned(
                            top: 0,
                            left: 10,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? scheme.primary
                                    : scheme.surface.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.primary,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                isSelected ? Icons.check_rounded : null,
                                size: 16,
                                color: scheme.onPrimary,
                              ),
                            ),
                          )
                        else if (shelf.isNotEmpty)
                          Positioned(
                            top: 0,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                shelf,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (isFavorite || rating > 0)
                          Positioned(
                            bottom: 2,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isFavorite)
                                    const Icon(
                                      Icons.favorite_rounded,
                                      size: 12,
                                      color: Colors.pinkAccent,
                                    ),
                                  if (isFavorite && rating > 0)
                                    const SizedBox(width: 4),
                                  if (rating > 0) ...[
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 12.5,
                                      color: Color(0xFFFBBF24),
                                    ),
                                    const SizedBox(width: 1),
                                    Text(
                                      '$rating',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Book title, author & quick button
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${b['title'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            (b['author'] ?? '').toString().trim().isEmpty
                                ? ((b['publisher'] ?? '').toString())
                                : '${b['author']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 34,
                                  child: avail > 0 && b['isWithdrawn'] != true
                                      ? FilledButton.tonalIcon(
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          onPressed: () => actions.onLoan(b),
                                          icon: const Icon(
                                            Icons.outbound_rounded,
                                            size: 14,
                                          ),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'Ödünç Ver',
                                              maxLines: 1,
                                              softWrap: false,
                                              style: TextStyle(fontSize: 11.5),
                                            ),
                                          ),
                                        )
                                      : loans.isNotEmpty
                                      ? OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          onPressed: () => actions.onReturn(b),
                                          icon: const Icon(
                                            Icons.assignment_returned_outlined,
                                            size: 14,
                                          ),
                                          label: const FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              'İade Al',
                                              maxLines: 1,
                                              softWrap: false,
                                              style: TextStyle(fontSize: 11.5),
                                            ),
                                          ),
                                        )
                                      : OutlinedButton(
                                          onPressed: () => actions.onEdit(b),
                                          child: const Text(
                                            'Düzenle',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                height: 34,
                                child: _buildBookPopupMenu(b, actions),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 2) Rich Large-Cover Card List (`CatalogViewMode.largeCards`).
class CatalogLargeCardsView extends StatelessWidget {
  const CatalogLargeCardsView({
    super.key,
    required this.books,
    required this.actions,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.onToggleSelect,
  });

  final List<Map<String, dynamic>> books;
  final BookActionCallbacks actions;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<String>? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final b = books[i];
        final id = '${b['id'] ?? ''}';
        final isSelected = selectedIds.contains(id);
        final isFavorite = b['isFavorite'] == true;
        final rating = (b['rating'] as int?) ?? 0;
        final heroTag = 'card-cover-$id';
        final badge = _stockBadgeInfo(b, scheme);
        final loans = activeLoans(b);
        final avail = availableCopies(b);
        final shelf = (b['shelf'] ?? '').toString().trim();
        final category = (b['category'] ?? '').toString().trim();
        final publisher = (b['publisher'] ?? '').toString().trim();
        final pageCount = (b['pageCount'] ?? '').toString().trim();
        final activeRes = reservationsOf(b).where(isActiveReservation).length;

        return StaggeredFadeSlide(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: BouncyTap(
              onTap: () {
                if (selectionMode && onToggleSelect != null) {
                  onToggleSelect!(id);
                } else {
                  showRichBookDetailSheet(ctx, b, actions);
                }
              },
              onLongPress: onToggleSelect == null
                  ? null
                  : () => onToggleSelect!(id),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: () {
                  final glass = appThemeNotifier.value.glassCardsEnabled;
                  final isDark = Theme.of(ctx).brightness == Brightness.dark;
                  return BoxDecoration(
                    color: isSelected
                        ? scheme.primaryContainer.withValues(
                            alpha: glass ? 0.50 : 0.32,
                          )
                        : glass
                        ? (isDark
                              ? scheme.surfaceContainerHigh.withValues(
                                  alpha: 0.72,
                                )
                              : scheme.surface.withValues(alpha: 0.76))
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? scheme.primary
                          : loans.any(isOverdue)
                          ? scheme.error.withValues(alpha: 0.65)
                          : glass
                          ? (isDark
                                ? Colors.white.withValues(alpha: 0.16)
                                : Colors.white.withValues(alpha: 0.58))
                          : scheme.outlineVariant.withValues(alpha: 0.45),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: glass ? (isDark ? 0.24 : 0.08) : 0.05,
                        ),
                        blurRadius: glass ? 14 : 10,
                        offset: Offset(0, glass ? 6 : 4),
                      ),
                    ],
                  );
                }(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (selectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 54),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isSelected ? scheme.primary : scheme.outline,
                        ),
                      ),
                    BookCoverWidget(
                      book: b,
                      width: 96,
                      height: 142,
                      heroTag: heroTag,
                      showZoomBadge: !selectionMode,
                      onTap: () {
                        if (selectionMode && onToggleSelect != null) {
                          onToggleSelect!(id);
                        } else {
                          actions.onOpenCover(b, heroTag);
                        }
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${b['title'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (isFavorite)
                                const Padding(
                                  padding: EdgeInsets.only(right: 2, top: 2),
                                  child: Icon(
                                    Icons.favorite_rounded,
                                    size: 16,
                                    color: Colors.pinkAccent,
                                  ),
                                ),
                              SizedBox(
                                width: 30,
                                height: 28,
                                child: _buildBookPopupMenu(b, actions),
                              ),
                            ],
                          ),
                          if ((b['author'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${b['author']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                          if (publisher.isNotEmpty || rating > 0) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (publisher.isNotEmpty)
                                  Expanded(
                                    child: Text(
                                      [
                                        publisher,
                                        if ((b['publicationYear'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty)
                                          b['publicationYear'],
                                        if (pageCount.isNotEmpty)
                                          '$pageCount s.',
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (rating > 0)
                                  StarRatingRow(
                                    rating: rating,
                                    size: 14,
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: badge.bg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  badge.text,
                                  style: TextStyle(
                                    color: badge.fg,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (shelf.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Raf: $shelf',
                                    style: TextStyle(
                                      color: scheme.onSecondaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (category.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    category.split('›').last.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              if (activeRes > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$activeRes Rezervasyon',
                                    style: TextStyle(
                                      color: scheme.onTertiaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (loans.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Ödünç: ${loans.map((l) => l['name']).join(', ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: loans.any(isOverdue)
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (avail > 0 && b['isWithdrawn'] != true)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    height: 32,
                                    child: FilledButton.tonalIcon(
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => actions.onLoan(b),
                                      icon: const Icon(
                                        Icons.outbound_rounded,
                                        size: 15,
                                      ),
                                      label: const Text(
                                        'Ödünç Ver',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ),
                              if (loans.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    height: 32,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () => actions.onReturn(b),
                                      icon: const Icon(
                                        Icons.assignment_returned_outlined,
                                        size: 15,
                                      ),
                                      label: const Text(
                                        'İade Al',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ),
                              SizedBox(
                                height: 32,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => actions.onEdit(b),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    'Düzenle',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 3) Visual 3D Wooden Bookshelf View (`CatalogViewMode.bookshelf`) displaying rows
/// of standing book covers resting on warm oak shelf ledges.
class CatalogBookshelfView extends StatelessWidget {
  const CatalogBookshelfView({
    super.key,
    required this.books,
    required this.actions,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.onToggleSelect,
  });

  final List<Map<String, dynamic>> books;
  final BookActionCallbacks actions;
  final Set<String> selectedIds;
  final bool selectionMode;
  final ValueChanged<String>? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final perRow = width >= 960 ? 6 : (width >= 600 ? 4 : 3);
    final rowCount = (books.length / perRow).ceil();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: rowCount,
      itemBuilder: (ctx, rowIdx) {
        final start = rowIdx * perRow;
        final end = (start + perRow).clamp(0, books.length);
        final rowBooks = books.sublist(start, end);

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int k = 0; k < perRow; k++)
                      Expanded(
                        child: k < rowBooks.length
                            ? _ShelfBookItem(
                                book: rowBooks[k],
                                actions: actions,
                                selected: selectedIds.contains(
                                  '${rowBooks[k]['id'] ?? ''}',
                                ),
                                selectionMode: selectionMode,
                                onToggleSelect: onToggleSelect,
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
              // Warm 3D wooden shelf plank + shadow
              Container(
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [
                            Color(0xFF6B4226),
                            Color(0xFF4A2C18),
                            Color(0xFF2D190C),
                          ]
                        : const [
                            Color(0xFFD6A46E),
                            Color(0xFFB57C47),
                            Color(0xFF8C582B),
                          ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                    bottom: Radius.circular(8),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1,
                    ),
                  ),
                ),
              ),
              Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.shadow.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShelfBookItem extends StatelessWidget {
  const _ShelfBookItem({
    required this.book,
    required this.actions,
    required this.selected,
    required this.selectionMode,
    this.onToggleSelect,
  });

  final Map<String, dynamic> book;
  final BookActionCallbacks actions;
  final bool selected;
  final bool selectionMode;
  final ValueChanged<String>? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = '${book['id'] ?? ''}';
    final avail = availableCopies(book);
    final loans = activeLoans(book);
    final hasOverdue = loans.any(isOverdue);
    final shelf = (book['shelf'] ?? '').toString().trim();
    final isFavorite = book['isFavorite'] == true;
    final heroTag = 'shelf-cover-$id';

    final statusColor = book['isWithdrawn'] == true
        ? scheme.outline
        : avail > 0
        ? const Color(0xFF22C55E)
        : hasOverdue
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return BouncyTap(
      onTap: () {
        if (selectionMode && onToggleSelect != null) {
          onToggleSelect!(id);
        } else {
          showRichBookDetailSheet(context, book, actions);
        }
      },
      onLongPress: onToggleSelect == null ? null : () => onToggleSelect!(id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 4, 5, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: selected
                    ? Border.all(color: scheme.primary, width: 2.5)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  BookCoverWidget(
                    book: book,
                    width: 96,
                    height: 142,
                    heroTag: heroTag,
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                  if (selectionMode || selected)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.primary
                              : Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    )
                  else if (isFavorite)
                    const Positioned(
                      top: 5,
                      left: 5,
                      child: Icon(
                        Icons.favorite_rounded,
                        size: 15,
                        color: Colors.pinkAccent,
                      ),
                    ),
                  if (shelf.isNotEmpty)
                    Positioned(
                      bottom: 5,
                      left: 5,
                      right: 5,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            shelf,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${book['title'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4) Interactive In-App Excel Spreadsheet Table View (`CatalogViewMode.excelTable`)
/// using virtualized row rendering for instant performance on thousands of books.
class CatalogExcelTableView extends StatefulWidget {
  const CatalogExcelTableView({
    super.key,
    required this.books,
    required this.actions,
    required this.busy,
    required this.onExportXlsx,
    required this.onImportXlsx,
    required this.onExportCsv,
    required this.onExportPdf,
  });

  final List<Map<String, dynamic>> books;
  final BookActionCallbacks actions;
  final bool busy;
  final VoidCallback onExportXlsx;
  final VoidCallback onImportXlsx;
  final VoidCallback onExportCsv;
  final VoidCallback onExportPdf;

  @override
  State<CatalogExcelTableView> createState() => _CatalogExcelTableViewState();
}

class _CatalogExcelTableViewState extends State<CatalogExcelTableView> {
  String _sortKey = 'title';
  bool _ascending = true;
  final ScrollController _horizontalScroll = ScrollController();

  @override
  void dispose() {
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _toggleSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _ascending = !_ascending;
      } else {
        _sortKey = key;
        _ascending = true;
      }
    });
  }

  List<Map<String, dynamic>> _sortedBooks() {
    final list = [...widget.books];
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      return switch (_sortKey) {
        'quantity' => ((a['quantity'] as int?) ?? 1).compareTo(
          (b['quantity'] as int?) ?? 1,
        ),
        'available' => availableCopies(a).compareTo(availableCopies(b)),
        'year' => (int.tryParse('${a['publicationYear'] ?? ''}') ?? 0)
            .compareTo(int.tryParse('${b['publicationYear'] ?? ''}') ?? 0),
        'pages' => (int.tryParse('${a['pageCount'] ?? ''}') ?? 0).compareTo(
          int.tryParse('${b['pageCount'] ?? ''}') ?? 0,
        ),
        _ => foldTurkish('${a[_sortKey] ?? ''}').compareTo(
          foldTurkish('${b[_sortKey] ?? ''}'),
        ),
      };
    }

    list.sort((a, b) => _ascending ? cmp(a, b) : cmp(b, a));
    return list;
  }

  Widget _headerCell(
    String label,
    double width, {
    String? sortKey,
    TextAlign align = TextAlign.left,
  }) {
    final active = sortKey != null && _sortKey == sortKey;
    return InkWell(
      onTap: sortKey == null ? null : () => _toggleSort(sortKey),
      child: Container(
        width: width,
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: align == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (sortKey != null) ...[
              const SizedBox(width: 3),
              Icon(
                active
                    ? (_ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded)
                    : Icons.unfold_more_rounded,
                size: 14,
                color: active
                    ? const Color(0xFFFDE68A)
                    : Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dataCell(
    Widget child,
    double width,
    Color borderColor, {
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Container(
      width: width,
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      alignment: alignment,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: borderColor, width: 0.8)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _sortedBooks();
    const totalTableWidth =
        52.0 +
        64.0 +
        112.0 +
        220.0 +
        160.0 +
        150.0 +
        130.0 +
        130.0 +
        100.0 +
        76.0 +
        76.0 +
        94.0 +
        120.0;
    final gridBorderColor = scheme.outlineVariant.withValues(alpha: 0.45);

    return Column(
      children: [
        // Excel Action Toolbar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: widget.busy ? null : widget.onExportXlsx,
                icon: const Icon(Icons.download_rounded, size: 17),
                label: Text('Excel İndir (${rows.length})'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: widget.busy ? null : widget.onImportXlsx,
                icon: const Icon(Icons.upload_file_rounded, size: 17),
                label: const Text('Excel\'den Yükle'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: widget.busy ? null : widget.onExportCsv,
                icon: const Icon(Icons.table_rows_outlined, size: 16),
                label: const Text('CSV'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: widget.busy ? null : widget.onExportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('PDF'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _horizontalScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalTableWidth,
                child: Column(
                  children: [
                    // Sticky Excel-Style Header Row
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF166534), Color(0xFF15803D)],
                        ),
                      ),
                      child: Row(
                        children: [
                          _headerCell('#', 52, align: TextAlign.center),
                          _headerCell('Kapak', 64, align: TextAlign.center),
                          _headerCell(
                            'Demirbaş',
                            112,
                            sortKey: 'accessionCode',
                          ),
                          _headerCell('Kitap Adı', 220, sortKey: 'title'),
                          _headerCell('Yazar', 160, sortKey: 'author'),
                          _headerCell('Yayınevi', 150, sortKey: 'publisher'),
                          _headerCell('ISBN', 130, sortKey: 'isbn'),
                          _headerCell('Kategori', 130, sortKey: 'category'),
                          _headerCell('Raf / Konum', 100, sortKey: 'shelf'),
                          _headerCell('Yıl', 76, sortKey: 'year'),
                          _headerCell('Sayfa', 76, sortKey: 'pages'),
                          _headerCell('Stok', 94, sortKey: 'available'),
                          _headerCell('İşlem', 120, align: TextAlign.center),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 92),
                        itemCount: rows.length,
                        itemBuilder: (ctx, i) {
                          final b = rows[i];
                          final badge = _stockBadgeInfo(b, scheme);
                          final heroTag = 'xlsx-cover-${b['id']}';
                          final copyCodes = ((b['copies'] as List?) ?? [])
                              .whereType<Map>()
                              .map((c) => '${c['accessionCode'] ?? ''}'.trim())
                              .where((s) => s.isNotEmpty)
                              .join(', ');
                          final acc =
                              '${b['accessionCode'] ?? ''}'.trim().isNotEmpty
                              ? '${b['accessionCode']}'
                              : copyCodes;

                          return InkWell(
                            onTap: () =>
                                showRichBookDetailSheet(ctx, b, widget.actions),
                            child: Container(
                              decoration: BoxDecoration(
                                color: i.isOdd
                                    ? scheme.surfaceContainerLowest
                                    : scheme.surfaceContainerLow.withValues(
                                        alpha: 0.55,
                                      ),
                                border: Border(
                                  bottom: BorderSide(
                                    color: gridBorderColor,
                                    width: 0.8,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _dataCell(
                                    Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    52,
                                    gridBorderColor,
                                    alignment: Alignment.center,
                                  ),
                                  _dataCell(
                                    BookCoverWidget(
                                      book: b,
                                      width: 38,
                                      height: 54,
                                      heroTag: heroTag,
                                      onTap: () =>
                                          widget.actions.onOpenCover(b, heroTag),
                                    ),
                                    64,
                                    gridBorderColor,
                                    alignment: Alignment.center,
                                  ),
                                  _dataCell(
                                    Text(
                                      acc,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    112,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['title'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    220,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['author'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                                    160,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['publisher'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    150,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['isbn'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    130,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['category'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    130,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['shelf'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    100,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['publicationYear'] ?? ''}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    76,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Text(
                                      '${b['pageCount'] ?? ''}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    76,
                                    gridBorderColor,
                                  ),
                                  _dataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badge.bg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        badge.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: badge.fg,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    94,
                                    gridBorderColor,
                                    alignment: Alignment.center,
                                  ),
                                  _dataCell(
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          tooltip: availableCopies(b) > 0
                                              ? 'Ödünç ver'
                                              : 'İade al',
                                          visualDensity: VisualDensity.compact,
                                          icon: Icon(
                                            availableCopies(b) > 0
                                                ? Icons.outbound_outlined
                                                : Icons
                                                      .assignment_returned_outlined,
                                            size: 19,
                                            color: scheme.primary,
                                          ),
                                          onPressed: () {
                                            if (availableCopies(b) > 0) {
                                              widget.actions.onLoan(b);
                                            } else {
                                              widget.actions.onReturn(b);
                                            }
                                          },
                                        ),
                                        IconButton(
                                          tooltip: 'Düzenle',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                          onPressed: () =>
                                              widget.actions.onEdit(b),
                                        ),
                                      ],
                                    ),
                                    120,
                                    gridBorderColor,
                                    alignment: Alignment.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _LoanFilterMode { all, overdue, dueSoon, reserved }

/// Modernized Loans (`Ödünç`) Tab with horizontal management cards, KPI strip,
/// reminder message generator, quick +7 day extend, and rich loan cards.
class ModernLoansTabView extends StatefulWidget {
  const ModernLoansTabView({
    super.key,
    required this.visibleBooks,
    required this.overdueOnly,
    required this.busy,
    required this.onToggleOverdue,
    required this.onStudents,
    required this.onClassLoan,
    required this.onTextbooks,
    required this.onChampions,
    required this.onStudentCards,
    required this.onClassSummary,
    required this.onLoanSettings,
    required this.onGradeRules,
    required this.actions,
  });

  final List<Map<String, dynamic>> visibleBooks;
  final bool overdueOnly;
  final bool busy;
  final ValueChanged<bool> onToggleOverdue;
  final VoidCallback onStudents;
  final VoidCallback onClassLoan;
  final VoidCallback onTextbooks;
  final VoidCallback onChampions;
  final VoidCallback onStudentCards;
  final VoidCallback onClassSummary;
  final VoidCallback onLoanSettings;
  final VoidCallback onGradeRules;
  final BookActionCallbacks actions;

  @override
  State<ModernLoansTabView> createState() => _ModernLoansTabViewState();
}

class _ModernLoansTabViewState extends State<ModernLoansTabView> {
  late _LoanFilterMode _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.overdueOnly
        ? _LoanFilterMode.overdue
        : _LoanFilterMode.all;
  }

  @override
  void didUpdateWidget(covariant ModernLoansTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.overdueOnly != oldWidget.overdueOnly) {
      if (widget.overdueOnly) {
        _filter = _LoanFilterMode.overdue;
      } else if (_filter == _LoanFilterMode.overdue) {
        _filter = _LoanFilterMode.all;
      }
    }
  }

  bool _isDueSoon(Map<String, dynamic> loan, DateTime today) {
    if (isOverdue(loan, now: today)) return false;
    final due = DateTime.tryParse('${loan['due'] ?? ''}');
    if (due == null) return false;
    final diff = DateTime(due.year, due.month, due.day).difference(today).inDays;
    return diff >= 0 && diff <= 3;
  }

  String _loanDueStatusLabel(Map<String, dynamic> loan, DateTime today) {
    final due = DateTime.tryParse('${loan['due'] ?? ''}');
    if (due == null) return 'Süresiz';
    final dueDay = DateTime(due.year, due.month, due.day);
    final diff = dueDay.difference(today).inDays;
    if (diff < 0) return '${-diff} gün gecikti';
    if (diff == 0) return 'Bugün teslim';
    if (diff == 1) return 'Yarın teslim';
    return '$diff gün kaldı';
  }

  void _selectFilter(_LoanFilterMode mode) {
    setState(() => _filter = mode);
    if (mode == _LoanFilterMode.overdue) {
      if (!widget.overdueOnly) widget.onToggleOverdue(true);
    } else if (widget.overdueOnly) {
      widget.onToggleOverdue(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var totalLoans = 0;
    var overdueCount = 0;
    var dueSoonCount = 0;
    var reservedBooksCount = 0;

    for (final b in widget.visibleBooks) {
      final loans = activeLoans(b);
      totalLoans += loans.length;
      overdueCount += loans.where((l) => isOverdue(l, now: now)).length;
      dueSoonCount += loans.where((l) => _isDueSoon(l, today)).length;
      if (reservationsOf(b).any(isActiveReservation)) reservedBooksCount++;
    }

    final displayBooks = widget.visibleBooks.where((b) {
      final loans = activeLoans(b);
      switch (_filter) {
        case _LoanFilterMode.all:
          return loans.isNotEmpty;
        case _LoanFilterMode.overdue:
          return loans.any((l) => isOverdue(l, now: now));
        case _LoanFilterMode.dueSoon:
          return loans.any((l) => _isDueSoon(l, today));
        case _LoanFilterMode.reserved:
          return reservationsOf(b).any(isActiveReservation);
      }
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            children: [
              GradientActionCard(
                title: 'Öğrenciler',
                subtitle: 'Üye ve sınıf listesi',
                icon: Icons.people_alt_rounded,
                colors: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
                onTap: widget.busy ? null : widget.onStudents,
              ),
              const SizedBox(width: 10),
              GradientActionCard(
                title: 'Sınıfa Ödünç',
                subtitle: 'Toplu kitap dağıt',
                icon: Icons.group_add_rounded,
                colors: const [Color(0xFF059669), Color(0xFF10B981)],
                onTap: widget.busy ? null : widget.onClassLoan,
              ),
              const SizedBox(width: 10),
              GradientActionCard(
                title: 'Okuma Şampiyonu',
                subtitle: 'Sıralama ve belge',
                icon: Icons.emoji_events_rounded,
                colors: const [Color(0xFFD97706), Color(0xFFF59E0B)],
                onTap: widget.onChampions,
              ),
              const SizedBox(width: 10),
              GradientActionCard(
                title: 'Ders Kitapları',
                subtitle: 'Dağıtım ve Excel',
                icon: Icons.menu_book_rounded,
                colors: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
                onTap: widget.busy ? null : widget.onTextbooks,
              ),
              const SizedBox(width: 10),
              GradientActionCard(
                title: 'Öğrenci Kartları',
                subtitle: 'Barkodlu PDF kart',
                icon: Icons.badge_rounded,
                colors: const [Color(0xFF7C3AED), Color(0xFFA855F7)],
                onTap: widget.onStudentCards,
              ),
              const SizedBox(width: 10),
              GradientActionCard(
                title: 'Sınıf Özeti',
                subtitle: 'Etkin ve gecikenler',
                icon: Icons.analytics_outlined,
                colors: const [Color(0xFF0F766E), Color(0xFF14B8A6)],
                onTap: widget.onClassSummary,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                CompactStatChip(
                  icon: Icons.swap_horiz_rounded,
                  label: '$totalLoans aktif ödünç',
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                CompactStatChip(
                  icon: Icons.warning_amber_rounded,
                  label: '$overdueCount gecikmiş',
                  color: overdueCount > 0 ? scheme.error : Colors.green,
                ),
                const SizedBox(width: 6),
                CompactStatChip(
                  icon: Icons.schedule_rounded,
                  label: '$dueSoonCount yaklaşan',
                  color: Colors.amber.shade800,
                ),
                const SizedBox(width: 6),
                CompactStatChip(
                  icon: Icons.bookmark_added_rounded,
                  label: '$reservedBooksCount rezerveli',
                  color: scheme.tertiary,
                ),
                if (overdueCount > 0) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.sms_outlined,
                      size: 15,
                      color: scheme.error,
                    ),
                    label: const Text('Geciken Listeyi Kopyala'),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: buildBulkOverdueSummaryText(
                            widget.visibleBooks,
                            now: now,
                          ),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Geciken kitap özeti panoya kopyalandı.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tümü'),
                  selected: _filter == _LoanFilterMode.all,
                  onSelected: (_) => _selectFilter(_LoanFilterMode.all),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('Geciken ($overdueCount)'),
                  avatar: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: _filter == _LoanFilterMode.overdue
                        ? scheme.onErrorContainer
                        : scheme.error,
                  ),
                  selected: _filter == _LoanFilterMode.overdue,
                  onSelected: (_) => _selectFilter(_LoanFilterMode.overdue),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('Yaklaşan 3 Gün ($dueSoonCount)'),
                  selected: _filter == _LoanFilterMode.dueSoon,
                  onSelected: (_) => _selectFilter(_LoanFilterMode.dueSoon),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('Rezerveli ($reservedBooksCount)'),
                  selected: _filter == _LoanFilterMode.reserved,
                  onSelected: (_) => _selectFilter(_LoanFilterMode.reserved),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Ödünç Ayarları'),
                  onPressed: widget.busy ? null : widget.onLoanSettings,
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.rule_rounded, size: 16),
                  label: const Text('Kademe Kuralları'),
                  onPressed: widget.busy ? null : widget.onGradeRules,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: displayBooks.isEmpty
              ? EmptyCatalogArtwork(
                  title: _filter == _LoanFilterMode.overdue
                      ? 'Geciken ödünç bulunmuyor'
                      : _filter == _LoanFilterMode.dueSoon
                      ? 'Yaklaşan teslim bulunmuyor'
                      : _filter == _LoanFilterMode.reserved
                      ? 'Etkin rezervasyon bulunmuyor'
                      : 'Şu anda ödünçte kitap yok',
                  subtitle: _filter == _LoanFilterMode.overdue
                      ? 'Tüm ödünç kitapların teslim süresi devam ediyor.'
                      : 'Kitaplar sekmesinden veya Akıllı Banko\'dan ödünç/rezervasyon işlemi yapabilirsiniz.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
                  itemCount: displayBooks.length,
                  itemBuilder: (ctx, i) {
                    final b = displayBooks[i];
                    final loans = activeLoans(b);
                    final activeRes = reservationsOf(
                      b,
                    ).where(isActiveReservation).toList();
                    final hasOverdue = loans.any((l) => isOverdue(l, now: now));
                    final heroTag = 'loan-cover-${b['id']}';

                    return StaggeredFadeSlide(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BouncyTap(
                          onTap: () =>
                              showRichBookDetailSheet(ctx, b, widget.actions),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: hasOverdue
                                    ? scheme.error.withValues(alpha: 0.65)
                                    : scheme.outlineVariant.withValues(
                                        alpha: 0.45,
                                      ),
                                width: hasOverdue ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BookCoverWidget(
                                  book: b,
                                  width: 78,
                                  height: 114,
                                  heroTag: heroTag,
                                  onTap: () =>
                                      widget.actions.onOpenCover(b, heroTag),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${b['title'] ?? ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      for (final l in loans)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 5,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isOverdue(l, now: now)
                                                    ? Icons.error_outline
                                                    : Icons.person_outline,
                                                size: 15,
                                                color: isOverdue(l, now: now)
                                                    ? scheme.error
                                                    : scheme.primary,
                                              ),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Builder(
                                                  builder: (_) {
                                                    final cls =
                                                        '${l['studentClass'] ?? ''}'
                                                            .trim();
                                                    final statusLabel =
                                                        _loanDueStatusLabel(
                                                          l,
                                                          today,
                                                        );
                                                    final overdue = isOverdue(
                                                      l,
                                                      now: now,
                                                    );
                                                    return Text(
                                                      '${l['name']}${cls.isEmpty ? '' : ' ($cls)'} · $statusLabel',
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        fontWeight: overdue
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: overdue
                                                            ? scheme.error
                                                            : null,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                onTap: () {
                                                  Clipboard.setData(
                                                    ClipboardData(
                                                      text:
                                                          buildOverdueReminderMessage(
                                                            b,
                                                            l,
                                                            now: now,
                                                          ),
                                                    ),
                                                  );
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        '${l['name']} için hatırlatma mesajı kopyalandı.',
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: Icon(
                                                    Icons.sms_outlined,
                                                    size: 16,
                                                    color: scheme.primary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (activeRes.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Text(
                                            'Rezervasyon sırası: ${activeRes.map((r) => '${r['name']}').join(', ')}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.tertiary,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          if (loans.isNotEmpty)
                                            SizedBox(
                                              height: 32,
                                              child: FilledButton.tonalIcon(
                                                style: FilledButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () =>
                                                    widget.actions.onReturn(b),
                                                icon: const Icon(
                                                  Icons
                                                      .assignment_returned_rounded,
                                                  size: 15,
                                                ),
                                                label: const Text(
                                                  'İade Al',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (loans.isNotEmpty)
                                            SizedBox(
                                              height: 32,
                                              child: OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () =>
                                                    widget.actions.onExtend(b),
                                                icon: const Icon(
                                                  Icons.update_rounded,
                                                  size: 15,
                                                ),
                                                label: const Text(
                                                  'Süre Uzat',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (loans.length == 1 &&
                                              widget.actions.onQuickExtend !=
                                                  null)
                                            SizedBox(
                                              height: 32,
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () => widget
                                                    .actions
                                                    .onQuickExtend!(
                                                  b,
                                                  '${loans.first['id']}',
                                                ),
                                                child: const Text(
                                                  '+7 Gün',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (activeRes.isNotEmpty)
                                            SizedBox(
                                              height: 32,
                                              child: OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                      ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                                onPressed: () => widget.actions
                                                    .onReservations(b),
                                                icon: const Icon(
                                                  Icons.bookmark_added_outlined,
                                                  size: 15,
                                                ),
                                                label: const Text(
                                                  'Sıra',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

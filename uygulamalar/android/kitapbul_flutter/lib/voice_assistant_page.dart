import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_proxy_service.dart';
import 'app_theme_settings.dart';
import 'book_lookup.dart';
import 'book_visuals.dart';
import 'catalog_search.dart' show foldTurkish;
import 'cover_fetch.dart';
import 'inventory_session.dart' show inventoryBookPlace;
import 'isbn.dart';
import 'loan_model.dart';
import 'school_automation_hub.dart' show findHighestAccessionNumber;
import 'school_duty_roster.dart';
import 'student_store.dart';

class VoiceBookDraft {
  const VoiceBookDraft({
    required this.title,
    this.author = '',
    this.publisher = '',
    this.isbn = '',
    this.shelf = '',
    this.category = '',
    this.quantity = 1,
  });

  final String title;
  final String author;
  final String publisher;
  final String isbn;
  final String shelf;
  final String category;
  final int quantity;
}

class LibraryRagPacket {
  const LibraryRagPacket({
    required this.contextPrompt,
    required this.matchedBooks,
    required this.offlineAnswer,
    this.detectedBookDraft,
  });

  final String contextPrompt;
  final List<Map<String, dynamic>> matchedBooks;
  final String offlineAnswer;
  final VoiceBookDraft? detectedBookDraft;
}

String _asciiFoldTr(String value) => foldTurkish(value)
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ı', 'i')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('û', 'u');

/// Sesli veya yazılı "Kitap ekle: Çalıkuşu, Reşat Nuri Güntekin, Dolap B" kalıbını ayrıştırır.
VoiceBookDraft? parseVoiceAddBookIntent(String rawQuery) {
  final trimmed = rawQuery.trim();
  final folded = _asciiFoldTr(trimmed);
  final prefixMatch = RegExp(
    r'^(?:sesle\s+)?(?:yeni\s+)?kitap\s+(?:ekle|kaydet|gir)\s*[:\-]?\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);

  String? payload;
  if (prefixMatch != null) {
    payload = prefixMatch.group(1)?.trim();
  } else if (folded.startsWith('kitap ekle ')) {
    payload = trimmed.substring('kitap ekle '.length).trim();
  }
  if (payload == null || payload.isEmpty) return null;

  final parts = payload
      .split(RegExp(r'[,;·\-]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  String title = parts.first;
  String author = '';
  String shelf = '';
  String publisher = '';
  int qty = 1;

  for (final seg in parts.skip(1)) {
    final f = _asciiFoldTr(seg);
    if (f.startsWith('dolap') || f.startsWith('raf')) {
      shelf = seg;
    } else if (RegExp(r'^(\d+)\s*(?:adet|nusha|kopya)$').hasMatch(f)) {
      final m = RegExp(r'(\d+)').firstMatch(f);
      if (m != null) qty = (int.tryParse(m.group(1)!) ?? 1).clamp(1, 50);
    } else if (f.contains('yayin') || f.contains('kitabevi')) {
      publisher = seg;
    } else if (author.isEmpty) {
      author = seg;
    } else if (publisher.isEmpty) {
      publisher = seg;
    }
  }

  return VoiceBookDraft(
    title: title,
    author: author,
    publisher: publisher,
    shelf: shelf,
    quantity: qty,
  );
}

bool _isLoanOverdueNow(Map<String, dynamic> loan, DateTime today) {
  final rawDue = loan['due']?.toString() ?? '';
  final dt = DateTime.tryParse(rawDue);
  if (dt == null) return false;
  final dueDate = DateTime(dt.year, dt.month, dt.day);
  final todayDate = DateTime(today.year, today.month, today.day);
  return dueDate.isBefore(todayDate);
}

/// 2.892+ kitaplık katalog, ödünçler, öğrenciler ve nöbet çizelgesinden
/// hem CLIProxy Gemini RAG bağlamını hem de çevrimdışı akıllı Türkçe yanıtı üretir.
LibraryRagPacket buildLibraryRagContext(
  String query,
  List<Map<String, dynamic>> books,
  List<Student> students,
  SchoolDutyRoster dutyRoster, {
  DateTime? now,
}) {
  final currentNow = now ?? DateTime.now();
  final activeBooks = books
      .where((b) => b['deletedAt'] == null && b['isWithdrawn'] != true)
      .toList();

  var totalCopies = 0;
  var activeLoanCount = 0;
  final overdueRecords = <String>[];
  final activeLoanRecords = <String>[];
  final shelfCounts = <String, int>{};

  for (final b in activeBooks) {
    final qty = (b['quantity'] as int?) ?? 1;
    totalCopies += qty;
    final place = inventoryBookPlace(b).trim();
    if (place.isNotEmpty) {
      shelfCounts[place] = (shelfCounts[place] ?? 0) + qty;
    }
    for (final loan in activeLoans(b)) {
      activeLoanCount++;
      final borrower = (loan['name'] ?? 'Bilinmeyen').toString();
      final sClass = (loan['studentClass'] ?? '').toString();
      final due = (loan['due'] ?? '').toString().split('T').first;
      final summary =
          '${b['title']} -> $borrower${sClass.isEmpty ? '' : ' ($sClass)'}${due.isEmpty ? '' : ' [Son gün: $due]'}';
      if (_isLoanOverdueNow(loan, currentNow)) {
        overdueRecords.add(summary);
      } else {
        activeLoanRecords.add(summary);
      }
    }
  }

  // Bugünün nöbetçileri
  final weekday = currentNow.weekday;
  final todayName = weekdayNamesTr[weekday] ?? 'Hafta Sonu';
  final todayDuties = dutyRoster.forWeekday(weekday);

  // Sorgu kelimeleriyle en alakalı 15 kitabı puanla
  final stopWords = <String>{
    'kitap',
    'kitaplari',
    'kitabi',
    'hangi',
    'nerede',
    'dolapta',
    'dolap',
    'rafta',
    'var',
    'mi',
    'kac',
    'tane',
    'adet',
    'bana',
    'soyle',
    'bul',
    'ara',
    'kutuphanede',
  };
  final qFolded = _asciiFoldTr(query)
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final qTokens = qFolded
      .split(' ')
      .where((t) => t.length >= 2 && !stopWords.contains(t))
      .toList();

  final scored = <({Map<String, dynamic> book, int score})>[];
  if (qTokens.isNotEmpty) {
    for (final b in activeBooks) {
      final titleF = _asciiFoldTr((b['title'] ?? '').toString());
      final authorF = _asciiFoldTr((b['author'] ?? '').toString());
      final pubF = _asciiFoldTr((b['publisher'] ?? '').toString());
      final catF = _asciiFoldTr((b['category'] ?? '').toString());
      final shelfF = _asciiFoldTr(inventoryBookPlace(b));
      final accF = _asciiFoldTr((b['accessionCode'] ?? '').toString());
      final isbnF = (b['isbn'] ?? '').toString();

      var sc = 0;
      if (qFolded.length >= 4 && titleF.contains(qFolded)) sc += 30;
      if (qFolded.length >= 4 && authorF.contains(qFolded)) sc += 28;
      for (final tok in qTokens) {
        if (titleF.contains(tok)) sc += 10;
        if (authorF.contains(tok)) sc += 11;
        if (catF.contains(tok)) sc += 5;
        if (pubF.contains(tok)) sc += 4;
        if (shelfF == tok || shelfF.contains(tok)) sc += 6;
        if (accF.contains(tok) || isbnF.contains(tok)) sc += 15;
      }
      if (sc > 0) scored.add((book: b, score: sc));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
  }

  final topBooks = scored.take(15).map((e) => e.book).toList();
  final draft = parseVoiceAddBookIntent(query);

  // Üst dolapların özeti
  final sortedShelves = shelfCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final shelfSummary = sortedShelves
      .take(16)
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');

  final buf = StringBuffer()
    ..writeln('=== CUMHURİYET ANADOLU LİSESİ KÜTÜPHANESİ CANLI VERİTABANI ===')
    ..writeln(
      'Toplam Çeşit: ${activeBooks.length} kitap | Toplam Fiziksel Nüsha: $totalCopies | Kayıtlı Öğrenci: ${students.length}',
    )
    ..writeln(
      'Aktif Ödünç: $activeLoanCount | Geciken Ödünç: ${overdueRecords.length}',
    )
    ..writeln('Dolap Dağılımı: $shelfSummary')
    ..writeln(
      'Bugün ($todayName) Nöbetçi Öğrenciler: ${todayDuties.isEmpty ? "Bugün nöbet kaydı yok" : todayDuties.map((d) => "${d.name} (${d.className}, No:${d.number})").join(", ")}',
    );

  if (overdueRecords.isNotEmpty) {
    buf.writeln('Geciken Ödünçler (İlk 12):');
    for (final r in overdueRecords.take(12)) {
      buf.writeln(' - $r');
    }
  } else if (activeLoanRecords.isNotEmpty) {
    buf.writeln('Aktif Ödünçler (İlk 8):');
    for (final r in activeLoanRecords.take(8)) {
      buf.writeln(' - $r');
    }
  }

  if (topBooks.isNotEmpty) {
    buf.writeln('Sorguyla Eşleşen Katalog Kayıtları:');
    for (final b in topBooks) {
      final place = inventoryBookPlace(b);
      final avail = physicalAvailableCopies(b);
      final qty = (b['quantity'] as int?) ?? 1;
      final acc = (b['accessionCode'] ?? '').toString();
      buf.writeln(
        ' * "${b['title']}" — Yazar: ${b['author'] ?? '-'} | Dolap/Raf: ${place.isEmpty ? 'Belirtilmemiş' : place} | Rafta: $avail/$qty | Demirbaş: ${acc.isEmpty ? '-' : acc}',
      );
    }
  }

  // Çevrimdışı / yerel akıllı yanıt oluştur
  String offline;
  if (draft != null) {
    offline =
        '"${draft.title}"${draft.author.isEmpty ? '' : ' (${draft.author})'} kitabını kataloğa eklemek üzere hazırladım. Aşağıdaki karttan tek dokunuşla kaydedebilirsiniz.';
  } else if (qFolded.contains('nobetci') || qFolded.contains('nobet')) {
    if (todayDuties.isEmpty) {
      offline =
          'Bugün ($todayName) için tanımlı nöbetçi öğrenci bulunmuyor. Hafta içi nöbet çizelgesinden tüm günleri görebilirsiniz.';
    } else {
      final names = todayDuties
          .map((d) => '${d.className} sınıfından ${d.name}')
          .join(' ve ');
      offline = 'Bugün $todayName nöbetçi öğrencilerimiz: $names.';
    }
  } else if (qFolded.contains('gecik') || qFolded.contains('iade')) {
    if (overdueRecords.isEmpty) {
      offline =
          'Harika haber! Şu anda kütüphanede teslim tarihi gecikmiş hiçbir ödünç kitap yok. Toplam $activeLoanCount aktif ödünç bulunuyor.';
    } else {
      offline =
          'Şu anda teslim süresi gecikmiş ${overdueRecords.length} kitap var: ${overdueRecords.take(4).join('; ')}.';
    }
  } else if (qFolded.contains('kac kitap') ||
      qFolded.contains('toplam kitap') ||
      qFolded.contains('istatistik') ||
      qFolded.contains('ozet')) {
    offline =
        'Kütüphanemizde ${activeBooks.length} farklı başlıkta toplam $totalCopies nüsha kitap, ${students.length} kayıtlı öğrenci ve $activeLoanCount aktif ödünç bulunuyor.';
  } else if (topBooks.isNotEmpty) {
    final first = topBooks.first;
    final place = inventoryBookPlace(first);
    final avail = physicalAvailableCopies(first);
    if (topBooks.length == 1) {
      offline =
          '"${first['title']}" (${first['author'] ?? ''}) kitabı ${place.isEmpty ? 'katalogda kayıtlı' : '$place konumunda kayıtlı'}. Şu anda rafta $avail adet mevcut.';
    } else {
      final sample = topBooks
          .take(4)
          .map((b) {
            final p = inventoryBookPlace(b);
            return '${b['title']}${p.isEmpty ? '' : ' ($p)'}';
          })
          .join(', ');
      offline =
          'Sorgunuzla eşleşen ${topBooks.length} kitap buldum: $sample.';
    }
  } else {
    offline =
        'Katalogda "${query.trim()}" ile doğrudan eşleşen bir kayıt bulamadım. Toplam ${activeBooks.length} kitabımız arasında yazar, kitap adı, dolap harfi veya nöbet/ödünç durumu sorabilirsiniz.';
  }

  return LibraryRagPacket(
    contextPrompt: buf.toString(),
    matchedBooks: topBooks.take(8).toList(),
    offlineAnswer: offline,
    detectedBookDraft: draft,
  );
}

class _AssistantChatItem {
  _AssistantChatItem({
    required this.isUser,
    required this.text,
    this.sourceLabel = '',
    this.matchedBooks = const [],
    this.bookDraft,
  });

  final bool isUser;
  final String text;
  final String sourceLabel;
  final List<Map<String, dynamic>> matchedBooks;
  final VoiceBookDraft? bookDraft;
  bool bookSaved = false;
}

class VoiceLibraryAssistantPage extends StatefulWidget {
  const VoiceLibraryAssistantPage({
    super.key,
    required this.initialBooks,
    required this.students,
    required this.dutyRoster,
    required this.onSaveBooks,
  });

  final List<Map<String, dynamic>> initialBooks;
  final List<Student> students;
  final SchoolDutyRoster dutyRoster;
  final Future<void> Function(List<Map<String, dynamic>> updated) onSaveBooks;

  @override
  State<VoiceLibraryAssistantPage> createState() =>
      _VoiceLibraryAssistantPageState();
}

class _VoiceLibraryAssistantPageState extends State<VoiceLibraryAssistantPage> {
  late List<Map<String, dynamic>> _books = List.of(widget.initialBooks);
  final List<_AssistantChatItem> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  StreamSubscription<VoiceEvent>? _voiceSub;
  bool _listening = false;
  bool _speaking = false;
  bool _thinking = false;
  double _rmsLevel = 0.0;
  String _livePartialText = '';

  static const _quickPrompts = <String>[
    'Sabahattin Ali kitapları hangi dolapta?',
    'Geciken ödünç kitapları söyle',
    'Bugün nöbetçi öğrenciler kim?',
    'Kütüphanede toplam kaç kitap var?',
    '9. sınıf öğrencisine sürükleyici roman öner',
    'Kitap ekle: Çalıkuşu, Reşat Nuri Güntekin, Dolap B',
  ];

  @override
  void initState() {
    super.initState();
    _messages.add(
      _AssistantChatItem(
        isUser: false,
        text:
            'Merhaba! Ben Cumhuriyet Kütüphanesi Sesli Yapay Zekâ Asistanıyım. Mikrofona dokunup kitapların hangi dolapta olduğunu, geciken ödünçleri, nöbetçi öğrencileri sorabilir veya sesle yeni kitap ekleyebilirsiniz.',
        sourceLabel: 'Hazır',
      ),
    );
    _voiceSub = NativeVoiceController.instance.events.listen(_onVoiceEvent);
  }

  @override
  void dispose() {
    _voiceSub?.cancel();
    NativeVoiceController.instance.cancelListening();
    NativeVoiceController.instance.stopSpeaking();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onVoiceEvent(VoiceEvent ev) {
    if (!mounted) return;
    switch (ev.type) {
      case 'ready':
        setState(() {
          _listening = true;
          _livePartialText = '';
        });
      case 'rms':
        setState(() {
          _rmsLevel = ((ev.value + 2.0) / 12.0).clamp(0.05, 1.0);
        });
      case 'partial':
        setState(() => _livePartialText = ev.text);
      case 'final':
        setState(() {
          _listening = false;
          _rmsLevel = 0;
          _livePartialText = '';
        });
        if (ev.text.trim().isNotEmpty) {
          _submitQuery(ev.text.trim(), fromVoice: true);
        }
      case 'error':
        setState(() {
          _listening = false;
          _rmsLevel = 0;
        });
        if (ev.text != 'no_match' && ev.text != 'speech_timeout') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ses tanıma uyarısı: ${ev.text}')),
          );
        }
      case 'ttsStart':
        setState(() => _speaking = true);
      case 'ttsDone':
        setState(() => _speaking = false);
        if (aiSettingsNotifier.value.handsFreeLoop &&
            !_thinking &&
            !_listening) {
          Future<void>.delayed(const Duration(milliseconds: 350), () {
            if (mounted && !_thinking && !_listening) {
              _toggleMic();
            }
          });
        }
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await NativeVoiceController.instance.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (_speaking) {
      await NativeVoiceController.instance.stopSpeaking();
      if (mounted) setState(() => _speaking = false);
    }
    try {
      final started = await NativeVoiceController.instance.startListening(
        locale: 'tr-TR',
      );
      if (started && mounted) {
        setState(() {
          _listening = true;
          _livePartialText = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mikrofon başlatılamadı: $e')),
        );
      }
    }
  }

  Future<void> _submitQuery(String rawText, {bool fromVoice = false}) async {
    final query = rawText.trim();
    if (query.isEmpty || _thinking) return;
    _inputCtrl.clear();

    setState(() {
      _thinking = true;
      _messages.add(_AssistantChatItem(isUser: true, text: query));
    });
    _scrollToBottom();

    final rag = buildLibraryRagContext(
      query,
      _books,
      widget.students,
      widget.dutyRoster,
    );

    String replyText = rag.offlineAnswer;
    String badge = 'Yerel Akıllı Katalog Yanıtı';
    VoiceBookDraft? draft = rag.detectedBookDraft;

    try {
      const sysPrompt = '''
Sen Cumhuriyet Anadolu Lisesi Kütüphanesi'nin Türkçe konuşan akıllı sesli kütüphane asistanısın.
Sana verilen CANLI VERİTABANI özetini kullanarak kullanıcının sorusunu doğal, net, samimi ve sesli okunmaya uygun kısa-orta uzunlukta yanıtla.
Yalnızca geçerli bir JSON nesnesi döndür:
{
  "spoken_reply": "Kullanıcıya sesli okunacak ve ekranda gösterilecek Türkçe yanıt.",
  "action": "NONE veya ADD_BOOK",
  "book": {
    "title": "",
    "author": "",
    "publisher": "",
    "shelf": "",
    "category": "",
    "quantity": 1
  }
}
Kurallar:
1. Kullanıcı yeni bir kitap eklemek/kaydetmek istiyorsa "action": "ADD_BOOK" yap ve "book" alanlarını doldur. Diğer tüm sorularda "action": "NONE" bırak.
2. Kitapların dolap/raf bilgisini ve rafta kaç adet bulunduğunu doğru söyle.
3. Yanıtlarında markdown yıldızları kullanma ki Türkçe seslendirme (TTS) pürüzsüz okusun.
''';
      final decoded = await AiProxyClient.generateStructuredJson(
        systemPrompt: sysPrompt,
        userPrompt: '${rag.contextPrompt}\n\nKULLANICI SORUSU: $query',
        timeout: const Duration(seconds: 35),
      );
      if (decoded is Map) {
        final spoken = (decoded['spoken_reply'] ?? decoded['reply'] ?? '')
            .toString()
            .trim();
        if (spoken.isNotEmpty) {
          replyText = spoken;
          badge =
              '${aiSettingsNotifier.value.mode.title} · ${aiSettingsNotifier.value.assistantModel}';
        }
        final action = (decoded['action'] ?? '').toString().toUpperCase();
        if (action == 'ADD_BOOK' && decoded['book'] is Map) {
          final bMap = decoded['book'] as Map;
          final bTitle = (bMap['title'] ?? '').toString().trim();
          if (bTitle.isNotEmpty) {
            draft = VoiceBookDraft(
              title: bTitle,
              author: (bMap['author'] ?? '').toString().trim(),
              publisher: (bMap['publisher'] ?? '').toString().trim(),
              shelf: (bMap['shelf'] ?? '').toString().trim(),
              category: (bMap['category'] ?? '').toString().trim(),
              quantity:
                  ((bMap['quantity'] as num?)?.toInt() ?? 1).clamp(1, 50),
            );
          }
        }
      }
    } catch (_) {
      // CLIProxy anahtarı henüz girilmemişse veya çevrimdışıysa yerel RAG yanıtı anında devreye girer!
    }

    if (!mounted) return;
    setState(() {
      _thinking = false;
      _messages.add(
        _AssistantChatItem(
          isUser: false,
          text: replyText,
          sourceLabel: badge,
          matchedBooks: rag.matchedBooks,
          bookDraft: draft,
        ),
      );
    });
    _scrollToBottom();

    if (aiSettingsNotifier.value.voiceAutoSpeak || fromVoice) {
      await NativeVoiceController.instance.speak(replyText);
    }
  }

  Future<void> _confirmSaveVoiceBook(_AssistantChatItem msg) async {
    final draft = msg.bookDraft;
    if (draft == null || msg.bookSaved) return;

    setState(() => _thinking = true);
    try {
      Map<String, String>? online;
      String? coverRef;
      try {
        online = await lookupKitapyurduFirstMatch(
          title: draft.title,
          author: draft.author,
          publisher: draft.publisher,
        );
        final foundIsbn = canonicalIsbn(online?['isbn'] ?? draft.isbn);
        final coverUrl = (online?['coverUrl'] ?? '').trim();
        if (coverUrl.isNotEmpty) {
          final dl = await fetchCoverBytesFromUrl(coverUrl);
          if (dl != null) coverRef = storeCoverBytes(dl);
        }
        if (coverRef == null && foundIsbn != null) {
          final dl = await fetchBestCover(foundIsbn);
          if (dl != null) coverRef = storeCoverBytes(dl.bytes);
        }
      } catch (_) {}

      final cfg = appThemeNotifier.value;
      var nextAcc =
          findHighestAccessionNumber(_books, prefix: cfg.accessionPrefix) + 1;
      final codes = <String>[
        for (var i = 0; i < draft.quantity; i++)
          '${cfg.accessionPrefix}${(nextAcc++).toString().padLeft(cfg.accessionDigits, '0')}',
      ];

      String pick(String v, String k) =>
          v.trim().isNotEmpty ? v.trim() : (online?[k] ?? '').trim();

      final created = normalizeBook({
        'id': 'voice-${DateTime.now().microsecondsSinceEpoch}',
        'title': pick(draft.title, 'title'),
        'author': pick(draft.author, 'author'),
        'publisher': pick(draft.publisher, 'publisher'),
        'isbn': canonicalIsbn(pick(draft.isbn, 'isbn')) ?? '',
        'category': pick(draft.category, 'category'),
        'publicationYear': (online?['publicationYear'] ?? '').trim(),
        'pageCount': (online?['pageCount'] ?? '').trim(),
        'language': 'Türkçe',
        'shelf': draft.shelf.trim(),
        'accessionCode': codes.join('; '),
        'quantity': draft.quantity,
        'coverBase64': coverRef,
        'loans': <Map<String, dynamic>>[],
      });

      final updated = [..._books, created];
      await widget.onSaveBooks(updated);
      if (!mounted) return;
      setState(() {
        _books = updated;
        msg.bookSaved = true;
        _thinking = false;
      });

      final confirmSpeech =
          '${created['title']} kitabı ${codes.first} demirbaş koduyla kataloğa kaydedildi.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(confirmSpeech)),
      );
      if (aiSettingsNotifier.value.voiceAutoSpeak) {
        await NativeVoiceController.instance.speak(confirmSpeech);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _thinking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kitap kaydedilemedi: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesli Yapay Zekâ Asistanı'),
        actions: [
          if (_speaking)
            IconButton(
              tooltip: 'Okumayı durdur',
              onPressed: () => NativeVoiceController.instance.stopSpeaking(),
              icon: const Icon(Icons.volume_off_rounded),
            ),
          IconButton(
            tooltip: 'CLIProxyAPI & Ses Ayarları',
            onPressed: () => showAiProxySettingsSheet(context),
            icon: const Icon(Icons.hub_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // Üst Görsel + Ses Dalgası Küresi
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  SizedBox(
                    height: 124,
                    width: double.infinity,
                    child: Image.asset(
                      'assets/images/voice_assistant_banner.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.80),
                            Colors.black.withValues(alpha: 0.42),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ValueListenableBuilder<AiProxySettings>(
                                  valueListenable: aiSettingsNotifier,
                                  builder: (_, cfg, _) => Text(
                                    '${cfg.mode.title} · ${cfg.assistantModel}',
                                    style: const TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _listening
                                      ? (_livePartialText.isEmpty
                                            ? 'Sizi dinliyorum, Türkçe konuşun...'
                                            : '“$_livePartialText”')
                                      : (_speaking
                                            ? 'Asistan sesli yanıtlıyor...'
                                            : 'Mikrofona dokunun ve kütüphaneye sorun'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_books.where((b) => b['deletedAt'] == null).length} kitap · ${widget.students.length} öğrenci canlı bağlı',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: _toggleMic,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: _listening ? 68 + (_rmsLevel * 16) : 64,
                              height: _listening ? 68 + (_rmsLevel * 16) : 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: _listening
                                      ? [Colors.redAccent, Colors.deepOrange]
                                      : [scheme.primary, Colors.teal],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_listening
                                            ? Colors.redAccent
                                            : Colors.cyanAccent)
                                        .withValues(alpha: 0.55),
                                    blurRadius: _listening ? 22 : 12,
                                    spreadRadius: _listening ? 3 : 1,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _listening
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Hazır Sesli Komut Önerileri
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _quickPrompts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.record_voice_over_rounded, size: 15),
                label: Text(
                  _quickPrompts[i],
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: _thinking
                    ? null
                    : () => _submitQuery(_quickPrompts[i]),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Sohbet Akışı
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: _messages.length + (_thinking ? 1 : 0),
              itemBuilder: (_, idx) {
                if (idx == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                          SizedBox(width: 10),
                          Text('Katalog ve CLIProxy sorgulanıyor...'),
                        ],
                      ),
                    ),
                  );
                }
                return _buildChatBubble(_messages[idx]);
              },
            ),
          ),

          // Alt Yazı + Mikrofon Çubuğu
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: _listening ? 'Dinlemeyi durdur' : 'Sesle konuş',
                    onPressed: _toggleMic,
                    icon: Icon(
                      _listening ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: _listening ? Colors.redAccent : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _submitQuery(v),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Sorunuzu yazın veya mikrofona konuşun...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Gönder',
                    onPressed: _thinking
                        ? null
                        : () => _submitQuery(_inputCtrl.text),
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(_AssistantChatItem msg) {
    final scheme = Theme.of(context).colorScheme;
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.text,
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 24),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    msg.sourceLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => NativeVoiceController.instance.speak(msg.text),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.volume_up_rounded, size: 16),
                        SizedBox(width: 3),
                        Text('Dinle', style: TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(msg.text, style: const TextStyle(height: 1.38)),

            // Eşleşen Katalog Kitap Kartları
            if (msg.matchedBooks.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: msg.matchedBooks.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final b = msg.matchedBooks[i];
                    final place = inventoryBookPlace(b);
                    final avail = physicalAvailableCopies(b);
                    return Container(
                      width: 225,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          BookCoverWidget(book: b, width: 44, height: 68),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  (b['title'] ?? '').toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${place.isEmpty ? 'Raf yok' : place} · Rafta: $avail',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            // Sesle Kitap Ekleme Eylem Kartı
            if (msg.bookDraft != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesli Kitap Kayıt Taslağı: ${msg.bookDraft!.title}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      [
                        if (msg.bookDraft!.author.isNotEmpty)
                          'Yazar: ${msg.bookDraft!.author}',
                        if (msg.bookDraft!.shelf.isNotEmpty)
                          'Konum: ${msg.bookDraft!.shelf}',
                        'Adet: ${msg.bookDraft!.quantity}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: msg.bookSaved || _thinking
                            ? null
                            : () => _confirmSaveVoiceBook(msg),
                        icon: Icon(
                          msg.bookSaved
                              ? Icons.check_circle_rounded
                              : Icons.add_task_rounded,
                        ),
                        label: Text(
                          msg.bookSaved
                              ? 'Kataloğa Kaydedildi'
                              : 'Amazon/Kitapyurdu Kapağı + CAL Koduyla Kaydet',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

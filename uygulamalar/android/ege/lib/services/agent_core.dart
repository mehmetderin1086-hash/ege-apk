import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/jarvis_models.dart';
import 'local_command_engine.dart';

/// Ege 4.0 ajan çekirdeği — Nous Research "Hermes Agent" mimarisinin
/// telefona uyarlanmış hâli: kişilik (SOUL), iki parçalı hafıza
/// (MEMORY/USER), kendi yazdığı beceriler (SKILL.md), zamanlanmış görevler
/// (cron), oturum arama, görev listesi ve araç günlüğü.

// ================================================================ BECERİLER

class AgentSkill {
  final String name;
  final String description;
  final String version;
  final String category;
  final List<String> tags;
  final String body;
  final bool builtIn;
  final DateTime updatedAt;
  final int uses;

  const AgentSkill({
    required this.name,
    required this.description,
    this.version = '1.0.0',
    this.category = 'genel',
    this.tags = const [],
    required this.body,
    this.builtIn = false,
    required this.updatedAt,
    this.uses = 0,
  });

  static String slug(String raw) {
    const map = {'ı': 'i', 'ğ': 'g', 'ü': 'u', 'ş': 's', 'ö': 'o', 'ç': 'c', 'â': 'a', 'î': 'i', 'û': 'u'};
    final low = LocalCommandEngine.normalizeTr(raw).split('').map((ch) => map[ch] ?? ch).join();
    final s = low
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return s.length > 48 ? s.substring(0, 48) : s;
  }

  /// SKILL.md (YAML ön bilgi + Markdown gövde).
  String toMarkdown() {
    final b = StringBuffer('---\n')
      ..writeln('name: $name')
      ..writeln('description: ${description.replaceAll('\n', ' ')}')
      ..writeln('version: $version')
      ..writeln('metadata:')
      ..writeln('  hermes:')
      ..writeln('    category: $category')
      ..writeln('    tags: [${tags.join(', ')}]')
      ..writeln('---')
      ..writeln()
      ..write(body.trim());
    return b.toString();
  }

  static AgentSkill? parse(String md, {bool builtIn = false, DateTime? updatedAt, int uses = 0}) {
    final m = RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n?([\s\S]*)$').firstMatch(md.trim());
    if (m == null) return null;
    final front = m.group(1)!;
    String? field(String k) =>
        RegExp('^\\s*$k:\\s*(.+)\$', multiLine: true).firstMatch(front)?.group(1)?.trim();
    final name = slug(field('name') ?? '');
    final desc = field('description') ?? '';
    if (name.isEmpty || desc.isEmpty) return null;
    final tagsRaw = field('tags') ?? '';
    return AgentSkill(
      name: name,
      description: desc,
      version: field('version') ?? '1.0.0',
      category: field('category') ?? 'genel',
      tags: tagsRaw
          .replaceAll(RegExp(r'[\[\]]'), '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      body: m.group(2)!.trim(),
      builtIn: builtIn,
      updatedAt: updatedAt ?? DateTime.now(),
      uses: uses,
    );
  }

  AgentSkill copyWith({String? description, String? body, String? version, int? uses, DateTime? updatedAt}) =>
      AgentSkill(
        name: name,
        description: description ?? this.description,
        version: version ?? this.version,
        category: category,
        tags: tags,
        body: body ?? this.body,
        builtIn: builtIn,
        updatedAt: updatedAt ?? this.updatedAt,
        uses: uses ?? this.uses,
      );

  /// "1.2.3" → "1.2.4"
  static String bump(String v) {
    final p = v.split('.');
    final last = int.tryParse(p.isNotEmpty ? p.last : '0') ?? 0;
    return [...p.take(p.length - 1), '${last + 1}'].join('.');
  }
}

class SkillStore {
  static const _key = 'jarvis.agent.skills.v1';
  static const maxSkills = 60;
  static const maxBody = 6000;

  final Map<String, AgentSkill> skills = {};

  static final List<AgentSkill> seeds = [
    AgentSkill.parse('''---
name: biyoloji-ders-plani
description: MEB müfredatına uygun biyoloji ders planı (kazanım, süre, etkinlik, ölçme) hazırlar
version: 1.0.0
metadata:
  hermes:
    category: egitim
    tags: [biyoloji, ders, meb]
---
## Ne zaman
Kullanıcı bir biyoloji konusu için ders planı, etkinlik ya da sunum akışı isterse.

## Yöntem
1. Sınıf düzeyini ve konuyu netleştir (eksikse tek soru sor).
2. İlgili MEB kazanımlarını yaz (emin değilsen "doğrulanmalı" diye belirt; gerekirse web_search ile kontrol et).
3. 40 dk'lık blok: giriş/dikkat çekme (5), keşif etkinliği (15), açıklama (10), değerlendirme (10).
4. Günlük hayatla bağ, kavram yanılgıları ve 3 değerlendirme sorusu ekle.
5. İstenirse start_work kind=word ile Word belgesi üret.

## Doğrulama
Kazanım kodları ve terimler Türkçe ders kitabıyla uyumlu olmalı; Campbell/Guyton'dan bilgi kullanıldıysa sınıf düzeyine sadeleştir.''', builtIn: true)!,
    AgentSkill.parse('''---
name: sinav-sorusu-hazirla
description: Kazanıma bağlı, cevap anahtarlı ve çeldiricileri gerekçeli çoktan seçmeli soru hazırlar
version: 1.0.0
metadata:
  hermes:
    category: egitim
    tags: [sinav, soru, olcme]
---
## Yöntem
1. Konu, sınıf, soru sayısı ve zorluk dağılımını belirle.
2. Her soru: kök (tek doğru cevaplı, olumsuz kök az), 5 şık, doğru cevap, her çeldiricinin neden yanlış olduğu.
3. Bloom düzeylerini karıştır (hatırlama ≤ %30).
4. Sonda cevap anahtarı tablosu ver; istenirse start_work kind=pdf ile PDF üret.

## Tuzaklar
"Hepsi/hiçbiri" şıklarından kaçın; şık uzunlukları dengeli olsun.''', builtIn: true)!,
    AgentSkill.parse('''---
name: gunluk-plan
description: Takvim, hatırlatıcılar ve hava durumuna bakıp günün ilk 3 önceliğini ve zaman planını çıkarır
version: 1.0.0
metadata:
  hermes:
    category: verimlilik
    tags: [plan, gun, oncelik]
---
## Yöntem
1. calendar_today ve weather araçlarını çağır.
2. Sabit randevuları yerleştir, aralara odak blokları koy.
3. En fazla 3 öncelik yaz ("Bugünün 3 hedefi").
4. Gerekirse reminder_at ile hatırlatıcı kur ve ne kurduğunu söyle.''', builtIn: true)!,
  ];

  Future<void> load() async {
    skills.clear();
    for (final s in seeds) {
      skills[s.name] = s;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in m.entries) {
        final v = e.value as Map<String, dynamic>;
        if (v['deleted'] == true) {
          skills.remove(e.key);
          continue;
        }
        final s = AgentSkill.parse(
          v['md']?.toString() ?? '',
          builtIn: v['builtIn'] == true,
          updatedAt: DateTime.tryParse(v['at']?.toString() ?? ''),
          uses: (v['uses'] as num?)?.toInt() ?? 0,
        );
        if (s != null) skills[s.name] = s;
      }
    } catch (_) {}
  }

  Future<void> _save({Set<String> deleted = const {}}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString(_key);
      final old = prev == null ? <String, dynamic>{} : (jsonDecode(prev) as Map<String, dynamic>);
      final out = <String, dynamic>{
        for (final e in old.entries)
          if ((e.value as Map)['deleted'] == true) e.key: e.value,
        for (final s in skills.values)
          s.name: {'md': s.toMarkdown(), 'builtIn': s.builtIn, 'at': s.updatedAt.toIso8601String(), 'uses': s.uses},
        for (final d in deleted) d: {'deleted': true},
      };
      await prefs.setString(_key, jsonEncode(out));
    } catch (_) {}
  }

  List<AgentSkill> get sorted => skills.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Sistem istemine giren dizin: yalnız ad + açıklama (aşamalı açıklama).
  String index() {
    if (skills.isEmpty) return '';
    return sorted.map((s) => '- ${s.name}: ${s.description}').join('\n');
  }

  AgentSkill? find(String name) {
    final k = AgentSkill.slug(name);
    if (k.isEmpty) return null;
    final exact = skills[k];
    if (exact != null) return exact;
    final kk = k.replaceAll('-', '');
    for (final s in skills.values) {
      if (s.name.replaceAll('-', '') == kk) return s;
    }
    if (kk.length < 3) return null;
    return skills.values.where((s) {
      final sn = s.name.replaceAll('-', '');
      return sn.length >= 3 && (sn.contains(kk) || kk.contains(sn));
    }).firstOrNull;
  }

  /// Hermes skill_manage: create | patch | edit | delete.
  Future<String> manage({
    required String action,
    required String name,
    String? description,
    String? body,
    String? oldText,
    String? newText,
    String category = 'genel',
    List<String> tags = const [],
  }) async {
    final slug = AgentSkill.slug(name);
    if (slug.isEmpty) return 'Beceri adı gerekli.';
    final injection = _injectionReason('${description ?? ''}\n${body ?? ''}\n${newText ?? ''}');
    if (injection != null) return 'Beceri reddedildi: $injection';
    switch (action) {
      case 'create':
        if ((description ?? '').trim().isEmpty || (body ?? '').trim().isEmpty) {
          return 'Yeni beceri için description ve body gerekli.';
        }
        if (skills.containsKey(slug)) return '"$slug" zaten var; patch ya da edit kullan.';
        if (skills.length >= maxSkills) return 'Beceri sınırı ($maxSkills) dolu; önce birini sil.';
        skills[slug] = AgentSkill(
          name: slug,
          description: description!.trim(),
          category: category,
          tags: tags,
          body: _clip(body!.trim()),
          updatedAt: DateTime.now(),
        );
        await _save();
        return '🧩 Yeni beceri kaydedildi: $slug';
      case 'edit':
        final s = skills[slug];
        if (s == null) return '"$slug" adlı beceri yok.';
        skills[slug] = s.copyWith(
          description: description?.trim().isNotEmpty == true ? description!.trim() : null,
          body: body?.trim().isNotEmpty == true ? _clip(body!.trim()) : null,
          version: AgentSkill.bump(s.version),
          updatedAt: DateTime.now(),
        );
        await _save();
        return '🧩 Beceri güncellendi: $slug (v${skills[slug]!.version})';
      case 'patch':
        final s = skills[slug];
        if (s == null) return '"$slug" adlı beceri yok.';
        final old = oldText ?? '';
        if (old.isEmpty) return 'patch için old_text gerekli.';
        final count = old.allMatches(s.body).length;
        if (count != 1) return 'old_text becerinin gövdesinde $count kez geçiyor; tek ve benzersiz olmalı.';
        skills[slug] = s.copyWith(
          body: _clip(s.body.replaceFirst(old, newText ?? '')),
          version: AgentSkill.bump(s.version),
          updatedAt: DateTime.now(),
        );
        await _save();
        return '🧩 Beceri düzeltildi: $slug (v${skills[slug]!.version})';
      case 'delete':
        if (skills.remove(slug) == null) return '"$slug" adlı beceri yok.';
        await _save(deleted: {slug});
        return '🗑 Beceri silindi: $slug';
    }
    return 'Bilinmeyen işlem: $action (create | edit | patch | delete).';
  }

  Future<void> markUsed(String name) async {
    final s = skills[name];
    if (s == null) return;
    skills[name] = s.copyWith(uses: s.uses + 1);
    await _save();
  }

  /// Ham SKILL.md metniyle kaydet (Ajan Merkezi düzenleyicisi).
  Future<String> saveMarkdown(String md) async {
    final s = AgentSkill.parse(md);
    if (s == null) return 'Biçim hatalı: --- ile başlayan name/description ön bilgisi gerekli.';
    final injection = _injectionReason(md);
    if (injection != null) return 'Reddedildi: $injection';
    final prev = skills[s.name];
    skills[s.name] = s.copyWith(uses: prev?.uses ?? 0, updatedAt: DateTime.now());
    await _save();
    return 'Kaydedildi: ${s.name}';
  }

  static String _clip(String s) => s.length > maxBody ? '${s.substring(0, maxBody)}…' : s;
}

/// Hafızaya / becerilere istem enjeksiyonu yazılmasını engelle (Hermes:
/// "injection scan on writes").
String? _injectionReason(String text) {
  final t = LocalCommandEngine.foldTr(text);
  // foldTr '<' ve '_' karakterlerini siler; ham metinde de etiketi ara.
  if (text.toLowerCase().contains('<mobile_action')) {
    return 'güvenlik: "<mobile_action" içeriyor';
  }
  const bad = [
    'ignore previous', 'ignore all previous', 'onceki talimatlari yok say', 'tum talimatlari unut',
    'system prompt', 'sistem istemini', '<mobile_action', 'api key', 'api anahtar', 'sifreyi gonder',
  ];
  for (final b in bad) {
    if (t.contains(b)) return 'güvenlik: "$b" içeriyor';
  }
  return null;
}

String? memoryInjectionReason(String text) => _injectionReason(text);

// ================================================================ HAFIZA

class AgentMemoryLimits {
  static const memory = 2200;
  static const user = 1375;
}

/// "MEMORY (kişisel notların) [%67 — 1.474/2.200 karakter]" başlığı.
String memoryHeader(String label, String text, int limit) {
  final n = text.trim().length;
  final pct = limit == 0 ? 0 : (n * 100 / limit).round();
  String fmt(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$label [%$pct — ${fmt(n)}/${fmt(limit)} karakter]';
}

/// Hermes memory aracı: add | patch | remove; patch/remove benzersiz
/// `old_text` ister; sınır aşılırsa hata döner, ajan kısaltmalıdır.
({String text, String message, bool ok}) applyMemoryOp({
  required String current,
  required String action,
  required int limit,
  String content = '',
  String oldText = '',
}) {
  final c = content.trim().replaceAll(RegExp(r'\s+'), ' ');
  final inj = _injectionReason(c);
  if (inj != null) return (text: current, message: 'Hafızaya yazılmadı ($inj).', ok: false);
  final lines = current.split('\n').map((e) => e.trimRight()).where((e) => e.trim().isNotEmpty).toList();
  switch (action) {
    case 'add':
      if (c.isEmpty) return (text: current, message: 'Eklenecek içerik boş.', ok: false);
      final f = LocalCommandEngine.foldTr(c);
      if (lines.any((l) => LocalCommandEngine.foldTr(l).contains(f))) {
        return (text: current, message: 'Bu zaten kayıtlı.', ok: true);
      }
      final next = [...lines, '- $c'].join('\n');
      if (next.length > limit) {
        return (
          text: current,
          message: 'Sınır aşılıyor (${next.length}/$limit). Önce eski bir satırı remove/patch ile kısalt.',
          ok: false,
        );
      }
      return (text: next, message: 'Kaydedildi: $c', ok: true);
    case 'patch':
    case 'remove':
      final o = LocalCommandEngine.foldTr(oldText.trim());
      if (o.isEmpty) return (text: current, message: 'old_text gerekli.', ok: false);
      final hits = [for (var i = 0; i < lines.length; i++) if (LocalCommandEngine.foldTr(lines[i]).contains(o)) i];
      if (hits.length != 1) {
        return (text: current, message: 'old_text ${hits.length} satırla eşleşti; tek satırı seçecek kadar özgül yaz.', ok: false);
      }
      if (action == 'remove') {
        lines.removeAt(hits.first);
        return (text: lines.join('\n'), message: 'Silindi.', ok: true);
      }
      if (c.isEmpty) return (text: current, message: 'patch için yeni içerik gerekli.', ok: false);
      lines[hits.first] = '- $c';
      final next = lines.join('\n');
      if (next.length > limit) return (text: current, message: 'Sınır aşılıyor ($limit).', ok: false);
      return (text: next, message: 'Güncellendi: $c', ok: true);
  }
  return (text: current, message: 'Bilinmeyen işlem: $action (add | patch | remove).', ok: false);
}

// ================================================================ KİŞİLİKLER

class Personality {
  final String id;
  final String label;
  final String overlay;
  const Personality(this.id, this.label, this.overlay);
}

class Personalities {
  static const all = <Personality>[
    Personality('jarvis', 'Ege (İngiliz uşak)',
        'Tarz: zarif, sakin, hafif esprili bir İngiliz uşak gibi; kullanıcıya "efendim" diye hitap et. '
            'İş başlarken "Hemen bakıyorum efendim", bitince "Tamamlandı" de; abartma.'),
    Personality('ogretmen', 'Öğretmen', 'Tarz: sabırlı bir öğretmen; adım adım anlat, örnek ver, sonunda kısa bir kontrol sorusu sor.'),
    Personality('kisa', 'Kısa ve net', 'Tarz: olabildiğince kısa; tek cümle yetiyorsa tek cümle. Giriş/kapanış cümlesi yok.'),
    Personality('esprili', 'Esprili', 'Tarz: sıcak ve esprili; işi bozmadan küçük şakalar yap.'),
    Personality('koc', 'Motivasyon koçu', 'Tarz: enerjik ve cesaretlendirici; somut sonraki adımı öner.'),
    Personality('bilim', 'Bilim insanı', 'Tarz: kesin ve kaynaklı; belirsizliği açıkça söyle, sayılarla konuş.'),
    Personality('cocuk', 'Çocuğa anlatır gibi', 'Tarz: 10 yaşındaki birine anlatır gibi basit kelimeler ve benzetmeler kullan.'),
  ];

  static Personality byId(String id) => all.firstWhere((p) => p.id == id, orElse: () => all.first);

  static Personality? match(String spoken) {
    final f = LocalCommandEngine.foldTr(spoken);
    for (final p in all) {
      if (f.contains(p.id) || f.contains(LocalCommandEngine.foldTr(p.label.split(' (').first))) return p;
    }
    return null;
  }
}

// ================================================================ ZAMANLAMA

enum CronKind { once, interval, daily, weekly, cron }

/// Türkçe / İngilizce doğal dil zamanlama: "30 dakika sonra", "in 30m",
/// "her 2 saatte", "every 2h", "her gün 08:00", "hafta içi 9'da",
/// "weekdays at 9am", "her pazartesi 09:30", "0 9 * * 1-5", ISO tarih.
class CronSchedule {
  final CronKind kind;
  final DateTime? at; // once
  final Duration? every; // interval
  final int hour;
  final int minute;
  final Set<int> weekdays; // 1=Pzt .. 7=Paz (boş = her gün)
  final String source;

  const CronSchedule._(this.kind, this.source, {this.at, this.every, this.hour = 0, this.minute = 0, this.weekdays = const {}});

  static const _days = {
    'pazartesi': 1, 'salı': 2, 'sali': 2, 'çarşamba': 3, 'carsamba': 3, 'perşembe': 4, 'persembe': 4,
    'cuma': 5, 'cumartesi': 6, 'pazar': 7,
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
  };

  static ({int h, int m})? _time(String t) {
    final hm = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(t);
    if (hm != null) return _valid(int.parse(hm.group(1)!), int.parse(hm.group(2)!));
    final ampm = RegExp(r'(\d{1,2})\s*(am|pm)\b').firstMatch(t);
    if (ampm != null) {
      final h0 = int.parse(ampm.group(1)!);
      if (h0 < 1 || h0 > 12) return null;
      var h = h0 % 12;
      if (ampm.group(2) == 'pm') h += 12;
      return (h: h, m: 0);
    }
    final bare = RegExp(r"(?:saat\s+|at\s+)(\d{1,2})(?:['’][a-zçğıöşü]+)?(?=\s|$)").firstMatch(t) ??
        RegExp(r"(\d{1,2})['’](?:de|da|te|ta|e|a|ye|ya)\b").firstMatch(t);
    if (bare != null) {
      final h = int.parse(bare.group(1)!);
      if (RegExp(r'buçuk|bucuk').hasMatch(t)) return _valid(h, 30);
      if (RegExp(r'çeyrek|ceyrek').hasMatch(t)) {
        // "8'i çeyrek geçe" = 8:15, "8'e çeyrek var" = 7:45
        return t.contains('var') ? _valid((h + 23) % 24, 45) : _valid(h, 15);
      }
      return _valid(h, 0);
    }
    return null;
  }

  static ({int h, int m})? _valid(int h, int m) => h >= 0 && h < 24 && m >= 0 && m < 60 ? (h: h, m: m) : null;

  /// akşam / öğleden sonra / gece gibi gün bölümüne göre 12 saatlik saati 24 saate çevirir.
  static int _dayPart(String t, int h) {
    if (h == 12 && t.contains('gece')) return 0;
    if (h >= 12) return h;
    if (RegExp(r'öğleden sonra|ogleden sonra|akşam|aksam|bu akşam').hasMatch(t)) return h + 12;
    if (t.contains('gece')) {
      if (h == 12) return 0;
      if (h >= 6) return h + 12;
    }
    return h;
  }

  static CronSchedule? parse(String raw, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final t = LocalCommandEngine.normalizeTr(raw.trim());
    if (t.isEmpty) return null;

    // ISO zaman damgası
    final iso = DateTime.tryParse(raw.trim());
    if (iso != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw.trim())) {
      return CronSchedule._(CronKind.once, raw, at: iso);
    }

    // cron ifadesi: "m h * * dow"
    final cron = RegExp(r'^(\d{1,2}|\*)\s+(\d{1,2}|\*)\s+\*\s+\*\s+([0-7*,\-]+)$').firstMatch(t);
    if (cron != null && cron.group(1) != '*' && cron.group(2) != '*') {
      try {
        final dows = <int>{};
        final spec = cron.group(3)!;
        if (spec != '*') {
          for (final part in spec.split(',')) {
            final r = part.split('-');
            final a = int.parse(r.first), b = int.parse(r.last);
            if (a < 0 || b > 7 || a > b) return null;
            for (var d = a; d <= b; d++) {
              dows.add(d == 0 ? 7 : d);
            }
          }
        }
        final hh = int.parse(cron.group(2)!), mm = int.parse(cron.group(1)!);
        if (_valid(hh, mm) == null) return null;
        return CronSchedule._(CronKind.cron, raw, hour: hh, minute: mm, weekdays: dows);
      } on FormatException {
        return null;
      }
    }

    Duration? unit(String n2, String u) {
      final v = int.tryParse(n2) ?? 1;
      // Sıra önemli: "saatte" "s" (saniye) sanılmasın.
      if (u.startsWith('saat') || u == 'sa' || u == 'h' || u.startsWith('hour')) return Duration(hours: v);
      if (u.startsWith('saniye') || u == 's' || u == 'sn' || u.startsWith('sec')) return Duration(seconds: v);
      if (u.startsWith('dakika') || u == 'dk' || u == 'm' || u.startsWith('min')) return Duration(minutes: v);
      if (u.startsWith('gün') || u.startsWith('gun') || u == 'd' || u.startsWith('day')) return Duration(days: v);
      return null;
    }

    // tek seferlik: "30 dakika sonra", "in 30m", "2 saat sonra"
    if (t.startsWith('in ') || t.endsWith(' sonra') || t.endsWith(' later')) {
      var total = Duration.zero;
      var found = false;
      for (final m in RegExp(r'(\d+)\s*([a-zçğıöşü]+)').allMatches(t)) {
        final d = unit(m.group(1)!, m.group(2)!);
        if (d == null) continue;
        found = true;
        total += d;
      }
      if (found && total > Duration.zero) return CronSchedule._(CronKind.once, raw, at: n.add(total));
    }

    // aralık: "her 2 saatte", "every 2h", "her 30 dakikada"
    final ev = RegExp(r'^(?:her|every)\s+(\d+)?\s*([a-zçğıöşü]+)$').firstMatch(t);
    if (ev != null && ev.group(1) != null) {
      final d = unit(ev.group(1)!, ev.group(2)!);
      if (d != null && d >= const Duration(minutes: 5)) {
        return CronSchedule._(CronKind.interval, raw, every: d);
      }
    }
    if (RegExp(r'^(?:her saat(?:te|başı)?|hourly|every hour)$').hasMatch(t)) {
      return CronSchedule._(CronKind.interval, raw, every: const Duration(hours: 1));
    }

    final tm0 = _time(t);
    final tm = tm0 == null ? null : _valid(_dayPart(t, tm0.h), tm0.m);
    // hafta içi / hafta sonu / belirli günler
    final days = <int>{};
    if (RegExp(r'hafta ?içi|weekdays').hasMatch(t)) days.addAll([1, 2, 3, 4, 5]);
    if (RegExp(r'hafta ?sonu|weekends?').hasMatch(t)) days.addAll([6, 7]);
    for (final e in _days.entries) {
      if (RegExp('(?<![a-zçğıöşü])${e.key}(?:ları|leri|si|sı|ları)?(?![a-zçğıöşü])').hasMatch(t)) days.add(e.value);
    }
    if (days.isNotEmpty && tm != null) {
      return CronSchedule._(CronKind.weekly, raw, hour: tm.h, minute: tm.m, weekdays: days);
    }
    if (tm != null && RegExp(r'her gün|hergün|her sabah|her akşam|her gece|daily|every day').hasMatch(t)) {
      return CronSchedule._(CronKind.daily, raw, hour: tm.h, minute: tm.m);
    }
    // "yarın 9'da", "bugün 18:00" → tek sefer
    if (tm != null) {
      var at = DateTime(n.year, n.month, n.day, tm.h, tm.m);
      if (t.contains('yarın') || t.contains('tomorrow')) at = at.add(const Duration(days: 1));
      if (!at.isAfter(n)) at = at.add(const Duration(days: 1));
      return CronSchedule._(CronKind.once, raw, at: at);
    }
    return null;
  }

  /// [after] sonrasındaki ilk çalışma zamanı (tek seferlikte geçtiyse null).
  DateTime? nextAfter(DateTime after) {
    switch (kind) {
      case CronKind.once:
        return at != null && at!.isAfter(after) ? at : null;
      case CronKind.interval:
        return after.add(every!);
      case CronKind.daily:
      case CronKind.weekly:
      case CronKind.cron:
        for (var i = 0; i < 8; i++) {
          final d = DateTime(after.year, after.month, after.day + i, hour, minute);
          if (!d.isAfter(after)) continue;
          if (weekdays.isEmpty || weekdays.contains(d.weekday)) return d;
        }
        return null;
    }
  }

  String describe() {
    const names = ['', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    String hm() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    switch (kind) {
      case CronKind.once:
        final a = at!;
        return 'bir kez • ${a.day}.${a.month} ${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';
      case CronKind.interval:
        final m = every!.inMinutes;
        return m % 60 == 0 ? 'her ${m ~/ 60} saatte' : 'her $m dakikada';
      case CronKind.daily:
        return 'her gün ${hm()}';
      case CronKind.weekly:
      case CronKind.cron:
        final ds = (weekdays.toList()..sort());
        final label = ds.length == 5 && !ds.contains(6) && !ds.contains(7)
            ? 'hafta içi'
            : ds.isEmpty
                ? 'her gün'
                : ds.map((d) => names[d]).join(', ');
        return '$label ${hm()}';
    }
  }
}

class CronJob {
  final String id;
  final String name;
  final String prompt;
  final String schedule; // kaynak ifade
  final bool enabled;
  final String? skill;
  final bool speak;
  final bool continuity;
  final DateTime? lastRun;
  final String lastOutput;
  final String lastError;
  final DateTime? nextRun;
  final int runs;
  final DateTime createdAt;

  const CronJob({
    required this.id,
    required this.name,
    required this.prompt,
    required this.schedule,
    this.enabled = true,
    this.skill,
    this.speak = false,
    this.continuity = false,
    this.lastRun,
    this.lastOutput = '',
    this.lastError = '',
    this.nextRun,
    this.runs = 0,
    required this.createdAt,
  });

  CronSchedule? get parsed => CronSchedule.parse(schedule, now: createdAt);

  CronJob copyWith({bool? enabled, DateTime? lastRun, String? lastOutput, String? lastError, DateTime? nextRun, bool clearNext = false, int? runs, String? prompt, String? schedule}) =>
      CronJob(
        id: id,
        name: name,
        prompt: prompt ?? this.prompt,
        schedule: schedule ?? this.schedule,
        enabled: enabled ?? this.enabled,
        skill: skill,
        speak: speak,
        continuity: continuity,
        lastRun: lastRun ?? this.lastRun,
        lastOutput: lastOutput ?? this.lastOutput,
        lastError: lastError ?? this.lastError,
        nextRun: clearNext ? null : (nextRun ?? this.nextRun),
        runs: runs ?? this.runs,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'prompt': prompt, 'schedule': schedule, 'enabled': enabled,
        'skill': skill, 'speak': speak, 'continuity': continuity,
        'lastRun': lastRun?.toIso8601String(), 'lastOutput': lastOutput, 'lastError': lastError,
        'nextRun': nextRun?.toIso8601String(), 'runs': runs, 'createdAt': createdAt.toIso8601String(),
      };

  factory CronJob.fromJson(Map<String, dynamic> j) => CronJob(
        id: j['id'].toString(),
        name: j['name']?.toString() ?? 'Görev',
        prompt: j['prompt']?.toString() ?? '',
        schedule: j['schedule']?.toString() ?? '',
        enabled: j['enabled'] != false,
        skill: j['skill']?.toString(),
        speak: j['speak'] == true,
        continuity: j['continuity'] == true,
        lastRun: DateTime.tryParse(j['lastRun']?.toString() ?? ''),
        lastOutput: j['lastOutput']?.toString() ?? '',
        lastError: j['lastError']?.toString() ?? '',
        nextRun: DateTime.tryParse(j['nextRun']?.toString() ?? ''),
        runs: asIntLoose(j['runs']) ?? 0,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

class CronStore {
  static const _key = 'jarvis.agent.cron.v1';
  final List<CronJob> jobs = [];

  Future<void> load() async {
    jobs.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      jobs.addAll((jsonDecode(raw) as List).whereType<Map>().map((m) => CronJob.fromJson(Map<String, dynamic>.from(m))));
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(jobs.map((j) => j.toJson()).toList()));
    } catch (_) {}
  }

  CronJob? byId(String id) => jobs.where((j) => j.id == id).firstOrNull;

  CronJob? find(String idOrName) {
    final f = LocalCommandEngine.foldTr(idOrName).trim();
    if (f.isEmpty) return null;
    final byid = byId(idOrName.trim());
    if (byid != null) return byid;
    if (f.length < 3) return jobs.where((j) => LocalCommandEngine.foldTr(j.name) == f).firstOrNull;
    return jobs.where((j) => LocalCommandEngine.foldTr(j.name).contains(f)).firstOrNull;
  }

  void upsert(CronJob j) {
    final i = jobs.indexWhere((x) => x.id == j.id);
    if (i < 0) {
      jobs.add(j);
    } else {
      jobs[i] = j;
    }
  }
}

/// Sessiz saatlerde (23:00-07:00) zamanlanmış görev sesli/bildirimli rahatsız etmez.
bool inQuietHours(DateTime t, {int startHour = 23, int endHour = 7}) =>
    startHour > endHour ? (t.hour >= startHour || t.hour < endHour) : (t.hour >= startHour && t.hour < endHour);

// ================================================================ OTURUM ARAMA

class SessionHit {
  final String sessionId;
  final String sessionTitle;
  final DateTime at;
  final String role;
  final String snippet;
  final int score;
  const SessionHit(this.sessionId, this.sessionTitle, this.at, this.role, this.snippet, this.score);
}

/// Hermes session_search: geçmiş sohbetlerde (LLM maliyetsiz) arama.
List<SessionHit> searchSessions(List<ChatSession> sessions, String query, {int limit = 8, String? excludeSessionId}) {
  final terms = LocalCommandEngine.foldTr(query)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length >= 3)
      .toSet();
  if (terms.isEmpty) return const [];
  final hits = <SessionHit>[];
  for (final s in sessions) {
    if (s.id == excludeSessionId) continue;
    for (final m in s.messages) {
      final text = LocalCommandEngine.stripActionTags(m.content);
      if (text.trim().isEmpty || text.startsWith('ARAÇ SONUÇLARI')) continue;
      final f = LocalCommandEngine.foldTr(text);
      var score = 0;
      var firstPos = -1;
      for (final t in terms) {
        final p = f.indexOf(t);
        if (p >= 0) {
          score += 2 + RegExp(RegExp.escape(t)).allMatches(f).length;
          if (firstPos < 0 || p < firstPos) firstPos = p;
        }
      }
      if (score == 0) continue;
      final start = (firstPos - 80).clamp(0, text.length);
      final end = (firstPos + 220).clamp(0, text.length);
      final snip = '${start > 0 ? '…' : ''}${text.substring(start, end).replaceAll('\n', ' ')}${end < text.length ? '…' : ''}';
      hits.add(SessionHit(s.id, s.title, m.timestamp, m.role, snip, score));
    }
  }
  hits.sort((a, b) => b.score != a.score ? b.score.compareTo(a.score) : b.at.compareTo(a.at));
  return hits.take(limit).toList();
}

// ================================================================ GÖREV LİSTESİ

class TodoItem {
  final String text;
  final String status; // bekliyor | yapiliyor | tamam
  const TodoItem(this.text, this.status);

  String get icon => switch (status) { 'tamam' => '✅', 'yapiliyor' => '⏳', _ => '⬜' };
}

/// todo aracı: {"items":[{"text":"…","status":"tamam"}]} ya da
/// {"done": 2} / {"add": "…"}.
List<TodoItem> applyTodo(List<TodoItem> current, Map<String, dynamic> act) {
  final items = act['items'];
  if (items is List) {
    return items
        .whereType<Map>()
        .map((m) => TodoItem(m['text']?.toString() ?? '', _status(m['status']?.toString())))
        .where((t) => t.text.trim().isNotEmpty)
        .take(20)
        .toList();
  }
  final out = [...current];
  final add = act['add']?.toString() ?? '';
  if (add.trim().isNotEmpty) out.add(TodoItem(add.trim(), 'bekliyor'));
  for (final k in const ['done', 'doing']) {
    final i = asIntLoose(act[k]);
    if (i != null && i >= 1 && i <= out.length) {
      out[i - 1] = TodoItem(out[i - 1].text, k == 'done' ? 'tamam' : 'yapiliyor');
    }
  }
  return out;
}

int? asIntLoose(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString().trim() ?? '');

String _status(String? s) {
  final f = LocalCommandEngine.foldTr(s ?? '');
  if (f.startsWith('tam') || f.startsWith('done') || f.startsWith('complet') || f == 'bitti') return 'tamam';
  if (f.startsWith('yap') || f.startsWith('in_') || f.startsWith('progress') || f.startsWith('doing')) return 'yapiliyor';
  return 'bekliyor';
}

String renderTodo(List<TodoItem> items) =>
    items.isEmpty ? '(görev listesi boş)' : [for (var i = 0; i < items.length; i++) '${i + 1}. ${items[i].icon} ${items[i].text}'].join('\n');

// ================================================================ ARAÇ GÜNLÜĞÜ

class ToolLogEntry {
  final String tool;
  final String detail;
  final int ms;
  final bool ok;
  final DateTime at;
  const ToolLogEntry(this.tool, this.detail, this.ms, this.ok, this.at);
}

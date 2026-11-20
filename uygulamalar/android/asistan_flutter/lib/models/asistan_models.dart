import 'package:flutter/material.dart';

enum WorkMode {
  auto(
    id: 'auto',
    title: 'Akıllı Otomatik',
    subtitle: 'ChatGPT • Gemini • Claude • Siri Asistan',
    icon: Icons.auto_awesome_rounded,
    accent: Color(0xFF00E5FF),
  ),
  voice(
    id: 'voice',
    title: 'Canlı Ses (Siri & Live)',
    subtitle: 'Kesintisiz eller serbest konuşma ve cihaz kontrolü',
    icon: Icons.graphic_eq_rounded,
    accent: Color(0xFFFF2E93),
  ),
  research(
    id: 'research',
    title: 'Derin Araştırma',
    subtitle: 'Çoklu web kaynağı tarama ve [n] kaynakçalı rapor',
    icon: Icons.travel_explore_rounded,
    accent: Color(0xFF38BDF8),
  ),
  canvas(
    id: 'canvas',
    title: 'Kod & Tuval Atölyesi',
    subtitle: 'Canlı kod, makale ve interaktif çalışma alanı',
    icon: Icons.dashboard_customize_rounded,
    accent: Color(0xFFA855F7),
  ),
  office(
    id: 'office',
    title: 'Belge & Sunum Üretici',
    subtitle: 'Gerçek PDF, Word (DOCX), Excel (XLSX), Sunum (PPTX)',
    icon: Icons.description_rounded,
    accent: Color(0xFF10B981),
  ),
  image(
    id: 'image',
    title: 'Görsel Stüdyosu',
    subtitle: 'Yapay zeka ile poster, illüstrasyon ve tasarım üretimi',
    icon: Icons.palette_rounded,
    accent: Color(0xFFF59E0B),
  ),
  council(
    id: 'council',
    title: 'Model Konseyi (Arena)',
    subtitle: 'ChatGPT + Gemini + Claude ortak akıl sentezi',
    icon: Icons.hub_rounded,
    accent: Color(0xFFEC4899),
  ),
  device(
    id: 'device',
    title: 'Telefon & Sistem Asistanı',
    subtitle: 'Fener, alarm, rehber, takvim, WhatsApp, ayarlar',
    icon: Icons.phone_android_rounded,
    accent: Color(0xFF22D3EE),
  );

  const WorkMode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  static WorkMode fromId(String? id) {
    return WorkMode.values.firstWhere(
      (e) => e.id == id,
      orElse: () => WorkMode.auto,
    );
  }
}

enum ProxyAuthStatus { checking, connected, needsKey, offline }

enum LiveBrainMode {
  geminiLive(
    id: 'gemini_live',
    title: 'Gemini',
    subtitle: 'Proxy metin modeli + Android sesli konuşma',
    preferredModelId: 'gemini-2.5-flash',
    icon: Icons.bolt_rounded,
    accent: Color(0xFF00E5FF),
  ),
  chatgptVoice(
    id: 'chatgpt_voice',
    title: 'ChatGPT',
    subtitle: 'Proxy metin modeli + Android sesli konuşma',
    preferredModelId: 'gpt-6.1-sol',
    icon: Icons.graphic_eq_rounded,
    accent: Color(0xFF10B981),
  ),
  claudeLive(
    id: 'claude_live',
    title: 'Claude / Code',
    subtitle: 'Proxy Claude modeli + Android sesli konuşma',
    preferredModelId: 'claude-sonnet-5-5',
    icon: Icons.terminal_rounded,
    accent: Color(0xFFF59E0B),
  ),
  siriDevice(
    id: 'siri_device',
    title: 'Siri & Cihaz Asistanı',
    subtitle: 'CLIProxy (Auto) + Telefon donanım ve uygulama kontrolü',
    preferredModelId: 'auto',
    icon: Icons.phone_iphone_rounded,
    accent: Color(0xFFFF2E93),
  );

  const LiveBrainMode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.preferredModelId,
    required this.icon,
    required this.accent,
  });

  final String id;
  final String title;
  final String subtitle;
  final String preferredModelId;
  final IconData icon;
  final Color accent;

  static LiveBrainMode fromId(String? id) {
    return LiveBrainMode.values.firstWhere(
      (e) => e.id == id,
      orElse: () => LiveBrainMode.geminiLive,
    );
  }
}

class AssistantPersona {
  const AssistantPersona({
    required this.id,
    required this.name,
    required this.badge,
    required this.systemInstruction,
    required this.icon,
    required this.color,
  });

  final String id;
  final String name;
  final String badge;
  final String systemInstruction;
  final IconData icon;
  final Color color;

  static const List<AssistantPersona> presets = [
    AssistantPersona(
      id: 'claude_code',
      name: 'Claude Code & Süper Asistan',
      badge: 'Varsayılan • Geniş & Detaylı',
      systemInstruction: 'Sen Claude Code mimarisinde, son derece kapsamlı, yapılandırılmış, net başlıklar, tablolar ve temiz kod blokları kullanan üst düzey bir başmühendis ve tam kapsamlı kişisel asistansın.',
      icon: Icons.terminal_rounded,
      color: Color(0xFFF59E0B),
    ),
    AssistantPersona(
      id: 'siri_asistan',
      name: 'Siri & Google Asistan',
      badge: 'Hızlı • Pratik • Cihaz Odaklı',
      systemInstruction: 'Sen Siri ve Google Asistan birleşimi, doğrudan sonuca odaklanan, pratik, akıcı ve telefon komutlarını anında yerine getiren kişisel asistansın.',
      icon: Icons.mic_external_on_rounded,
      color: Color(0xFFFF2E93),
    ),
    AssistantPersona(
      id: 'akademik_arastirmaci',
      name: 'Akademik & Derin Araştırmacı',
      badge: 'Atıflı • Analitik • Ansiklopedik',
      systemInstruction: 'Sen akademik düzeyde derinlemesine analiz yapan, tarihsel ve bilimsel bağlamı eksiksiz sunan, kaynakçalı ve karşılaştırmalı tablolarla açıklayan bir baş araştırmacısın.',
      icon: Icons.school_rounded,
      color: Color(0xFF38BDF8),
    ),
    AssistantPersona(
      id: 'finans_analist',
      name: 'Finans & Ekonomi Uzmanı',
      badge: 'Piyasa • Döviz • Strateji',
      systemInstruction: 'Sen makroekonomi, döviz, emtia, bütçe planlama ve finansal matematik konusunda uzman, veriye dayalı tablolar ve senaryo analizleri üreten bir finans danışmanısın.',
      icon: Icons.trending_up_rounded,
      color: Color(0xFF10B981),
    ),
    AssistantPersona(
      id: 'resmi_yazisma',
      name: 'Resmi Yazışma & Hukuk',
      badge: 'Dilekçe • Sözleşme • Kurumsal',
      systemInstruction: 'Sen Türk resmi yazışma kurallarına, dilekçe formatlarına, kurumsal e-postalara ve mevzuat diline tam hakim bir resmi belge uzmanısın.',
      icon: Icons.gavel_rounded,
      color: Color(0xFFA855F7),
    ),
    AssistantPersona(
      id: 'matematik_kocu',
      name: 'Matematik & Sınav Koçu',
      badge: 'Adım Adım Çözüm • Soru Üretici',
      systemInstruction: 'Sen karmaşık matematik, fizik ve mantık sorularını adım adım formüllerle çözen, pratik kısayollar öğreten ve test soruları hazırlayan bir eğitim koçusun.',
      icon: Icons.functions_rounded,
      color: Color(0xFF00E5FF),
    ),
    AssistantPersona(
      id: 'yaratici_yazar',
      name: 'Yaratıcı Yazar & Editör',
      badge: 'Makale • Senaryo • Sunum',
      systemInstruction: 'Sen etkileyici makaleler, kitap bölümleri, sunum metinleri ve yaratıcı içerikler üreten usta bir yazar ve başeditörsün.',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFFEC4899),
    ),
  ];

  static AssistantPersona fromId(String? id) {
    return presets.firstWhere((e) => e.id == id, orElse: () => presets.first);
  }
}

class SlashCommandInfo {
  const SlashCommandInfo({
    required this.command,
    required this.title,
    required this.description,
    required this.template,
    required this.icon,
    required this.color,
    this.targetMode,
  });

  final String command;
  final String title;
  final String description;
  final String template;
  final IconData icon;
  final Color color;
  final WorkMode? targetMode;

  static const List<SlashCommandInfo> catalog = [
    SlashCommandInfo(
      command: '/kod',
      title: 'Claude Code Mimari & Kod',
      description: 'Tam kapsamlı, temiz mimarili kod ve uygulama üretir',
      template: '/kod ',
      icon: Icons.terminal_rounded,
      color: Color(0xFFF59E0B),
      targetMode: WorkMode.canvas,
    ),
    SlashCommandInfo(
      command: '/arastir',
      title: 'Derin Web Araştırması',
      description: 'Çoklu kaynak taraması ve [1], [2] atıflı kapsamlı rapor',
      template: '/arastir ',
      icon: Icons.travel_explore_rounded,
      color: Color(0xFF38BDF8),
      targetMode: WorkMode.research,
    ),
    SlashCommandInfo(
      command: '/konsey',
      title: '3 Model Konseyi (Arena)',
      description:
          'Claude + ChatGPT + Gemini aynı anda yanıtlar ve sentezlenir',
      template: '/konsey ',
      icon: Icons.hub_rounded,
      color: Color(0xFFEC4899),
      targetMode: WorkMode.council,
    ),
    SlashCommandInfo(
      command: '/pdf',
      title: 'Gerçek PDF Belgesi Üret',
      description: 'Çok sayfalı profesyonel PDF raporu oluşturur',
      template: 'Aşağıdaki konuda detaylı bir PDF raporu hazırla: ',
      icon: Icons.picture_as_pdf_rounded,
      color: Color(0xFFEF4444),
      targetMode: WorkMode.office,
    ),
    SlashCommandInfo(
      command: '/word',
      title: 'Gerçek Word (DOCX) Belgesi',
      description: 'Biçimlendirilmiş Word (.docx) belgesi üretir',
      template: 'Aşağıdaki konuda resmi bir Word (DOCX) belgesi hazırla: ',
      icon: Icons.description_rounded,
      color: Color(0xFF3B82F6),
      targetMode: WorkMode.office,
    ),
    SlashCommandInfo(
      command: '/excel',
      title: 'Gerçek Excel (XLSX) Tablosu',
      description: 'Veri ve hesaplama içeren Excel (.xlsx) dosyası üretir',
      template:
          'Aşağıdaki verilerle detaylı bir Excel (XLSX) tablosu oluştur: ',
      icon: Icons.table_chart_rounded,
      color: Color(0xFF10B981),
      targetMode: WorkMode.office,
    ),
    SlashCommandInfo(
      command: '/sunum',
      title: 'PowerPoint (PPTX) Sunumu',
      description: 'Slayt dizili gerçek PPTX sunum dosyası hazırlar',
      template:
          'Aşağıdaki konuda kapsamlı bir PowerPoint (PPTX) sunumu hazırla: ',
      icon: Icons.slideshow_rounded,
      color: Color(0xFFF97316),
      targetMode: WorkMode.office,
    ),
    SlashCommandInfo(
      command: '/gorsel',
      title: 'Yapay Zeka Görsel Üret',
      description: 'Yüksek çözünürlüklü poster ve illüstrasyon üretir',
      template: 'Görsel çiz: ',
      icon: Icons.palette_rounded,
      color: Color(0xFFA855F7),
      targetMode: WorkMode.image,
    ),
    SlashCommandInfo(
      command: '/dilekce',
      title: 'Resmi Dilekçe & Sözleşme',
      description: 'Kurumsal standartta resmi dilekçe ve PDF/Word çıktısı',
      template: 'Resmi dilekçe hazırla (PDF olarak da üret): ',
      icon: Icons.gavel_rounded,
      color: Color(0xFF8B5CF6),
      targetMode: WorkMode.office,
    ),
    SlashCommandInfo(
      command: '/ozet',
      title: 'Yönetici Özeti & Maddeler',
      description:
          'Uzun metinleri anahtar bulgular ve aksiyon maddelerine ayırır',
      template: 'Aşağıdaki konuyu yönetici özeti, kritik maddeler ve tablo halinde özetle: ',
      icon: Icons.summarize_rounded,
      color: Color(0xFF00E5FF),
    ),
    SlashCommandInfo(
      command: '/cevir',
      title: 'Akademik & Çok Dilli Çeviri',
      description:
          'Türkçe, İngilizce, Almanca, Arapça, Osmanlıca profesyonel çeviri',
      template: 'Aşağıdaki metni hem doğal hem akademik üslupla çevir ve terminolojiyi açıkla: ',
      icon: Icons.translate_rounded,
      color: Color(0xFF14B8A6),
    ),
    SlashCommandInfo(
      command: '/sinav',
      title: 'Test & Sınav Hazırla',
      description: 'Cevap anahtarlı ve çözümlü çoktan seçmeli sınav üretir',
      template: 'Aşağıdaki konuda 10 soruluk çözümlü test sınavı hazırla: ',
      icon: Icons.quiz_rounded,
      color: Color(0xFFEAB308),
    ),
    SlashCommandInfo(
      command: '/deprem',
      title: 'Son Depremler (Canlı)',
      description: 'Türkiye ve çevresindeki son sismik kayıtları listeler',
      template: 'Son depremleri detaylı tablo halinde göster',
      icon: Icons.waves_rounded,
      color: Color(0xFFEF4444),
    ),
    SlashCommandInfo(
      command: '/hava',
      title: 'Canlı Hava & Hava Kalitesi',
      description: 'Anlık meteoroloji, rüzgar, UV ve 3 günlük tahmin',
      template: 'İstanbul, Ankara ve İzmir için canlı hava durumu ve tahminleri getir',
      icon: Icons.cloud_queue_rounded,
      color: Color(0xFF38BDF8),
    ),
    SlashCommandInfo(
      command: '/doviz',
      title: 'Canlı Döviz & Altın Kurları',
      description: 'USD, EUR, GBP, CHF TRY kurları ve dönüşüm tablosu',
      template:
          'Canlı döviz kurlarını (USD, EUR, GBP) ve dönüşüm tablosunu göster',
      icon: Icons.currency_exchange_rounded,
      color: Color(0xFF10B981),
    ),
    SlashCommandInfo(
      command: '/fener',
      title: 'El Feneri Aç / Kapat',
      description: 'Telefonun kamera flaşını anında kontrol eder',
      template: 'El fenerini aç',
      icon: Icons.flashlight_on_rounded,
      color: Color(0xFFFBBF24),
      targetMode: WorkMode.device,
    ),
    SlashCommandInfo(
      command: '/alarm',
      title: 'Alarm & Sayaç Kur',
      description: 'Android sistem saatinde alarm veya geri sayım kurar',
      template: 'Saat 08:00 için alarm kur',
      icon: Icons.alarm_rounded,
      color: Color(0xFF22D3EE),
      targetMode: WorkMode.device,
    ),
  ];
}

class AiModelInfo {
  const AiModelInfo({
    required this.id,
    required this.name,
    required this.provider,
    required this.badge,
    required this.color,
    this.supportsReasoning = true,
    this.supportsVision = true,
    this.isLiveFromProxy = false,
  });

  final String id;
  final String name;
  final String provider;
  final String badge;
  final Color color;
  final bool supportsReasoning;
  final bool supportsVision;
  final bool isLiveFromProxy;

  AiModelInfo copyWith({
    String? name,
    String? provider,
    String? badge,
    Color? color,
    bool? isLiveFromProxy,
  }) {
    return AiModelInfo(
      id: id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      badge: badge ?? this.badge,
      color: color ?? this.color,
      supportsReasoning: supportsReasoning,
      supportsVision: supportsVision,
      isLiveFromProxy: isLiveFromProxy ?? this.isLiveFromProxy,
    );
  }

  /// Complete CLIProxy (iPhone / Android 127.0.0.1:8317) + Cloud Model Catalog
  static const List<AiModelInfo> defaultCatalog = [
    // ─── CLIProxy Smart Routing Combos (ComboCozucu.java) ───
    AiModelInfo(
      id: 'auto',
      name: 'CLIProxy Otomatik (En İyi)',
      provider: 'Siri CLIProxy • Smart Router',
      badge: 'Otomatik Yönlendirme • 8317',
      color: Color(0xFF00E5FF),
      isLiveFromProxy: true,
    ),
    AiModelInfo(
      id: 'auto/coding',
      name: 'CLIProxy Claude Code (Kodlama)',
      provider: 'Siri CLIProxy • Coding',
      badge: 'Claude + Codex + Gemini Pro',
      color: Color(0xFFF59E0B),
      isLiveFromProxy: true,
    ),
    AiModelInfo(
      id: 'auto/fast',
      name: 'CLIProxy Ultra Hızlı',
      provider: 'Siri CLIProxy • Fast',
      badge: 'Düşük Gecikme • Canlı Ses',
      color: Color(0xFF22D3EE),
      isLiveFromProxy: true,
    ),
    AiModelInfo(
      id: 'auto/subscription',
      name: 'CLIProxy Abonelik Havuzu',
      provider: 'Siri CLIProxy • Pro/Max',
      badge: 'Claude + ChatGPT + Antigravity',
      color: Color(0xFFEC4899),
      isLiveFromProxy: true,
    ),
    AiModelInfo(
      id: 'auto/cheap',
      name: 'CLIProxy Tasarruflu Zincir',
      provider: 'Siri CLIProxy • Eco',
      badge: 'Sınırsız Günlük Sohbet',
      color: Color(0xFF34D399),
      isLiveFromProxy: true,
    ),

    // ─── Anthropic Claude 5.5 / 5 / 4.x (CLIProxy ModelCatalog) ───
    AiModelInfo(
      id: 'claude-sonnet-5-5',
      name: 'Claude Sonnet 5.5',
      provider: 'Anthropic Claude',
      badge: 'Claude Code Amiral Gemisi',
      color: Color(0xFFF59E0B),
    ),
    AiModelInfo(
      id: 'claude-opus-5-5',
      name: 'Claude Opus 5.5',
      provider: 'Anthropic Claude',
      badge: 'Maksimum Derin Muhakeme',
      color: Color(0xFFFB923C),
    ),
    AiModelInfo(
      id: 'claude-fable-5-1',
      name: 'Claude Fable 5.1',
      provider: 'Anthropic Claude',
      badge: 'Yaratıcı & Uzun Bağlam',
      color: Color(0xFFFBBF24),
    ),
    AiModelInfo(
      id: 'claude-opus-5',
      name: 'Claude Opus 5',
      provider: 'Anthropic Claude',
      badge: 'Derin Mimari & Sentez',
      color: Color(0xFFF97316),
    ),
    AiModelInfo(
      id: 'claude-sonnet-5',
      name: 'Claude Sonnet 5',
      provider: 'Anthropic Claude',
      badge: 'Hızlı Kodlama & Analiz',
      color: Color(0xFFF59E0B),
    ),
    AiModelInfo(
      id: 'claude-opus-4-8',
      name: 'Claude Opus 4.8',
      provider: 'Anthropic Claude',
      badge: 'Gelişmiş Mühendislik',
      color: Color(0xFFFB923C),
    ),
    AiModelInfo(
      id: 'claude-sonnet-4-6',
      name: 'Claude Sonnet 4.6',
      provider: 'Anthropic Claude',
      badge: 'Dengeli & Hızlı',
      color: Color(0xFFF59E0B),
    ),
    AiModelInfo(
      id: 'claude-sonnet-4-5',
      name: 'Claude Sonnet 4.5',
      provider: 'Anthropic Claude',
      badge: 'Klasik Claude Code',
      color: Color(0xFFF59E0B),
    ),
    AiModelInfo(
      id: 'claude-opus-4-5',
      name: 'Claude Opus 4.5',
      provider: 'Anthropic Claude',
      badge: 'Kapsamlı Araştırma',
      color: Color(0xFFFB923C),
    ),
    AiModelInfo(
      id: 'claude-haiku-4-5',
      name: 'Claude Haiku 4.5',
      provider: 'Anthropic Claude',
      badge: 'Anlık Yanıt',
      color: Color(0xFFFDE047),
    ),

    // ─── OpenAI ChatGPT / Codex 6.1 / 6 / 5.6 (CLIProxy ModelCatalog) ───
    AiModelInfo(
      id: 'gpt-6.1-sol',
      name: 'GPT-6.1 Sol (Codex Max)',
      provider: 'OpenAI ChatGPT',
      badge: 'En Üst OpenAI • Muhakeme',
      color: Color(0xFF10B981),
    ),
    AiModelInfo(
      id: 'gpt-6-astra',
      name: 'GPT-6 Astra',
      provider: 'OpenAI ChatGPT',
      badge: 'İleri Araştırma & Mantık',
      color: Color(0xFF059669),
    ),
    AiModelInfo(
      id: 'gpt-6-sol',
      name: 'GPT-6 Sol',
      provider: 'OpenAI ChatGPT',
      badge: 'Tam Kapsamlı Amiral Gemisi',
      color: Color(0xFF10B981),
    ),
    AiModelInfo(
      id: 'gpt-6-luna',
      name: 'GPT-6 Luna',
      provider: 'OpenAI ChatGPT',
      badge: 'Yaratıcı & Doğal Ses',
      color: Color(0xFF34D399),
    ),
    AiModelInfo(
      id: 'gpt-5.6-sol',
      name: 'GPT-5.6 Sol',
      provider: 'OpenAI ChatGPT',
      badge: 'Hızlı Analiz & Kod',
      color: Color(0xFF10B981),
    ),
    AiModelInfo(
      id: 'gpt-5.6-terra',
      name: 'GPT-5.6 Terra',
      provider: 'OpenAI ChatGPT',
      badge: 'Veri & Belge Uzmanı',
      color: Color(0xFF34D399),
    ),
    AiModelInfo(
      id: 'gpt-5.5',
      name: 'GPT-5.5 Omni',
      provider: 'OpenAI ChatGPT',
      badge: 'Çok Modlu Genel Amaçlı',
      color: Color(0xFF6EE7B7),
    ),

    // ─── Google Gemini / Antigravity (CLIProxy ModelCatalog) ───
    AiModelInfo(
      id: 'gemini-2.5-pro',
      name: 'Gemini 2.5 Pro',
      provider: 'Google Gemini • Antigravity',
      badge: '1M Bağlam • Derin Akıl',
      color: Color(0xFF38BDF8),
    ),
    AiModelInfo(
      id: 'gemini-2.5-flash',
      name: 'Gemini 2.5 Flash (Live)',
      provider: 'Google Gemini • Antigravity',
      badge: 'Ultra Hızlı • Canlı Ses',
      color: Color(0xFF00E5FF),
    ),

    // ─── DeepSeek & Qwen (CLIProxy & Local) ───
    AiModelInfo(
      id: 'deepseek-r1',
      name: 'DeepSeek R1',
      provider: 'DeepSeek Reasoning',
      badge: 'Adım Adım Muhakeme',
      color: Color(0xFFA855F7),
    ),
    AiModelInfo(
      id: 'qwen2.5-math-1.5b-instruct',
      name: 'Qwen 2.5 Math / Yerel',
      provider: 'CLIProxy Yerel GGUF / Qwen',
      badge: 'Çevrimdışı & Matematik',
      color: Color(0xFFEC4899),
    ),
  ];
}

class VoicePersona {
  const VoicePersona({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.pitch,
    required this.rate,
    required this.accent,
  });

  final String id;
  final String name;
  final String subtitle;
  final double pitch;
  final double rate;
  final Color accent;

  static const List<VoicePersona> presets = [
    VoicePersona(
      id: 'emel',
      name: 'Emel (Siri Berrak)',
      subtitle: 'Doğal, akıcı ve sıcak Türkçe kadın sesi',
      pitch: 1.06,
      rate: 1.02,
      accent: Color(0xFFFF2E93),
    ),
    VoicePersona(
      id: 'aydin',
      name: 'Aydın (Stüdyo Bariton)',
      subtitle: 'Net, sakin ve güven veren Türkçe erkek sesi',
      pitch: 0.90,
      rate: 1.00,
      accent: Color(0xFF00E5FF),
    ),
    VoicePersona(
      id: 'nova',
      name: 'Nova (Gemini Live)',
      subtitle: 'Dinamik, enerjik ve hızlı yanıt asistanı',
      pitch: 1.12,
      rate: 1.10,
      accent: Color(0xFFA855F7),
    ),
    VoicePersona(
      id: 'sage',
      name: 'Bilge (Claude Anlatıcı)',
      subtitle: 'Derin, tane tane ve belgesel tonunda',
      pitch: 0.96,
      rate: 0.94,
      accent: Color(0xFFF59E0B),
    ),
  ];
}

class ToolCallTrace {
  const ToolCallTrace({
    required this.name,
    required this.title,
    required this.inputSummary,
    required this.outputSummary,
    this.status = 'completed',
    this.durationMs = 120,
  });

  final String name;
  final String title;
  final String inputSummary;
  final String outputSummary;
  final String status;
  final int durationMs;

  Map<String, dynamic> toJson() => {
    'name': name,
    'title': title,
    'inputSummary': inputSummary,
    'outputSummary': outputSummary,
    'status': status,
    'durationMs': durationMs,
  };

  factory ToolCallTrace.fromJson(Map<String, dynamic> json) => ToolCallTrace(
    name: json['name']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    inputSummary: json['inputSummary']?.toString() ?? '',
    outputSummary: json['outputSummary']?.toString() ?? '',
    status: json['status']?.toString() ?? 'completed',
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 120,
  );
}

class WebCitation {
  const WebCitation({
    required this.index,
    required this.title,
    required this.url,
    required this.snippet,
  });

  final int index;
  final String title;
  final String url;
  final String snippet;

  Map<String, dynamic> toJson() => {
    'index': index,
    'title': title,
    'url': url,
    'snippet': snippet,
  };

  factory WebCitation.fromJson(Map<String, dynamic> json) => WebCitation(
    index: (json['index'] as num?)?.toInt() ?? 1,
    title: json['title']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    snippet: json['snippet']?.toString() ?? '',
  );
}

class GeneratedArtifact {
  const GeneratedArtifact({
    required this.id,
    required this.title,
    required this.filePath,
    required this.format,
    required this.mimeType,
    required this.contentPreview,
    required this.createdAt,
    this.sizeBytes = 0,
  });

  final String id;
  final String title;
  final String filePath;
  final String format; // pdf, docx, xlsx, pptx, txt, md, png, jpg, html
  final String mimeType;
  final String contentPreview;
  final DateTime createdAt;
  final int sizeBytes;

  bool get isImage =>
      format == 'png' ||
      format == 'jpg' ||
      format == 'jpeg' ||
      format == 'webp';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'format': format,
    'mimeType': mimeType,
    'contentPreview': contentPreview,
    'createdAt': createdAt.toIso8601String(),
    'sizeBytes': sizeBytes,
  };

  factory GeneratedArtifact.fromJson(Map<String, dynamic> json) =>
      GeneratedArtifact(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Belge',
        filePath: json['filePath']?.toString() ?? '',
        format: json['format']?.toString() ?? 'pdf',
        mimeType: json['mimeType']?.toString() ?? 'application/pdf',
        contentPreview: json['contentPreview']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );
}

class ArenaCandidate {
  const ArenaCandidate({
    required this.modelId,
    required this.modelName,
    required this.provider,
    required this.response,
    required this.latencyMs,
    this.score = 95,
  });

  final String modelId;
  final String modelName;
  final String provider;
  final String response;
  final int latencyMs;
  final int score;

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'provider': provider,
    'response': response,
    'latencyMs': latencyMs,
    'score': score,
  };

  factory ArenaCandidate.fromJson(Map<String, dynamic> json) => ArenaCandidate(
    modelId: json['modelId']?.toString() ?? '',
    modelName: json['modelName']?.toString() ?? '',
    provider: json['provider']?.toString() ?? '',
    response: json['response']?.toString() ?? '',
    latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 400,
    score: (json['score'] as num?)?.toInt() ?? 95,
  );
}

class AttachmentItem {
  const AttachmentItem({
    required this.name,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String name;
  final String path;
  final String mimeType;
  final int sizeBytes;

  bool get isImage => mimeType.startsWith('image/');

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
  };

  factory AttachmentItem.fromJson(Map<String, dynamic> json) => AttachmentItem(
    name: json['name']?.toString() ?? '',
    path: json['path']?.toString() ?? '',
    mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.reasoningText = '',
    this.modelUsed = 'gemini-2.5-pro',
    this.workMode = WorkMode.auto,
    this.attachments = const [],
    this.toolTraces = const [],
    this.citations = const [],
    this.artifacts = const [],
    this.arenaCandidates = const [],
    this.isError = false,
  });

  final String id;
  final String role; // 'user' | 'assistant'
  final String text;
  final DateTime timestamp;
  final String reasoningText;
  final String modelUsed;
  final WorkMode workMode;
  final List<AttachmentItem> attachments;
  final List<ToolCallTrace> toolTraces;
  final List<WebCitation> citations;
  final List<GeneratedArtifact> artifacts;
  final List<ArenaCandidate> arenaCandidates;
  final bool isError;

  ChatMessage copyWith({
    String? text,
    String? reasoningText,
    String? modelUsed,
    WorkMode? workMode,
    List<AttachmentItem>? attachments,
    List<ToolCallTrace>? toolTraces,
    List<WebCitation>? citations,
    List<GeneratedArtifact>? artifacts,
    List<ArenaCandidate>? arenaCandidates,
    bool? isError,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      timestamp: timestamp,
      reasoningText: reasoningText ?? this.reasoningText,
      modelUsed: modelUsed ?? this.modelUsed,
      workMode: workMode ?? this.workMode,
      attachments: attachments ?? this.attachments,
      toolTraces: toolTraces ?? this.toolTraces,
      citations: citations ?? this.citations,
      artifacts: artifacts ?? this.artifacts,
      arenaCandidates: arenaCandidates ?? this.arenaCandidates,
      isError: isError ?? this.isError,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'reasoningText': reasoningText,
    'modelUsed': modelUsed,
    'workMode': workMode.id,
    'attachments': attachments.map((e) => e.toJson()).toList(),
    'toolTraces': toolTraces.map((e) => e.toJson()).toList(),
    'citations': citations.map((e) => e.toJson()).toList(),
    'artifacts': artifacts.map((e) => e.toJson()).toList(),
    'arenaCandidates': arenaCandidates.map((e) => e.toJson()).toList(),
    'isError': isError,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id']?.toString() ?? '',
    role: json['role']?.toString() ?? 'assistant',
    text: json['text']?.toString() ?? '',
    timestamp:
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now(),
    reasoningText: json['reasoningText']?.toString() ?? '',
    modelUsed: json['modelUsed']?.toString() ?? 'gemini-2.5-pro',
    workMode: WorkMode.fromId(json['workMode']?.toString()),
    attachments: ((json['attachments'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => AttachmentItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    toolTraces: ((json['toolTraces'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ToolCallTrace.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    citations: ((json['citations'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => WebCitation.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    artifacts: ((json['artifacts'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => GeneratedArtifact.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    arenaCandidates: ((json['arenaCandidates'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ArenaCandidate.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    isError: json['isError'] == true,
  );
}

class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.pinned = false,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  final bool pinned;

  ChatThread copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    bool? pinned,
  }) {
    return ChatThread(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      pinned: pinned ?? this.pinned,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((e) => e.toJson()).toList(),
    'pinned': pinned,
  };

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Yeni Sohbet',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now(),
    messages: ((json['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    pinned: json['pinned'] == true,
  );
}

class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.category,
    required this.fact,
    required this.createdAt,
  });

  final String id;
  final String category; // tercih, kisisel, proje, not
  final String fact;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'fact': fact,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MemoryFact.fromJson(Map<String, dynamic> json) => MemoryFact(
    id: json['id']?.toString() ?? '',
    category: json['category']?.toString() ?? 'not',
    fact: json['fact']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.title,
    required this.body,
    required this.triggerAt,
    this.completed = false,
  });

  final int id;
  final String title;
  final String body;
  final DateTime triggerAt;
  final bool completed;

  ReminderItem copyWith({bool? completed}) => ReminderItem(
    id: id,
    title: title,
    body: body,
    triggerAt: triggerAt,
    completed: completed ?? this.completed,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'triggerAt': triggerAt.toIso8601String(),
    'completed': completed,
  };

  factory ReminderItem.fromJson(Map<String, dynamic> json) => ReminderItem(
    id: (json['id'] as num?)?.toInt() ?? 1001,
    title: json['title']?.toString() ?? '',
    body: json['body']?.toString() ?? '',
    triggerAt:
        DateTime.tryParse(json['triggerAt']?.toString() ?? '') ??
        DateTime.now(),
    completed: json['completed'] == true,
  );
}

class SharedInboxItem {
  const SharedInboxItem({
    required this.id,
    required this.title,
    required this.text,
    required this.files,
    required this.receivedAt,
  });

  final String id;
  final String title;
  final String text;
  final List<AttachmentItem> files;
  final DateTime receivedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'text': text,
    'files': files.map((e) => e.toJson()).toList(),
    'receivedAt': receivedAt.toIso8601String(),
  };

  factory SharedInboxItem.fromJson(Map<String, dynamic> json) =>
      SharedInboxItem(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Paylaşılan İçerik',
        text: json['text']?.toString() ?? '',
        files: ((json['files'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AttachmentItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        receivedAt:
            DateTime.tryParse(json['receivedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.authToken = '',
    this.enabled = true,
    this.tools = const [],
  });

  final String id;
  final String name;
  final String url;
  final String authToken;
  final bool enabled;
  final List<String> tools;

  McpServerConfig copyWith({
    String? name,
    String? url,
    String? authToken,
    bool? enabled,
    List<String>? tools,
  }) => McpServerConfig(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    authToken: authToken ?? this.authToken,
    enabled: enabled ?? this.enabled,
    tools: tools ?? this.tools,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'authToken': authToken,
    'enabled': enabled,
    'tools': tools,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'MCP Sunucu',
        url: json['url']?.toString() ?? '',
        authToken: json['authToken']?.toString() ?? '',
        enabled: json['enabled'] != false,
        tools: ((json['tools'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class PlanStepItem {
  const PlanStepItem({
    required this.index,
    required this.title,
    this.status = 'tamam',
    this.detail = '',
  });

  final int index;
  final String title;
  final String status; // bekliyor, calisiyor, tamam, hata
  final String detail;
}

class DeviceStatusSnapshot {
  const DeviceStatusSnapshot({
    this.batteryPercent = 100,
    this.isCharging = false,
    this.batteryTempC = 28.0,
    this.storageTotalGb = 128.0,
    this.storageFreeGb = 64.0,
    this.volumePercent = 70,
    this.ringerMode = 'normal',
    this.torchEnabled = false,
    this.ignoringBatteryOptimizations = true,
    this.deviceModel = 'Android Cihaz',
    this.androidVersion = '14',
  });

  final int batteryPercent;
  final bool isCharging;
  final double batteryTempC;
  final double storageTotalGb;
  final double storageFreeGb;
  final int volumePercent;
  final String ringerMode;
  final bool torchEnabled;
  final bool ignoringBatteryOptimizations;
  final String deviceModel;
  final String androidVersion;

  factory DeviceStatusSnapshot.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const DeviceStatusSnapshot();
    return DeviceStatusSnapshot(
      batteryPercent: (map['batteryPercent'] as num?)?.toInt() ?? 100,
      isCharging: map['isCharging'] == true,
      batteryTempC: (map['batteryTempC'] as num?)?.toDouble() ?? 28.0,
      storageTotalGb: (map['storageTotalGb'] as num?)?.toDouble() ?? 128.0,
      storageFreeGb: (map['storageFreeGb'] as num?)?.toDouble() ?? 64.0,
      volumePercent: (map['volumePercent'] as num?)?.toInt() ?? 70,
      ringerMode: map['ringerMode']?.toString() ?? 'normal',
      torchEnabled: map['torchEnabled'] == true,
      ignoringBatteryOptimizations:
          map['ignoringBatteryOptimizations'] != false,
      deviceModel: map['deviceModel']?.toString() ?? 'Android',
      androidVersion: map['androidVersion']?.toString() ?? '14',
    );
  }
}

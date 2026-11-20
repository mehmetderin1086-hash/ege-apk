import 'dart:convert';

enum ApiProvider { cliProxyApi, geminiDirect, openAiCompatible }

extension ApiProviderX on ApiProvider {
  String get label => switch (this) {
    ApiProvider.cliProxyApi => 'CLI Proxy API',
    ApiProvider.geminiDirect => 'Gemini',
    ApiProvider.openAiCompatible => 'OpenAI',
  };
}

class ProxyModelInfo {
  final String id;
  final String ownedBy;
  final String category; // 'chat' | 'image' | 'tts' | 'embedding'

  const ProxyModelInfo({
    required this.id,
    this.ownedBy = 'cliproxy',
    this.category = 'chat',
  });

  factory ProxyModelInfo.classify(String id, [String ownedBy = 'cliproxy']) {
    final lower = id.toLowerCase();
    String category = 'chat';
    if (lower.contains('image') ||
        lower.contains('nano-banana') ||
        lower.startsWith('imagen-') ||
        lower.startsWith('dall-e')) {
      category = 'image';
    } else if (lower.endsWith('-tts') || lower.contains('tts')) {
      category = 'tts';
    } else if (lower.contains('embedding')) {
      category = 'embedding';
    }
    return ProxyModelInfo(
      id: id,
      ownedBy: ownedBy.isEmpty ? 'cliproxy' : ownedBy,
      category: category,
    );
  }

  String get familyLabel {
    final l = id.toLowerCase();
    final o = ownedBy.toLowerCase();
    if (l.startsWith('dersdas-') || l.startsWith('qwen')) return 'DersDas';
    if (l.startsWith('antigravity-') ||
        l.contains('claude') ||
        o == 'anthropic' ||
        o == 'claude') {
      return l.contains('claude') ? 'Claude' : 'Antigravity';
    }
    if (l.startsWith('gemini') ||
        l.startsWith('gemma-') ||
        o == 'google' ||
        o == 'gemini' ||
        o == 'gemini-script' ||
        o == 'gemini-tts' ||
        o == 'gemini-api') {
      return 'Gemini';
    }
    if (l.startsWith('gpt') ||
        l.contains('codex') ||
        RegExp(r'^o[134](?:-|$)').hasMatch(l) ||
        o == 'openai' ||
        o == 'openai-api' ||
        o == 'codex') {
      return 'GPT / Codex';
    }
    return ownedBy;
  }

  String get categoryLabel {
    switch (category) {
      case 'image':
        return 'Görsel Üretim';
      case 'tts':
        return 'Ses (TTS)';
      case 'embedding':
        return 'Embedding';
      default:
        return 'Sohbet & Kod';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owned_by': ownedBy,
    'category': category,
  };

  factory ProxyModelInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final ownedBy = json['owned_by']?.toString() ?? 'cliproxy';
    final cat = json['category']?.toString();
    if (cat != null && cat.isNotEmpty) {
      return ProxyModelInfo(id: id, ownedBy: ownedBy, category: cat);
    }
    return ProxyModelInfo.classify(id, ownedBy);
  }

  static List<ProxyModelInfo> mergeCatalog(
    Iterable<ProxyModelInfo> primary, [
    Iterable<ProxyModelInfo> fallback = fallbackCatalog,
  ]) {
    final seen = <String>{};
    final merged = <ProxyModelInfo>[];
    for (final m in primary) {
      final id = m.id.trim();
      if (id.isNotEmpty && seen.add(id)) {
        merged.add(m);
      }
    }
    for (final m in fallback) {
      final id = m.id.trim();
      if (id.isNotEmpty && seen.add(id)) {
        merged.add(m);
      }
    }
    return merged;
  }

  static const List<ProxyModelInfo> fallbackCatalog = [
    // Gemini 4 (En Yeni Frontier Nesil)
    ProxyModelInfo(id: 'gemini-4-carbon', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-4-carbon-high', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-carbon-medium', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-carbon-low', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-argon', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-4-argon-high', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-argon-medium', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-argon-low', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-hydrogen', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-4-hydrogen-xhigh', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-hydrogen-high', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-hydrogen-medium', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-4-hydrogen-low', ownedBy: 'cliproxy'),
    // Gemini 3.8 / 3.x / Omni / Gemma 4
    ProxyModelInfo(id: 'gemini-3.8-flash', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3.8-flash-high', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-3.8-flash-medium', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-3.8-flash-low', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-3.8-live', ownedBy: 'gemini-script'),
    ProxyModelInfo(id: 'gemini-omni-1.2-flash', ownedBy: 'gemini-script'),
    ProxyModelInfo(id: 'gemini-3.7-flash', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3.6-flash', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3.5-flash', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3.5-flash-lite', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3.5-transcribe', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3.1-pro-preview', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3.1-pro-high', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-3.1-pro-low', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gemini-3.1-flash-lite', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-3-flash-preview', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemma-4-31b-it', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemma-4-26b-a4b-it', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-flash-latest', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-flash-lite-latest', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-pro-latest', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-2.5-pro', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-2.5-flash', ownedBy: 'google'),
    ProxyModelInfo(id: 'gemini-2.5-flash-lite', ownedBy: 'google'),
    // Claude 5.5 / 5 / 4.x & Antigravity
    ProxyModelInfo(id: 'claude-opus-5-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-opus-5-5-high', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'claude-opus-5-5-medium', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'claude-opus-5-5-low', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'claude-sonnet-5-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-sonnet-5-5-high', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'claude-sonnet-5-5-medium', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'claude-sonnet-5-5-low', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'claude-fable-5-1', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-opus-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-sonnet-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-fable-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-opus-4-8', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-opus-4-7', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-opus-4-6', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-sonnet-4-6', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-opus-4-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-sonnet-4-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'claude-haiku-4-5', ownedBy: 'anthropic'),
    ProxyModelInfo(id: 'antigravity-claude-opus-5-5', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'antigravity-claude-sonnet-5-5', ownedBy: 'cliproxy'),
    // OpenAI GPT-6.2 / GPT-6.1 / GPT-6 / Codex / o-Serisi
    ProxyModelInfo(id: 'gpt-6.2-sol', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-6.2-astra', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-6.1-terra', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-6.1-sol', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-6-astra', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-6-sol', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-6-luna', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-reserve', ownedBy: 'openai'),
    ProxyModelInfo(id: 'codex-auto-review', ownedBy: 'codex'),
    ProxyModelInfo(id: 'gpt-5.6-sol', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-5.6-terra', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-5.6-luna', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-5.5', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gpt-5.4', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gpt-5.3-codex', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'gpt-oss-120b-medium', ownedBy: 'cliproxy'),
    ProxyModelInfo(id: 'o3', ownedBy: 'openai'),
    ProxyModelInfo(id: 'o4-mini', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-4.1', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-4o', ownedBy: 'openai'),
    ProxyModelInfo(id: 'gpt-4o-mini', ownedBy: 'openai'),
    // DersDas & Özel Araç Modelleri
    ProxyModelInfo(id: 'dersdas-gemini-tools', ownedBy: 'gemini-script'),
    ProxyModelInfo(id: 'dersdas-gemini-verifier', ownedBy: 'gemini-script'),
    ProxyModelInfo(id: 'dersdas-gemini-ocr', ownedBy: 'gemini-script'),
    ProxyModelInfo(id: 'qwen2.5-math-1.5b-instruct', ownedBy: 'qwen-math'),
    // Görsel Üretim Modelleri
    ProxyModelInfo(
      id: 'gemini-nano-banana-2.1',
      ownedBy: 'gemini-script',
      category: 'image',
    ),
    ProxyModelInfo(
      id: 'gemini-3-pro-image',
      ownedBy: 'gemini-script',
      category: 'image',
    ),
    ProxyModelInfo(
      id: 'gemini-3.1-flash-lite-image',
      ownedBy: 'gemini-script',
      category: 'image',
    ),
    ProxyModelInfo(
      id: 'gemini-3.1-flash-image',
      ownedBy: 'gemini-script',
      category: 'image',
    ),
    ProxyModelInfo(
      id: 'antigravity-gemini-image',
      ownedBy: 'cliproxy',
      category: 'image',
    ),
    ProxyModelInfo(
      id: 'gpt-image-2.6',
      ownedBy: 'codex',
      category: 'image',
    ),
    ProxyModelInfo(
      id: 'gpt-image-2.5-flare',
      ownedBy: 'codex',
      category: 'image',
    ),
    ProxyModelInfo(
      id: 'gpt-image-2.5-sunburst',
      ownedBy: 'codex',
      category: 'image',
    ),
    // Ses (TTS) Modelleri
    ProxyModelInfo(
      id: 'gemini-3.8-flash-tts',
      ownedBy: 'google',
      category: 'tts',
    ),
    ProxyModelInfo(
      id: 'gemini-3.8-flash-lite-tts',
      ownedBy: 'google',
      category: 'tts',
    ),
    ProxyModelInfo(
      id: 'gpt-4o-mini-tts',
      ownedBy: 'openai-api',
      category: 'tts',
    ),
    // Embedding Modelleri
    ProxyModelInfo(
      id: 'gemini-embedding-2',
      ownedBy: 'google',
      category: 'embedding',
    ),
    ProxyModelInfo(
      id: 'gemini-embedding-001',
      ownedBy: 'google',
      category: 'embedding',
    ),
    ProxyModelInfo(
      id: 'text-embedding-3-large',
      ownedBy: 'openai',
      category: 'embedding',
    ),
    ProxyModelInfo(
      id: 'text-embedding-3-small',
      ownedBy: 'openai',
      category: 'embedding',
    ),
  ];
}

class JarvisVoiceOption {
  final String id;
  final String label;
  final String engine; // 'azure' | 'chirp' | 'openai' | 'edge'

  /// 'f' | 'm' | 'n'
  final String gender;
  final String description;

  const JarvisVoiceOption({
    required this.id,
    required this.label,
    required this.engine,
    this.gender = 'n',
    this.description = '',
  });

  String get shortName => label.split(' • ').first;

  String get engineLabel => switch (engine) {
    'chirp' => 'Google Chirp 3 HD / Gemini',
    'openai' => 'OpenAI TTS',
    'edge' => 'Edge Neural (ücretsiz)',
    _ => 'Azure Speech',
  };
}

/// Speaking style applied to cloud TTS engines.
class JarvisVoiceStyle {
  final String id;
  final String label;
  final String gemini;
  final String openai;

  /// Preferred Azure `mstts:express-as` styles, best first. Each Azure voice
  /// supports its own list (MAI voices reject unknown styles with HTTP 400),
  /// so the first one the voice supports is used.
  final List<String> azureStyles;

  /// Prosody nudges (percent) used when no style can be applied.
  final int ratePct;
  final int pitchPct;

  const JarvisVoiceStyle({
    required this.id,
    required this.label,
    required this.gemini,
    required this.openai,
    this.azureStyles = const [],
    this.ratePct = 0,
    this.pitchPct = 0,
  });
}

class JarvisVoiceCatalog {
  /// Recommended default cloud voice (Azure MAI HD, ~0.9 s latency).
  static const String defaultHdVoice = 'tr-TR-Aydin:MAI-Voice-2.1-Flash';

  static const Map<String, String> chirpVoices = {
    'zephyr': 'Zephyr',
    'puck': 'Puck',
    'charon': 'Charon',
    'kore': 'Kore',
    'fenrir': 'Fenrir',
    'leda': 'Leda',
    'orus': 'Orus',
    'aoede': 'Aoede',
    'callirrhoe': 'Callirrhoe',
    'autonoe': 'Autonoe',
    'enceladus': 'Enceladus',
    'iapetus': 'Iapetus',
    'umbriel': 'Umbriel',
    'algieba': 'Algieba',
    'despina': 'Despina',
    'erinome': 'Erinome',
    'algenib': 'Algenib',
    'rasalgethi': 'Rasalgethi',
    'laomedeia': 'Laomedeia',
    'achernar': 'Achernar',
    'alnilam': 'Alnilam',
    'schedar': 'Schedar',
    'gacrux': 'Gacrux',
    'pulcherrima': 'Pulcherrima',
    'achird': 'Achird',
    'zubenelgenubi': 'Zubenelgenubi',
    'vindemiatrix': 'Vindemiatrix',
    'sadachbia': 'Sadachbia',
    'sadaltager': 'Sadaltager',
    'sulafat': 'Sulafat',
  };

  static const Map<String, JarvisVoiceStyle> styles = {
    'jarvis': JarvisVoiceStyle(
      id: 'jarvis',
      label: 'Ege',
      gemini:
          'kibar, özgüvenli, hafif resmi ve zeki bir yapay zekâ asistanı tonu',
      openai: 'Ege gibi kibar, özgüvenli, hafif resmi ve net bir Türkçe telaffuzla konuş.',
      azureStyles: ['agent', 'educational'],
    ),
    'natural': JarvisVoiceStyle(
      id: 'natural',
      label: 'Doğal',
      gemini: 'doğal, akıcı ve net Türkçe konuşma',
      openai: 'Doğal, akıcı ve net bir Türkçe telaffuzla konuş.',
    ),
    'warm': JarvisVoiceStyle(
      id: 'warm',
      label: 'Sıcak',
      gemini: 'sıcak, samimi ve gülümseyen bir ses tonu',
      openai: 'Sıcak, samimi ve gülümseyen bir ses tonuyla Türkçe konuş.',
      azureStyles: [
        'friendlycheerful',
        'caringempathy',
        'friendly',
        'cheerful',
      ],
      pitchPct: 2,
    ),
    'energetic': JarvisVoiceStyle(
      id: 'energetic',
      label: 'Enerjik',
      gemini: 'enerjik, heyecanlı ve canlı bir ses tonu',
      openai: 'Enerjik, heyecanlı ve canlı bir tonla Türkçe konuş.',
      azureStyles: ['excited', 'encouraging', 'adventurous', 'cheerful'],
      ratePct: 7,
      pitchPct: 4,
    ),
    'calm': JarvisVoiceStyle(
      id: 'calm',
      label: 'Sakin',
      gemini: 'sakin, yavaş ve rahatlatıcı bir ses tonu',
      openai: 'Sakin, yavaş ve rahatlatıcı bir tonla Türkçe konuş.',
      azureStyles: ['reflective', 'caringempathy', 'calm'],
      ratePct: -8,
      pitchPct: -2,
    ),
    'news': JarvisVoiceStyle(
      id: 'news',
      label: 'Haber Spikeri',
      gemini: 'profesyonel bir haber spikeri gibi net ve vurgulu',
      openai:
          'Profesyonel bir haber spikeri gibi net, vurgulu ve tarafsız konuş.',
      azureStyles: ['serious', 'educational', 'newscast'],
    ),
    'story': JarvisVoiceStyle(
      id: 'story',
      label: 'Hikâye',
      gemini: 'sürükleyici bir hikâye anlatıcısı gibi duygulu',
      openai: 'Sürükleyici bir hikâye anlatıcısı gibi duygulu ve akıcı konuş.',
      azureStyles: ['narrator', 'audiobook', 'nostalgic', 'narration-relaxed'],
      ratePct: -4,
    ),
    'whisper': JarvisVoiceStyle(
      id: 'whisper',
      label: 'Fısıltı',
      gemini: 'yumuşak bir fısıltı',
      openai: 'Yumuşak ve alçak sesle, fısıldar gibi konuş.',
      azureStyles: ['whispering'],
      ratePct: -6,
    ),
  };

  static JarvisVoiceStyle styleFor(String id) =>
      styles[id] ?? styles['jarvis']!;

  static const List<String> _maiStyles = [
    'adventurous',
    'caringempathy',
    'curious',
    'encouraging',
    'excited',
    'friendlycheerful',
    'nostalgic',
    'reflective',
    'saddisappointed',
    'serious',
  ];

  /// Styles accepted by Dragon HD voices (they tolerate standard styles).
  static const List<String> _dragonStyles = [
    'cheerful',
    'calm',
    'excited',
    'friendly',
    'serious',
    'whispering',
    'newscast',
    'narration-relaxed',
  ];

  /// Azure styles a voice accepts (empty = no `express-as`).
  static List<String> azureStylesFor(String voiceId) {
    final v = voiceId.toLowerCase();
    if (v.contains('mai-voice')) {
      if (v.contains('grant')) return const ['educational', 'narrator'];
      if (v.contains('harper')) {
        return const ['agent', 'audiobook', 'customer_call_center'];
      }
      return _maiStyles;
    }
    if (v.contains('dragon')) return _dragonStyles;
    return const [];
  }

  /// First style of [style] that [voiceId] supports, or null.
  static String? resolveAzureStyle(String voiceId, JarvisVoiceStyle style) {
    final supported = azureStylesFor(voiceId);
    for (final s in style.azureStyles) {
      if (supported.contains(s)) return s;
    }
    return null;
  }

  /// Maps legacy short ids to real Azure voice names.
  static String azureVoiceName(String rawVoice) {
    final v = stripVoicePrefix(rawVoice);
    switch (v.toLowerCase()) {
      case 'elif':
        return 'tr-TR-Elif:MAI-Voice-2-Flash';
      case 'aydin':
      case 'aydın':
        return 'tr-TR-Aydın:MAI-Voice-2-Flash';
      case 'ahmet':
        return 'tr-TR-AhmetNeural';
      case 'emel':
        return 'tr-TR-EmelNeural';
    }
    return v;
  }

  static const List<JarvisVoiceOption> azureVoices = [
    JarvisVoiceOption(
      id: 'tr-TR-Aydin:MAI-Voice-2.1-Flash',
      label: 'Aydın 2.1 • Azure HD (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Önerilen • doğal HD erkek, ~0,9 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Elif:MAI-Voice-2.1-Flash',
      label: 'Elif 2.1 • Azure HD (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Doğal HD kadın, ~1 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Ahmet:DragonLatestNeural',
      label: 'Ahmet Dragon • Azure HD (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Dragon HD, sıcak ve akıcı, ~0,8 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Seda:DragonLatestNeural',
      label: 'Seda Dragon • Azure HD (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Dragon HD, net ve akıcı, ~0,8 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Grant:MAI-Voice-2.1-Flash',
      label: 'Grant • Azure HD (Anlatıcı Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Eğitici / anlatıcı tonu',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Harper:MAI-Voice-2.1-Flash',
      label: 'Harper • Azure HD (Asistan Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Asistan / sesli kitap tonu',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Aydin:MAI-Voice-2.1',
      label: 'Aydın Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'm',
      description: 'En yüksek kalite, ~1,4 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Elif:MAI-Voice-2.1',
      label: 'Elif Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'f',
      description: 'En yüksek kalite, ~1,5 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Grant:MAI-Voice-2.1',
      label: 'Grant Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'm',
      description: 'Anlatıcı, en yüksek kalite',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Harper:MAI-Voice-2.1',
      label: 'Harper Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'f',
      description: 'Asistan, en yüksek kalite',
    ),
    JarvisVoiceOption(
      id: 'aydin',
      label: 'Aydın 2.0 • Azure HD (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'MAI-Voice-2 Flash',
    ),
    JarvisVoiceOption(
      id: 'elif',
      label: 'Elif 2.0 • Azure HD (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'MAI-Voice-2 Flash',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-AhmetNeural',
      label: 'Ahmet • Azure Neural (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Standart neural, ~0,6 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-EmelNeural',
      label: 'Emel • Azure Neural (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Standart neural, ~0,7 sn',
    ),
    JarvisVoiceOption(
      id: 'en-US-AndrewMultilingualNeural',
      label: 'Andrew • Azure Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Türkçe konuşur, sıcak erkek',
    ),
    JarvisVoiceOption(
      id: 'en-US-AvaMultilingualNeural',
      label: 'Ava • Azure Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Türkçe konuşur, akıcı kadın',
    ),
    JarvisVoiceOption(
      id: 'en-US-BrianMultilingualNeural',
      label: 'Brian • Azure Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Türkçe konuşur, genç erkek',
    ),
    JarvisVoiceOption(
      id: 'en-US-EmmaMultilingualNeural',
      label: 'Emma • Azure Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Türkçe konuşur, neşeli kadın',
    ),
    JarvisVoiceOption(
      id: 'de-DE-FlorianMultilingualNeural',
      label: 'Florian • Azure Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Tok, profesyonel erkek',
    ),
    JarvisVoiceOption(
      id: 'de-DE-SeraphinaMultilingualNeural',
      label: 'Seraphina • Azure Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Yumuşak, olgun kadın',
    ),
    JarvisVoiceOption(
      id: 'en-US-Andrew:DragonHDLatestNeural',
      label: 'Andrew Dragon • Azure HD Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Dragon HD, Türkçe konuşur',
    ),
    JarvisVoiceOption(
      id: 'en-US-Ava:DragonHDLatestNeural',
      label: 'Ava Dragon • Azure HD Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Dragon HD, Türkçe konuşur',
    ),
  ];

  static const List<JarvisVoiceOption> chirpCatalog = [
    JarvisVoiceOption(
      id: 'Zephyr',
      label: 'Zephyr • Google Chirp 3 HD (Parlak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Parlak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Puck',
      label: 'Puck • Google Chirp 3 HD (Neşeli)',
      engine: 'chirp',
      gender: 'm',
      description: 'Neşeli • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Charon',
      label: 'Charon • Google Chirp 3 HD (Bilgilendirici)',
      engine: 'chirp',
      gender: 'm',
      description: 'Bilgilendirici • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Kore',
      label: 'Kore • Google Chirp 3 HD (Kararlı, net)',
      engine: 'chirp',
      gender: 'f',
      description: 'Kararlı, net • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Fenrir',
      label: 'Fenrir • Google Chirp 3 HD (Heyecanlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Heyecanlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Leda',
      label: 'Leda • Google Chirp 3 HD (Genç)',
      engine: 'chirp',
      gender: 'f',
      description: 'Genç • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Orus',
      label: 'Orus • Google Chirp 3 HD (Sakin, kararlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Sakin, kararlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Aoede',
      label: 'Aoede • Google Chirp 3 HD (Ferah, doğal)',
      engine: 'chirp',
      gender: 'f',
      description: 'Ferah, doğal • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Callirrhoe',
      label: 'Callirrhoe • Google Chirp 3 HD (Rahat)',
      engine: 'chirp',
      gender: 'f',
      description: 'Rahat • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Autonoe',
      label: 'Autonoe • Google Chirp 3 HD (Parlak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Parlak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Enceladus',
      label: 'Enceladus • Google Chirp 3 HD (Derin, nefesli)',
      engine: 'chirp',
      gender: 'm',
      description: 'Derin, nefesli • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Iapetus',
      label: 'Iapetus • Google Chirp 3 HD (Net)',
      engine: 'chirp',
      gender: 'm',
      description: 'Net • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Umbriel',
      label: 'Umbriel • Google Chirp 3 HD (Rahat)',
      engine: 'chirp',
      gender: 'm',
      description: 'Rahat • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Algieba',
      label: 'Algieba • Google Chirp 3 HD (Pürüzsüz)',
      engine: 'chirp',
      gender: 'm',
      description: 'Pürüzsüz • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Despina',
      label: 'Despina • Google Chirp 3 HD (Pürüzsüz)',
      engine: 'chirp',
      gender: 'f',
      description: 'Pürüzsüz • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Erinome',
      label: 'Erinome • Google Chirp 3 HD (Net)',
      engine: 'chirp',
      gender: 'f',
      description: 'Net • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Algenib',
      label: 'Algenib • Google Chirp 3 HD (Tok, pürüzlü)',
      engine: 'chirp',
      gender: 'm',
      description: 'Tok, pürüzlü • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Rasalgethi',
      label: 'Rasalgethi • Google Chirp 3 HD (Bilgilendirici)',
      engine: 'chirp',
      gender: 'm',
      description: 'Bilgilendirici • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Laomedeia',
      label: 'Laomedeia • Google Chirp 3 HD (Neşeli)',
      engine: 'chirp',
      gender: 'f',
      description: 'Neşeli • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Achernar',
      label: 'Achernar • Google Chirp 3 HD (Yumuşak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Yumuşak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Alnilam',
      label: 'Alnilam • Google Chirp 3 HD (Kararlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Kararlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Schedar',
      label: 'Schedar • Google Chirp 3 HD (Dengeli)',
      engine: 'chirp',
      gender: 'm',
      description: 'Dengeli • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Gacrux',
      label: 'Gacrux • Google Chirp 3 HD (Olgun)',
      engine: 'chirp',
      gender: 'f',
      description: 'Olgun • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Pulcherrima',
      label: 'Pulcherrima • Google Chirp 3 HD (Atak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Atak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Achird',
      label: 'Achird • Google Chirp 3 HD (Samimi)',
      engine: 'chirp',
      gender: 'm',
      description: 'Samimi • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Zubenelgenubi',
      label: 'Zubenelgenubi • Google Chirp 3 HD (Gündelik)',
      engine: 'chirp',
      gender: 'm',
      description: 'Gündelik • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Vindemiatrix',
      label: 'Vindemiatrix • Google Chirp 3 HD (Nazik)',
      engine: 'chirp',
      gender: 'f',
      description: 'Nazik • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Sadachbia',
      label: 'Sadachbia • Google Chirp 3 HD (Canlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Canlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Sadaltager',
      label: 'Sadaltager • Google Chirp 3 HD (Bilgili)',
      engine: 'chirp',
      gender: 'm',
      description: 'Bilgili • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Sulafat',
      label: 'Sulafat • Google Chirp 3 HD (Sıcak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Sıcak • Kadın',
    ),
  ];

  static const List<JarvisVoiceOption> openAiTtsVoices = [
    JarvisVoiceOption(
      id: 'alloy',
      label: 'Alloy • OpenAI TTS (Dengeli)',
      engine: 'openai',
      gender: 'n',
      description: 'gpt-4o-mini-tts • Dengeli',
    ),
    JarvisVoiceOption(
      id: 'ash',
      label: 'Ash • OpenAI TTS (Sakin)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Sakin',
    ),
    JarvisVoiceOption(
      id: 'ballad',
      label: 'Ballad • OpenAI TTS (Sıcak)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Sıcak',
    ),
    JarvisVoiceOption(
      id: 'coral',
      label: 'Coral • OpenAI TTS (Canlı)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Canlı',
    ),
    JarvisVoiceOption(
      id: 'echo',
      label: 'Echo • OpenAI TTS (Tok)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Tok',
    ),
    JarvisVoiceOption(
      id: 'fable',
      label: 'Fable • OpenAI TTS (Anlatıcı)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Anlatıcı',
    ),
    JarvisVoiceOption(
      id: 'nova',
      label: 'Nova • OpenAI TTS (Enerjik)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Enerjik',
    ),
    JarvisVoiceOption(
      id: 'onyx',
      label: 'Onyx • OpenAI TTS (Derin)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Derin',
    ),
    JarvisVoiceOption(
      id: 'sage',
      label: 'Sage • OpenAI TTS (Bilge)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Bilge',
    ),
    JarvisVoiceOption(
      id: 'shimmer',
      label: 'Shimmer • OpenAI TTS (Parlak)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Parlak',
    ),
    JarvisVoiceOption(
      id: 'verse',
      label: 'Verse • OpenAI TTS (Akıcı)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Akıcı',
    ),
    JarvisVoiceOption(
      id: 'marin',
      label: 'Marin • OpenAI TTS (Net)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Net',
    ),
    JarvisVoiceOption(
      id: 'cedar',
      label: 'Cedar • OpenAI TTS (Doğal)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Doğal',
    ),
  ];

  static const List<JarvisVoiceOption> edgeVoices = [
    JarvisVoiceOption(
      id: 'tr-TR-AhmetNeural',
      label: 'Ahmet • Edge Neural (ücretsiz)',
      engine: 'edge',
      gender: 'm',
      description: 'Anahtar gerektirmez • ~1,5 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-EmelNeural',
      label: 'Emel • Edge Neural (ücretsiz)',
      engine: 'edge',
      gender: 'f',
      description: 'Anahtar gerektirmez • ~2 sn',
    ),
  ];

  /// Every selectable cloud voice (Azure + Chirp 3 HD + OpenAI).
  static const List<JarvisVoiceOption> presets = [
    JarvisVoiceOption(
      id: 'tr-TR-Aydin:MAI-Voice-2.1-Flash',
      label: 'Aydın 2.1 • Azure HD (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Önerilen • doğal HD erkek, ~0,9 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Elif:MAI-Voice-2.1-Flash',
      label: 'Elif 2.1 • Azure HD (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Doğal HD kadın, ~1 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Ahmet:DragonLatestNeural',
      label: 'Ahmet Dragon • Azure HD (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Dragon HD, sıcak ve akıcı, ~0,8 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Seda:DragonLatestNeural',
      label: 'Seda Dragon • Azure HD (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Dragon HD, net ve akıcı, ~0,8 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Grant:MAI-Voice-2.1-Flash',
      label: 'Grant • Azure HD (Anlatıcı Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Eğitici / anlatıcı tonu',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Harper:MAI-Voice-2.1-Flash',
      label: 'Harper • Azure HD (Asistan Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Asistan / sesli kitap tonu',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Aydin:MAI-Voice-2.1',
      label: 'Aydın Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'm',
      description: 'En yüksek kalite, ~1,4 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Elif:MAI-Voice-2.1',
      label: 'Elif Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'f',
      description: 'En yüksek kalite, ~1,5 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Grant:MAI-Voice-2.1',
      label: 'Grant Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'm',
      description: 'Anlatıcı, en yüksek kalite',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-Harper:MAI-Voice-2.1',
      label: 'Harper Pro • Azure NeuralHD',
      engine: 'azure',
      gender: 'f',
      description: 'Asistan, en yüksek kalite',
    ),
    JarvisVoiceOption(
      id: 'aydin',
      label: 'Aydın 2.0 • Azure HD (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'MAI-Voice-2 Flash',
    ),
    JarvisVoiceOption(
      id: 'elif',
      label: 'Elif 2.0 • Azure HD (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'MAI-Voice-2 Flash',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-AhmetNeural',
      label: 'Ahmet • Azure Neural (Türkçe Erkek)',
      engine: 'azure',
      gender: 'm',
      description: 'Standart neural, ~0,6 sn',
    ),
    JarvisVoiceOption(
      id: 'tr-TR-EmelNeural',
      label: 'Emel • Azure Neural (Türkçe Kadın)',
      engine: 'azure',
      gender: 'f',
      description: 'Standart neural, ~0,7 sn',
    ),
    JarvisVoiceOption(
      id: 'en-US-AndrewMultilingualNeural',
      label: 'Andrew • Azure Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Türkçe konuşur, sıcak erkek',
    ),
    JarvisVoiceOption(
      id: 'en-US-AvaMultilingualNeural',
      label: 'Ava • Azure Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Türkçe konuşur, akıcı kadın',
    ),
    JarvisVoiceOption(
      id: 'en-US-BrianMultilingualNeural',
      label: 'Brian • Azure Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Türkçe konuşur, genç erkek',
    ),
    JarvisVoiceOption(
      id: 'en-US-EmmaMultilingualNeural',
      label: 'Emma • Azure Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Türkçe konuşur, neşeli kadın',
    ),
    JarvisVoiceOption(
      id: 'de-DE-FlorianMultilingualNeural',
      label: 'Florian • Azure Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Tok, profesyonel erkek',
    ),
    JarvisVoiceOption(
      id: 'de-DE-SeraphinaMultilingualNeural',
      label: 'Seraphina • Azure Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Yumuşak, olgun kadın',
    ),
    JarvisVoiceOption(
      id: 'en-US-Andrew:DragonHDLatestNeural',
      label: 'Andrew Dragon • Azure HD Çok Dilli',
      engine: 'azure',
      gender: 'm',
      description: 'Dragon HD, Türkçe konuşur',
    ),
    JarvisVoiceOption(
      id: 'en-US-Ava:DragonHDLatestNeural',
      label: 'Ava Dragon • Azure HD Çok Dilli',
      engine: 'azure',
      gender: 'f',
      description: 'Dragon HD, Türkçe konuşur',
    ),
    JarvisVoiceOption(
      id: 'Zephyr',
      label: 'Zephyr • Google Chirp 3 HD (Parlak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Parlak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Puck',
      label: 'Puck • Google Chirp 3 HD (Neşeli)',
      engine: 'chirp',
      gender: 'm',
      description: 'Neşeli • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Charon',
      label: 'Charon • Google Chirp 3 HD (Bilgilendirici)',
      engine: 'chirp',
      gender: 'm',
      description: 'Bilgilendirici • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Kore',
      label: 'Kore • Google Chirp 3 HD (Kararlı, net)',
      engine: 'chirp',
      gender: 'f',
      description: 'Kararlı, net • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Fenrir',
      label: 'Fenrir • Google Chirp 3 HD (Heyecanlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Heyecanlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Leda',
      label: 'Leda • Google Chirp 3 HD (Genç)',
      engine: 'chirp',
      gender: 'f',
      description: 'Genç • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Orus',
      label: 'Orus • Google Chirp 3 HD (Sakin, kararlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Sakin, kararlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Aoede',
      label: 'Aoede • Google Chirp 3 HD (Ferah, doğal)',
      engine: 'chirp',
      gender: 'f',
      description: 'Ferah, doğal • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Callirrhoe',
      label: 'Callirrhoe • Google Chirp 3 HD (Rahat)',
      engine: 'chirp',
      gender: 'f',
      description: 'Rahat • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Autonoe',
      label: 'Autonoe • Google Chirp 3 HD (Parlak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Parlak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Enceladus',
      label: 'Enceladus • Google Chirp 3 HD (Derin, nefesli)',
      engine: 'chirp',
      gender: 'm',
      description: 'Derin, nefesli • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Iapetus',
      label: 'Iapetus • Google Chirp 3 HD (Net)',
      engine: 'chirp',
      gender: 'm',
      description: 'Net • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Umbriel',
      label: 'Umbriel • Google Chirp 3 HD (Rahat)',
      engine: 'chirp',
      gender: 'm',
      description: 'Rahat • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Algieba',
      label: 'Algieba • Google Chirp 3 HD (Pürüzsüz)',
      engine: 'chirp',
      gender: 'm',
      description: 'Pürüzsüz • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Despina',
      label: 'Despina • Google Chirp 3 HD (Pürüzsüz)',
      engine: 'chirp',
      gender: 'f',
      description: 'Pürüzsüz • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Erinome',
      label: 'Erinome • Google Chirp 3 HD (Net)',
      engine: 'chirp',
      gender: 'f',
      description: 'Net • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Algenib',
      label: 'Algenib • Google Chirp 3 HD (Tok, pürüzlü)',
      engine: 'chirp',
      gender: 'm',
      description: 'Tok, pürüzlü • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Rasalgethi',
      label: 'Rasalgethi • Google Chirp 3 HD (Bilgilendirici)',
      engine: 'chirp',
      gender: 'm',
      description: 'Bilgilendirici • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Laomedeia',
      label: 'Laomedeia • Google Chirp 3 HD (Neşeli)',
      engine: 'chirp',
      gender: 'f',
      description: 'Neşeli • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Achernar',
      label: 'Achernar • Google Chirp 3 HD (Yumuşak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Yumuşak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Alnilam',
      label: 'Alnilam • Google Chirp 3 HD (Kararlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Kararlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Schedar',
      label: 'Schedar • Google Chirp 3 HD (Dengeli)',
      engine: 'chirp',
      gender: 'm',
      description: 'Dengeli • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Gacrux',
      label: 'Gacrux • Google Chirp 3 HD (Olgun)',
      engine: 'chirp',
      gender: 'f',
      description: 'Olgun • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Pulcherrima',
      label: 'Pulcherrima • Google Chirp 3 HD (Atak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Atak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Achird',
      label: 'Achird • Google Chirp 3 HD (Samimi)',
      engine: 'chirp',
      gender: 'm',
      description: 'Samimi • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Zubenelgenubi',
      label: 'Zubenelgenubi • Google Chirp 3 HD (Gündelik)',
      engine: 'chirp',
      gender: 'm',
      description: 'Gündelik • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Vindemiatrix',
      label: 'Vindemiatrix • Google Chirp 3 HD (Nazik)',
      engine: 'chirp',
      gender: 'f',
      description: 'Nazik • Kadın',
    ),
    JarvisVoiceOption(
      id: 'Sadachbia',
      label: 'Sadachbia • Google Chirp 3 HD (Canlı)',
      engine: 'chirp',
      gender: 'm',
      description: 'Canlı • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Sadaltager',
      label: 'Sadaltager • Google Chirp 3 HD (Bilgili)',
      engine: 'chirp',
      gender: 'm',
      description: 'Bilgili • Erkek',
    ),
    JarvisVoiceOption(
      id: 'Sulafat',
      label: 'Sulafat • Google Chirp 3 HD (Sıcak)',
      engine: 'chirp',
      gender: 'f',
      description: 'Sıcak • Kadın',
    ),
    JarvisVoiceOption(
      id: 'alloy',
      label: 'Alloy • OpenAI TTS (Dengeli)',
      engine: 'openai',
      gender: 'n',
      description: 'gpt-4o-mini-tts • Dengeli',
    ),
    JarvisVoiceOption(
      id: 'ash',
      label: 'Ash • OpenAI TTS (Sakin)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Sakin',
    ),
    JarvisVoiceOption(
      id: 'ballad',
      label: 'Ballad • OpenAI TTS (Sıcak)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Sıcak',
    ),
    JarvisVoiceOption(
      id: 'coral',
      label: 'Coral • OpenAI TTS (Canlı)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Canlı',
    ),
    JarvisVoiceOption(
      id: 'echo',
      label: 'Echo • OpenAI TTS (Tok)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Tok',
    ),
    JarvisVoiceOption(
      id: 'fable',
      label: 'Fable • OpenAI TTS (Anlatıcı)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Anlatıcı',
    ),
    JarvisVoiceOption(
      id: 'nova',
      label: 'Nova • OpenAI TTS (Enerjik)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Enerjik',
    ),
    JarvisVoiceOption(
      id: 'onyx',
      label: 'Onyx • OpenAI TTS (Derin)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Derin',
    ),
    JarvisVoiceOption(
      id: 'sage',
      label: 'Sage • OpenAI TTS (Bilge)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Bilge',
    ),
    JarvisVoiceOption(
      id: 'shimmer',
      label: 'Shimmer • OpenAI TTS (Parlak)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Parlak',
    ),
    JarvisVoiceOption(
      id: 'verse',
      label: 'Verse • OpenAI TTS (Akıcı)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Akıcı',
    ),
    JarvisVoiceOption(
      id: 'marin',
      label: 'Marin • OpenAI TTS (Net)',
      engine: 'openai',
      gender: 'f',
      description: 'gpt-4o-mini-tts • Net',
    ),
    JarvisVoiceOption(
      id: 'cedar',
      label: 'Cedar • OpenAI TTS (Doğal)',
      engine: 'openai',
      gender: 'm',
      description: 'gpt-4o-mini-tts • Doğal',
    ),
  ];

  static JarvisVoiceOption? find(String id) {
    final l = id.trim().toLowerCase();
    for (final v in presets) {
      if (v.id.toLowerCase() == l) return v;
    }
    return null;
  }

  static String stripVoicePrefix(String rawVoice) {
    var clean = rawVoice.trim();
    const prefixes = ['azure:', 'chirp:', 'gemini:', 'tr-tr-chirp3-hd-'];
    final lower = clean.toLowerCase();
    for (final p in prefixes) {
      if (lower.startsWith(p)) {
        clean = clean.substring(p.length);
        break;
      }
    }
    return clean;
  }

  static bool isChirpVoice(String rawVoice) {
    final lower = rawVoice.trim().toLowerCase();
    if (lower.startsWith('chirp:') ||
        lower.startsWith('gemini:') ||
        lower.startsWith('tr-tr-chirp3-hd-')) {
      return true;
    }
    final stripped = stripVoicePrefix(rawVoice).toLowerCase();
    return chirpVoices.containsKey(stripped);
  }

  static String normalizeChirpName(String rawVoice) {
    final stripped = stripVoicePrefix(rawVoice).toLowerCase();
    return chirpVoices[stripped] ?? 'Kore';
  }

  static const List<JarvisVoiceOption> openAiLiveVoices = [
    JarvisVoiceOption(id: 'alloy', label: 'Alloy (Dengeli)', engine: 'openai'),
    JarvisVoiceOption(id: 'ash', label: 'Ash (Sakin)', engine: 'openai'),
    JarvisVoiceOption(id: 'ballad', label: 'Ballad (Sıcak)', engine: 'openai'),
    JarvisVoiceOption(id: 'coral', label: 'Coral (Canlı)', engine: 'openai'),
    JarvisVoiceOption(id: 'echo', label: 'Echo (Tok)', engine: 'openai'),
    JarvisVoiceOption(id: 'sage', label: 'Sage (Bilge)', engine: 'openai'),
    JarvisVoiceOption(
      id: 'shimmer',
      label: 'Shimmer (Parlak)',
      engine: 'openai',
    ),
    JarvisVoiceOption(id: 'verse', label: 'Verse (Akıcı)', engine: 'openai'),
    JarvisVoiceOption(id: 'marin', label: 'Marin (Net)', engine: 'openai'),
    JarvisVoiceOption(id: 'cedar', label: 'Cedar (Doğal)', engine: 'openai'),
  ];
}

class DeviceAppInfo {
  final String name;
  final String packageName;
  final String versionName;
  final bool isSystem;
  final int firstInstallMs;
  final int lastUpdateMs;

  const DeviceAppInfo({
    required this.name,
    required this.packageName,
    this.versionName = '',
    this.isSystem = false,
    this.firstInstallMs = 0,
    this.lastUpdateMs = 0,
  });
}

/// A file download tracked through Android DownloadManager.
class DownloadItem {
  final bool managed;
  final int speed;
  final int id;
  final String title;
  final String url;
  final String localUri;
  final String mimeType;
  final int totalBytes;
  final int downloadedBytes;

  /// 'pending' | 'running' | 'paused' | 'successful' | 'failed'
  final String status;
  final String reason;
  final int lastModifiedMs;

  const DownloadItem({
    required this.id,
    this.managed = false,
    this.speed = 0,
    required this.title,
    this.url = '',
    this.localUri = '',
    this.mimeType = '',
    this.totalBytes = -1,
    this.downloadedBytes = 0,
    this.status = 'pending',
    this.reason = '',
    this.lastModifiedMs = 0,
  });

  double? get progress => totalBytes > 0
      ? (downloadedBytes / totalBytes).clamp(0.0, 1.0).toDouble()
      : null;

  bool get isDone => status == 'successful';
  bool get isFailed => status == 'failed';

  factory DownloadItem.fromMap(Map<dynamic, dynamic> m) => DownloadItem(
    managed: m['managed'] == true,
    speed: (m['speed'] as num?)?.toInt() ?? 0,
    id: (m['id'] as num?)?.toInt() ?? -1,
    title: m['title']?.toString() ?? '',
    url: m['url']?.toString() ?? '',
    localUri: m['localUri']?.toString() ?? '',
    mimeType: m['mimeType']?.toString() ?? '',
    totalBytes: (m['totalBytes'] as num?)?.toInt() ?? -1,
    downloadedBytes: (m['downloadedBytes'] as num?)?.toInt() ?? 0,
    status: m['status']?.toString() ?? 'pending',
    reason: m['reason']?.toString() ?? '',
    lastModifiedMs: (m['lastModifiedMs'] as num?)?.toInt() ?? 0,
  );
}

class AppUsageInfo {
  final String packageName;
  final String name;
  final int foregroundMs;
  final int lastUsedMs;

  const AppUsageInfo({
    required this.packageName,
    required this.name,
    this.foregroundMs = 0,
    this.lastUsedMs = 0,
  });

  factory AppUsageInfo.fromMap(Map<dynamic, dynamic> m) => AppUsageInfo(
    packageName: m['package']?.toString() ?? '',
    name: m['name']?.toString() ?? '',
    foregroundMs: (m['foregroundMs'] as num?)?.toInt() ?? 0,
    lastUsedMs: (m['lastUsedMs'] as num?)?.toInt() ?? 0,
  );
}

class ContactInfo {
  final String name;
  final String phone;

  const ContactInfo({required this.name, required this.phone});

  factory ContactInfo.fromMap(Map<dynamic, dynamic> m) => ContactInfo(
    name: m['name']?.toString() ?? '',
    phone: m['phone']?.toString() ?? '',
  );
}

/// One attempt in the cloud TTS chain, used for diagnostics in Settings.
class TtsAttempt {
  final String provider;
  final bool ok;
  final String detail;
  final int ms;

  const TtsAttempt({
    required this.provider,
    required this.ok,
    this.detail = '',
    this.ms = 0,
  });

  @override
  String toString() =>
      '${ok ? '✅' : '❌'} $provider (${ms}ms)${detail.isEmpty ? '' : ': $detail'}';
}

class JarvisSettings {
  final ApiProvider provider;
  final String apiKey;
  final String baseUrl;
  final String model;
  final double ttsRate;
  final double ttsPitch;
  final bool autoTts;
  final bool googleGrounding;
  final bool preferStreaming;
  final bool useProxyTts;
  final String proxyTtsVoice;
  final String azureSpeechKey;
  final String azureSpeechRegion;

  /// Speech-to-text engine. Only OpenAI Whisper is supported ('whisper').
  final String sttMode;

  /// OpenAI Whisper speech recognition (the only STT engine).
  /// 'local' = whisper.cpp on the phone (model from Hugging Face, offline),
  /// 'api' = OpenAI-compatible `/audio/transcriptions` endpoint.
  final String whisperEngine;

  /// Local ggml model id (see LocalWhisper.models).
  final String localWhisperModel;

  /// Shorter encoder window for short commands (much faster on phones).
  final bool whisperFastMode;
  final String whisperKey;
  final String whisperBaseUrl;
  final String whisperModel;
  final String liveEngine; // 'gemini_live' | 'openai_live' | 'turn_based'
  final String geminiLiveVoice;
  final String openAiLiveUrl;
  final String openAiLiveKey;
  final String openAiLiveModel;
  final String openAiLiveVoice;
  final String personaPrompt;
  final String memoryText;

  /// 'auto' | 'proxy' | 'azure' | 'gemini' | 'google_cloud' | 'openai' | 'device'
  final String ttsEngine;

  /// CLI Proxy URL used for TTS even when chat runs on another provider.
  final String ttsProxyUrl;
  final String geminiTtsKey;
  final String googleCloudTtsKey;
  final String openAiTtsKey;
  final bool agentTools;

  /// Ege PC Köprüsü (Windows) adresi, ör. http://192.168.1.20:8765
  final String pcBridgeUrl;
  final String pcBridgeToken;
  final String pcBridgeName;

  /// Bearer key for the CLI Proxy used for cloud TTS (when chat uses another provider).
  final String ttsProxyKey;

  /// Bulut seslerin konuşma tonu: natural | jarvis | warm | energetic | calm | news | whisper | story
  final String ttsStyle;

  /// CLI Proxy erişilemezse sohbeti doğrudan Gemini API ile sürdür.
  final bool autoFallbackGemini;

  /// Version of the build-time embedded key bundle already applied (0 = none).
  final int embeddedKeysVersion;

  /// Kalıcı kullanıcı hafızası (Windows Ege "Tercihler.md" karşılığı) her
  /// sistem istemine eklenir; sohbetteki "hatırla" komutlarıyla güncellenir.
  final bool memoryEnabled;

  /// Animated backdrop, glows and motion effects (Ayarlar → Görünüm).
  final bool uiEffects;
  final String themeMode;
  final int themeAccent;
  final double liveOrbSize;

  /// Uygulama içi en büyük yazı ölçeği (telefonun yazı boyutu bundan büyükse sınırlanır).
  final double textScaleMax;

  /// Canlı Ses: Ege konuşurken sesle sözünü kesebilme (kapalıyken yankı kapısı mikrofonu susturur).
  final bool liveBargeIn;

  /// Canlı Ses / dikte / uyandırma sırasında ön plan servisi (realme dondurmasın).
  final bool keepAliveService;

  /// "Asistan" uyandırma sözcüğü (cihazda, sherpa-onnx).
  final bool wakeWordEnabled;

  /// Uyandırma duyarlılığı 0..1 (yüksek = daha kolay tetiklenir).
  final double wakeWordSensitivity;

  /// Her sabah sesli özet (hava, ajanda, hatırlatıcılar, haberler).
  final bool briefingEnabled;

  /// Sabah özeti saati (SS:DD).
  final String briefingTime;

  /// Hava durumu şehri (boşsa konum kullanılır).
  final String briefingCity;

  /// Gelen mesaj bildirimlerini sesli oku (bildirim erişimi gerekir).
  final bool announceNotifications;

  /// Yerel Whisper iş parçacığı sayısı (0 = otomatik).
  final int whisperThreads;

  /// Varsayılan asistan hareketiyle açılınca hemen dinlemeye başla.
  final bool assistantAutoListen;

  /// Hermes USER.md: kullanıcı hakkında kalıcı bilgiler (en çok 1375 karakter).
  final String userProfile;

  /// Kişilik katmanı (jarvis, ogretmen, kisa, esprili, koc, bilim, cocuk).
  final String personality;

  /// Öğrenme döngüsü: karmaşık işlerden sonra beceri/hafıza kaydı.
  final bool learningLoop;

  /// Sessiz saatler (23:00-07:00): zamanlanmış görevler sesli okunmaz.
  final bool quietHours;

  const JarvisSettings({
    this.provider = ApiProvider.cliProxyApi,
    this.apiKey = 'sk-local',
    this.baseUrl = 'http://127.0.0.1:8317',
    this.model = 'gemini-2.5-flash',
    this.ttsRate = 0.52,
    this.ttsPitch = 1.0,
    this.autoTts = false,
    this.googleGrounding = true,
    this.preferStreaming = true,
    this.useProxyTts = true,
    this.proxyTtsVoice = 'tr-TR-AhmetNeural',
    this.azureSpeechKey = '',
    this.azureSpeechRegion = 'westeurope',
    this.sttMode = 'system',
    this.whisperEngine = 'local',
    this.localWhisperModel = 'base-q5_1',
    this.whisperFastMode = true,
    this.whisperKey = '',
    this.whisperBaseUrl = 'https://api.openai.com/v1',
    this.whisperModel = 'whisper-1',
    this.liveEngine = 'turn_based',
    this.geminiLiveVoice = 'Kore',
    this.openAiLiveUrl = 'wss://api.openai.com/v1/realtime',
    this.openAiLiveKey = '',
    this.openAiLiveModel = 'gpt-realtime',
    this.openAiLiveVoice = 'alloy',
    this.personaPrompt = 'Sen Ege, kullanıcının Android telefonundaki akıllı Türkçe kişisel asistansın. Kısa, net, pratik ve doğru yanıt ver.',
    this.memoryText = '',
    this.ttsEngine = 'auto',
    this.ttsProxyUrl = 'http://127.0.0.1:8317',
    this.geminiTtsKey = '',
    this.googleCloudTtsKey = '',
    this.openAiTtsKey = '',
    this.agentTools = true,
    this.pcBridgeUrl = '',
    this.pcBridgeToken = '',
    this.pcBridgeName = '',
    this.ttsProxyKey = '',
    this.ttsStyle = 'jarvis',
    this.autoFallbackGemini = true,
    this.embeddedKeysVersion = 0,
    this.memoryEnabled = true,
    this.uiEffects = true,
    this.themeMode = 'light',
    this.themeAccent = 0xFFB85C3D,
    this.liveOrbSize = 132,
    this.textScaleMax = 1.15,
    this.liveBargeIn = false,
    this.keepAliveService = true,
    this.wakeWordEnabled = false,
    this.wakeWordSensitivity = 0.5,
    this.briefingEnabled = false,
    this.briefingTime = '07:30',
    this.briefingCity = '',
    this.announceNotifications = false,
    this.whisperThreads = 0,
    this.assistantAutoListen = true,
    this.userProfile = '',
    this.personality = 'jarvis',
    this.learningLoop = true,
    this.quietHours = true,
  });

  bool get pcPaired =>
      pcBridgeUrl.trim().isNotEmpty && pcBridgeToken.trim().isNotEmpty;

  /// True when the chat endpoint still points to the phone itself, which only
  /// works if a CLI Proxy app is running on the phone.
  bool get usesLoopbackProxy {
    final u = baseUrl.toLowerCase();
    return provider == ApiProvider.cliProxyApi &&
        (u.contains('127.0.0.1') || u.contains('localhost'));
  }

  JarvisSettings copyWith({
    ApiProvider? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
    double? ttsRate,
    double? ttsPitch,
    bool? autoTts,
    bool? googleGrounding,
    bool? preferStreaming,
    bool? useProxyTts,
    String? proxyTtsVoice,
    String? azureSpeechKey,
    String? azureSpeechRegion,
    String? sttMode,
    String? whisperEngine,
    String? localWhisperModel,
    bool? whisperFastMode,
    String? whisperKey,
    String? whisperBaseUrl,
    String? whisperModel,
    String? liveEngine,
    String? geminiLiveVoice,
    String? openAiLiveUrl,
    String? openAiLiveKey,
    String? openAiLiveModel,
    String? openAiLiveVoice,
    String? personaPrompt,
    String? memoryText,
    String? ttsEngine,
    String? ttsProxyUrl,
    String? geminiTtsKey,
    String? googleCloudTtsKey,
    String? openAiTtsKey,
    bool? agentTools,
    String? pcBridgeUrl,
    String? pcBridgeToken,
    String? pcBridgeName,
    String? ttsProxyKey,
    String? ttsStyle,
    bool? autoFallbackGemini,
    int? embeddedKeysVersion,
    bool? memoryEnabled,
    bool? uiEffects,
    String? themeMode,
    int? themeAccent,
    double? liveOrbSize,
    double? textScaleMax,
    bool? liveBargeIn,
    bool? keepAliveService,
    bool? wakeWordEnabled,
    double? wakeWordSensitivity,
    bool? briefingEnabled,
    String? briefingTime,
    String? briefingCity,
    bool? announceNotifications,
    int? whisperThreads,
    bool? assistantAutoListen,
    String? userProfile,
    String? personality,
    bool? learningLoop,
    bool? quietHours,
  }) {
    return JarvisSettings(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      autoTts: autoTts ?? this.autoTts,
      googleGrounding: googleGrounding ?? this.googleGrounding,
      preferStreaming: preferStreaming ?? this.preferStreaming,
      useProxyTts: useProxyTts ?? this.useProxyTts,
      proxyTtsVoice: proxyTtsVoice ?? this.proxyTtsVoice,
      azureSpeechKey: azureSpeechKey ?? this.azureSpeechKey,
      azureSpeechRegion: azureSpeechRegion ?? this.azureSpeechRegion,
      sttMode: sttMode ?? this.sttMode,
      whisperEngine: whisperEngine ?? this.whisperEngine,
      localWhisperModel: localWhisperModel ?? this.localWhisperModel,
      whisperFastMode: whisperFastMode ?? this.whisperFastMode,
      whisperKey: whisperKey ?? this.whisperKey,
      whisperBaseUrl: whisperBaseUrl ?? this.whisperBaseUrl,
      whisperModel: whisperModel ?? this.whisperModel,
      liveEngine: liveEngine ?? this.liveEngine,
      geminiLiveVoice: geminiLiveVoice ?? this.geminiLiveVoice,
      openAiLiveUrl: openAiLiveUrl ?? this.openAiLiveUrl,
      openAiLiveKey: openAiLiveKey ?? this.openAiLiveKey,
      openAiLiveModel: openAiLiveModel ?? this.openAiLiveModel,
      openAiLiveVoice: openAiLiveVoice ?? this.openAiLiveVoice,
      personaPrompt: personaPrompt ?? this.personaPrompt,
      memoryText: memoryText ?? this.memoryText,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsProxyUrl: ttsProxyUrl ?? this.ttsProxyUrl,
      geminiTtsKey: geminiTtsKey ?? this.geminiTtsKey,
      googleCloudTtsKey: googleCloudTtsKey ?? this.googleCloudTtsKey,
      openAiTtsKey: openAiTtsKey ?? this.openAiTtsKey,
      agentTools: agentTools ?? this.agentTools,
      pcBridgeUrl: pcBridgeUrl ?? this.pcBridgeUrl,
      pcBridgeToken: pcBridgeToken ?? this.pcBridgeToken,
      pcBridgeName: pcBridgeName ?? this.pcBridgeName,
      ttsProxyKey: ttsProxyKey ?? this.ttsProxyKey,
      ttsStyle: ttsStyle ?? this.ttsStyle,
      autoFallbackGemini: autoFallbackGemini ?? this.autoFallbackGemini,
      embeddedKeysVersion: embeddedKeysVersion ?? this.embeddedKeysVersion,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      uiEffects: uiEffects ?? this.uiEffects,
      themeMode: themeMode ?? this.themeMode,
      themeAccent: themeAccent ?? this.themeAccent,
      liveOrbSize: liveOrbSize ?? this.liveOrbSize,
      textScaleMax: textScaleMax ?? this.textScaleMax,
      liveBargeIn: liveBargeIn ?? this.liveBargeIn,
      keepAliveService: keepAliveService ?? this.keepAliveService,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      wakeWordSensitivity: wakeWordSensitivity ?? this.wakeWordSensitivity,
      briefingEnabled: briefingEnabled ?? this.briefingEnabled,
      briefingTime: briefingTime ?? this.briefingTime,
      briefingCity: briefingCity ?? this.briefingCity,
      announceNotifications:
          announceNotifications ?? this.announceNotifications,
      whisperThreads: whisperThreads ?? this.whisperThreads,
      assistantAutoListen: assistantAutoListen ?? this.assistantAutoListen,
      userProfile: userProfile ?? this.userProfile,
      personality: personality ?? this.personality,
      learningLoop: learningLoop ?? this.learningLoop,
      quietHours: quietHours ?? this.quietHours,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'model': model,
    'ttsRate': ttsRate,
    'ttsPitch': ttsPitch,
    'autoTts': autoTts,
    'googleGrounding': googleGrounding,
    'preferStreaming': preferStreaming,
    'useProxyTts': useProxyTts,
    'proxyTtsVoice': proxyTtsVoice,
    'azureSpeechKey': azureSpeechKey,
    'azureSpeechRegion': azureSpeechRegion,
    'sttMode': sttMode,
    'whisperEngine': whisperEngine,
    'localWhisperModel': localWhisperModel,
    'whisperFastMode': whisperFastMode,
    'whisperKey': whisperKey,
    'whisperBaseUrl': whisperBaseUrl,
    'whisperModel': whisperModel,
    'liveEngine': liveEngine,
    'geminiLiveVoice': geminiLiveVoice,
    'openAiLiveUrl': openAiLiveUrl,
    'openAiLiveKey': openAiLiveKey,
    'openAiLiveModel': openAiLiveModel,
    'openAiLiveVoice': openAiLiveVoice,
    'personaPrompt': personaPrompt,
    'memoryText': memoryText,
    'ttsEngine': ttsEngine,
    'ttsProxyUrl': ttsProxyUrl,
    'geminiTtsKey': geminiTtsKey,
    'googleCloudTtsKey': googleCloudTtsKey,
    'openAiTtsKey': openAiTtsKey,
    'agentTools': agentTools,
    'pcBridgeUrl': pcBridgeUrl,
    'pcBridgeToken': pcBridgeToken,
    'pcBridgeName': pcBridgeName,
    'ttsProxyKey': ttsProxyKey,
    'ttsStyle': ttsStyle,
    'autoFallbackGemini': autoFallbackGemini,
    'embeddedKeysVersion': embeddedKeysVersion,
    'memoryEnabled': memoryEnabled,
    'uiEffects': uiEffects,
    'themeMode': themeMode,
    'themeAccent': themeAccent,
    'liveOrbSize': liveOrbSize,
    'textScaleMax': textScaleMax,
    'liveBargeIn': liveBargeIn,
    'keepAliveService': keepAliveService,
    'wakeWordEnabled': wakeWordEnabled,
    'wakeWordSensitivity': wakeWordSensitivity,
    'briefingEnabled': briefingEnabled,
    'briefingTime': briefingTime,
    'briefingCity': briefingCity,
    'announceNotifications': announceNotifications,
    'whisperThreads': whisperThreads,
    'assistantAutoListen': assistantAutoListen,
    'userProfile': userProfile,
    'personality': personality,
    'learningLoop': learningLoop,
    'quietHours': quietHours,
    'settingsVersion': 10,
  };

  factory JarvisSettings.fromJson(Map<String, dynamic> json) {
    final provStr = json['provider']?.toString() ?? 'cliProxyApi';
    final prov = ApiProvider.values.firstWhere(
      (e) => e.name == provStr,
      orElse: () => ApiProvider.cliProxyApi,
    );
    final defaultBase = switch (prov) {
      ApiProvider.cliProxyApi => 'http://127.0.0.1:8317',
      ApiProvider.geminiDirect => 'https://generativelanguage.googleapis.com',
      ApiProvider.openAiCompatible => 'https://api.openai.com',
    };
    // Settings saved before v4 may have persisted `useProxyTts: false` or
    // `ttsEngine: 'device'` after older failed cloud TTS handshakes; migrate to cloud auto mode.
    final version = (json['settingsVersion'] as num?)?.toInt() ?? 1;
    final legacyUseProxy = json['useProxyTts'] != false;
    final storedEngine = json['ttsEngine']?.toString();
    final migratedUseProxy = version < 4 ? true : legacyUseProxy;
    final engine =
        (version < 4 && (storedEngine == null || storedEngine == 'device'))
        ? 'auto'
        : (storedEngine ?? (migratedUseProxy ? 'auto' : 'device'));
    final baseUrl = json['baseUrl']?.toString() ?? defaultBase;
    return JarvisSettings(
      provider: prov,
      apiKey:
          json['apiKey']?.toString() ??
          (prov == ApiProvider.cliProxyApi ? 'sk-local' : ''),
      baseUrl: baseUrl,
      model: json['model']?.toString() ?? 'gemini-2.5-flash',
      ttsRate: (json['ttsRate'] as num?)?.toDouble().clamp(0.3, 1.0) ?? 0.52,
      ttsPitch: (json['ttsPitch'] as num?)?.toDouble().clamp(0.6, 1.5) ?? 1.0,
      autoTts: json['autoTts'] == true,
      googleGrounding: json['googleGrounding'] != false,
      preferStreaming: json['preferStreaming'] != false,
      useProxyTts: migratedUseProxy,
      proxyTtsVoice: json['proxyTtsVoice']?.toString() ?? 'tr-TR-AhmetNeural',
      azureSpeechKey: json['azureSpeechKey']?.toString() ?? '',
      azureSpeechRegion: json['azureSpeechRegion']?.toString() ?? 'westeurope',
      // v9: prefer the phone recognition service; retain an explicit Whisper choice.
      sttMode: version < 9
          ? 'system'
          : (json['sttMode'] == 'whisper' ? 'whisper' : 'system'),
      // v7: on-device Whisper becomes the default engine for everybody.
      whisperEngine: version >= 7 && json['whisperEngine']?.toString() == 'api'
          ? 'api'
          : 'local',
      // v8: Small realme 10'da 5-8 sn sürüyordu; varsayılan Base'e geçer
      // (Small dosyası silinmez, Ayarlar'dan yeniden seçilebilir).
      localWhisperModel:
          version < 8 && json['localWhisperModel']?.toString() == 'small-q5_1'
          ? 'base-q5_1'
          : const {
              'tiny-q5_1',
              'base-q5_1',
              'small-q5_1',
              'large-v3-turbo-q5_0',
            }.contains(json['localWhisperModel']?.toString())
          ? json['localWhisperModel'].toString()
          : 'base-q5_1',
      whisperFastMode: json['whisperFastMode'] != false,
      whisperKey: json['whisperKey']?.toString() ?? '',
      whisperBaseUrl: (json['whisperBaseUrl']?.toString() ?? '').trim().isEmpty
          ? 'https://api.openai.com/v1'
          : json['whisperBaseUrl'].toString().trim(),
      whisperModel: (json['whisperModel']?.toString() ?? '').trim().isEmpty
          ? 'whisper-1'
          : json['whisperModel'].toString().trim(),
      liveEngine: 'turn_based',
      geminiLiveVoice: json['geminiLiveVoice']?.toString() ?? 'Kore',
      openAiLiveUrl:
          json['openAiLiveUrl']?.toString() ??
          'wss://api.openai.com/v1/realtime',
      openAiLiveKey: json['openAiLiveKey']?.toString() ?? '',
      openAiLiveModel: json['openAiLiveModel']?.toString() ?? 'gpt-realtime',
      openAiLiveVoice: json['openAiLiveVoice']?.toString() ?? 'alloy',
      personaPrompt:
          (json['personaPrompt']?.toString() ??
                  'Sen Ege, kullanıcının Android telefonundaki akıllı Türkçe kişisel asistansın. Kısa, net, pratik ve doğru yanıt ver.')
              .replaceAll(RegExp(r'\bjarvis\b', caseSensitive: false), 'Ege'),
      memoryText: json['memoryText']?.toString() ?? '',
      ttsEngine: engine,
      ttsProxyUrl:
          json['ttsProxyUrl']?.toString() ??
          (prov == ApiProvider.cliProxyApi ? baseUrl : 'http://127.0.0.1:8317'),
      geminiTtsKey: json['geminiTtsKey']?.toString() ?? '',
      googleCloudTtsKey: json['googleCloudTtsKey']?.toString() ?? '',
      openAiTtsKey: json['openAiTtsKey']?.toString() ?? '',
      agentTools: json['agentTools'] != false,
      pcBridgeUrl: json['pcBridgeUrl']?.toString() ?? '',
      pcBridgeToken: json['pcBridgeToken']?.toString() ?? '',
      pcBridgeName: json['pcBridgeName']?.toString() ?? '',
      ttsProxyKey: json['ttsProxyKey']?.toString() ?? '',
      ttsStyle: JarvisVoiceCatalog.styles.containsKey(json['ttsStyle'])
          ? json['ttsStyle'].toString()
          : 'jarvis',
      autoFallbackGemini: json['autoFallbackGemini'] != false,
      embeddedKeysVersion: (json['embeddedKeysVersion'] as num?)?.toInt() ?? 0,
      memoryEnabled: json['memoryEnabled'] != false,
      uiEffects: json['uiEffects'] != false,
      themeMode: const {'light', 'dark', 'system'}.contains(json['themeMode'])
          ? json['themeMode'].toString()
          : 'light',
      themeAccent:
          ((json['themeAccent'] as num?)?.toInt() ?? 0xFFB85C3D) | 0xFF000000,
      liveOrbSize: ((json['liveOrbSize'] as num?)?.toDouble() ?? 132).clamp(
        96,
        180,
      ),
      textScaleMax: ((json['textScaleMax'] as num?)?.toDouble() ?? 1.15)
          .clamp(0.8, 2.0)
          .toDouble(),
      liveBargeIn: json['liveBargeIn'] == true,
      keepAliveService: json['keepAliveService'] != false,
      wakeWordEnabled: json['wakeWordEnabled'] == true,
      wakeWordSensitivity:
          ((json['wakeWordSensitivity'] as num?)?.toDouble() ?? 0.5)
              .clamp(0.0, 1.0)
              .toDouble(),
      briefingEnabled: json['briefingEnabled'] == true,
      briefingTime: _validHm(json['briefingTime']?.toString()) ?? '07:30',
      briefingCity: json['briefingCity']?.toString() ?? '',
      announceNotifications: json['announceNotifications'] == true,
      whisperThreads: ((json['whisperThreads'] as num?)?.toInt() ?? 0)
          .clamp(0, 8)
          .toInt(),
      assistantAutoListen: json['assistantAutoListen'] != false,
      userProfile: json['userProfile']?.toString() ?? '',
      personality: json['personality']?.toString() ?? 'jarvis',
      learningLoop: json['learningLoop'] != false,
      quietHours: json['quietHours'] != false,
    );
  }

  static String? _validHm(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${m.group(2)}';
  }
}

class ChatAttachment {
  final String id;
  final String name;
  final String mimeType;
  final String kind; // 'image' | 'text'
  final String? base64Data;
  final String? textContent;
  final String? localPath;
  final String? publicUri;

  const ChatAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.kind,
    this.base64Data,
    this.textContent,
    this.localPath,
    this.publicUri,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'kind': kind,
    if (kind == 'text' && textContent != null) 'textContent': textContent,
    if (localPath != null) 'localPath': localPath,
    if (publicUri != null) 'publicUri': publicUri,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'ek',
    mimeType: json['mimeType']?.toString() ?? 'text/plain',
    kind: json['kind']?.toString() ?? 'text',
    textContent: json['textContent']?.toString(),
    localPath: json['localPath']?.toString(),
    publicUri: json['publicUri']?.toString(),
  );
}

class JarvisMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final String? modelUsed;
  final double? durationSec;
  final List<ChatAttachment> attachments;
  final String? actionBanner;

  const JarvisMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.modelUsed,
    this.durationSec,
    this.attachments = const [],
    this.actionBanner,
  });

  JarvisMessage copyWith({
    String? content,
    DateTime? timestamp,
    String? modelUsed,
    double? durationSec,
    List<ChatAttachment>? attachments,
    String? actionBanner,
  }) {
    return JarvisMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      modelUsed: modelUsed ?? this.modelUsed,
      durationSec: durationSec ?? this.durationSec,
      attachments: attachments ?? this.attachments,
      actionBanner: actionBanner ?? this.actionBanner,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'modelUsed': modelUsed,
    'durationSec': durationSec,
    'actionBanner': actionBanner,
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };

  factory JarvisMessage.fromJson(Map<String, dynamic> json) => JarvisMessage(
    id: json['id']?.toString() ?? '',
    role: json['role']?.toString() == 'user' ? 'user' : 'assistant',
    content: json['content']?.toString() ?? '',
    timestamp:
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now(),
    modelUsed: json['modelUsed']?.toString(),
    durationSec: (json['durationSec'] as num?)?.toDouble(),
    actionBanner: json['actionBanner']?.toString(),
    attachments:
        (json['attachments'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(ChatAttachment.fromJson)
            .toList() ??
        const [],
  );
}

class ChatSession {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<JarvisMessage> messages;

  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<JarvisMessage>? messages,
  }) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id']?.toString() ?? 'session-1',
    title: json['title']?.toString() ?? 'Ana Sohbet',
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now(),
    messages:
        (json['messages'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(JarvisMessage.fromJson)
            .toList() ??
        const [],
  );
}

class JarvisNote {
  final String id;
  final String title;
  final String content;
  final DateTime updatedAt;

  const JarvisNote({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  JarvisNote copyWith({String? title, String? content, DateTime? updatedAt}) {
    return JarvisNote(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory JarvisNote.fromJson(Map<String, dynamic> json) => JarvisNote(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? 'Yeni Not',
    content: json['content']?.toString() ?? '',
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

class JarvisTimer {
  final String id;
  final String label;
  final int durationSec;
  final int createdAtEpoch;
  final int fireAtEpoch;
  final bool fired;
  final bool acknowledged;

  const JarvisTimer({
    required this.id,
    required this.label,
    required this.durationSec,
    required this.createdAtEpoch,
    required this.fireAtEpoch,
    this.fired = false,
    this.acknowledged = false,
  });

  int remainingSec(int nowEpoch) =>
      fired ? 0 : (fireAtEpoch - nowEpoch).clamp(0, durationSec * 2 + 86400);

  JarvisTimer copyWith({bool? fired, bool? acknowledged}) {
    return JarvisTimer(
      id: id,
      label: label,
      durationSec: durationSec,
      createdAtEpoch: createdAtEpoch,
      fireAtEpoch: fireAtEpoch,
      fired: fired ?? this.fired,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'durationSec': durationSec,
    'createdAtEpoch': createdAtEpoch,
    'fireAtEpoch': fireAtEpoch,
    'fired': fired,
    'acknowledged': acknowledged,
  };

  factory JarvisTimer.fromJson(Map<String, dynamic> json) => JarvisTimer(
    id: json['id']?.toString() ?? '',
    label: json['label']?.toString() ?? 'Sayaç',
    durationSec: (json['durationSec'] as num?)?.toInt() ?? 60,
    createdAtEpoch: (json['createdAtEpoch'] as num?)?.toInt() ?? 0,
    fireAtEpoch: (json['fireAtEpoch'] as num?)?.toInt() ?? 0,
    fired: json['fired'] == true,
    acknowledged: json['acknowledged'] == true,
  );
}

class StudyArtifact {
  final String id;
  final String kind;
  final String title;
  final String content;
  final DateTime createdAt;

  const StudyArtifact({
    required this.id,
    required this.kind,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': title,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StudyArtifact.fromJson(Map<String, dynamic> json) => StudyArtifact(
    id: json['id']?.toString() ?? '',
    kind: json['kind']?.toString() ?? 'research',
    title: json['title']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

class DeviceMetrics {
  final String manufacturer;
  final String model;
  final String androidVersion;
  final int sdkInt;
  final int batteryPct;
  final bool charging;
  final int totalRamMb;
  final int usedRamMb;
  final double totalStorageGb;
  final double freeStorageGb;
  final String networkType;

  const DeviceMetrics({
    this.manufacturer = 'Android',
    this.model = 'Cihaz',
    this.androidVersion = '-',
    this.sdkInt = 0,
    this.batteryPct = -1,
    this.charging = false,
    this.totalRamMb = 0,
    this.usedRamMb = 0,
    this.totalStorageGb = 0,
    this.freeStorageGb = 0,
    this.networkType = 'Bilinmiyor',
  });

  factory DeviceMetrics.fromMap(Map<dynamic, dynamic> map) => DeviceMetrics(
    manufacturer: map['manufacturer']?.toString() ?? 'Android',
    model: map['model']?.toString() ?? 'Cihaz',
    androidVersion: map['androidVersion']?.toString() ?? '-',
    sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
    batteryPct: (map['batteryPct'] as num?)?.toInt() ?? -1,
    charging: map['charging'] == true,
    totalRamMb: (map['totalRamMb'] as num?)?.toInt() ?? 0,
    usedRamMb: (map['usedRamMb'] as num?)?.toInt() ?? 0,
    totalStorageGb: (map['totalStorageGb'] as num?)?.toDouble() ?? 0.0,
    freeStorageGb: (map['freeStorageGb'] as num?)?.toDouble() ?? 0.0,
    networkType: map['networkType']?.toString() ?? 'Bilinmiyor',
  );
}

String encodeJsonList<T>(
  List<T> items,
  Map<String, dynamic> Function(T) toJson,
) {
  return jsonEncode(items.map(toJson).toList());
}

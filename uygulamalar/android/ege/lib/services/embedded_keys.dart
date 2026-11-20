import 'dart:convert';

import '../models/jarvis_models.dart';

/// API keys baked into this personal build at compile time so the phone works
/// on its own (no PC needed): chat via Gemini, cloud voices via Azure Speech.
///
/// The payload comes from `--dart-define=JARVIS_KEYS=...`, produced by
/// `tool/jarvis_keys.py` from the PC's CLI Proxy API environment. Keys are
/// never written to source control. The light XOR layer only prevents the
/// keys from showing up as plain strings inside the APK.
class EmbeddedKeys {
  static const String _payload = String.fromEnvironment('JARVIS_KEYS');
  static const int version =
      int.fromEnvironment('JARVIS_KEYS_VERSION', defaultValue: 1);
  static const String _salt = 'J.A.R.V.I.S-mobil-2026';

  final String gemini;
  final String azureKey;
  final String azureRegion;
  final String proxyUrl;
  final String proxyKey;

  /// OpenAI key used for Whisper speech recognition (and OpenAI TTS).
  final String openai;

  const EmbeddedKeys({
    this.gemini = '',
    this.azureKey = '',
    this.azureRegion = 'westeurope',
    this.proxyUrl = '',
    this.proxyKey = '',
    this.openai = '',
  });

  bool get available => gemini.isNotEmpty || azureKey.isNotEmpty;

  static EmbeddedKeys? _cached;

  static EmbeddedKeys get instance => _cached ??= decode(_payload);

  /// Test seam.
  static set debugOverride(EmbeddedKeys? value) => _cached = value;

  static List<int> _xor(List<int> data) {
    final salt = utf8.encode(_salt);
    return [
      for (var i = 0; i < data.length; i++)
        data[i] ^ salt[i % salt.length] ^ ((i * 31) & 0xFF),
    ];
  }

  static String encode(Map<String, String> values) =>
      base64Url.encode(_xor(utf8.encode(jsonEncode(values))));

  static EmbeddedKeys decode(String payload) {
    if (payload.trim().isEmpty) return const EmbeddedKeys();
    try {
      final raw = utf8.decode(_xor(base64Url.decode(base64Url.normalize(payload.trim()))));
      final m = jsonDecode(raw);
      if (m is! Map) return const EmbeddedKeys();
      String s(String k) => (m[k] ?? '').toString().trim();
      return EmbeddedKeys(
        gemini: s('g'),
        azureKey: s('az'),
        azureRegion: s('azr').isEmpty ? 'westeurope' : s('azr'),
        proxyUrl: s('pu'),
        proxyKey: s('px'),
        openai: s('oa'),
      );
    } catch (_) {
      return const EmbeddedKeys();
    }
  }

  static String _geminiModelFor(String current) {
    final m = current.trim().toLowerCase();
    const known = {
      'gemini-4-carbon',
      'gemini-4-carbon-high',
      'gemini-4-carbon-medium',
      'gemini-4-carbon-low',
      'gemini-4-argon',
      'gemini-4-argon-high',
      'gemini-4-argon-medium',
      'gemini-4-argon-low',
      'gemini-4-hydrogen',
      'gemini-4-hydrogen-xhigh',
      'gemini-4-hydrogen-high',
      'gemini-4-hydrogen-medium',
      'gemini-4-hydrogen-low',
      'gemini-3.8-flash',
      'gemini-3.8-flash-high',
      'gemini-3.8-flash-medium',
      'gemini-3.8-flash-low',
      'gemini-3.7-flash',
      'gemini-3.6-flash',
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-flash-latest',
      'gemini-flash-lite-latest',
      'gemini-pro-latest',
      'gemini-3.5-flash',
      'gemini-3.5-flash-lite',
      'gemini-3-flash-preview',
      'gemini-3.1-pro-preview',
      'gemini-3.1-flash-lite',
      'gemma-4-31b-it',
      'gemma-4-26b-a4b-it',
    };
    return known.contains(m) ? m : 'gemini-2.5-flash';
  }

  /// Fills missing keys and repairs a chat setup that cannot work on the
  /// phone (CLI Proxy on 127.0.0.1 / `sk-local`). With [force] every embedded
  /// key overwrites the stored one.
  JarvisSettings applyTo(JarvisSettings s, {bool force = false}) {
    var n = s;
    if (gemini.isNotEmpty && (force || n.geminiTtsKey.trim().isEmpty)) {
      n = n.copyWith(geminiTtsKey: gemini);
    }
    if (azureKey.isNotEmpty && (force || n.azureSpeechKey.trim().isEmpty)) {
      n = n.copyWith(
        azureSpeechKey: azureKey,
        azureSpeechRegion: azureRegion.isEmpty ? 'westeurope' : azureRegion,
      );
    }
    if (proxyKey.isNotEmpty &&
        proxyUrl.isNotEmpty &&
        (force || n.ttsProxyKey.trim().isEmpty)) {
      final loopback = n.ttsProxyUrl.trim().isEmpty ||
          n.ttsProxyUrl.contains('127.0.0.1') ||
          n.ttsProxyUrl.contains('localhost');
      n = n.copyWith(ttsProxyKey: proxyKey, ttsProxyUrl: loopback ? proxyUrl : null);
    }
    final key = n.apiKey.trim();
    final chatBroken = n.provider == ApiProvider.cliProxyApi &&
        (key.isEmpty || key == 'sk-local');
    final geminiNoKey = n.provider == ApiProvider.geminiDirect && key.isEmpty;
    // Only repair a chat setup that cannot work on the phone; a working
    // choice (e.g. the PC proxy) is never switched away.
    final staleGemini = force &&
        n.provider == ApiProvider.geminiDirect &&
        key != gemini;
    if (gemini.isNotEmpty && staleGemini && !chatBroken && !geminiNoKey) {
      n = n.copyWith(apiKey: gemini, model: _geminiModelFor(n.model));
    }
    if (gemini.isNotEmpty && (chatBroken || geminiNoKey)) {
      n = n.copyWith(
        provider: ApiProvider.geminiDirect,
        baseUrl: 'https://generativelanguage.googleapis.com',
        apiKey: gemini,
        model: _geminiModelFor(n.model),
      );
    }
    if (openai.isNotEmpty && (force || n.whisperKey.trim().isEmpty)) {
      n = n.copyWith(whisperKey: openai);
    }
    if (openai.isNotEmpty && (force || n.openAiTtsKey.trim().isEmpty)) {
      n = n.copyWith(openAiTtsKey: openai);
    }
    if (n.ttsEngine == 'device') n = n.copyWith(ttsEngine: 'auto');
    if (azureKey.isNotEmpty &&
        (n.proxyTtsVoice.trim().isEmpty || n.proxyTtsVoice == 'tr-TR-AhmetNeural')) {
      n = n.copyWith(proxyTtsVoice: JarvisVoiceCatalog.defaultHdVoice);
    }
    return n.copyWith(useProxyTts: true, embeddedKeysVersion: version);
  }
}

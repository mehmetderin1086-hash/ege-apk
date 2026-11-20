import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Pure-Dart Microsoft Edge ReadAloud Neural TTS client (no API key required)
/// with exact Sec-MS-GEC v2 DRM token generation + Google Translate cloud backup.
class EdgeTtsClient {
  static const String trustedClientToken =
      '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
  static const String chromiumFullVersion = '143.0.3650.75';
  static const String secMsGecVersion = '2-$chromiumFullVersion';
  static const String _wssBase =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const String _origin =
      'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0';

  static const int _winEpoch = 11644473600;
  static const double _sTo100Ns = 10000000.0;
  static const int _mask32 = 0xFFFFFFFF;

  /// Clock skew correction (seconds) learned from server Date header if 403 occurs.
  static double clockSkewSeconds = 0.0;

  /// Optional test seam for unit tests without live network WebSockets.
  static Future<({Uint8List? bytes, String ext, String error})> Function(
    String text,
    String voice,
    double rateMultiplier,
  )? testSynthesizer;

  static const List<int> _sha256Initial = [
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
  ];

  static const List<int> _sha256State = [
    0xFD9FBEA2,
    0x91243CE7,
    0xBE499094,
    0xCD2E1E0A,
    0x6C006F49,
    0x04BD35AB,
    0xFEB0A7E4,
    0x03EFFBD2,
  ];

  static const List<int> _sha256Schedule = [
    0xEB24BF9E,
    0x1558691F,
    0xA0C09EE2,
    0x0CFA32BA,
    0xA622EE8C,
    0xD1DD9491,
    0xC0DD25A0,
    0xF9E70AB6,
    0xF0C31573,
    0x7058CE4E,
    0x7188E606,
    0x00E5AB33,
    0xD258B060,
    0x72766564,
  ];

  static const List<int> _sha256RoundConstants = [
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
  ];

  static const int _sha256Adjustment = 0xC9DC06A7;
  static const int _sha256Sigma0Adjustment = 0x059C0B80;
  static const int _sha256Sigma1Adjustment = 0x000B92C0;

  static const List<(int, int)> _cs64Coefficients = [
    (0xE82E91B1, 0xB32700D0),
    (0x44DE24C6, 0x88DFF51D),
    (0x3BEB65BC, 0x29514038),
    (0xC89C5933, 0xB328CBDF),
    (0x8D1EC211, 0xD405B4D5),
    (0x314EF5D5, 0x26E55F3C),
    (0xE92491B1, 0x607801C6),
    (0xF0A5B9D5, 0x82B2C1FB),
    (0x06064CF3, 0xFA51A3DA),
    (0xDA79FA60, 0x207CC464),
    (0xBED20560, 0x3C3C74F3),
    (0x89F9C9F8, 0xD2D14B61),
    (0x35FA38C6, 0xBB04A2C1),
    (0xCB49E3C6, 0xC5626167),
  ];

  static const int _cs64Factor = 0x82893933;
  static const int _cs64Adjustment0 = 0xF2F90B1A;
  static const int _cs64Adjustment1 = 0x0B1A0000;

  static final Random _rng = Random.secure();

  static int _rotr32(int value, int shift) {
    final v = value & _mask32;
    return ((v >> shift) | ((v << (32 - shift)) & _mask32)) & _mask32;
  }

  static int _rol16(int value) {
    final v = value & _mask32;
    return ((v << 16) | (v >> 16)) & _mask32;
  }

  static int _sigma0(int value) {
    final v = value & _mask32;
    return (_rotr32(v, 7) ^ _rotr32(v, 18) ^ (v >> 3)) & _mask32;
  }

  static int _sigma1(int value) {
    final v = value & _mask32;
    return (_rotr32(v, 17) ^ _rotr32(v, 19) ^ (v >> 10)) & _mask32;
  }

  static List<int> _sha256Rounds(
    List<int> state,
    List<int> words, {
    int firstRound = 0,
  }) {
    var a = state[0] & _mask32;
    var b = state[1] & _mask32;
    var c = state[2] & _mask32;
    var d = state[3] & _mask32;
    var e = state[4] & _mask32;
    var f = state[5] & _mask32;
    var g = state[6] & _mask32;
    var h = state[7] & _mask32;

    for (var i = firstRound; i < 64; i++) {
      final k = (firstRound == 14 && i == 14)
          ? _sha256Adjustment
          : _sha256RoundConstants[i];
      final s1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
      final ch = g ^ (e & (f ^ g));
      final t1 = (h + s1 + ch + k + words[i]) & _mask32;
      final s0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
      final maj = (a & b) | (c & (a | b));
      final t2 = (s0 + maj) & _mask32;

      h = g;
      g = f;
      f = e;
      e = (d + t1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _mask32;
    }
    return [a, b, c, d, e, f, g, h];
  }

  static void _expandSha256Schedule(List<int> words, [int firstWord = 16]) {
    for (var i = firstWord; i < 64; i++) {
      final s1 = _sigma1(words[i - 2]);
      final s0 = _sigma0(words[i - 15]);
      words.add((s1 + words[i - 7] + s0 + words[i - 16]) & _mask32);
    }
  }

  static List<int> _sha256Init(Uint8List prefix7) {
    final words = List<int>.filled(14, 0, growable: true);
    words.add((prefix7[0] << 16) | (prefix7[1] << 8) | prefix7[2]);
    words.add(
      (prefix7[3] << 24) |
          (prefix7[4] << 16) |
          (prefix7[5] << 8) |
          prefix7[6],
    );
    for (var i = 16; i < 30; i++) {
      var val = _sha256Schedule[i - 16];
      if (i - 2 >= 14) {
        val += i == 16
            ? (_sigma1(words[i - 2]) ^ _sha256Sigma1Adjustment)
            : _sigma1(words[i - 2]);
      }
      if (i - 7 >= 14) {
        val += words[i - 7];
      }
      if (i - 15 >= 14) {
        val += i == 29
            ? (_sigma0(words[i - 15]) ^ _sha256Sigma0Adjustment)
            : _sigma0(words[i - 15]);
      }
      words.add(val & _mask32);
    }
    words.add(
      (_sigma1(words[28]) +
              words[23] +
              _sigma0(words[15]) +
              words[14] +
              _sha256Adjustment -
              _sha256RoundConstants[14]) &
          _mask32,
    );
    _expandSha256Schedule(words, 31);
    final working = _sha256Rounds(_sha256State, words, firstRound: 14);
    return List<int>.generate(
      8,
      (i) => (_sha256Initial[i] + working[i]) & _mask32,
    );
  }

  static Uint8List _sha256Digest(Uint8List data) {
    if (data.length < 7) {
      throw ArgumentError('Token salt must contain at least 7 bytes');
    }
    final length = 57 + data.length;
    final zeroPadLen = ((55 - length) % 64 + 64) % 64;
    final tailLen = (data.length - 7) + 1 + zeroPadLen + 8;
    final padded = Uint8List(tailLen);
    padded.setRange(0, data.length - 7, data, 7);
    padded[data.length - 7] = 0x80;
    final bd = ByteData.sublistView(padded);
    final bitLen = length * 8;
    // Set 64-bit big-endian bit length safely across platforms
    bd.setUint32(tailLen - 8, (bitLen ~/ 0x100000000), Endian.big);
    bd.setUint32(tailLen - 4, bitLen & _mask32, Endian.big);

    var state = _sha256Init(data.sublist(0, 7));
    for (var offset = 0; offset < padded.length; offset += 64) {
      final words = <int>[
        for (var j = 0; j < 16; j++)
          bd.getUint32(offset + j * 4, Endian.big),
      ];
      _expandSha256Schedule(words);
      final working = _sha256Rounds(state, words);
      state = List<int>.generate(8, (i) => (state[i] + working[i]) & _mask32);
    }

    final out = Uint8List(32);
    final outBd = ByteData.sublistView(out);
    for (var i = 0; i < 8; i++) {
      outBd.setUint32(i * 4, state[i], Endian.big);
    }
    return out;
  }

  static List<int> _wordsLe4Even(Uint8List data) {
    final rem = data.length % 4;
    final padLen = rem == 0 ? data.length : data.length + (4 - rem);
    final padded = Uint8List(padLen)..setRange(0, data.length, data);
    final bd = ByteData.sublistView(padded);
    final words = <int>[
      for (var i = 0; i < padLen; i += 4) bd.getUint32(i, Endian.little),
    ];
    if (words.length.isOdd) words.add(0);
    return words;
  }

  static (int, int) _cs64Digest(Uint8List data, Uint8List digest) {
    final bd = ByteData.sublistView(digest);
    final keyA = bd.getUint32(0, Endian.little) | 1;
    final keyB = bd.getUint32(4, Endian.little) | 1;
    final factors = (
      (keyA * _cs64Factor) & _mask32,
      (keyB * _cs64Factor) & _mask32,
    );
    final terms = <int>[
      for (var i = 0; i < _cs64Coefficients.length; i++)
        (_cs64Coefficients[i].$1 * (i.isEven ? factors.$1 : factors.$2)) &
            _mask32,
    ];
    final offsets = <int>[
      for (final c in _cs64Coefficients) c.$2,
    ];

    final prefixed = Uint8List(data.length + 1)..setRange(1, data.length + 1, data);
    final words = _wordsLe4Even(prefixed);
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      var term = (w * (i.isEven ? keyA : keyB)) & _mask32;
      var offset =
          (_rol16(w) * (i.isEven ? 0xEF0569FB : 0xC31713DB)) & _mask32;
      if (i == 0) {
        term = (term + (_cs64Adjustment0 * factors.$1)) & _mask32;
        offset = (offset + _cs64Adjustment1) & _mask32;
      }
      terms.add(term);
      offsets.add(offset);
    }

    var swapAcc = 0;
    var swapLast = 0;
    var state = 0;
    var acc = 0;
    for (var i = 0; i < terms.length; i += 2) {
      final x = terms[i];
      final y = terms[i + 1];
      var t = _rol16((offsets[i] + x) & _mask32);
      var q = (t * 0x76F50F34) & _mask32;
      swapAcc = (swapAcc + ((_rol16(q) * 0xC3EFEA97) + q)) & _mask32;

      t = _rol16((offsets[i + 1] + y) & _mask32);
      q = (t * 0x1881CE3C) & _mask32;
      swapLast = ((_rol16(q) * 0x35BD1EC9) + q) & _mask32;
      swapAcc = (swapAcc + swapLast) & _mask32;

      state = ((state * keyA) + x) & _mask32;
      state = (_rol16(state) * 0xCF98B111) & _mask32;
      state = (_rol16(state) * 0x87085B9F) & _mask32;
      state = (_rol16(state) * 0x12CEB96D) & _mask32;
      state = (_rol16(state) * 0x257E1D83) & _mask32;
      acc = (acc + state) & _mask32;

      t = ((state * keyB) + y) & _mask32;
      t = (_rol16(t) * 0xA27416F5) & _mask32;
      t = (_rol16(t) * 0xD38396FF) & _mask32;
      state = (_rol16((_rol16(t) * 0x7C932B89) & _mask32) * 0xBFA49F69) &
          _mask32;
      acc = (acc + state) & _mask32;
    }

    return (swapLast ^ state, swapAcc ^ acc);
  }

  /// Generates a v2 Sec-MS-GEC token matching Microsoft Edge ReadAloud DRM.
  static String generateSecMsGecV2({double? unixTimestamp}) {
    var ticks = unixTimestamp ??
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0 +
            clockSkewSeconds);
    ticks += _winEpoch;
    ticks -= ticks % 300.0;
    ticks *= _sTo100Ns;
    final strToHash = '${ticks.toStringAsFixed(0)}$trustedClientToken';
    final data = Uint8List.fromList(ascii.encode(strToHash));
    final digest = _sha256Digest(data);
    final (c0, c1) = _cs64Digest(data, digest);
    final cs64Bytes = Uint8List(8);
    final bd = ByteData.sublistView(cs64Bytes);
    bd.setUint32(0, c0, Endian.little);
    bd.setUint32(4, c1, Endian.little);
    return '${_hexUpper(cs64Bytes)}-${_hexUpper(digest)}';
  }

  static String _hexUpper(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }

  static String _randomHex(int byteCount) {
    final sb = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _jsUtcTimestamp() {
    final now = DateTime.now().toUtc();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String d2(int v) => v.toString().padLeft(2, '0');
    return '${days[now.weekday - 1]} ${months[now.month - 1]} ${d2(now.day)} '
        '${now.year} ${d2(now.hour)}:${d2(now.minute)}:${d2(now.second)} '
        'GMT+0000 (Coordinated Universal Time)';
  }

  static String _escapeXml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _removeControlChars(String text) {
    final sb = StringBuffer();
    for (final rune in text.runes) {
      if ((rune >= 0 && rune <= 8) ||
          (rune >= 11 && rune <= 12) ||
          (rune >= 14 && rune <= 31)) {
        sb.write(' ');
      } else {
        sb.writeCharCode(rune);
      }
    }
    return sb.toString();
  }

  /// Resolves any JARVIS voice selection into a valid Microsoft Edge Neural voice ID.
  static String resolveEdgeVoice(String rawVoice, {required bool isFemale}) {
    var clean = rawVoice.trim();
    for (final prefix in const [
      'azure:',
      'chirp:',
      'gemini:',
      'openai:',
      'tr-tr-chirp3-hd-',
    ]) {
      if (clean.toLowerCase().startsWith(prefix)) {
        clean = clean.substring(prefix.length).trim();
      }
    }
    final lower = clean.toLowerCase();
    if (lower.contains('emel') || lower == 'elif') {
      return 'tr-TR-EmelNeural';
    }
    if (lower.contains('ahmet') || lower == 'aydin' || lower == 'aydın') {
      return 'tr-TR-AhmetNeural';
    }
    // Azure-only variants (Dragon HD "name:Model", MAI voices) do not exist on
    // the free Edge endpoint, so they map to the gender-matched Turkish voice.
    if (clean.contains('-') &&
        !clean.contains(':') &&
        lower.endsWith('neural') &&
        !lower.contains('chirp') &&
        !lower.contains('mai-voice')) {
      return clean;
    }
    return isFemale ? 'tr-TR-EmelNeural' : 'tr-TR-AhmetNeural';
  }

  static Future<void> _syncClockSkewFromBing() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .headUrl(Uri.parse('https://speech.platform.bing.com'))
          .timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final dateStr = res.headers.value(HttpHeaders.dateHeader);
      await res.drain<void>();
      if (dateStr != null && dateStr.isNotEmpty) {
        final serverDt = HttpDate.parse(dateStr).toUtc();
        final clientSec = DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;
        final serverSec = serverDt.millisecondsSinceEpoch / 1000.0;
        clockSkewSeconds = serverSec - clientSec;
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }

  /// Synthesizes Turkish speech directly via Microsoft Edge ReadAloud Neural WebSocket.
  static Future<({Uint8List? bytes, String ext, String error})> synthesize({
    required String text,
    required String voice,
    bool isFemale = false,
    double rateMultiplier = 1.0,
  }) async {
    final seam = testSynthesizer;
    if (seam != null) {
      return seam(text, voice, rateMultiplier);
    }
    final clean = _removeControlChars(text).trim();
    if (clean.isEmpty) {
      return (bytes: null, ext: 'mp3', error: 'Boş metin');
    }
    final edgeVoice = resolveEdgeVoice(voice, isFemale: isFemale);
    final ratePct = ((rateMultiplier - 1.0) * 100).round().clamp(-50, 80);
    final rateStr = '${ratePct >= 0 ? '+' : ''}$ratePct%';

    Future<({Uint8List? bytes, String ext, String error})> attempt() async {
      WebSocket? ws;
      // dart:io adds its own "Dart/x.y (dart:io)" User-Agent next to ours;
      // Microsoft rejects that handshake with HTTP 403. A client without a
      // default user agent sends only the Edge browser UA below.
      final wsHttp = HttpClient()
        ..userAgent = null
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final connId = _randomHex(16);
        final uri = Uri.parse(
          '$_wssBase?TrustedClientToken=$trustedClientToken'
          '&ConnectionId=$connId'
          '&Sec-MS-GEC=${generateSecMsGecV2()}'
          '&Sec-MS-GEC-Version=$secMsGecVersion',
        );
        ws = await WebSocket.connect(
          uri.toString(),
          headers: {
            'Pragma': 'no-cache',
            'Cache-Control': 'no-cache',
            'Origin': _origin,
            'User-Agent': _userAgent,
            'Accept-Language': 'en-US,en;q=0.9',
            'Cookie': 'muid=${_randomHex(16).toUpperCase()};',
          },
          customClient: wsHttp,
        ).timeout(const Duration(seconds: 10));

        final ts = _jsUtcTimestamp();
        ws.add(
          'X-Timestamp:$ts\r\n'
          'Content-Type:application/json; charset=utf-8\r\n'
          'Path:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":{'
          '"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},'
          '"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n',
        );

        final ssml =
            "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='tr-TR'>"
            "<voice name='$edgeVoice'>"
            "<prosody pitch='+0Hz' rate='$rateStr' volume='+0%'>"
            '${_escapeXml(clean)}'
            '</prosody></voice></speak>';
        ws.add(
          'X-RequestId:${_randomHex(16)}\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${ts}Z\r\n'
          'Path:ssml\r\n\r\n'
          '$ssml',
        );

        final out = BytesBuilder(copy: false);
        final done = Completer<void>();
        late final StreamSubscription<dynamic> sub;
        sub = ws.listen(
          (msg) {
            if (msg is String) {
              if (msg.contains('Path:turn.end') && !done.isCompleted) {
                done.complete();
              }
            } else if (msg is List<int>) {
              final data = msg is Uint8List ? msg : Uint8List.fromList(msg);
              if (data.length < 2) return;
              final headerLen = (data[0] << 8) | data[1];
              final payloadStart = headerLen + 2;
              if (payloadStart >= data.length) return;
              final hdr = ascii.decode(
                data.sublist(2, payloadStart.clamp(2, data.length)),
                allowInvalid: true,
              );
              if (hdr.contains('Path:audio')) {
                out.add(data.sublist(payloadStart));
              }
            }
          },
          onError: (Object err) {
            if (!done.isCompleted) done.completeError(err);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );

        try {
          await done.future.timeout(const Duration(seconds: 22));
        } finally {
          await sub.cancel();
        }
        final bytes = out.toBytes();
        if (bytes.length > 200) {
          return (bytes: bytes, ext: 'mp3', error: '');
        }
        return (bytes: null, ext: 'mp3', error: 'Edge Neural ses verisi dönmedi');
      } catch (e) {
        return (bytes: null, ext: 'mp3', error: 'Edge Neural: $e');
      } finally {
        try {
          await ws?.close();
        } catch (_) {}
        wsHttp.close(force: true);
      }
    }

    final first = await attempt();
    if (first.bytes != null) return first;
    // Retry once with clock skew adjustment if handshake was rejected (e.g., 403)
    if (first.error.contains('403') || first.error.contains('not upgraded')) {
      await _syncClockSkewFromBing();
      return attempt();
    }
    return first;
  }

  /// Cloud-hosted Google Translate Turkish MP3 backup (no API key required).
  static Future<({Uint8List? bytes, String ext, String error})>
      synthesizeGoogleTranslate({
    required String text,
    required http.Client client,
  }) async {
    var q = _removeControlChars(text).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.isEmpty) {
      return (bytes: null, ext: 'mp3', error: 'Boş metin');
    }
    if (q.length > 195) {
      final cut = q.lastIndexOf(RegExp(r'[\s,.!?]'), 195);
      q = q.substring(0, cut > 80 ? cut : 195).trim();
    }
    try {
      final uri = Uri.parse(
        'https://translate.google.com/translate_tts?ie=UTF-8&tl=tr&client=tw-ob&q=${Uri.encodeQueryComponent(q)}',
      );
      final r = await client.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Referer': 'https://translate.google.com/',
        },
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200 && r.bodyBytes.length > 200) {
        return (bytes: r.bodyBytes, ext: 'mp3', error: '');
      }
      return (
        bytes: null,
        ext: 'mp3',
        error: 'HTTP ${r.statusCode}',
      );
    } catch (e) {
      return (bytes: null, ext: 'mp3', error: '$e');
    }
  }
}

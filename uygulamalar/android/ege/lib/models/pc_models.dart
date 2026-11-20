// Data models for the JARVIS PC Bridge (Windows companion server).

int _int(dynamic v, [int fallback = 0]) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback;

double _dbl(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;

class PcRoot {
  final String name;
  final String path;

  const PcRoot({required this.name, required this.path});

  factory PcRoot.fromJson(Map<String, dynamic> j) => PcRoot(
        name: j['name']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
      );
}

class PcDiscovered {
  final String url;
  final String host;
  final String version;
  final int devices;

  const PcDiscovered({
    required this.url,
    required this.host,
    this.version = '',
    this.devices = 0,
  });

  String get ip => Uri.tryParse(url)?.host ?? url;
}

class PcFileEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime modified;
  final bool hidden;

  const PcFileEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    required this.modified,
    this.hidden = false,
  });

  String get ext {
    final i = name.lastIndexOf('.');
    return i <= 0 ? '' : name.substring(i).toLowerCase();
  }

  factory PcFileEntry.fromJson(Map<String, dynamic> j) => PcFileEntry(
        name: j['name']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
        isDir: j['dir'] == true,
        size: _int(j['size']),
        modified: DateTime.fromMillisecondsSinceEpoch(_int(j['mtime'])),
        hidden: j['hidden'] == true,
      );
}

class PcDirListing {
  final String path;
  final String? parent;
  final PcRoot? root;
  final List<PcFileEntry> entries;

  const PcDirListing({
    required this.path,
    this.parent,
    this.root,
    this.entries = const [],
  });

  factory PcDirListing.fromJson(Map<String, dynamic> j) => PcDirListing(
        path: j['path']?.toString() ?? '',
        parent: j['parent']?.toString(),
        root: j['root'] is Map
            ? PcRoot.fromJson(Map<String, dynamic>.from(j['root'] as Map))
            : null,
        entries: (j['entries'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => PcFileEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class PcFileContent {
  final String path;
  final String name;
  final int size;
  final bool binary;
  final bool image;
  final String? imageBase64;
  final String content;
  final String encoding;
  final bool truncated;
  final String sha256;
  final String eol;

  const PcFileContent({
    required this.path,
    required this.name,
    this.size = 0,
    this.binary = false,
    this.image = false,
    this.imageBase64,
    this.content = '',
    this.encoding = 'utf-8',
    this.truncated = false,
    this.sha256 = '',
    this.eol = 'lf',
  });

  bool get editable => !binary && !truncated;

  factory PcFileContent.fromJson(Map<String, dynamic> j) => PcFileContent(
        path: j['path']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        size: _int(j['size']),
        binary: j['binary'] == true,
        image: j['image'] == true,
        imageBase64: j['imageBase64']?.toString(),
        content: j['content']?.toString() ?? '',
        encoding: j['encoding']?.toString() ?? 'utf-8',
        truncated: j['truncated'] == true,
        sha256: j['sha256']?.toString() ?? '',
        eol: j['eol']?.toString() ?? 'lf',
      );
}

class PcSearchHit {
  final String path;
  final String rel;
  final int line;
  final String text;

  const PcSearchHit({
    required this.path,
    required this.rel,
    this.line = 0,
    this.text = '',
  });

  factory PcSearchHit.fromJson(Map<String, dynamic> j) => PcSearchHit(
        path: j['path']?.toString() ?? '',
        rel: j['rel']?.toString() ?? j['name']?.toString() ?? '',
        line: _int(j['line']),
        text: j['text']?.toString() ?? '',
      );
}

class PcTask {
  final String id;
  final String label;

  const PcTask({required this.id, required this.label});
}

class PcJob {
  final String id;
  final String kind; // task | agent
  final String label;
  final String cwd;
  final String status; // running | done | failed | cancelled
  final int? exitCode;
  final DateTime started;
  final DateTime? ended;
  final String output;
  final int next;

  const PcJob({
    required this.id,
    required this.kind,
    required this.label,
    required this.cwd,
    required this.status,
    this.exitCode,
    required this.started,
    this.ended,
    this.output = '',
    this.next = 0,
  });

  bool get running => status == 'running';

  factory PcJob.fromJson(Map<String, dynamic> j) => PcJob(
        id: j['id']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'task',
        label: j['label']?.toString() ?? '',
        cwd: j['cwd']?.toString() ?? '',
        status: j['status']?.toString() ?? 'running',
        exitCode: j['exitCode'] == null ? null : _int(j['exitCode']),
        started: DateTime.fromMillisecondsSinceEpoch(_int(j['started'])),
        ended: j['ended'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(_int(j['ended'])),
        output: j['output']?.toString() ?? '',
        next: _int(j['next']),
      );
}

class PcApkInfo {
  final String name;
  final int size;
  final DateTime modified;

  const PcApkInfo({
    required this.name,
    required this.size,
    required this.modified,
  });

  factory PcApkInfo.fromJson(Map<String, dynamic> j) => PcApkInfo(
        name: j['name']?.toString() ?? 'JARVIS.apk',
        size: _int(j['size']),
        modified: DateTime.fromMillisecondsSinceEpoch(_int(j['mtime'])),
      );
}

class PcHostInfo {
  final String host;
  final String user;
  final String os;
  final List<String> ips;
  final String bridgeVersion;
  final double ramTotalGb;
  final int ramUsedPct;
  final double diskTotalGb;
  final double diskFreeGb;
  final int? batteryPct;
  final bool charging;
  final int uptimeMin;
  final Map<String, bool> tools;
  final List<PcRoot> roots;
  final PcApkInfo? apk;

  const PcHostInfo({
    this.host = '',
    this.user = '',
    this.os = '',
    this.ips = const [],
    this.bridgeVersion = '',
    this.ramTotalGb = 0,
    this.ramUsedPct = 0,
    this.diskTotalGb = 0,
    this.diskFreeGb = 0,
    this.batteryPct,
    this.charging = false,
    this.uptimeMin = 0,
    this.tools = const {},
    this.roots = const [],
    this.apk,
  });

  factory PcHostInfo.fromJson(Map<String, dynamic> j) {
    final ram = j['ram'] is Map ? Map<String, dynamic>.from(j['ram']) : {};
    final disk = j['disk'] is Map ? Map<String, dynamic>.from(j['disk']) : {};
    final bat = j['battery'] is Map ? Map<String, dynamic>.from(j['battery']) : null;
    final tools = <String, bool>{};
    if (j['tools'] is Map) {
      (j['tools'] as Map).forEach((k, v) => tools['$k'] = v == true);
    }
    return PcHostInfo(
      host: j['host']?.toString() ?? '',
      user: j['user']?.toString() ?? '',
      os: j['os']?.toString() ?? '',
      ips: (j['ips'] as List? ?? const []).map((e) => '$e').toList(),
      bridgeVersion: j['bridgeVersion']?.toString() ?? '',
      ramTotalGb: _dbl(ram['totalGb']),
      ramUsedPct: _int(ram['usedPct']),
      diskTotalGb: _dbl(disk['totalGb']),
      diskFreeGb: _dbl(disk['freeGb']),
      batteryPct: bat == null ? null : _int(bat['pct']),
      charging: bat?['charging'] == true,
      uptimeMin: _int(j['uptimeMin']),
      tools: tools,
      roots: (j['roots'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PcRoot.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      apk: j['apk'] is Map
          ? PcApkInfo.fromJson(Map<String, dynamic>.from(j['apk'] as Map))
          : null,
    );
  }
}

/// API keys exported by the PC Bridge from the CLI Proxy API environment.
class PcKeyBundle {
  final String proxyBaseUrl;
  final String proxyApiKey;
  final bool proxyReachable;
  final int proxyModelCount;
  final String azureKey;
  final String azureRegion;
  final String geminiKey;
  final String googleCloudKey;
  final String openAiKey;
  final List<String> sources;

  const PcKeyBundle({
    this.proxyBaseUrl = '',
    this.proxyApiKey = '',
    this.proxyReachable = false,
    this.proxyModelCount = 0,
    this.azureKey = '',
    this.azureRegion = 'westeurope',
    this.geminiKey = '',
    this.googleCloudKey = '',
    this.openAiKey = '',
    this.sources = const [],
  });

  factory PcKeyBundle.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> sub(String k) =>
        j[k] is Map ? Map<String, dynamic>.from(j[k] as Map) : <String, dynamic>{};
    final proxy = sub('proxy');
    final azure = sub('azure');
    return PcKeyBundle(
      proxyBaseUrl: proxy['baseUrl']?.toString() ?? '',
      proxyApiKey: proxy['apiKey']?.toString() ?? '',
      proxyReachable: proxy['reachable'] == true,
      proxyModelCount: _int(proxy['modelCount']),
      azureKey: azure['key']?.toString() ?? '',
      azureRegion: (azure['region']?.toString() ?? '').trim().isEmpty
          ? 'westeurope'
          : azure['region'].toString().trim(),
      geminiKey: sub('gemini')['key']?.toString() ?? '',
      googleCloudKey: sub('googleCloud')['key']?.toString() ?? '',
      openAiKey: sub('openai')['key']?.toString() ?? '',
      sources: (j['sources'] as List? ?? const []).map((e) => '$e').toList(),
    );
  }

  /// Human readable list of what the bundle contains (never the secrets).
  List<String> get summary => [
        if (proxyApiKey.isNotEmpty)
          'CLI Proxy API anahtarı • $proxyBaseUrl'
              '${proxyReachable ? ' • $proxyModelCount model' : ' • (proxy yanıt vermedi)'}',
        if (azureKey.isNotEmpty) 'Azure Speech anahtarı ($azureRegion)',
        if (geminiKey.isNotEmpty) 'Gemini API anahtarı (Gemini TTS / Chirp 3 HD)',
        if (googleCloudKey.isNotEmpty) 'Google Cloud anahtarı',
        if (openAiKey.isNotEmpty) 'OpenAI anahtarı (OpenAI TTS)',
      ];
}

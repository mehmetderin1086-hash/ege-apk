import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jarvis_models.dart';

class StorageService {
  static const _settingsKey = 'jarvis.mobile.settings.v1';
  static const _sessionsKey = 'jarvis.mobile.sessions.v1';
  static const _activeSessionKey = 'jarvis.mobile.activeSession.v1';
  static const _notesKey = 'jarvis.mobile.notes.v1';
  static const _timersKey = 'jarvis.mobile.timers.v1';
  static const _studiesKey = 'jarvis.mobile.studies.v1';
  static const _modelsKey = 'jarvis.mobile.proxyModels.v1';

  Future<JarvisSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const JarvisSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return JarvisSettings.fromJson(decoded);
      }
    } catch (_) {}
    return const JarvisSettings();
  }

  Future<void> saveSettings(JarvisSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<({List<ChatSession> sessions, String activeId})> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    final activeId = prefs.getString(_activeSessionKey) ?? 'session-1';
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final parsed = decoded
              .whereType<Map<String, dynamic>>()
              .map(ChatSession.fromJson)
              .toList();
          if (parsed.isNotEmpty) {
            return (sessions: parsed, activeId: activeId);
          }
        }
      } catch (_) {}
    }
    return (
      sessions: [
        ChatSession(
          id: 'session-1',
          title: 'Ana Sohbet',
          updatedAt: DateTime.now(),
          messages: const [],
        ),
      ],
      activeId: 'session-1',
    );
  }

  Future<void> _sessionWrites = Future<void>.value();
  Future<void> saveSessions(List<ChatSession> sessions, String activeId) {
    // Capture now and serialize writes so a slower older save cannot erase a new turn.
    final encoded = encodeJsonList<ChatSession>(sessions, (s) => s.toJson());
    final write = _sessionWrites.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(_sessionsKey, encoded)) {
        throw StateError('Sohbet geçmişi kaydedilemedi');
      }
      await prefs.setString(_activeSessionKey, activeId);
    });
    _sessionWrites = write;
    return write;
  }

  Future<List<JarvisNote>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final parsed = decoded
              .whereType<Map<String, dynamic>>()
              .map(JarvisNote.fromJson)
              .toList();
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (_) {}
    }
    return [
      JarvisNote(
        id: 'note-1',
        title: 'Hızlı Notlar',
        content: '',
        updatedAt: DateTime.now(),
      ),
    ];
  }

  Future<void> saveNotes(List<JarvisNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notesKey,
      encodeJsonList<JarvisNote>(notes.take(50).toList(), (n) => n.toJson()),
    );
  }

  Future<List<JarvisTimer>> loadTimers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_timersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(JarvisTimer.fromJson)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveTimers(List<JarvisTimer> timers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _timersKey,
      encodeJsonList<JarvisTimer>(timers.take(25).toList(), (t) => t.toJson()),
    );
  }

  Future<List<StudyArtifact>> loadStudies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_studiesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(StudyArtifact.fromJson)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveStudies(List<StudyArtifact> studies) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _studiesKey,
      encodeJsonList<StudyArtifact>(studies.take(40).toList(), (s) => s.toJson()),
    );
  }

  Future<List<ProxyModelInfo>> loadCachedModels() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_modelsKey);
    if (raw == null || raw.isEmpty) return ProxyModelInfo.fallbackCatalog;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final parsed = decoded
            .whereType<Map<String, dynamic>>()
            .map(ProxyModelInfo.fromJson)
            .where((m) => m.id.isNotEmpty)
            .toList();
        if (parsed.isNotEmpty) {
          return ProxyModelInfo.mergeCatalog(parsed);
        }
      }
    } catch (_) {}
    return ProxyModelInfo.fallbackCatalog;
  }

  Future<void> saveCachedModels(List<ProxyModelInfo> models) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _modelsKey,
      encodeJsonList<ProxyModelInfo>(models, (m) => m.toJson()),
    );
  }
}

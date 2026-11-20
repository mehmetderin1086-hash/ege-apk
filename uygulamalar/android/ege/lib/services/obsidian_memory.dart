import 'dart:convert';

import '../models/jarvis_models.dart';
import 'agent_core.dart';
import 'local_command_engine.dart';

class ObsidianMemory {
  static String safeId(String id) =>
      base64Url.encode(utf8.encode(id)).replaceAll('=', '');
  static Map<String, String> files(
    List<ChatSession> sessions,
    JarvisSettings settings,
    List<Map<String, dynamic>> evidence,
    List<AgentSkill> skills,
  ) {
    final files = <String, String>{
      'Ege/BASLA.md':
          '# Ege Hafıza\n\n'
          'Bu kasa Ege tarafından Markdown olarak güncellenir. Sohbetler tam metindir; model bağlamı ayrı olarak kısaltılabilir.\n\n'
          '[[Profil]] · [[Hafiza]] · [[Cikarimlar]]\n\n'
          'Kendi notlarını kasanın istediğin yerinde tutabilirsin; Ege aramada bunları gözlem verisi olarak okur. '
          'Ege klasöründeki oluşturulmuş notları değiştirirsen, sonraki güncellemede eski sürümün Obsidian kopyası korunur.\n'
          'Ses ve resim dosyalarının kendileri bu metin kasasına kopyalanmaz.\n',
      'Ege/Profil.md': '# Kullanıcı profili\n\n${settings.userProfile}\n',
      'Ege/Hafiza.md':
          '# Kullanıcının kaydettiği bilgiler\n\n${settings.memoryText}\n',
      'Ege/Cikarimlar.md':
          '# Kaynaklı bilgiler ve çıkarımlar\n\n'
          '${evidence.map((e) => '## ${e['kind'] == 'fact' ? 'Kullanıcı beyanı' : 'Doğrulanmamış çıkarım'}\n${e['text']}\n\n'
              '${(e['sources'] as List? ?? []).whereType<Map>().map((s) => '- [[Sohbetler/${safeId(s['sessionId'].toString())}|Kaynak sohbet]] · ${s['at']} · “${s['quote']}”').join('\n')}\n').join('\n')}',
    };
    for (final session in sessions) {
      final body = StringBuffer(
        '---\ntitle: ${jsonEncode(session.title)}\nupdated: ${session.updatedAt.toIso8601String()}\n---\n\n# ${session.title}\n\n',
      );
      for (final m in session.messages) {
        body.writeln(
          '## ${m.role == 'user' ? 'Sen' : 'Ege'} · ${m.timestamp.toIso8601String()}\n',
        );
        body.writeln(LocalCommandEngine.stripActionTags(m.content));
        if (m.actionBanner?.isNotEmpty == true) {
          body.writeln('\nİşlem: ${m.actionBanner}');
        }
        for (final a in m.attachments) {
          body.writeln('\nEk: ${a.name}');
        }
        body.writeln('\n^${safeId(m.id)}\n');
      }
      files['Ege/Sohbetler/${safeId(session.id)}.md'] = body.toString();
    }
    for (final skill in skills.where((s) => !s.builtIn)) {
      files['Ege/Beceriler/${AgentSkill.slug(skill.name)}.md'] = skill
          .toMarkdown();
    }
    return files;
  }
}

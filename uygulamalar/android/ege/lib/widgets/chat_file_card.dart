import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/jarvis_models.dart';
import '../services/device_bridge.dart';
import 'chat_palette.dart';

class ChatFileCard extends StatelessWidget {
  const ChatFileCard({super.key, required this.file});
  final ChatAttachment file;

  Future<void> _open(BuildContext context) async {
    var ok = false;
    if (file.publicUri?.isNotEmpty == true) {
      ok = await DeviceBridge.openFileUri(
        file.publicUri!,
        mimeType: file.mimeType,
      );
    }
    if (!ok && file.localPath?.isNotEmpty == true) {
      ok = await DeviceBridge.openFileUri(
        file.localPath!,
        mimeType: file.mimeType,
      );
    }
    if (!ok && context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dosya açılamadı. Uygun bir görüntüleyici bulunmayabilir veya dosya taşınmış olabilir.',
          ),
        ),
      );
  }

  Future<void> _share(BuildContext context) async {
    try {
      final path = file.localPath;
      if (path == null || !await File(path).exists())
        throw StateError('missing');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: file.mimeType)],
          title: file.name,
        ),
      );
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dosya paylaşılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 360),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: ChatPalette.soft,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ChatPalette.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, color: ChatPalette.accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                file.name,
                style: TextStyle(color: ChatPalette.ink),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Aç'),
            ),
            TextButton.icon(
              onPressed: () => _share(context),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Paylaş'),
            ),
          ],
        ),
      ],
    ),
  );
}

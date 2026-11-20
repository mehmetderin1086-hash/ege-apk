import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/jarvis_models.dart';
import '../state/jarvis_controller.dart';
import '../widgets/chat_palette.dart';
import '../widgets/jarvis_fx.dart';
import '../widgets/markdown_message.dart';
import '../widgets/chat_file_card.dart';

class ChatScreen extends StatefulWidget {
  final JarvisController controller;

  const ChatScreen({super.key, required this.controller});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  int _lastMsgCount = 0;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? overrideText]) async {
    final text = overrideText ?? _inputCtrl.text;
    if (text.trim().isEmpty && widget.controller.pendingAttachments.isEmpty) {
      return;
    }
    if (overrideText == null) {
      _inputCtrl.clear();
    }
    await widget.controller.sendMessage(text);
    _scrollToBottomSoon();
  }

  Future<void> _showAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ChatPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.camera_alt_outlined,
                  color: ChatPalette.accent,
                ),
                title: const Text('Kameradan Fotoğraf Çek'),
                subtitle: const Text('Görsel analiz için Ege\'ye gönder'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_library_outlined,
                  color: ChatPalette.accent,
                ),
                title: const Text('Galeriden Görsel Seç'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF34D399),
                ),
                title: const Text('Metin veya kod dosyaları ekle'),
                subtitle: const Text('Birlikte incelemek için birden fazla dosya seçebilirsin.'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    String? err;
    if (choice == 'camera') {
      err = await widget.controller.pickImage(source: ImageSource.camera);
    } else if (choice == 'gallery') {
      err = await widget.controller.pickImage(source: ImageSource.gallery);
    } else if (choice == 'file') {
      err = await widget.controller.pickTextFile();
    }

    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final session = c.activeSession;
    final messages = session.messages;

    // Paylaş / seçili metin ("Ege'e sor") ile gelen taslak.
    final draft = c.pendingDraft;
    if (draft != null) {
      c.pendingDraft = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _inputCtrl.text = draft;
        _inputCtrl.selection = TextSelection.collapsed(offset: draft.length);
      });
    }

    if (messages.length != _lastMsgCount) {
      _lastMsgCount = messages.length;
      if (messages.isNotEmpty) {
        _scrollToBottomSoon();
      }
    }

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const SizedBox.expand(key: Key('empty_chat_canvas'))
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  itemCount: messages.length,
                  itemBuilder: (context, idx) {
                    final msg = messages[idx];
                    final isStreamingLast =
                        c.isStreaming && idx == messages.length - 1;
                    return _MessageBubble(
                      key: ValueKey(msg.id),
                      message: msg,
                      animate: idx >= messages.length - 2,
                      isStreaming: isStreamingLast,
                      isSpeaking: c.speakingMessageId == msg.id,
                      onSpeakTap: () => c.speakMessage(msg.id, msg.content),
                    );
                  },
                ),
        ),
        if (c.pendingAttachments.isNotEmpty) _PendingAttachmentsBar(c: c),
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => c.pendingApproval == null
              ? const SizedBox.shrink()
              : _ApprovalCard(c: c),
        ),
        _ComposerBar(
          controller: _inputCtrl,
          isStreaming: c.isStreaming,
          isDictating: c.isDictating,
          level: c.orbAmplitude,
          isImageModel: c.isImageGenerationModel,
          onAttach: _showAttachMenu,
          onMicToggle: () async {
            final messenger = ScaffoldMessenger.of(context);
            final err = await c.toggleDictation(
              onTranscript: (text) {
                _inputCtrl.text = text;
                _inputCtrl.selection = TextSelection.collapsed(
                  offset: _inputCtrl.text.length,
                );
              },
            );
            if (err != null && mounted) {
              messenger.showSnackBar(SnackBar(content: Text(err)));
            }
          },
          onSend: () => _send(),
          onStop: c.stopStreaming,
          onLiveVoice: () => c.openTab(1),
          hasAttachments: c.pendingAttachments.isNotEmpty,
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final JarvisMessage message;
  final bool isStreaming;
  final bool isSpeaking;
  final bool animate;
  final VoidCallback onSpeakTap;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isStreaming,
    required this.isSpeaking,
    required this.onSpeakTap,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    return FadeSlideIn(
      enabled: animate,
      dy: 14,
      duration: const Duration(milliseconds: 340),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.88,
          ),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
          decoration: BoxDecoration(
            color: isUser ? ChatPalette.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: ChatPalette.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Ege',
                        style: const TextStyle(
                          fontSize: 11.2,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB85C3D),
                          letterSpacing: 0.6,
                        ),
                      ),
                      if (message.modelUsed != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '• ${message.modelUsed}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.8,
                              color: Color(0xFF74736D),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (message.attachments.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final att in message.attachments)
                      _AttachmentChipPreview(attachment: att),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (message.content.isEmpty && isStreaming)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TypingDots(),
                      SizedBox(width: 10),
                      Text(
                        'Ege düşünüyor…',
                        style: TextStyle(
                          color: Color(0xFF74736D),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              else if (isUser)
                MarkdownMessage(
                  text: message.content,
                  baseStyle: TextStyle(
                    color: ChatPalette.ink,
                    fontSize: 14.5,
                    height: 1.42,
                  ),
                )
              else
                MarkdownMessage(
                  text: message.content,
                  baseStyle: TextStyle(
                    color: ChatPalette.ink,
                    fontSize: 15.5,
                    height: 1.6,
                  ),
                ),
              if (message.actionBanner != null &&
                  message.actionBanner!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9F0E8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        size: 14,
                        color: Color(0xFF315C3C),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          message.actionBanner!,
                          style: const TextStyle(
                            color: Color(0xFF315C3C),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.durationSec != null
                        ? '$timeStr • ${message.durationSec!.toStringAsFixed(1)}s'
                        : timeStr,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF74736D),
                    ),
                  ),
                  if (!isUser && message.content.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: onSpeakTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSpeaking
                                ? Icons.stop_circle_outlined
                                : Icons.volume_up_outlined,
                            size: 15,
                            color: isSpeaking
                                ? const Color(0xFF34D399)
                                : const Color(0xFF74736D),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isSpeaking ? 'Durdur' : 'Seslendir',
                            style: TextStyle(
                              fontSize: 11,
                              color: isSpeaking
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF74736D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: message.content),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Yanıt panoya kopyalandı'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: Color(0xFF74736D),
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Kopyala',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF74736D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChipPreview extends StatelessWidget {
  final ChatAttachment attachment;

  const _AttachmentChipPreview({required this.attachment});

  void _openPreview(BuildContext context, {Uint8List? bytes, File? file}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ChatPalette.surface,
        insetPadding: const EdgeInsets.all(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF30302E),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Paylaş',
                    icon: const Icon(
                      Icons.share_rounded,
                      color: Color(0xFFB85C3D),
                    ),
                    onPressed: () async {
                      String? sharePath = file?.path;
                      if (sharePath == null && bytes != null) {
                        final tmp = File(
                          '${Directory.systemTemp.path}/${attachment.id}.png',
                        );
                        await tmp.writeAsBytes(bytes);
                        sharePath = tmp.path;
                      }
                      if (sharePath != null) {
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [XFile(sharePath)],
                            text: attachment.name,
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: InteractiveViewer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: bytes != null
                        ? Image.memory(bytes, fit: BoxFit.contain)
                        : Image.file(file!, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (attachment.kind == 'file' ||
        (attachment.kind != 'image' && attachment.localPath != null)) {
      return ChatFileCard(file: attachment);
    }
    if (attachment.kind == 'image') {
      Uint8List? memBytes;
      if (attachment.base64Data != null && attachment.base64Data!.isNotEmpty) {
        memBytes = base64Decode(attachment.base64Data!);
      }
      final File? localFile =
          attachment.localPath != null &&
              attachment.localPath!.isNotEmpty &&
              File(attachment.localPath!).existsSync()
          ? File(attachment.localPath!)
          : null;

      if (memBytes != null || localFile != null) {
        return GestureDetector(
          onTap: () => _openPreview(context, bytes: memBytes, file: localFile),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: memBytes != null
                    ? Image.memory(
                        memBytes,
                        width: 190,
                        height: 150,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        localFile!,
                        width: 190,
                        height: 150,
                        fit: BoxFit.cover,
                      ),
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.zoom_out_map_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: ChatPalette.soft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE3E0D8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 14,
            color: Color(0xFFB85C3D),
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              attachment.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: ChatPalette.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final JarvisController c;
  const _ApprovalCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final p = c.pendingApproval!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: ChatPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ChatPalette.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: ChatPalette.accent,
                  size: 18,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'PC komutu onay bekliyor',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ChatPalette.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ChatPalette.soft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                p.cmd,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.reason,
              style: TextStyle(fontSize: 12, color: ChatPalette.muted),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton(
                  onPressed: () => c.resolveApproval(approve: true),
                  child: const Text('Onayla'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      c.resolveApproval(approve: true, always: true),
                  child: const Text('Her zaman izin ver'),
                ),
                TextButton(
                  onPressed: () => c.resolveApproval(approve: false),
                  child: Text(
                    'Reddet',
                    style: TextStyle(color: ChatPalette.accent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingAttachmentsBar extends StatelessWidget {
  final JarvisController c;

  const _PendingAttachmentsBar({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: c.pendingAttachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final att = c.pendingAttachments[idx];
          return Chip(
            backgroundColor: ChatPalette.surface,
            side: const BorderSide(color: Color(0xFFE3E0D8)),
            avatar: Icon(
              att.kind == 'image'
                  ? Icons.image_outlined
                  : Icons.description_outlined,
              size: 16,
              color: const Color(0xFFB85C3D),
            ),
            label: Text(
              att.name,
              style: const TextStyle(fontSize: 12, color: Color(0xFF30302E)),
            ),
            onDeleted: () => c.removeAttachment(att.id),
          );
        },
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isStreaming;
  final bool isDictating;
  final double level;
  final bool isImageModel;
  final VoidCallback onAttach;
  final VoidCallback onMicToggle;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onLiveVoice;
  final bool hasAttachments;

  const _ComposerBar({
    required this.controller,
    required this.isStreaming,
    required this.isDictating,
    this.level = 0,
    this.isImageModel = false,
    required this.onAttach,
    required this.onMicToggle,
    required this.onSend,
    required this.onStop,
    required this.onLiveVoice,
    required this.hasAttachments,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: ChatPalette.surface,
                border: Border.all(color: ChatPalette.border),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(6, 8, 8, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      color: ChatPalette.ink,
                      fontSize: 16,
                      height: 1.45,
                    ),
                    decoration: InputDecoration(
                      hintText: isDictating
                          ? 'Dinliyorum…'
                          : isImageModel
                          ? 'Hayalindeki görseli anlat…'
                          : 'Ege’ye bir şey sor',
                      hintStyle: TextStyle(color: ChatPalette.muted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Kamera, galeri veya dosya ekle',
                        onPressed: onAttach,
                        icon: const Icon(Icons.add_rounded),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: isDictating
                            ? 'Dikteyi durdur'
                            : 'Sesle dikte et',
                        onPressed: onMicToggle,
                        icon: Icon(
                          isDictating
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: isDictating
                              ? ChatPalette.accent
                              : ChatPalette.ink,
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) {
                          final canSend =
                              value.text.trim().isNotEmpty || hasAttachments;
                          return IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: ChatPalette.ink,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(44, 44),
                            ),
                            tooltip: isStreaming
                                ? 'Yanıtı durdur'
                                : canSend
                                ? 'Gönder'
                                : 'Canlı Ses',
                            onPressed: isStreaming
                                ? onStop
                                : canSend
                                ? onSend
                                : onLiveVoice,
                            icon: Icon(
                              isStreaming
                                  ? Icons.stop_rounded
                                  : canSend
                                  ? Icons.arrow_upward_rounded
                                  : Icons.graphic_eq_rounded,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Ege hata yapabilir. Önemli bilgileri kontrol et.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: ChatPalette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

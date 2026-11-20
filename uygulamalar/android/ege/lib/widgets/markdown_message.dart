import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/device_bridge.dart';
import 'chat_palette.dart';

/// Pure-Flutter Markdown renderer supporting headings, fenced code blocks with
/// one-tap copy, tables, blockquotes, lists, inline code/bold/italic, and clickable URLs.
class MarkdownMessage extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;

  const MarkdownMessage({super.key, required this.text, this.baseStyle});

  @override
  Widget build(BuildContext context) {
    final defaultStyle =
        baseStyle ??
        const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14.5, height: 1.48);

    final blocks = _parseBlocks(text);
    if (blocks.isEmpty) {
      return SelectableText(text, style: defaultStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          _buildBlock(context, blocks[i], defaultStyle),
          if (i < blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildBlock(
    BuildContext context,
    _MdBlock block,
    TextStyle baseStyle,
  ) {
    switch (block.type) {
      case _MdBlockType.code:
        return _CodeBlockCard(language: block.meta, code: block.content);
      case _MdBlockType.heading:
        final level = int.tryParse(block.meta) ?? 2;
        final size = switch (level) {
          1 => baseStyle.fontSize! + 5.5,
          2 => baseStyle.fontSize! + 3.5,
          3 => baseStyle.fontSize! + 1.8,
          _ => baseStyle.fontSize! + 0.5,
        };
        return _RichInlineText(
          raw: block.content,
          style: baseStyle.copyWith(
            fontSize: size,
            fontWeight: FontWeight.w700,
            color: baseStyle.color,
            height: 1.32,
          ),
        );
      case _MdBlockType.blockquote:
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light
                ? ChatPalette.soft
                : const Color(0xFF0E1B2E),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
            ),
          ),
          child: _RichInlineText(raw: block.content, style: baseStyle),
        );
      case _MdBlockType.divider:
        return Divider(
          color: const Color(0xFF334155).withValues(alpha: 0.7),
          height: 12,
        );
      case _MdBlockType.table:
        return _MarkdownTableView(rows: block.rows, baseStyle: baseStyle);
      case _MdBlockType.bulletList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in block.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Text(
                        '•',
                        style: baseStyle.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _RichInlineText(raw: item, style: baseStyle),
                    ),
                  ],
                ),
              ),
          ],
        );
      case _MdBlockType.numberedList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < block.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1, right: 8),
                      child: Text(
                        '${i + 1}.',
                        style: baseStyle.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _RichInlineText(
                        raw: block.items[i],
                        style: baseStyle,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      case _MdBlockType.paragraph:
        return _RichInlineText(raw: block.content, style: baseStyle);
    }
  }
}

enum _MdBlockType {
  paragraph,
  heading,
  code,
  blockquote,
  bulletList,
  numberedList,
  table,
  divider,
}

class _MdBlock {
  final _MdBlockType type;
  final String content;
  final String meta;
  final List<String> items;
  final List<List<String>> rows;

  const _MdBlock({
    required this.type,
    this.content = '',
    this.meta = '',
    this.items = const [],
    this.rows = const [],
  });
}

List<_MdBlock> _parseBlocks(String input) {
  final lines = input.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_MdBlock>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    // Fenced code block (``` or ~~~)
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      final fence = trimmed.startsWith('```') ? '```' : '~~~';
      final lang = trimmed.substring(3).trim();
      final buf = StringBuffer();
      i++;
      while (i < lines.length && !lines[i].trim().startsWith(fence)) {
        if (buf.isNotEmpty) buf.writeln();
        buf.write(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      blocks.add(
        _MdBlock(type: _MdBlockType.code, content: buf.toString(), meta: lang),
      );
      continue;
    }

    // Heading (# .. ####)
    final headingMatch = RegExp(r'^(#{1,4})\s+(.+)$').firstMatch(trimmed);
    if (headingMatch != null) {
      blocks.add(
        _MdBlock(
          type: _MdBlockType.heading,
          meta: '${headingMatch.group(1)!.length}',
          content: headingMatch.group(2)!.trim(),
        ),
      );
      i++;
      continue;
    }

    // Horizontal divider
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
      blocks.add(const _MdBlock(type: _MdBlockType.divider));
      i++;
      continue;
    }

    // Markdown table
    if (trimmed.contains('|') &&
        i + 1 < lines.length &&
        RegExp(r'^\|?[\s:\-]+\|').hasMatch(lines[i + 1].trim())) {
      final rows = <List<String>>[];
      rows.add(_splitTableRow(trimmed));
      i += 2; // skip header + separator
      while (i < lines.length && lines[i].trim().contains('|')) {
        rows.add(_splitTableRow(lines[i].trim()));
        i++;
      }
      blocks.add(_MdBlock(type: _MdBlockType.table, rows: rows));
      continue;
    }

    // Blockquote
    if (trimmed.startsWith('>')) {
      final quoteLines = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quoteLines.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      blocks.add(
        _MdBlock(type: _MdBlockType.blockquote, content: quoteLines.join('\n')),
      );
      continue;
    }

    // Bullet list
    if (RegExp(r'^[-*+]\s+').hasMatch(trimmed)) {
      final items = <String>[];
      while (i < lines.length &&
          RegExp(r'^[-*+]\s+').hasMatch(lines[i].trim())) {
        items.add(lines[i].trim().replaceFirst(RegExp(r'^[-*+]\s+'), ''));
        i++;
      }
      blocks.add(_MdBlock(type: _MdBlockType.bulletList, items: items));
      continue;
    }

    // Numbered list
    if (RegExp(r'^\d+[.)]\s+').hasMatch(trimmed)) {
      final items = <String>[];
      while (i < lines.length &&
          RegExp(r'^\d+[.)]\s+').hasMatch(lines[i].trim())) {
        items.add(lines[i].trim().replaceFirst(RegExp(r'^\d+[.)]\s+'), ''));
        i++;
      }
      blocks.add(_MdBlock(type: _MdBlockType.numberedList, items: items));
      continue;
    }

    // Regular paragraph until blank line or next special block
    final para = <String>[];
    while (i < lines.length) {
      final cur = lines[i].trim();
      if (cur.isEmpty ||
          cur.startsWith('```') ||
          cur.startsWith('~~~') ||
          cur.startsWith('>') ||
          RegExp(r'^#{1,4}\s+').hasMatch(cur) ||
          RegExp(r'^[-*+]\s+').hasMatch(cur) ||
          RegExp(r'^\d+[.)]\s+').hasMatch(cur) ||
          RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(cur)) {
        break;
      }
      para.add(lines[i].trimRight());
      i++;
    }
    if (para.isNotEmpty) {
      blocks.add(
        _MdBlock(type: _MdBlockType.paragraph, content: para.join('\n')),
      );
    }
  }

  return blocks;
}

List<String> _splitTableRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((c) => c.trim()).toList();
}

class _CodeBlockCard extends StatefulWidget {
  final String language;
  final String code;

  const _CodeBlockCard({required this.language, required this.code});

  @override
  State<_CodeBlockCard> createState() => _CodeBlockCardState();
}

class _CodeBlockCardState extends State<_CodeBlockCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF040812),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0A1424),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Text(
                  widget.language.isEmpty ? 'kod' : widget.language,
                  style: const TextStyle(
                    color: Color(0xFF67E8F9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (!mounted) return;
                    setState(() => _copied = true);
                    Future<void>.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 14,
                        color: _copied
                            ? const Color(0xFF34D399)
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Kopyalandı' : 'Kopyala',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _copied
                              ? const Color(0xFF34D399)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 12.8,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownTableView extends StatelessWidget {
  final List<List<String>> rows;
  final TextStyle baseStyle;

  const _MarkdownTableView({required this.rows, required this.baseStyle});

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.fold<int>(
      0,
      (prev, r) => r.length > prev ? r.length : prev,
    );
    if (colCount == 0) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: light ? ChatPalette.surface : const Color(0xFF0A1424),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: light ? ChatPalette.border : const Color(0xFF1E3A5F),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.symmetric(
            inside: BorderSide(
              color: light
                  ? ChatPalette.border
                  : const Color(0xFF1E3A5F).withValues(alpha: 0.7),
            ),
          ),
          children: [
            for (var rIdx = 0; rIdx < rows.length; rIdx++)
              TableRow(
                decoration: BoxDecoration(
                  color: rIdx == 0
                      ? (light ? ChatPalette.soft : const Color(0xFF11223B))
                      : (rIdx.isEven
                            ? (light
                                  ? ChatPalette.background
                                  : const Color(0xFF07101F))
                            : Colors.transparent),
                ),
                children: [
                  for (var c = 0; c < colCount; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: _RichInlineText(
                        raw: c < rows[rIdx].length ? rows[rIdx][c] : '',
                        style: rIdx == 0
                            ? baseStyle.copyWith(
                                fontWeight: FontWeight.w700,
                                color: baseStyle.color,
                                fontSize: 13.2,
                              )
                            : baseStyle.copyWith(fontSize: 13.2),
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

class _RichInlineText extends StatelessWidget {
  final String raw;
  final TextStyle style;

  const _RichInlineText({required this.raw, required this.style});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _parseInline(raw, style), style: style),
    );
  }

  List<InlineSpan> _parseInline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final tokenRegex = RegExp(
      r'(\[[^\]]+\]\((?:https?://|mailto:|tel:|geo:|sms:|smsto:)[^\s)]+\))'
      r'|((?:https?://|www\.|mailto:|tel:|geo:|sms:|smsto:)[^\s<>\[\]()]+)'
      r'|(`[^`]+`)'
      r'|(\*\*[^*]+\*\*|__[^_]+__)'
      r'|(\*[^*]+\*|_[^_]+_)'
      r'|(~~[^~]+~~)',
    );

    var cursor = 0;
    for (final match in tokenRegex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final tok = match.group(0)!;
      if (tok.startsWith('[') && tok.contains('](')) {
        final linkMatch = RegExp(
          r'^\[([^\]]+)\]\(((?:https?://|mailto:|tel:|geo:|sms:|smsto:)[^\s)]+)\)$',
        ).firstMatch(tok);
        if (linkMatch != null) {
          final label = linkMatch.group(1)!;
          final url = linkMatch.group(2)!;
          spans.add(_buildLinkSpan(label, url, base));
        } else {
          spans.add(TextSpan(text: tok));
        }
      } else if (RegExp(r'^(https?://|www\.|mailto:|tel:|geo:|sms:|smsto:)')
          .hasMatch(tok)) {
        final url = tok.replaceFirst(RegExp(r'[.,;!?]+$'), '');
        spans.add(
          _buildLinkSpan(
            url,
            url.startsWith('www.') ? 'https://$url' : url,
            base,
          ),
        );
        if (url.length < tok.length)
          spans.add(TextSpan(text: tok.substring(url.length)));
      } else if (tok.startsWith('`') && tok.endsWith('`') && tok.length >= 2) {
        spans.add(
          TextSpan(
            text: ' ${tok.substring(1, tok.length - 1)} ',
            style: base.copyWith(
              fontFamily: 'monospace',
              fontSize: (base.fontSize ?? 14) - 1,
              color: const Color(0xFF67E8F9),
              backgroundColor: const Color(0xFF0A1628),
            ),
          ),
        );
      } else if ((tok.startsWith('**') && tok.endsWith('**')) ||
          (tok.startsWith('__') && tok.endsWith('__'))) {
        spans.add(
          TextSpan(
            text: tok.substring(2, tok.length - 2),
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else if ((tok.startsWith('*') && tok.endsWith('*')) ||
          (tok.startsWith('_') && tok.endsWith('_'))) {
        spans.add(
          TextSpan(
            text: tok.substring(1, tok.length - 1),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (tok.startsWith('~~') &&
          tok.endsWith('~~') &&
          tok.length >= 4) {
        spans.add(
          TextSpan(
            text: tok.substring(2, tok.length - 2),
            style: base.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  InlineSpan _buildLinkSpan(String label, String url, TextStyle base) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: InkWell(
        onTap: () => DeviceBridge.openUrl(url),
        child: Text(
          label,
          style: base.copyWith(
            color: (base.color?.computeLuminance() ?? 1) < 0.5
                ? ChatPalette.accent
                : const Color(0xFF38BDF8),
            decoration: TextDecoration.underline,
            decorationColor: (base.color?.computeLuminance() ?? 1) < 0.5
                ? ChatPalette.accent
                : const Color(0xFF38BDF8),
          ),
        ),
      ),
    );
  }
}

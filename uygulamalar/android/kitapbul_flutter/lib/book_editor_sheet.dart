import 'package:flutter/material.dart';

import 'catalog_search.dart';

/// Extracts the most frequently used distinct non-empty values for a book field
/// (such as `'shelf'`, `'category'`, or `'language'`), sorted by frequency desc.
List<String> topFieldSuggestions(
  List<Map<String, dynamic>> books,
  String field, {
  int limit = 8,
}) {
  final display = <String, String>{};
  final counts = <String, int>{};
  for (final book in books) {
    if (book['deletedAt'] != null) continue;
    final raw = (book[field] ?? '').toString().trim();
    if (raw.isEmpty) continue;
    final key = foldTurkish(raw);
    display.putIfAbsent(key, () => raw);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final keys = display.keys.toList()
    ..sort((a, b) {
      final cmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
      return cmp != 0
          ? cmp
          : foldTurkish(display[a]!).compareTo(foldTurkish(display[b]!));
    });
  return keys.take(limit).map((k) => display[k]!).toList();
}

/// Consistent modern outlined decoration for fields inside the Book Editor.
InputDecoration bookFieldDecoration(
  String label, {
  String? hint,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) => InputDecoration(
  labelText: label,
  hintText: hint,
  prefixIcon: prefixIcon,
  suffixIcon: suffixIcon,
  isDense: true,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

/// Grouped visual card for organizing sections in the full-screen Book Editor.
class BookEditorSectionCard extends StatelessWidget {
  const BookEditorSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: scheme.primary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

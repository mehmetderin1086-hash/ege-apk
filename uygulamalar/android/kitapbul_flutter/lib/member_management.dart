import 'package:flutter/material.dart';
import 'catalog_search.dart' show foldTurkish;
import 'loan_model.dart';
import 'loan_settings.dart' show newGradeRuleId;
import 'member_store.dart';
import 'reservation_model.dart';

class MemberManagementPage extends StatefulWidget {
  const MemberManagementPage({
    super.key,
    required this.initialMembers,
    required this.books,
    required this.save,
  });
  final List<Member> initialMembers;
  final List<Map<String, dynamic>> books;
  final Future<bool> Function(List<Member>) save;
  @override
  State<MemberManagementPage> createState() => _MemberManagementPageState();
}

class _MemberManagementPageState extends State<MemberManagementPage> {
  late List<Member> members;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    members = [...widget.initialMembers];
  }

  Future<void> edit([Member? old]) async {
    var name = old?.name ?? '';
    var number = old?.number ?? '';
    var note = old?.note ?? '';
    String? kind = old?.kind ?? (old == null ? 'other' : null);
    String? error;
    final result = await showDialog<Member>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text(old == null ? 'Üye ekle' : 'Üyeyi düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  decoration: const InputDecoration(labelText: 'Ad soyad'),
                  onChanged: (value) => name = value,
                ),
                TextFormField(
                  initialValue: number,
                  decoration: const InputDecoration(labelText: 'Üye numarası'),
                  onChanged: (value) => number = value,
                ),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Üye türü'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Türü belirtilmemiş'),
                    ),
                    ...memberKinds.entries.map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    ),
                  ],
                  onChanged: (value) => refresh(() => kind = value),
                ),
                TextFormField(
                  initialValue: note,
                  decoration: const InputDecoration(labelText: 'Not'),
                  onChanged: (value) => note = value,
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final clean = name.trim();
                if (clean.isEmpty ||
                    members.any(
                      (m) =>
                          m.id != old?.id &&
                          foldTurkish(m.name.trim()) == foldTurkish(clean) &&
                          m.number == number.trim(),
                    )) {
                  refresh(
                    () => error = clean.isEmpty
                        ? 'Ad soyad gerekli.'
                        : 'Aynı ad ve numarayla bir üye var.',
                  );
                  return;
                }
                Navigator.pop(
                  ctx,
                  Member(
                    id: old?.id ?? newGradeRuleId(),
                    name: clean,
                    number: number.trim(),
                    note: note.trim(),
                    kind: kind,
                  ),
                );
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (old == null) {
        members.add(result);
      } else {
        members[members.indexWhere((member) => member.id == old.id)] = result;
      }
    });
  }

  Future<void> remove(Member member) async {
    final id = member.id.toUpperCase();
    final linked = widget.books.any(
      (book) =>
          activeLoans(book).any(
            (loan) => (loan['memberId']?.toString().toUpperCase() ?? '') == id,
          ) ||
          reservationsOf(book).any(
            (r) =>
                isActiveReservation(r) &&
                (r['memberId']?.toString().toUpperCase() ?? '') == id,
          ),
    );
    if (linked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Üyenin etkin ödüncünü ve açık rezervasyonunu önce kapatın.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Üye silinsin mi?'),
        content: Text(member.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted)
      setState(() => members.removeWhere((m) => m.id == member.id));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Üyeler'),
      actions: [
        TextButton(
          onPressed: saving
              ? null
              : () async {
                  setState(() => saving = true);
                  final success = await widget.save(members);
                  if (!mounted) return;
                  setState(() => saving = false);
                  if (success) {
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Üyeler kaydedilemedi.')),
                    );
                  }
                },
          child: const Text('Kaydet'),
        ),
      ],
    ),
    body: members.isEmpty
        ? const Center(child: Text('Henüz üye yok.'))
        : ListView.builder(
            itemCount: members.length,
            itemBuilder: (ctx, index) {
              final member = members[index];
              return ListTile(
                title: Text(member.name),
                subtitle: Text(
                  [
                    member.kindTitle,
                    if (member.number.isNotEmpty) member.number,
                    if (member.note.isNotEmpty) member.note,
                  ].join(' · '),
                ),
                onTap: saving ? null : () => edit(member),
                trailing: IconButton(
                  tooltip: 'Üyeyi sil',
                  onPressed: saving ? null : () => remove(member),
                  icon: const Icon(Icons.delete_outline),
                ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: saving ? null : () => edit(),
      icon: const Icon(Icons.person_add),
      label: const Text('Üye ekle'),
    ),
  );
}

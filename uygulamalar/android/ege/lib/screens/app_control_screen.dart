import 'package:flutter/material.dart';

import '../models/jarvis_models.dart';
import '../services/device_bridge.dart';
import '../widgets/chat_palette.dart';

class AppControlScreen extends StatefulWidget {
  const AppControlScreen({super.key});
  @override
  State<AppControlScreen> createState() => _AppControlScreenState();
}

class _AppControlScreenState extends State<AppControlScreen> {
  List<DeviceAppInfo> _apps = [];
  final _query = TextEditingController();
  final _target = TextEditingController();
  final _text = TextEditingController();
  DeviceAppInfo? _selected;
  String _action = 'click';
  bool _busy = false;
  String? _result;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await DeviceBridge.listInstalledApps();
    if (mounted) setState(() => _apps = apps);
  }

  @override
  void dispose() {
    _query.dispose();
    _target.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ChatPalette.theme,
    child: Scaffold(
      appBar: AppBar(title: const Text('Uygulama kontrolü')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Uygulamayı seç, aç veya içindeki bir kontrolü kullan.',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
           Text(
            'Uygulama içindeki işlemler için Ege Uygulama Kontrolü erişilebilirlik iznini aç. Düğme veya alanın ekranda görünen adını yaz. Desteklenmeyen ekranlarda işlem yapılmaz.',
            style: TextStyle(color: ChatPalette.muted, height: 1.5),
          ),
          TextButton.icon(
            onPressed: () => DeviceBridge.openSystemSettings('accessibility'),
            icon: const Icon(Icons.accessibility_new),
            label: const Text('Erişilebilirlik ayarlarını aç'),
          ),
          TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Uygulama ara',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView(
              children: [
                for (final app in _apps.where(
                  (a) =>
                      a.name.toLowerCase().contains(_query.text.toLowerCase()),
                ))
                  ListTile(
                    title: Text(app.name),
                    subtitle: Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: _selected?.packageName == app.packageName,
                    selectedTileColor: ChatPalette.soft,
                    trailing: _selected?.packageName == app.packageName
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => setState(() => _selected = app),
                  ),
              ],
            ),
          ),
          if (_apps.isEmpty) const Text('Başlatılabilir uygulama bulunamadı.'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _selected == null
                ? null
                : () => DeviceBridge.launchApp(_selected!.packageName),
            icon: const Icon(Icons.open_in_new),
            label: Text(
              _selected == null ? 'Önce uygulama seç' : '${_selected!.name} aç',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _action,
            decoration: const InputDecoration(labelText: 'İşlem'),
            items: const [
              DropdownMenuItem(value: 'click', child: Text('Düğmeye dokun')),
              DropdownMenuItem(value: 'text', child: Text('Alana yaz')),
              DropdownMenuItem(value: 'scroll', child: Text('Aşağı kaydır')),
              DropdownMenuItem(value: 'back', child: Text('Geri git')),
            ],
            onChanged: (v) => setState(() => _action = v!),
          ),
          if (_action == 'click' || _action == 'text')
            TextField(
              controller: _target,
              decoration: const InputDecoration(
                labelText: 'Düğmenin veya alanın tam adı',
                hintText: 'Örn: Ara',
              ),
            ),
          if (_action == 'text')
            TextField(
              controller: _text,
              decoration: const InputDecoration(labelText: 'Yazılacak metin'),
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _selected == null || _busy
                ? null
                : () async {
                    if ((_action == 'click' || _action == 'text') &&
                        _target.text.trim().isEmpty) {
                      setState(() => _result = 'Düğme veya alan adını yaz.');
                      return;
                    }
                    setState(() {
                      _busy = true;
                      _result = null;
                    });
                    final result = await DeviceBridge.controlApp(
                      packageName: _selected!.packageName,
                      action: _action,
                      target: _target.text.trim(),
                      text: _text.text,
                    );
                    if (mounted) {
                      setState(() {
                        _busy = false;
                        _result = result;
                      });
                    }
                  },
            child: Text(
              _busy ? 'Uygulanıyor…' : 'Uygulamayı aç ve işlemi uygula',
            ),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_result!),
            ),
          const SizedBox(height: 16),
           Text(
            'Sesli komut: “YouTube aç” veya “YouTube uygulamasında Ara düğmesine bas”. Metin yazma işlemi formu otomatik göndermez.',
            style: TextStyle(color: ChatPalette.muted, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

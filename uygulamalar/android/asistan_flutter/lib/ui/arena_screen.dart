import 'package:flutter/material.dart';

import '../models/asistan_models.dart';
import '../services/asistan_controller.dart';
import 'theme_asistan.dart';

class ArenaScreen extends StatefulWidget {
  const ArenaScreen({
    super.key,
    required this.controller,
    required this.onSwitchTab,
  });

  final AsistanController controller;
  final void Function(int index) onSwitchTab;

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  final TextEditingController _promptCtrl = TextEditingController();
  bool _isDeepResearchTab = false;

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _runCouncilOrResearch() async {
    final q = _promptCtrl.text.trim();
    if (q.isEmpty) return;
    _promptCtrl.clear();
    final mode = _isDeepResearchTab ? WorkMode.research : WorkMode.council;
    await widget.controller.sendMessage(q, overrideMode: mode);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final preset = c.themePreset;

    final councilMessages = c.activeThread.messages
        .where((m) => m.arenaCandidates.isNotEmpty || m.citations.isNotEmpty)
        .toList()
        .reversed
        .toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Artwork Banner Card
          GlassCard3D(
            padding: EdgeInsets.zero,
            borderColor: preset.primary.withValues(alpha: 0.45),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/card_model_arena.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xEB070B19),
                        const Color(0xB8070B19),
                        preset.secondary.withValues(alpha: 0.28),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: preset.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'MULTI-MODEL COUNCIL & DEEP RESEARCH',
                          style: TextStyle(
                            color: preset.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Model Konseyi & Derin Araştırma',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ChatGPT-5, Gemini 2.5 Pro ve Claude 4.5 Sonnet aynı soruyu paralel yanıtlar ve ortak sentez üretir.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Mode Segmented Switch
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  selected: !_isDeepResearchTab,
                  label: const Text('🏛️ 3 Model Konseyi (Arena)'),
                  selectedColor: preset.primary,
                  labelStyle: TextStyle(
                    color: !_isDeepResearchTab ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  onSelected: (_) => setState(() => _isDeepResearchTab = false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ChoiceChip(
                  selected: _isDeepResearchTab,
                  label: const Text('🌐 Derin Web Araştırması'),
                  selectedColor: preset.secondary,
                  labelStyle: TextStyle(
                    color: _isDeepResearchTab ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                  onSelected: (_) => setState(() => _isDeepResearchTab = true),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Input Box
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _promptCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: _isDeepResearchTab
                        ? 'Kaynakçalı derin araştırma konusunu yazın (örn: Kuantum bilgisayarların kriptografiye etkisi)...'
                        : '3 modele aynı anda sorulacak konuyu yazın (örn: Flutter vs Kotlin Multiplatform 2026 mimari karşılaştırması)...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _isDeepResearchTab
                        ? preset.secondary
                        : preset.primary,
                    foregroundColor: _isDeepResearchTab
                        ? Colors.white
                        : Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: c.isGenerating ? null : _runCouncilOrResearch,
                  icon: Icon(
                    _isDeepResearchTab
                        ? Icons.travel_explore_rounded
                        : Icons.hub_rounded,
                  ),
                  label: Text(
                    c.isGenerating
                        ? 'Modeller Çalışıyor...'
                        : (_isDeepResearchTab
                              ? 'Derin Araştırmayı Başlat'
                              : 'Gemini + ChatGPT + Claude Konseyini Başlat'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (councilMessages.isEmpty)
            GlassCard3D(
              enable3DTilt: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Örnek Konsey & Araştırma Başlıkları',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _sampleTopicChip(
                        c,
                        'Yapay Zeka Ajanları 2026',
                        'Otonom yapay zeka ajanlarının yazılım mühendisliğindeki geleceğini karşılaştır.',
                        WorkMode.council,
                      ),
                      _sampleTopicChip(
                        c,
                        'Kuantum Hesaplama',
                        'Kuantum bilgisayarların çalışma prensibi ve güncel gelişmeleri kaynaklarıyla araştır.',
                        WorkMode.research,
                      ),
                      _sampleTopicChip(
                        c,
                        'Mobil Mimari Kıyaslama',
                        'Yüksek performanslı mobil uygulamalarda yerel köprü ve 3D grafik optimizasyonlarını analiz et.',
                        WorkMode.council,
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ...councilMessages.map(
              (m) => _buildCouncilResultCard(c, m, preset),
            ),
        ],
      ),
    );
  }

  Widget _sampleTopicChip(
    AsistanController c,
    String title,
    String prompt,
    WorkMode mode,
  ) {
    return ActionChip(
      label: Text(title, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      onPressed: () => c.sendMessage(prompt, overrideMode: mode),
    );
  }

  Widget _buildCouncilResultCard(
    AsistanController c,
    ChatMessage msg,
    AsistanThemePreset preset,
  ) {
    return GlassCard3D(
      margin: const EdgeInsets.only(bottom: 14),
      borderColor: preset.primary.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: preset.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ortak Akıl Sentezi (${msg.modelUsed})',
                  style: TextStyle(
                    color: preset.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onSwitchTab(0),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                label: const Text('Sohbette Gör'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            msg.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.8,
              height: 1.48,
            ),
          ),
          if (msg.arenaCandidates.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 22),
            const Text(
              'Modellerin Bireysel Görüşleri:',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 8),
            ...msg.arenaCandidates.map((cand) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          cand.modelName,
                          style: TextStyle(
                            color: preset.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${cand.provider}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11.5,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${cand.latencyMs} ms',
                            style: const TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      cand.response,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.8,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

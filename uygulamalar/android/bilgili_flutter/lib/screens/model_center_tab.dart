import 'package:flutter/material.dart';
import '../models/quiz_models.dart';
import '../services/ai_gateway_service.dart';
import '../state/arena_controller.dart';
import '../theme/arena_design.dart';

class ModelCenterTab extends StatefulWidget {
  final ArenaController controller;
  const ModelCenterTab({super.key, required this.controller});

  @override
  State<ModelCenterTab> createState() => _ModelCenterTabState();
}

class _ModelCenterTabState extends State<ModelCenterTab> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _customModelCtrl;

  String _familyFilter = 'Tümü';
  String _searchQuery = '';
  Topic _genTopic = Topic.science;
  Difficulty _genDifficulty = Difficulty.medium;
  int _genCount = 10;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.controller.aiConfig.customBaseUrl);
    _keyCtrl = TextEditingController(text: widget.controller.aiConfig.apiKey);
    _customModelCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _customModelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final cfg = ctrl.aiConfig;
    final accent = ctrl.currentWallpaper.primary;

    final families = [
      'Tümü',
      'Gemini',
      'Claude',
      'OpenAI',
      'DeepSeek',
      'Qwen',
      'Llama & Açık',
      'Diğer Liderler',
    ];

    final models = ctrl.availableModels.where((m) {
      if (_familyFilter != 'Tümü' && m.family != _familyFilter) return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        return m.id.toLowerCase().contains(q) || m.displayName.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        ArenaSceneHeader(title: 'CLIProxy & AI Stüdyosu', description: 'Tüm model aileleri · Model Takımı · İkinci Model Denetimi · Çevrimdışı Paket Üretimi', scene: 'cyber_arena'),
        const SizedBox(height: 14),

        // AI Question Generator Studio Card
        ArenaGlassCard(
          tint: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_fix_high_rounded, color: accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AI Soru Üretim Stüdyosu',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      cfg.useModelTeam ? '${cfg.teamModels.length} Model Takımı' : cfg.primaryModel,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ArenaScrollPills<Topic>(
                items: Topic.poolCategories,
                selected: _genTopic,
                labelBuilder: (t) => t.label,
                onSelected: (t) => setState(() => _genTopic = t),
                accent: accent,
              ),
              const SizedBox(height: 10),
              ArenaScrollPills<Difficulty>(
                items: Difficulty.values,
                selected: _genDifficulty,
                labelBuilder: (d) => d.label,
                onSelected: (d) => setState(() => _genDifficulty = d),
                accent: accent,
              ),
              const SizedBox(height: 8),
              ArenaScrollPills<int>(
                items: const [5, 10, 20, 30],
                selected: _genCount,
                labelBuilder: (n) => '$n Soru',
                onSelected: (n) => setState(() => _genCount = n),
                accent: accent,
              ),
              if (ctrl.aiGenerationStatus.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  ctrl.aiGenerationStatus,
                  style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: ctrl.isGeneratingAiQuestions
                          ? null
                          : () => ctrl.generateAiQuestionsPack(
                                topic: _genTopic,
                                difficulty: _genDifficulty,
                                format: QuestionFormat.mixed,
                                count: _genCount,
                                startImmediately: true,
                              ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: const Color(0xFF06101F),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 17),
                      label: Text(
                        ctrl.isGeneratingAiQuestions ? 'Üretiliyor...' : 'Üret & Oyna',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ctrl.isGeneratingAiQuestions
                          ? null
                          : () => ctrl.generateAiQuestionsPack(
                                topic: _genTopic,
                                difficulty: _genDifficulty,
                                format: QuestionFormat.mixed,
                                count: _genCount,
                                startImmediately: false,
                              ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      ),
                      icon: const Icon(Icons.save_alt_rounded, size: 16),
                      label: const Text(
                        'Havuza Ekle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Gateway Connection Card
        ArenaGlassCard(
          tint: const Color(0xFF8AB4FF),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Sunucu & Bağlantı Yolu',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 10),
              ArenaScrollPills<AiConnectionMode>(
                items: AiConnectionMode.values,
                selected: cfg.mode,
                labelBuilder: (m) => m.label,
                onSelected: (m) => ctrl.updateAiConfig(cfg.copyWith(mode: m)),
                accent: const Color(0xFF8AB4FF),
              ),
              const SizedBox(height: 8),
              Text(
                'Aktif uç nokta: ${cfg.effectiveBaseUrl}',
                style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
              ),
              if (cfg.mode == AiConnectionMode.customServer) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _urlCtrl,
                  onChanged: (v) => ctrl.updateAiConfig(cfg.copyWith(customBaseUrl: v)),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'CLIProxy / OpenAI Uyumlu Sunucu URL',
                    hintText: 'http://127.0.0.1:8317',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              if (cfg.mode != AiConnectionMode.phoneCliProxy) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _keyCtrl,
                  obscureText: true,
                  onChanged: (v) => ctrl.updateAiConfig(cfg.copyWith(apiKey: v)),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: cfg.mode == AiConnectionMode.directGemini
                        ? 'Gemini API Anahtarı'
                        : 'Bearer API Anahtarı (İsteğe bağlı)',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ctrl.isDiscoveringModels
                          ? null
                          : () async {
                              final count = await ctrl.refreshLiveModels();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      count > 0
                                          ? 'Sunucudan $count canlı model keşfedildi!'
                                          : 'Canlı sunucu yanıt vermedi; yerleşik tüm model kataloğu hazır.',
                                    ),
                                  ),
                                );
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      icon: const Icon(Icons.sync_rounded, size: 16),
                      label: Text(
                        ctrl.isDiscoveringModels ? 'Taranıyor...' : 'Yenile',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: ctrl.probeTeamModels,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      icon: const Icon(Icons.network_check_rounded, size: 16),
                      label: const Text(
                        'Takım Testi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 22),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: cfg.useModelTeam,
                activeTrackColor: accent,
                title: const Text(
                  'Model Takımı (Çoklu Model Döngüsü)',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                subtitle: Text(
                  'Soruları 5\'erli gruplar halinde seçili modeller arasında paylaştırır.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                ),
                onChanged: (v) => ctrl.updateAiConfig(cfg.copyWith(useModelTeam: v)),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: cfg.useSecondModelReview,
                activeTrackColor: accent,
                title: const Text(
                  'İkinci Model Denetimi',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                subtitle: Text(
                  'Denetçi model: ${cfg.reviewerModel}',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                ),
                onChanged: (v) => ctrl.updateAiConfig(cfg.copyWith(useSecondModelReview: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Model Catalog Header & Custom Model Adder
        Row(
          children: [
            Expanded(
              child: Text(
                'Tüm Modeller (${models.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Model ara (gemini, claude, gpt, deepseek, qwen, llama...)',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12.5),
            prefixIcon: Icon(Icons.search_rounded, color: accent, size: 19),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ArenaScrollPills<String>(
          items: families,
          selected: _familyFilter,
          labelBuilder: (f) => f,
          onSelected: (f) => setState(() => _familyFilter = f),
          accent: accent,
        ),
        const SizedBox(height: 10),

        for (final m in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildModelTile(ctrl, cfg, m, accent),
          ),
      ],
    );
  }

  Widget _buildModelTile(
    ArenaController ctrl,
    AiGatewayConfig cfg,
    AiModelDescriptor model,
    Color accent,
  ) {
    final isPrimary = cfg.primaryModel == model.id;
    final inTeam = cfg.teamModels.contains(model.id);
    final isReviewer = cfg.reviewerModel == model.id;
    final probe = ctrl.modelHealth[model.id];

    return ArenaGlassCard(
      tint: isPrimary ? accent : Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  model.family,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  model.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              if (probe != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (probe.healthy ? const Color(0xFF5CE09B) : const Color(0xFFFF7B89))
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    probe.healthy ? '${probe.latencyMs} ms' : 'Yanıt Yok',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: probe.healthy ? const Color(0xFF5CE09B) : const Color(0xFFFF7B89),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${model.id} · ${model.badge}',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.62)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _miniRoleChip(
                label: isPrimary ? 'Ana Model ✓' : 'Ana Yap',
                selected: isPrimary,
                accent: accent,
                onTap: () => ctrl.updateAiConfig(cfg.copyWith(primaryModel: model.id)),
              ),
              _miniRoleChip(
                label: inTeam ? 'Takımda ✓' : '+ Takım',
                selected: inTeam,
                accent: const Color(0xFFF6C453),
                onTap: () => ctrl.toggleTeamModel(model.id),
              ),
              _miniRoleChip(
                label: isReviewer ? 'Denetçi ✓' : 'Denetçi Yap',
                selected: isReviewer,
                accent: const Color(0xFFC5A3FF),
                onTap: () => ctrl.updateAiConfig(cfg.copyWith(reviewerModel: model.id)),
              ),
              _miniRoleChip(
                label: 'Ping Test',
                selected: false,
                accent: Colors.white70,
                onTap: () => ctrl.probeModel(model.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniRoleChip({
    required String label,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: selected ? accent.withValues(alpha: 0.24) : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: selected ? accent : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? accent : Colors.white.withValues(alpha: 0.82),
          ),
        ),
      ),
    );
  }
}

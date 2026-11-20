import 'package:flutter/material.dart';

import '../models/asistan_models.dart';
import '../services/asistan_controller.dart';
import 'animations_3d.dart';
import 'theme_asistan.dart';

class LiveVoiceScreen extends StatelessWidget {
  const LiveVoiceScreen({super.key, required this.controller});
  final AsistanController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final listening = c.orbState == OrbActivityState.listening;
    final speaking = c.orbState == OrbActivityState.speaking;
    final busy = c.isGenerating || c.orbState == OrbActivityState.thinking;
    final status = listening
        ? 'Sizi dinliyorum'
        : speaking
        ? 'Yanıt seslendiriliyor'
        : busy
        ? 'Yanıt hazırlanıyor'
        : 'Konuşmaya hazır';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Sesli konuşma',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Konuşun, yanıtı dinleyin. İstediğiniz zaman durdurabilirsiniz.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in LiveBrainMode.values.where(
                (m) => m != LiveBrainMode.siriDevice,
              ))
                ChoiceChip(
                  label: Text(mode.title),
                  selected: c.liveBrainMode == mode,
                  onSelected: busy ? null : (_) => c.setLiveBrainMode(mode),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Model: ${c.voiceModelFor(c.liveBrainMode) ?? "Bağlantı bekleniyor"}',
          ),
          const SizedBox(height: 4),
          const Text(
            'Ses → metin → proxy yanıtı → ses. Bu mod, sağlayıcıların gerçek zamanlı ses API’si değildir.',
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
          TextButton.icon(
            onPressed: c.refreshProxyAndModels,
            icon: const Icon(Icons.refresh),
            label: Text(
              c.proxyOnline
                  ? 'Modelleri yenile'
                  : 'Proxy bağlantısını kontrol et',
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              liveRegion: true,
              child: Text(
                status,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 112,
              height: 112,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const CircleBorder()),
                onPressed: busy
                    ? null
                    : () => listening
                          ? c.stopSpeechAndListening()
                          : c.startVoiceListening(),
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  size: 48,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              listening ? 'Durdurmak için dokunun' : 'Konuşmak için dokunun',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              if (speaking)
                OutlinedButton.icon(
                  onPressed: c.interruptSpeechAndListen,
                  icon: const Icon(Icons.record_voice_over),
                  label: const Text('Sözünü kes'),
                ),
              OutlinedButton.icon(
                onPressed: c.stopSpeechAndListening,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Durdur'),
              ),
            ],
          ),
          if (c.voiceError.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  c.voiceError,
                  style: const TextStyle(color: Color(0xFFFFE0B2)),
                ),
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Eller serbest'),
            subtitle: const Text('Yanıt bittikten sonra yeniden dinle'),
            value: c.handsFreeVoiceLoop,
            onChanged: c.setHandsFreeVoiceLoop,
          ),
          const SizedBox(height: 12),
          if (c.livePartialTranscript.isNotEmpty)
            GlassCard3D(
              enable3DTilt: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Siz',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(c.livePartialTranscript),
                ],
              ),
            ),
          const SizedBox(height: 12),
          GlassCard3D(
            enable3DTilt: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Son yanıt',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Yanıtı tekrar dinle',
                      onPressed: busy
                          ? null
                          : () => c.speakText(c.lastVoiceReply),
                      icon: const Icon(Icons.volume_up_outlined),
                    ),
                  ],
                ),
                SelectableText(c.lastVoiceReply),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Sohbet geçmişi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final message in c.activeThread.messages.reversed.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${message.role == "user" ? "Siz" : "Asistan"}: ${message.text}',
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

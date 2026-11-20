import 'dart:math' as math;
import 'dart:typed_data';

/// Bounded gain for quiet microphone speech; never amplifies digital silence.
class WakeAudioNormalizer {
  double _gain = 1;
  int _quietFrames = 0;
  void process(Float32List samples) {
    if (samples.isEmpty) return;
    final rms = math.sqrt(
      samples.fold<double>(0, (s, x) => s + x * x) / samples.length,
    );
    // Keep gain across short quiet consonants instead of chopping the phrase.
    // Return to unity after sustained silence; zero PCM always stays zero.
    _quietFrames = rms < 0.00008 ? _quietFrames + 1 : 0;
    final desired = rms >= 0.00008
        ? (0.05 / rms).clamp(1.0, 64.0)
        : (_quietFrames > 10 ? 1.0 : _gain);
    _gain = _gain * 0.4 + desired * 0.6;
    for (var i = 0; i < samples.length; i++) {
      samples[i] = (samples[i] * _gain).clamp(-1.0, 1.0);
    }
  }
}

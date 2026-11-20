import 'package:flutter/foundation.dart';

/// Telefonda ağır bir iş (cihazdaki Whisper) sürerken arayüz animasyonlarını
/// duraklatmak için ortak bayrak. realme 10'da animasyonlar + 8 Whisper iş
/// parçacığı çekirdekleri aşırı yükleyip çözümü 2-3 kat yavaşlatıyordu.
class PerfGate {
  PerfGate._();

  static final ValueNotifier<bool> heavyWork = ValueNotifier<bool>(false);

  static Future<T> run<T>(Future<T> Function() work) async {
    heavyWork.value = true;
    try {
      return await work();
    } finally {
      heavyWork.value = false;
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/widgets/device_controls.dart';

void main() {
  test('turkishLower İ ve I harflerini doğru küçültür', () {
    expect(turkishLower('İşCep'), 'işcep');
    expect(turkishLower('ISIK'), 'ısık');
  });

  test('uygulama araması İşCep için "iş" sorgusunu bulur', () {
    expect(appMatchesQuery('İşCep', 'com.isbank.cep', 'iş'), isTrue);
    expect(appMatchesQuery('Instagram', 'com.instagram.android', 'instagram'), isTrue);
    expect(appMatchesQuery('Kamera', 'com.cam', 'xyz'), isFalse);
    expect(appMatchesQuery('Kamera', 'com.cam', ''), isTrue);
  });
}

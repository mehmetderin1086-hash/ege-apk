import 'package:bilgili_flutter/models/quiz_models.dart';
import 'package:flutter_test/flutter_test.dart';

Question withAnswer(String answer, {Topic category = Topic.mathematics}) =>
    Question(
      id: 'input',
      text: 'Yanıtı girin',
      options: [answer],
      answer: 0,
      responseType: ResponseType.fill,
      explanation: 'Örnek bir yazılı yanıt.',
      category: category,
      difficulty: Difficulty.medium,
    );

void main() {
  test(
    'rational input accepts equivalents and distinguishes close probabilities',
    () {
      final rare = withAnswer('1/158224');
      expect(rare.acceptsWritten('2/316448'), isTrue);
      expect(rare.acceptsWritten('1/158225'), isFalse);
      expect(rare.acceptsWritten('1/0'), isFalse);
      expect(withAnswer('−1,25').acceptsWritten('-5/4'), isTrue);
      expect(withAnswer('0,0075').acceptsWritten('7.5e-3'), isTrue);
    },
  );

  test('magnitude and units are preserved in equivalent answers', () {
    expect(withAnswer('‰24,15').acceptsWritten('24.15‰'), isTrue);
    expect(withAnswer('%25').acceptsWritten('25%'), isTrue);
    expect(withAnswer('‰25').acceptsWritten('25%'), isFalse);
    expect(withAnswer('6 MW').acceptsWritten('6 mW'), isFalse);
    expect(withAnswer('6 N·s').acceptsWritten('6'), isTrue);
    expect(withAnswer('12 + x').acceptsWritten('12'), isFalse);
    expect(withAnswer('12 + x').acceptsWritten('12 - x'), isFalse);
  });

  test('case folding keeps Turkish academic terms usable', () {
    expect(
      withAnswer(
        'identify',
        category: Topic.language,
      ).acceptsWritten('IDENTIFY'),
      isTrue,
    );
    expect(withAnswer('IŞIK').acceptsWritten('ışık'), isTrue);
    expect(withAnswer('İvme').acceptsWritten('ivme'), isTrue);
    expect(withAnswer('İvme').acceptsWritten('hız'), isFalse);
    expect(withAnswer('İvme').acceptsWritten(''), isFalse);
  });
}

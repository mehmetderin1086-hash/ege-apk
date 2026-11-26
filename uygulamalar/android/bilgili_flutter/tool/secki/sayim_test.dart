import 'package:bilgili_flutter/data/advanced/catalog.dart';
import 'package:bilgili_flutter/data/advanced/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sayım', () {
    var lise = 0, uygun = 0, uni = 0, gorsel = 0, ailL = 0, ailU = 0;
    for (final f in AdvancedCatalog.families) {
      if (f.level == StudyLevel.universite) { uni += f.count; ailU++; continue; }
      lise += f.count;
      if (f.activityKind == null && f.creation == null && f.multiSelect == null) {
        uygun += f.count; ailL++;
        if (f.visualKind != null) gorsel += f.count;
      }
    }
    // ignore: avoid_print
    print('lise $lise uygun $uygun ($ailL aile, gorselli $gorsel) uni $uni ($ailU aile)');
  });
}

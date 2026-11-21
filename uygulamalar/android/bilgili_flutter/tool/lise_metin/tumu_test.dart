// 200 ailenin tamamını tek seferde denetler; kökler alanlar arasında da tektir.
import 'package:bilgili_flutter/data/advanced/lise_metin.dart';

import 'denetim.dart';

void main() => liseMetinDenetle(
  'lise metin bankası',
  liseMetinFamilies,
  beklenenAile: 200,
  ornekYaz: false,
);

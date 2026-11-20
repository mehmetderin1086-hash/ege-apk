# Ege yerel ses profili

Model: wespeaker_en_voxceleb_resnet34.onnx (Sherpa-ONNX speaker identification release).
Kaynak: https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models
API: https://k2-fsa.github.io/sherpa/onnx/speaker-identification/
Boyut: 26534365 byte.
SHA-256: 5ef208a9da1453335308a6b6f4e6dfbd7e183a38b604de0a57664f45d257fe94

Model APK içinde paketlenir. Kullanıcı üç ayrı kayıtla açıkça kayıt olur. Örneklerin tüm çiftleri ve yeni sesin en az iki örnekle kosinüs benzerliği en az 0.65 olmalıdır. Eşik cihaz/kullanıcı için henüz kalibre edilmemiştir; gerçek pozitif ve negatif ses denemeleri gerekir. Türkçe performans ayrıca doğrulanmalıdır.

Ham kayıtlar yalnızca RAM'de işlenir. Üç vektör Android noBackupFilesDir içinde atomik yazılır; sohbet, Obsidian, indirmeler ve Android yedeklerine eklenmez. Profil silme ayarı vardır. Bozuk etkin profil veya doğrulama hatası kabul sayılmaz.

Bu bir konuşmacı filtresidir; güvenilir kimlik doğrulama, replay/deepfake savunması veya bütün diğer seslerin kesin reddi vaadi değildir. Kısa komutlar, düşük ses ve eşzamanlı konuşmalar reddedilebilir.

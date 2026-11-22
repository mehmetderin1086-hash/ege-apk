// Üretilen dosya: tool/ozgun/uret.py. Elle yazılmış, birbirinden ayrışan özgün
// çoktan seçmeli sorular; her aile bir alt alanın bir zorluk düzeyidir.
import '../common.dart';
import 'oz_science_1_orta.dart';
import 'oz_science_1_kolay.dart';
import 'oz_science_1_zor.dart';
import 'oz_science_2_kolay.dart';
import 'oz_science_2_orta.dart';
import 'oz_science_2_zor.dart';
import 'oz_science_3_kolay.dart';
import 'oz_science_3_orta.dart';
import 'oz_science_3_zor.dart';
import 'oz_science_4_orta.dart';
import 'oz_science_4_kolay.dart';
import 'oz_science_4_zor.dart';
import 'oz_history_1_kolay.dart';
import 'oz_history_1_orta.dart';
import 'oz_history_1_zor.dart';
import 'oz_history_2_orta.dart';
import 'oz_history_2_kolay.dart';
import 'oz_history_2_zor.dart';
import 'oz_history_3_kolay.dart';
import 'oz_history_3_orta.dart';
import 'oz_history_3_zor.dart';
import 'oz_history_4_kolay.dart';
import 'oz_history_4_orta.dart';
import 'oz_history_4_zor.dart';
import 'oz_geography_1_kolay.dart';
import 'oz_geography_1_orta.dart';
import 'oz_geography_1_zor.dart';
import 'oz_geography_2_kolay.dart';
import 'oz_geography_2_orta.dart';
import 'oz_geography_2_zor.dart';
import 'oz_geography_3_kolay.dart';
import 'oz_geography_3_orta.dart';
import 'oz_geography_3_zor.dart';
import 'oz_geography_4_orta.dart';
import 'oz_geography_4_kolay.dart';
import 'oz_geography_4_zor.dart';
import 'oz_art_1_kolay.dart';
import 'oz_art_1_orta.dart';
import 'oz_art_1_zor.dart';
import 'oz_art_2_kolay.dart';
import 'oz_art_2_orta.dart';
import 'oz_art_2_zor.dart';
import 'oz_art_3_kolay.dart';
import 'oz_art_3_orta.dart';
import 'oz_art_3_zor.dart';
import 'oz_art_4_kolay.dart';
import 'oz_art_4_orta.dart';
import 'oz_art_4_zor.dart';
import 'oz_sport_1_kolay.dart';
import 'oz_sport_1_orta.dart';
import 'oz_sport_1_zor.dart';
import 'oz_sport_2_kolay.dart';
import 'oz_sport_2_orta.dart';
import 'oz_sport_2_zor.dart';
import 'oz_sport_3_kolay.dart';
import 'oz_sport_3_orta.dart';
import 'oz_sport_3_zor.dart';
import 'oz_sport_4_orta.dart';
import 'oz_sport_4_kolay.dart';
import 'oz_sport_4_zor.dart';
import 'oz_culture_1_kolay.dart';
import 'oz_culture_1_orta.dart';
import 'oz_culture_1_zor.dart';
import 'oz_culture_2_kolay.dart';
import 'oz_culture_2_orta.dart';
import 'oz_culture_2_zor.dart';
import 'oz_culture_3_kolay.dart';
import 'oz_culture_3_orta.dart';
import 'oz_culture_3_zor.dart';
import 'oz_culture_4_kolay.dart';
import 'oz_culture_4_orta.dart';
import 'oz_culture_4_zor.dart';
import 'oz_cinema_1_kolay.dart';
import 'oz_cinema_1_orta.dart';
import 'oz_cinema_1_zor.dart';
import 'oz_cinema_2_orta.dart';
import 'oz_cinema_2_zor.dart';
import 'oz_cinema_2_kolay.dart';
import 'oz_cinema_3_kolay.dart';
import 'oz_cinema_3_orta.dart';
import 'oz_cinema_3_zor.dart';
import 'oz_cinema_4_kolay.dart';
import 'oz_cinema_4_orta.dart';
import 'oz_cinema_4_zor.dart';
import 'oz_language_1_kolay.dart';
import 'oz_language_1_orta.dart';
import 'oz_language_1_zor.dart';
import 'oz_language_2_kolay.dart';
import 'oz_language_2_orta.dart';
import 'oz_language_2_zor.dart';
import 'oz_language_3_kolay.dart';
import 'oz_language_3_orta.dart';
import 'oz_language_3_zor.dart';
import 'oz_language_4_kolay.dart';
import 'oz_language_4_orta.dart';
import 'oz_language_4_zor.dart';
import 'oz_technology_1_kolay.dart';
import 'oz_technology_1_orta.dart';
import 'oz_technology_1_zor.dart';
import 'oz_technology_2_kolay.dart';
import 'oz_technology_2_orta.dart';
import 'oz_technology_2_zor.dart';
import 'oz_technology_3_orta.dart';
import 'oz_technology_3_kolay.dart';
import 'oz_technology_3_zor.dart';
import 'oz_technology_4_kolay.dart';
import 'oz_technology_4_zor.dart';
import 'oz_technology_4_orta.dart';
import 'oz_literature_1_kolay.dart';
import 'oz_literature_1_orta.dart';
import 'oz_literature_1_zor.dart';
import 'oz_literature_2_kolay.dart';
import 'oz_literature_2_orta.dart';
import 'oz_literature_2_zor.dart';
import 'oz_literature_3_kolay.dart';
import 'oz_literature_3_orta.dart';
import 'oz_literature_3_zor.dart';
import 'oz_literature_4_kolay.dart';
import 'oz_literature_4_orta.dart';
import 'oz_literature_4_zor.dart';
import 'oz_music_1_kolay.dart';
import 'oz_music_1_zor.dart';
import 'oz_music_1_orta.dart';
import 'oz_music_2_kolay.dart';
import 'oz_music_2_orta.dart';
import 'oz_music_2_zor.dart';
import 'oz_music_3_kolay.dart';
import 'oz_music_3_orta.dart';
import 'oz_music_3_zor.dart';
import 'oz_music_4_kolay.dart';
import 'oz_music_4_zor.dart';
import 'oz_music_4_orta.dart';
import 'oz_nature_1_orta.dart';
import 'oz_nature_1_kolay.dart';
import 'oz_nature_1_zor.dart';
import 'oz_nature_2_kolay.dart';
import 'oz_nature_2_orta.dart';
import 'oz_nature_2_zor.dart';
import 'oz_nature_3_kolay.dart';
import 'oz_nature_3_orta.dart';
import 'oz_nature_3_zor.dart';
import 'oz_nature_4_kolay.dart';
import 'oz_nature_4_orta.dart';
import 'oz_nature_4_zor.dart';
import 'oz_exam_1_kolay.dart';
import 'oz_exam_1_orta.dart';
import 'oz_exam_1_zor.dart';
import 'oz_exam_2_kolay.dart';
import 'oz_exam_2_orta.dart';
import 'oz_exam_2_zor.dart';
import 'oz_exam_3_orta.dart';
import 'oz_exam_3_kolay.dart';
import 'oz_exam_3_zor.dart';
import 'oz_mathematics_1_kolay.dart';
import 'oz_mathematics_1_orta.dart';
import 'oz_mathematics_1_zor.dart';
import 'oz_mathematics_2_kolay.dart';
import 'oz_mathematics_2_orta.dart';
import 'oz_mathematics_2_zor.dart';
import 'oz_mathematics_3_kolay.dart';
import 'oz_mathematics_3_orta.dart';
import 'oz_mathematics_3_zor.dart';
import 'oz_mathematics_4_kolay.dart';
import 'oz_mathematics_4_zor.dart';
import 'oz_mathematics_4_orta.dart';
import 'oz_physics_1_kolay.dart';
import 'oz_physics_1_orta.dart';
import 'oz_physics_1_zor.dart';
import 'oz_physics_2_kolay.dart';
import 'oz_physics_2_orta.dart';
import 'oz_physics_2_zor.dart';
import 'oz_physics_3_kolay.dart';
import 'oz_physics_3_orta.dart';
import 'oz_physics_3_zor.dart';
import 'oz_physics_4_kolay.dart';
import 'oz_physics_4_orta.dart';
import 'oz_physics_4_zor.dart';
import 'oz_chemistry_1_orta.dart';
import 'oz_chemistry_1_kolay.dart';
import 'oz_chemistry_1_zor.dart';
import 'oz_chemistry_2_kolay.dart';
import 'oz_chemistry_2_orta.dart';
import 'oz_chemistry_2_zor.dart';
import 'oz_chemistry_3_kolay.dart';
import 'oz_chemistry_3_orta.dart';
import 'oz_chemistry_3_zor.dart';
import 'oz_chemistry_4_kolay.dart';
import 'oz_chemistry_4_orta.dart';
import 'oz_chemistry_4_zor.dart';
import 'oz_biology_1_kolay.dart';
import 'oz_biology_1_orta.dart';
import 'oz_biology_1_zor.dart';
import 'oz_biology_2_kolay.dart';
import 'oz_biology_2_orta.dart';
import 'oz_biology_2_zor.dart';
import 'oz_biology_3_kolay.dart';
import 'oz_biology_3_orta.dart';
import 'oz_biology_3_zor.dart';
import 'oz_biology_4_kolay.dart';
import 'oz_biology_4_zor.dart';
import 'oz_biology_4_orta.dart';
import 'oz_engineering_1_kolay.dart';
import 'oz_engineering_1_orta.dart';
import 'oz_engineering_1_zor.dart';
import 'oz_engineering_2_kolay.dart';
import 'oz_engineering_2_orta.dart';
import 'oz_engineering_2_zor.dart';
import 'oz_engineering_3_orta.dart';
import 'oz_engineering_3_kolay.dart';
import 'oz_engineering_3_zor.dart';
import 'oz_engineering_4_kolay.dart';
import 'oz_engineering_4_orta.dart';
import 'oz_engineering_4_zor.dart';
import 'oz_computing_1_kolay.dart';
import 'oz_computing_1_orta.dart';
import 'oz_computing_1_zor.dart';
import 'oz_computing_2_kolay.dart';
import 'oz_computing_2_orta.dart';
import 'oz_computing_2_zor.dart';
import 'oz_computing_3_kolay.dart';
import 'oz_computing_3_orta.dart';
import 'oz_computing_3_zor.dart';
import 'oz_computing_4_kolay.dart';
import 'oz_computing_4_zor.dart';
import 'oz_computing_4_orta.dart';
import 'oz_statistics_1_kolay.dart';
import 'oz_statistics_1_orta.dart';
import 'oz_statistics_1_zor.dart';
import 'oz_statistics_2_kolay.dart';
import 'oz_statistics_2_orta.dart';
import 'oz_statistics_2_zor.dart';
import 'oz_statistics_3_kolay.dart';
import 'oz_statistics_3_orta.dart';
import 'oz_statistics_3_zor.dart';
import 'oz_statistics_4_kolay.dart';
import 'oz_statistics_4_orta.dart';
import 'oz_statistics_4_zor.dart';
import 'oz_economics_1_kolay.dart';
import 'oz_economics_1_orta.dart';
import 'oz_economics_1_zor.dart';
import 'oz_economics_2_kolay.dart';
import 'oz_economics_2_orta.dart';
import 'oz_economics_2_zor.dart';
import 'oz_economics_3_kolay.dart';
import 'oz_economics_3_orta.dart';
import 'oz_economics_3_zor.dart';
import 'oz_economics_4_kolay.dart';
import 'oz_economics_4_orta.dart';
import 'oz_economics_4_zor.dart';
import 'oz_socialscience_1_kolay.dart';
import 'oz_socialscience_1_orta.dart';
import 'oz_socialscience_1_zor.dart';
import 'oz_socialscience_2_kolay.dart';
import 'oz_socialscience_2_orta.dart';
import 'oz_socialscience_2_zor.dart';
import 'oz_socialscience_3_kolay.dart';
import 'oz_socialscience_3_orta.dart';
import 'oz_socialscience_3_zor.dart';
import 'oz_socialscience_4_kolay.dart';
import 'oz_socialscience_4_orta.dart';
import 'oz_socialscience_4_zor.dart';
import 'oz_research_1_kolay.dart';
import 'oz_research_1_orta.dart';
import 'oz_research_1_zor.dart';
import 'oz_research_2_kolay.dart';
import 'oz_research_2_orta.dart';
import 'oz_research_2_zor.dart';
import 'oz_research_3_kolay.dart';
import 'oz_research_3_orta.dart';
import 'oz_research_3_zor.dart';
import 'oz_research_4_kolay.dart';
import 'oz_research_4_orta.dart';
import 'oz_research_4_zor.dart';

AdvancedFamily _aile(String key, String title, Topic topic, Difficulty d, BloomLevel b, List<(String, String, List<String>, String)> v) =>
    AdvancedFamily(key: key, title: title, topic: topic, level: StudyLevel.lise, count: v.length, difficulty: d, bloom: b,
        lesson: title, sourceLabel: 'Bilgili · Özgün Soru Bankası', build: (i) => AdvancedItem(v[i].$1, v[i].$2, v[i].$3, v[i].$4));

final ozgunAileler = <AdvancedFamily>[
  _aile('oz_science_1_orta', 'Bilim tarihi ve büyük keşifler', Topic.science, Difficulty.medium, BloomLevel.hatirlama, ozScience1Orta),
  _aile('oz_science_1_kolay', 'Bilim tarihi ve büyük keşifler', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience1Kolay),
  _aile('oz_science_1_zor', 'Bilim tarihi ve büyük keşifler', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience1Zor),
  _aile('oz_science_2_kolay', 'Gündelik hayatta bilim', Topic.science, Difficulty.easy, BloomLevel.anlama, ozScience2Kolay),
  _aile('oz_science_2_orta', 'Gündelik hayatta bilim', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience2Orta),
  _aile('oz_science_2_zor', 'Gündelik hayatta bilim', Topic.science, Difficulty.hard, BloomLevel.anlama, ozScience2Zor),
  _aile('oz_science_3_kolay', 'Uzay, Güneş Sistemi ve gözlemsel astronomi', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience3Kolay),
  _aile('oz_science_3_orta', 'Uzay, Güneş Sistemi ve gözlemsel astronomi', Topic.science, Difficulty.medium, BloomLevel.hatirlama, ozScience3Orta),
  _aile('oz_science_3_zor', 'Uzay, Güneş Sistemi ve gözlemsel astronomi', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience3Zor),
  _aile('oz_science_4_orta', 'Yer bilimleri: depremler, volkanlar, kayaçlar, atmosfer olayları', Topic.science, Difficulty.medium, BloomLevel.hatirlama, ozScience4Orta),
  _aile('oz_science_4_kolay', 'Yer bilimleri: depremler, volkanlar, kayaçlar, atmosfer olayları', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience4Kolay),
  _aile('oz_science_4_zor', 'Yer bilimleri: depremler, volkanlar, kayaçlar, atmosfer olayları', Topic.science, Difficulty.hard, BloomLevel.hatirlama, ozScience4Zor),
  _aile('oz_history_1_kolay', 'İlk Çağ ve Orta Çağ uygarlıkları', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory1Kolay),
  _aile('oz_history_1_orta', 'İlk Çağ ve Orta Çağ uygarlıkları', Topic.history, Difficulty.medium, BloomLevel.anlama, ozHistory1Orta),
  _aile('oz_history_1_zor', 'İlk Çağ ve Orta Çağ uygarlıkları', Topic.history, Difficulty.hard, BloomLevel.analiz, ozHistory1Zor),
  _aile('oz_history_2_orta', 'Türk-İslam devletleri ve Selçuklular', Topic.history, Difficulty.medium, BloomLevel.analiz, ozHistory2Orta),
  _aile('oz_history_2_kolay', 'Türk-İslam devletleri ve Selçuklular', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory2Kolay),
  _aile('oz_history_2_zor', 'Türk-İslam devletleri ve Selçuklular', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory2Zor),
  _aile('oz_history_3_kolay', 'Osmanlı Devleti: kuruluştan dağılmaya olaylar, kurumlar, kişiler', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory3Kolay),
  _aile('oz_history_3_orta', 'Osmanlı Devleti: kuruluştan dağılmaya olaylar, kurumlar, kişiler', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory3Orta),
  _aile('oz_history_3_zor', 'Osmanlı Devleti: kuruluştan dağılmaya olaylar, kurumlar, kişiler', Topic.history, Difficulty.hard, BloomLevel.analiz, ozHistory3Zor),
  _aile('oz_history_4_kolay', 'Millî Mücadele, Atatürk dönemi ve Cumhuriyet tarihi; 20. yüzyıl dünya tarihi', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory4Kolay),
  _aile('oz_history_4_orta', 'Millî Mücadele, Atatürk dönemi ve Cumhuriyet tarihi; 20. yüzyıl dünya tarihi', Topic.history, Difficulty.medium, BloomLevel.analiz, ozHistory4Orta),
  _aile('oz_history_4_zor', 'Millî Mücadele, Atatürk dönemi ve Cumhuriyet tarihi; 20. yüzyıl dünya tarihi', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory4Zor),
  _aile('oz_geography_1_kolay', 'Türkiye fiziki coğrafyası', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography1Kolay),
  _aile('oz_geography_1_orta', 'Türkiye fiziki coğrafyası', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography1Orta),
  _aile('oz_geography_1_zor', 'Türkiye fiziki coğrafyası', Topic.geography, Difficulty.hard, BloomLevel.analiz, ozGeography1Zor),
  _aile('oz_geography_2_kolay', 'Türkiye beşeri ve ekonomik coğrafyası', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography2Kolay),
  _aile('oz_geography_2_orta', 'Türkiye beşeri ve ekonomik coğrafyası', Topic.geography, Difficulty.medium, BloomLevel.analiz, ozGeography2Orta),
  _aile('oz_geography_2_zor', 'Türkiye beşeri ve ekonomik coğrafyası', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography2Zor),
  _aile('oz_geography_3_kolay', 'Dünya ülkeleri, başkentler, kıtalar, okyanuslar ve önemli yer şekilleri', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography3Kolay),
  _aile('oz_geography_3_orta', 'Dünya ülkeleri, başkentler, kıtalar, okyanuslar ve önemli yer şekilleri', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography3Orta),
  _aile('oz_geography_3_zor', 'Dünya ülkeleri, başkentler, kıtalar, okyanuslar ve önemli yer şekilleri', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography3Zor),
  _aile('oz_geography_4_orta', 'Doğal sistemler: iklim, biyomlar, harita bilgisi, doğal afetler', Topic.geography, Difficulty.medium, BloomLevel.anlama, ozGeography4Orta),
  _aile('oz_geography_4_kolay', 'Doğal sistemler: iklim, biyomlar, harita bilgisi, doğal afetler', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography4Kolay),
  _aile('oz_geography_4_zor', 'Doğal sistemler: iklim, biyomlar, harita bilgisi, doğal afetler', Topic.geography, Difficulty.hard, BloomLevel.analiz, ozGeography4Zor),
  _aile('oz_art_1_kolay', 'Resim tarihi: akımlar, ressamlar ve eserler', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt1Kolay),
  _aile('oz_art_1_orta', 'Resim tarihi: akımlar, ressamlar ve eserler', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt1Orta),
  _aile('oz_art_1_zor', 'Resim tarihi: akımlar, ressamlar ve eserler', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt1Zor),
  _aile('oz_art_2_kolay', 'Heykel, mimarlık ve dünya mimari eserleri', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt2Kolay),
  _aile('oz_art_2_orta', 'Heykel, mimarlık ve dünya mimari eserleri', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt2Orta),
  _aile('oz_art_2_zor', 'Heykel, mimarlık ve dünya mimari eserleri', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt2Zor),
  _aile('oz_art_3_kolay', 'Türk ve İslam sanatları', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt3Kolay),
  _aile('oz_art_3_orta', 'Türk ve İslam sanatları', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt3Orta),
  _aile('oz_art_3_zor', 'Türk ve İslam sanatları', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt3Zor),
  _aile('oz_art_4_kolay', 'Sanat kavramları, teknikleri, renk ve tasarım ilkeleri; fotoğraf ve tiyatro', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt4Kolay),
  _aile('oz_art_4_orta', 'Sanat kavramları, teknikleri, renk ve tasarım ilkeleri; fotoğraf ve tiyatro', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt4Orta),
  _aile('oz_art_4_zor', 'Sanat kavramları, teknikleri, renk ve tasarım ilkeleri; fotoğraf ve tiyatro', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt4Zor),
  _aile('oz_sport_1_kolay', 'Futbol: kurallar, turnuvalar, tarih', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport1Kolay),
  _aile('oz_sport_1_orta', 'Futbol: kurallar, turnuvalar, tarih', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport1Orta),
  _aile('oz_sport_1_zor', 'Futbol: kurallar, turnuvalar, tarih', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport1Zor),
  _aile('oz_sport_2_kolay', 'Olimpiyatlar ve atletizm; olimpik sporların kuralları', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport2Kolay),
  _aile('oz_sport_2_orta', 'Olimpiyatlar ve atletizm; olimpik sporların kuralları', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport2Orta),
  _aile('oz_sport_2_zor', 'Olimpiyatlar ve atletizm; olimpik sporların kuralları', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport2Zor),
  _aile('oz_sport_3_kolay', 'Basketbol, voleybol, tenis, güreş, yüzme ve diğer branşların kuralları', Topic.sport, Difficulty.easy, BloomLevel.anlama, ozSport3Kolay),
  _aile('oz_sport_3_orta', 'Basketbol, voleybol, tenis, güreş, yüzme ve diğer branşların kuralları', Topic.sport, Difficulty.medium, BloomLevel.anlama, ozSport3Orta),
  _aile('oz_sport_3_zor', 'Basketbol, voleybol, tenis, güreş, yüzme ve diğer branşların kuralları', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport3Zor),
  _aile('oz_sport_4_orta', 'Spor bilimi, sağlıklı yaşam, Türk spor tarihi ve geleneksel sporlar', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport4Orta),
  _aile('oz_sport_4_kolay', 'Spor bilimi, sağlıklı yaşam, Türk spor tarihi ve geleneksel sporlar', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport4Kolay),
  _aile('oz_sport_4_zor', 'Spor bilimi, sağlıklı yaşam, Türk spor tarihi ve geleneksel sporlar', Topic.sport, Difficulty.hard, BloomLevel.analiz, ozSport4Zor),
  _aile('oz_culture_1_kolay', 'Dünya kültürleri, gelenekler, bayramlar ve yemek kültürü', Topic.culture, Difficulty.easy, BloomLevel.uygulama, ozCulture1Kolay),
  _aile('oz_culture_1_orta', 'Dünya kültürleri, gelenekler, bayramlar ve yemek kültürü', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture1Orta),
  _aile('oz_culture_1_zor', 'Dünya kültürleri, gelenekler, bayramlar ve yemek kültürü', Topic.culture, Difficulty.hard, BloomLevel.analiz, ozCulture1Zor),
  _aile('oz_culture_2_kolay', 'Türk kültürü, gelenekler, el sanatları, deyim ve atasözlerinin kökenleri', Topic.culture, Difficulty.easy, BloomLevel.anlama, ozCulture2Kolay),
  _aile('oz_culture_2_orta', 'Türk kültürü, gelenekler, el sanatları, deyim ve atasözlerinin kökenleri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture2Orta),
  _aile('oz_culture_2_zor', 'Türk kültürü, gelenekler, el sanatları, deyim ve atasözlerinin kökenleri', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture2Zor),
  _aile('oz_culture_3_kolay', 'Bilinmesi gereken genel bilgiler: ölçü birimleri, takvim, simgeler, kurumlar', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture3Kolay),
  _aile('oz_culture_3_orta', 'Bilinmesi gereken genel bilgiler: ölçü birimleri, takvim, simgeler, kurumlar', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture3Orta),
  _aile('oz_culture_3_zor', 'Bilinmesi gereken genel bilgiler: ölçü birimleri, takvim, simgeler, kurumlar', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture3Zor),
  _aile('oz_culture_4_kolay', 'Ünlü yapılar, icatların hikâyesi, ilginç tarih ve dünya bilgileri', Topic.culture, Difficulty.easy, BloomLevel.anlama, ozCulture4Kolay),
  _aile('oz_culture_4_orta', 'Ünlü yapılar, icatların hikâyesi, ilginç tarih ve dünya bilgileri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture4Orta),
  _aile('oz_culture_4_zor', 'Ünlü yapılar, icatların hikâyesi, ilginç tarih ve dünya bilgileri', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture4Zor),
  _aile('oz_cinema_1_kolay', 'Dünya sinema tarihi, akımlar ve klasik filmler', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema1Kolay),
  _aile('oz_cinema_1_orta', 'Dünya sinema tarihi, akımlar ve klasik filmler', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema1Orta),
  _aile('oz_cinema_1_zor', 'Dünya sinema tarihi, akımlar ve klasik filmler', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema1Zor),
  _aile('oz_cinema_2_orta', 'Türk sineması ve televizyon tarihi', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema2Orta),
  _aile('oz_cinema_2_zor', 'Türk sineması ve televizyon tarihi', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema2Zor),
  _aile('oz_cinema_2_kolay', 'Türk sineması ve televizyon tarihi', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema2Kolay),
  _aile('oz_cinema_3_kolay', 'Sinema dili ve teknikleri: çekim, kurgu, senaryo, ses, ödüller', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema3Kolay),
  _aile('oz_cinema_3_orta', 'Sinema dili ve teknikleri: çekim, kurgu, senaryo, ses, ödüller', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema3Orta),
  _aile('oz_cinema_3_zor', 'Sinema dili ve teknikleri: çekim, kurgu, senaryo, ses, ödüller', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema3Zor),
  _aile('oz_cinema_4_kolay', 'Animasyon, belgesel ve uyarlamalar', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema4Kolay),
  _aile('oz_cinema_4_orta', 'Animasyon, belgesel ve uyarlamalar', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema4Orta),
  _aile('oz_cinema_4_zor', 'Animasyon, belgesel ve uyarlamalar', Topic.cinema, Difficulty.hard, BloomLevel.analiz, ozCinema4Zor),
  _aile('oz_language_1_kolay', 'İngilizce dil bilgisi', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage1Kolay),
  _aile('oz_language_1_orta', 'İngilizce dil bilgisi', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage1Orta),
  _aile('oz_language_1_zor', 'İngilizce dil bilgisi', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage1Zor),
  _aile('oz_language_2_kolay', 'İngilizce sözcük bilgisi, eş ve zıt anlamlılar, phrasal verbs', Topic.language, Difficulty.easy, BloomLevel.anlama, ozLanguage2Kolay),
  _aile('oz_language_2_orta', 'İngilizce sözcük bilgisi, eş ve zıt anlamlılar, phrasal verbs', Topic.language, Difficulty.medium, BloomLevel.anlama, ozLanguage2Orta),
  _aile('oz_language_2_zor', 'İngilizce sözcük bilgisi, eş ve zıt anlamlılar, phrasal verbs', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage2Zor),
  _aile('oz_language_3_kolay', 'İngilizce okuma: kısa paragraf ve diyalog tamamlama', Topic.language, Difficulty.easy, BloomLevel.anlama, ozLanguage3Kolay),
  _aile('oz_language_3_orta', 'İngilizce okuma: kısa paragraf ve diyalog tamamlama', Topic.language, Difficulty.medium, BloomLevel.analiz, ozLanguage3Orta),
  _aile('oz_language_3_zor', 'İngilizce okuma: kısa paragraf ve diyalog tamamlama', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage3Zor),
  _aile('oz_language_4_kolay', 'Yabancı dillerden Türkçeye geçen sözcükler, dil aileleri ve dünya dilleri', Topic.language, Difficulty.easy, BloomLevel.anlama, ozLanguage4Kolay),
  _aile('oz_language_4_orta', 'Yabancı dillerden Türkçeye geçen sözcükler, dil aileleri ve dünya dilleri', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage4Orta),
  _aile('oz_language_4_zor', 'Yabancı dillerden Türkçeye geçen sözcükler, dil aileleri ve dünya dilleri', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage4Zor),
  _aile('oz_technology_1_kolay', 'Bilgisayar donanımı ve işletim sistemleri', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology1Kolay),
  _aile('oz_technology_1_orta', 'Bilgisayar donanımı ve işletim sistemleri', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology1Orta),
  _aile('oz_technology_1_zor', 'Bilgisayar donanımı ve işletim sistemleri', Topic.technology, Difficulty.hard, BloomLevel.analiz, ozTechnology1Zor),
  _aile('oz_technology_2_kolay', 'İnternet, ağlar ve siber güvenlik', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology2Kolay),
  _aile('oz_technology_2_orta', 'İnternet, ağlar ve siber güvenlik', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology2Orta),
  _aile('oz_technology_2_zor', 'İnternet, ağlar ve siber güvenlik', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology2Zor),
  _aile('oz_technology_3_orta', 'Teknoloji tarihi ve icatlar', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology3Orta),
  _aile('oz_technology_3_kolay', 'Teknoloji tarihi ve icatlar', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology3Kolay),
  _aile('oz_technology_3_zor', 'Teknoloji tarihi ve icatlar', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology3Zor),
  _aile('oz_technology_4_kolay', 'Yapay zekâ, robotik, enerji teknolojileri ve dijital vatandaşlık', Topic.technology, Difficulty.easy, BloomLevel.anlama, ozTechnology4Kolay),
  _aile('oz_technology_4_zor', 'Yapay zekâ, robotik, enerji teknolojileri ve dijital vatandaşlık', Topic.technology, Difficulty.hard, BloomLevel.analiz, ozTechnology4Zor),
  _aile('oz_technology_4_orta', 'Yapay zekâ, robotik, enerji teknolojileri ve dijital vatandaşlık', Topic.technology, Difficulty.medium, BloomLevel.analiz, ozTechnology4Orta),
  _aile('oz_literature_1_kolay', 'Türk edebiyatı: İslamiyet öncesi, Divan ve Halk edebiyatı', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature1Kolay),
  _aile('oz_literature_1_orta', 'Türk edebiyatı: İslamiyet öncesi, Divan ve Halk edebiyatı', Topic.literature, Difficulty.medium, BloomLevel.analiz, ozLiterature1Orta),
  _aile('oz_literature_1_zor', 'Türk edebiyatı: İslamiyet öncesi, Divan ve Halk edebiyatı', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature1Zor),
  _aile('oz_literature_2_kolay', 'Türk edebiyatı: Tanzimat\'tan Cumhuriyet\'e yazarlar ve eserler', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature2Kolay),
  _aile('oz_literature_2_orta', 'Türk edebiyatı: Tanzimat\'tan Cumhuriyet\'e yazarlar ve eserler', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature2Orta),
  _aile('oz_literature_2_zor', 'Türk edebiyatı: Tanzimat\'tan Cumhuriyet\'e yazarlar ve eserler', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature2Zor),
  _aile('oz_literature_3_kolay', 'Dünya edebiyatı: yazarlar, eserler, akımlar', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature3Kolay),
  _aile('oz_literature_3_orta', 'Dünya edebiyatı: yazarlar, eserler, akımlar', Topic.literature, Difficulty.medium, BloomLevel.anlama, ozLiterature3Orta),
  _aile('oz_literature_3_zor', 'Dünya edebiyatı: yazarlar, eserler, akımlar', Topic.literature, Difficulty.hard, BloomLevel.analiz, ozLiterature3Zor),
  _aile('oz_literature_4_kolay', 'Edebî türler, şiir bilgisi, söz sanatları ve anlatım teknikleri', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature4Kolay),
  _aile('oz_literature_4_orta', 'Edebî türler, şiir bilgisi, söz sanatları ve anlatım teknikleri', Topic.literature, Difficulty.medium, BloomLevel.uygulama, ozLiterature4Orta),
  _aile('oz_literature_4_zor', 'Edebî türler, şiir bilgisi, söz sanatları ve anlatım teknikleri', Topic.literature, Difficulty.hard, BloomLevel.analiz, ozLiterature4Zor),
  _aile('oz_music_1_kolay', 'Batı müziği tarihi: besteciler ve dönemler', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic1Kolay),
  _aile('oz_music_1_zor', 'Batı müziği tarihi: besteciler ve dönemler', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic1Zor),
  _aile('oz_music_1_orta', 'Batı müziği tarihi: besteciler ve dönemler', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic1Orta),
  _aile('oz_music_2_kolay', 'Türk müziği: makamlar, çalgılar, besteciler, halk müziği', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic2Kolay),
  _aile('oz_music_2_orta', 'Türk müziği: makamlar, çalgılar, besteciler, halk müziği', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic2Orta),
  _aile('oz_music_2_zor', 'Türk müziği: makamlar, çalgılar, besteciler, halk müziği', Topic.music, Difficulty.hard, BloomLevel.analiz, ozMusic2Zor),
  _aile('oz_music_3_kolay', 'Müzik kuramı: nota, ritim, aralık, akor, form', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic3Kolay),
  _aile('oz_music_3_orta', 'Müzik kuramı: nota, ritim, aralık, akor, form', Topic.music, Difficulty.medium, BloomLevel.uygulama, ozMusic3Orta),
  _aile('oz_music_3_zor', 'Müzik kuramı: nota, ritim, aralık, akor, form', Topic.music, Difficulty.hard, BloomLevel.analiz, ozMusic3Zor),
  _aile('oz_music_4_kolay', 'Çalgılar, orkestra, müzik türleri ve dünya müzikleri', Topic.music, Difficulty.easy, BloomLevel.anlama, ozMusic4Kolay),
  _aile('oz_music_4_zor', 'Çalgılar, orkestra, müzik türleri ve dünya müzikleri', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic4Zor),
  _aile('oz_music_4_orta', 'Çalgılar, orkestra, müzik türleri ve dünya müzikleri', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic4Orta),
  _aile('oz_nature_1_orta', 'Hayvanlar: davranış, yaşam alanı, sınıflandırma', Topic.nature, Difficulty.medium, BloomLevel.anlama, ozNature1Orta),
  _aile('oz_nature_1_kolay', 'Hayvanlar: davranış, yaşam alanı, sınıflandırma', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature1Kolay),
  _aile('oz_nature_1_zor', 'Hayvanlar: davranış, yaşam alanı, sınıflandırma', Topic.nature, Difficulty.hard, BloomLevel.analiz, ozNature1Zor),
  _aile('oz_nature_2_kolay', 'Bitkiler ve ormanlar; Türkiye\'nin endemik türleri', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature2Kolay),
  _aile('oz_nature_2_orta', 'Bitkiler ve ormanlar; Türkiye\'nin endemik türleri', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature2Orta),
  _aile('oz_nature_2_zor', 'Bitkiler ve ormanlar; Türkiye\'nin endemik türleri', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature2Zor),
  _aile('oz_nature_3_kolay', 'Ekoloji, ekosistemler ve çevre sorunları', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature3Kolay),
  _aile('oz_nature_3_orta', 'Ekoloji, ekosistemler ve çevre sorunları', Topic.nature, Difficulty.medium, BloomLevel.analiz, ozNature3Orta),
  _aile('oz_nature_3_zor', 'Ekoloji, ekosistemler ve çevre sorunları', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature3Zor),
  _aile('oz_nature_4_kolay', 'Doğa olayları, okyanuslar, mağaralar ve millî parklar', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature4Kolay),
  _aile('oz_nature_4_orta', 'Doğa olayları, okyanuslar, mağaralar ve millî parklar', Topic.nature, Difficulty.medium, BloomLevel.anlama, ozNature4Orta),
  _aile('oz_nature_4_zor', 'Doğa olayları, okyanuslar, mağaralar ve millî parklar', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature4Zor),
  _aile('oz_exam_1_kolay', 'TYT Türkçe: sözcükte ve cümlede anlam', Topic.exam, Difficulty.easy, BloomLevel.anlama, ozExam1Kolay),
  _aile('oz_exam_1_orta', 'TYT Türkçe: sözcükte ve cümlede anlam', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam1Orta),
  _aile('oz_exam_1_zor', 'TYT Türkçe: sözcükte ve cümlede anlam', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam1Zor),
  _aile('oz_exam_2_kolay', 'TYT Türkçe: kısa paragrafta anlam', Topic.exam, Difficulty.easy, BloomLevel.anlama, ozExam2Kolay),
  _aile('oz_exam_2_orta', 'TYT Türkçe: kısa paragrafta anlam', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam2Orta),
  _aile('oz_exam_2_zor', 'TYT Türkçe: kısa paragrafta anlam', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam2Zor),
  _aile('oz_exam_3_orta', 'Sayısal mantık ve problemler', Topic.exam, Difficulty.medium, BloomLevel.uygulama, ozExam3Orta),
  _aile('oz_exam_3_kolay', 'Sayısal mantık ve problemler', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam3Kolay),
  _aile('oz_exam_3_zor', 'Sayısal mantık ve problemler', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam3Zor),
  _aile('oz_mathematics_1_kolay', 'Sayılar, bölünebilme, EBOB-EKOK, üslü ve köklü sayılar', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics1Kolay),
  _aile('oz_mathematics_1_orta', 'Sayılar, bölünebilme, EBOB-EKOK, üslü ve köklü sayılar', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics1Orta),
  _aile('oz_mathematics_1_zor', 'Sayılar, bölünebilme, EBOB-EKOK, üslü ve köklü sayılar', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics1Zor),
  _aile('oz_mathematics_2_kolay', 'Cebir: denklemler, eşitsizlikler, fonksiyonlar, polinomlar', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics2Kolay),
  _aile('oz_mathematics_2_orta', 'Cebir: denklemler, eşitsizlikler, fonksiyonlar, polinomlar', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics2Orta),
  _aile('oz_mathematics_2_zor', 'Cebir: denklemler, eşitsizlikler, fonksiyonlar, polinomlar', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics2Zor),
  _aile('oz_mathematics_3_kolay', 'Geometri: üçgenler, dörtgenler, çember, katı cisimler', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics3Kolay),
  _aile('oz_mathematics_3_orta', 'Geometri: üçgenler, dörtgenler, çember, katı cisimler', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics3Orta),
  _aile('oz_mathematics_3_zor', 'Geometri: üçgenler, dörtgenler, çember, katı cisimler', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics3Zor),
  _aile('oz_mathematics_4_kolay', 'Olasılık, permütasyon, kombinasyon, diziler, logaritma, türev ve integral', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics4Kolay),
  _aile('oz_mathematics_4_zor', 'Olasılık, permütasyon, kombinasyon, diziler, logaritma, türev ve integral', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics4Zor),
  _aile('oz_mathematics_4_orta', 'Olasılık, permütasyon, kombinasyon, diziler, logaritma, türev ve integral', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics4Orta),
  _aile('oz_physics_1_kolay', 'Mekanik: hareket, kuvvet, Newton yasaları, iş-enerji, momentum', Topic.physics, Difficulty.easy, BloomLevel.uygulama, ozPhysics1Kolay),
  _aile('oz_physics_1_orta', 'Mekanik: hareket, kuvvet, Newton yasaları, iş-enerji, momentum', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics1Orta),
  _aile('oz_physics_1_zor', 'Mekanik: hareket, kuvvet, Newton yasaları, iş-enerji, momentum', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics1Zor),
  _aile('oz_physics_2_kolay', 'Elektrik ve manyetizma', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics2Kolay),
  _aile('oz_physics_2_orta', 'Elektrik ve manyetizma', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics2Orta),
  _aile('oz_physics_2_zor', 'Elektrik ve manyetizma', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics2Zor),
  _aile('oz_physics_3_kolay', 'Dalgalar, ses, optik ve ışık', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics3Kolay),
  _aile('oz_physics_3_orta', 'Dalgalar, ses, optik ve ışık', Topic.physics, Difficulty.medium, BloomLevel.analiz, ozPhysics3Orta),
  _aile('oz_physics_3_zor', 'Dalgalar, ses, optik ve ışık', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics3Zor),
  _aile('oz_physics_4_kolay', 'Isı, madde ve özellikleri, basınç, modern fizik ve astronomi', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics4Kolay),
  _aile('oz_physics_4_orta', 'Isı, madde ve özellikleri, basınç, modern fizik ve astronomi', Topic.physics, Difficulty.medium, BloomLevel.anlama, ozPhysics4Orta),
  _aile('oz_physics_4_zor', 'Isı, madde ve özellikleri, basınç, modern fizik ve astronomi', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics4Zor),
  _aile('oz_chemistry_1_orta', 'Atom, periyodik sistem ve kimyasal bağlar', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry1Orta),
  _aile('oz_chemistry_1_kolay', 'Atom, periyodik sistem ve kimyasal bağlar', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry1Kolay),
  _aile('oz_chemistry_1_zor', 'Atom, periyodik sistem ve kimyasal bağlar', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry1Zor),
  _aile('oz_chemistry_2_kolay', 'Maddenin halleri, karışımlar, çözeltiler', Topic.chemistry, Difficulty.easy, BloomLevel.anlama, ozChemistry2Kolay),
  _aile('oz_chemistry_2_orta', 'Maddenin halleri, karışımlar, çözeltiler', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry2Orta),
  _aile('oz_chemistry_2_zor', 'Maddenin halleri, karışımlar, çözeltiler', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry2Zor),
  _aile('oz_chemistry_3_kolay', 'Kimyasal tepkimeler, mol, asitler-bazlar, denge, hız', Topic.chemistry, Difficulty.easy, BloomLevel.anlama, ozChemistry3Kolay),
  _aile('oz_chemistry_3_orta', 'Kimyasal tepkimeler, mol, asitler-bazlar, denge, hız', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry3Orta),
  _aile('oz_chemistry_3_zor', 'Kimyasal tepkimeler, mol, asitler-bazlar, denge, hız', Topic.chemistry, Difficulty.hard, BloomLevel.uygulama, ozChemistry3Zor),
  _aile('oz_chemistry_4_kolay', 'Organik kimya ve günlük hayatta kimya', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry4Kolay),
  _aile('oz_chemistry_4_orta', 'Organik kimya ve günlük hayatta kimya', Topic.chemistry, Difficulty.medium, BloomLevel.hatirlama, ozChemistry4Orta),
  _aile('oz_chemistry_4_zor', 'Organik kimya ve günlük hayatta kimya', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry4Zor),
  _aile('oz_biology_1_kolay', 'Hücre, canlıların temel bileşenleri ve hücre bölünmeleri', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology1Kolay),
  _aile('oz_biology_1_orta', 'Hücre, canlıların temel bileşenleri ve hücre bölünmeleri', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology1Orta),
  _aile('oz_biology_1_zor', 'Hücre, canlıların temel bileşenleri ve hücre bölünmeleri', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology1Zor),
  _aile('oz_biology_2_kolay', 'Kalıtım, genetik ve evrim', Topic.biology, Difficulty.easy, BloomLevel.anlama, ozBiology2Kolay),
  _aile('oz_biology_2_orta', 'Kalıtım, genetik ve evrim', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology2Orta),
  _aile('oz_biology_2_zor', 'Kalıtım, genetik ve evrim', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology2Zor),
  _aile('oz_biology_3_kolay', 'İnsan fizyolojisi: sistemler', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology3Kolay),
  _aile('oz_biology_3_orta', 'İnsan fizyolojisi: sistemler', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology3Orta),
  _aile('oz_biology_3_zor', 'İnsan fizyolojisi: sistemler', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology3Zor),
  _aile('oz_biology_4_kolay', 'Bitki biyolojisi, ekoloji ve canlıların sınıflandırılması', Topic.biology, Difficulty.easy, BloomLevel.anlama, ozBiology4Kolay),
  _aile('oz_biology_4_zor', 'Bitki biyolojisi, ekoloji ve canlıların sınıflandırılması', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology4Zor),
  _aile('oz_biology_4_orta', 'Bitki biyolojisi, ekoloji ve canlıların sınıflandırılması', Topic.biology, Difficulty.medium, BloomLevel.analiz, ozBiology4Orta),
  _aile('oz_engineering_1_kolay', 'İnşaat ve yapı mühendisliği temel kavramları, ünlü yapılar', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering1Kolay),
  _aile('oz_engineering_1_orta', 'İnşaat ve yapı mühendisliği temel kavramları, ünlü yapılar', Topic.engineering, Difficulty.medium, BloomLevel.hatirlama, ozEngineering1Orta),
  _aile('oz_engineering_1_zor', 'İnşaat ve yapı mühendisliği temel kavramları, ünlü yapılar', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering1Zor),
  _aile('oz_engineering_2_kolay', 'Makine, otomotiv ve havacılık temel kavramları', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering2Kolay),
  _aile('oz_engineering_2_orta', 'Makine, otomotiv ve havacılık temel kavramları', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering2Orta),
  _aile('oz_engineering_2_zor', 'Makine, otomotiv ve havacılık temel kavramları', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering2Zor),
  _aile('oz_engineering_3_orta', 'Elektrik-elektronik mühendisliği temel kavramları ve devre elemanları', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering3Orta),
  _aile('oz_engineering_3_kolay', 'Elektrik-elektronik mühendisliği temel kavramları ve devre elemanları', Topic.engineering, Difficulty.easy, BloomLevel.anlama, ozEngineering3Kolay),
  _aile('oz_engineering_3_zor', 'Elektrik-elektronik mühendisliği temel kavramları ve devre elemanları', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering3Zor),
  _aile('oz_engineering_4_kolay', 'Tasarım süreci, malzeme bilgisi, ölçme ve mühendislik etiği', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering4Kolay),
  _aile('oz_engineering_4_orta', 'Tasarım süreci, malzeme bilgisi, ölçme ve mühendislik etiği', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering4Orta),
  _aile('oz_engineering_4_zor', 'Tasarım süreci, malzeme bilgisi, ölçme ve mühendislik etiği', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering4Zor),
  _aile('oz_computing_1_kolay', 'Algoritma ve akış şeması mantığı', Topic.computing, Difficulty.easy, BloomLevel.uygulama, ozComputing1Kolay),
  _aile('oz_computing_1_orta', 'Algoritma ve akış şeması mantığı', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing1Orta),
  _aile('oz_computing_1_zor', 'Algoritma ve akış şeması mantığı', Topic.computing, Difficulty.hard, BloomLevel.uygulama, ozComputing1Zor),
  _aile('oz_computing_2_kolay', 'Programlama temelleri: değişken, döngü, koşul, fonksiyon', Topic.computing, Difficulty.easy, BloomLevel.uygulama, ozComputing2Kolay),
  _aile('oz_computing_2_orta', 'Programlama temelleri: değişken, döngü, koşul, fonksiyon', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing2Orta),
  _aile('oz_computing_2_zor', 'Programlama temelleri: değişken, döngü, koşul, fonksiyon', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing2Zor),
  _aile('oz_computing_3_kolay', 'Veri yapıları, sayı sistemleri, veri birimleri', Topic.computing, Difficulty.easy, BloomLevel.uygulama, ozComputing3Kolay),
  _aile('oz_computing_3_orta', 'Veri yapıları, sayı sistemleri, veri birimleri', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing3Orta),
  _aile('oz_computing_3_zor', 'Veri yapıları, sayı sistemleri, veri birimleri', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing3Zor),
  _aile('oz_computing_4_kolay', 'Veritabanı, yazılım geliştirme süreçleri ve bilgisayar biliminin tarihi', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing4Kolay),
  _aile('oz_computing_4_zor', 'Veritabanı, yazılım geliştirme süreçleri ve bilgisayar biliminin tarihi', Topic.computing, Difficulty.hard, BloomLevel.hatirlama, ozComputing4Zor),
  _aile('oz_computing_4_orta', 'Veritabanı, yazılım geliştirme süreçleri ve bilgisayar biliminin tarihi', Topic.computing, Difficulty.medium, BloomLevel.hatirlama, ozComputing4Orta),
  _aile('oz_statistics_1_kolay', 'Merkezî eğilim ve yayılım ölçüleri', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics1Kolay),
  _aile('oz_statistics_1_orta', 'Merkezî eğilim ve yayılım ölçüleri', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics1Orta),
  _aile('oz_statistics_1_zor', 'Merkezî eğilim ve yayılım ölçüleri', Topic.statistics, Difficulty.hard, BloomLevel.uygulama, ozStatistics1Zor),
  _aile('oz_statistics_2_kolay', 'Olasılık ve olasılık dağılımlarına giriş', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics2Kolay),
  _aile('oz_statistics_2_orta', 'Olasılık ve olasılık dağılımlarına giriş', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics2Orta),
  _aile('oz_statistics_2_zor', 'Olasılık ve olasılık dağılımlarına giriş', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics2Zor),
  _aile('oz_statistics_3_kolay', 'Veri toplama, örnekleme, anket ve grafik yorumlama', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics3Kolay),
  _aile('oz_statistics_3_orta', 'Veri toplama, örnekleme, anket ve grafik yorumlama', Topic.statistics, Difficulty.medium, BloomLevel.analiz, ozStatistics3Orta),
  _aile('oz_statistics_3_zor', 'Veri toplama, örnekleme, anket ve grafik yorumlama', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics3Zor),
  _aile('oz_statistics_4_kolay', 'Veri bilimi kavramları, korelasyon, istatistiksel yanılgılar', Topic.statistics, Difficulty.easy, BloomLevel.anlama, ozStatistics4Kolay),
  _aile('oz_statistics_4_orta', 'Veri bilimi kavramları, korelasyon, istatistiksel yanılgılar', Topic.statistics, Difficulty.medium, BloomLevel.analiz, ozStatistics4Orta),
  _aile('oz_statistics_4_zor', 'Veri bilimi kavramları, korelasyon, istatistiksel yanılgılar', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics4Zor),
  _aile('oz_economics_1_kolay', 'Temel ekonomi kavramları: arz-talep, piyasa, üretim', Topic.economics, Difficulty.easy, BloomLevel.anlama, ozEconomics1Kolay),
  _aile('oz_economics_1_orta', 'Temel ekonomi kavramları: arz-talep, piyasa, üretim', Topic.economics, Difficulty.medium, BloomLevel.analiz, ozEconomics1Orta),
  _aile('oz_economics_1_zor', 'Temel ekonomi kavramları: arz-talep, piyasa, üretim', Topic.economics, Difficulty.hard, BloomLevel.analiz, ozEconomics1Zor),
  _aile('oz_economics_2_kolay', 'Para, bankacılık, enflasyon, faiz ve kişisel finans', Topic.economics, Difficulty.easy, BloomLevel.anlama, ozEconomics2Kolay),
  _aile('oz_economics_2_orta', 'Para, bankacılık, enflasyon, faiz ve kişisel finans', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics2Orta),
  _aile('oz_economics_2_zor', 'Para, bankacılık, enflasyon, faiz ve kişisel finans', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics2Zor),
  _aile('oz_economics_3_kolay', 'Uluslararası ekonomi, ticaret ve ekonomi tarihi', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics3Kolay),
  _aile('oz_economics_3_orta', 'Uluslararası ekonomi, ticaret ve ekonomi tarihi', Topic.economics, Difficulty.medium, BloomLevel.hatirlama, ozEconomics3Orta),
  _aile('oz_economics_3_zor', 'Uluslararası ekonomi, ticaret ve ekonomi tarihi', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics3Zor),
  _aile('oz_economics_4_kolay', 'Girişimcilik, işletme, muhasebe ve vergi temel kavramları', Topic.economics, Difficulty.easy, BloomLevel.anlama, ozEconomics4Kolay),
  _aile('oz_economics_4_orta', 'Girişimcilik, işletme, muhasebe ve vergi temel kavramları', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics4Orta),
  _aile('oz_economics_4_zor', 'Girişimcilik, işletme, muhasebe ve vergi temel kavramları', Topic.economics, Difficulty.hard, BloomLevel.analiz, ozEconomics4Zor),
  _aile('oz_socialScience_1_kolay', 'Sosyoloji temel kavramları ve toplumsal kurumlar', Topic.socialScience, Difficulty.easy, BloomLevel.anlama, ozSocialscience1Kolay),
  _aile('oz_socialScience_1_orta', 'Sosyoloji temel kavramları ve toplumsal kurumlar', Topic.socialScience, Difficulty.medium, BloomLevel.analiz, ozSocialscience1Orta),
  _aile('oz_socialScience_1_zor', 'Sosyoloji temel kavramları ve toplumsal kurumlar', Topic.socialScience, Difficulty.hard, BloomLevel.degerlendirme, ozSocialscience1Zor),
  _aile('oz_socialScience_2_kolay', 'Psikoloji temel kavramları', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience2Kolay),
  _aile('oz_socialScience_2_orta', 'Psikoloji temel kavramları', Topic.socialScience, Difficulty.medium, BloomLevel.hatirlama, ozSocialscience2Orta),
  _aile('oz_socialScience_2_zor', 'Psikoloji temel kavramları', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience2Zor),
  _aile('oz_socialScience_3_kolay', 'Felsefe ve mantık temel kavramları', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience3Kolay),
  _aile('oz_socialScience_3_orta', 'Felsefe ve mantık temel kavramları', Topic.socialScience, Difficulty.medium, BloomLevel.hatirlama, ozSocialscience3Orta),
  _aile('oz_socialScience_3_zor', 'Felsefe ve mantık temel kavramları', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience3Zor),
  _aile('oz_socialScience_4_kolay', 'Hukuk, vatandaşlık, demokrasi, insan hakları ve Türkiye\'nin anayasal düzeni', Topic.socialScience, Difficulty.easy, BloomLevel.anlama, ozSocialscience4Kolay),
  _aile('oz_socialScience_4_orta', 'Hukuk, vatandaşlık, demokrasi, insan hakları ve Türkiye\'nin anayasal düzeni', Topic.socialScience, Difficulty.medium, BloomLevel.hatirlama, ozSocialscience4Orta),
  _aile('oz_socialScience_4_zor', 'Hukuk, vatandaşlık, demokrasi, insan hakları ve Türkiye\'nin anayasal düzeni', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience4Zor),
  _aile('oz_research_1_kolay', 'Bilimsel yöntem, hipotez, değişkenler ve deney tasarımı', Topic.research, Difficulty.easy, BloomLevel.anlama, ozResearch1Kolay),
  _aile('oz_research_1_orta', 'Bilimsel yöntem, hipotez, değişkenler ve deney tasarımı', Topic.research, Difficulty.medium, BloomLevel.analiz, ozResearch1Orta),
  _aile('oz_research_1_zor', 'Bilimsel yöntem, hipotez, değişkenler ve deney tasarımı', Topic.research, Difficulty.hard, BloomLevel.degerlendirme, ozResearch1Zor),
  _aile('oz_research_2_kolay', 'Kaynak değerlendirme, bilgi okuryazarlığı, alıntı ve intihal', Topic.research, Difficulty.easy, BloomLevel.anlama, ozResearch2Kolay),
  _aile('oz_research_2_orta', 'Kaynak değerlendirme, bilgi okuryazarlığı, alıntı ve intihal', Topic.research, Difficulty.medium, BloomLevel.anlama, ozResearch2Orta),
  _aile('oz_research_2_zor', 'Kaynak değerlendirme, bilgi okuryazarlığı, alıntı ve intihal', Topic.research, Difficulty.hard, BloomLevel.anlama, ozResearch2Zor),
  _aile('oz_research_3_kolay', 'Gözlem, anket, görüşme ve örnekleme yöntemleri', Topic.research, Difficulty.easy, BloomLevel.anlama, ozResearch3Kolay),
  _aile('oz_research_3_orta', 'Gözlem, anket, görüşme ve örnekleme yöntemleri', Topic.research, Difficulty.medium, BloomLevel.degerlendirme, ozResearch3Orta),
  _aile('oz_research_3_zor', 'Gözlem, anket, görüşme ve örnekleme yöntemleri', Topic.research, Difficulty.hard, BloomLevel.anlama, ozResearch3Zor),
  _aile('oz_research_4_kolay', 'Veriyi yorumlama, nedensellik-korelasyon, yanlılık ve geçerlilik', Topic.research, Difficulty.easy, BloomLevel.uygulama, ozResearch4Kolay),
  _aile('oz_research_4_orta', 'Veriyi yorumlama, nedensellik-korelasyon, yanlılık ve geçerlilik', Topic.research, Difficulty.medium, BloomLevel.analiz, ozResearch4Orta),
  _aile('oz_research_4_zor', 'Veriyi yorumlama, nedensellik-korelasyon, yanlılık ve geçerlilik', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch4Zor),
];

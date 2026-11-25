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
import 'oz_art_2_orta.dart';
import 'oz_art_2_kolay.dart';
import 'oz_art_2_zor.dart';
import 'oz_art_3_kolay.dart';
import 'oz_art_3_orta.dart';
import 'oz_art_3_zor.dart';
import 'oz_art_4_orta.dart';
import 'oz_art_4_zor.dart';
import 'oz_art_4_kolay.dart';
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
import 'oz_exam_4_kolay.dart';
import 'oz_exam_4_orta.dart';
import 'oz_exam_4_zor.dart';
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
import 'oz_biology_2_orta.dart';
import 'oz_biology_2_kolay.dart';
import 'oz_biology_2_zor.dart';
import 'oz_biology_3_kolay.dart';
import 'oz_biology_3_orta.dart';
import 'oz_biology_3_zor.dart';
import 'oz_biology_4_kolay.dart';
import 'oz_biology_4_orta.dart';
import 'oz_biology_4_zor.dart';
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
import 'oz_art_5_orta.dart';
import 'oz_art_5_kolay.dart';
import 'oz_art_5_zor.dart';
import 'oz_biology_5_kolay.dart';
import 'oz_biology_5_orta.dart';
import 'oz_biology_5_zor.dart';
import 'oz_chemistry_5_zor.dart';
import 'oz_chemistry_5_orta.dart';
import 'oz_chemistry_5_kolay.dart';
import 'oz_cinema_5_kolay.dart';
import 'oz_cinema_5_orta.dart';
import 'oz_cinema_5_zor.dart';
import 'oz_computing_5_orta.dart';
import 'oz_computing_5_kolay.dart';
import 'oz_computing_5_zor.dart';
import 'oz_culture_5_orta.dart';
import 'oz_culture_5_kolay.dart';
import 'oz_culture_5_zor.dart';
import 'oz_economics_5_kolay.dart';
import 'oz_economics_5_orta.dart';
import 'oz_economics_5_zor.dart';
import 'oz_engineering_5_orta.dart';
import 'oz_engineering_5_zor.dart';
import 'oz_engineering_5_kolay.dart';
import 'oz_exam_5_kolay.dart';
import 'oz_exam_5_orta.dart';
import 'oz_exam_5_zor.dart';
import 'oz_geography_5_kolay.dart';
import 'oz_geography_5_orta.dart';
import 'oz_geography_5_zor.dart';
import 'oz_history_5_zor.dart';
import 'oz_history_5_orta.dart';
import 'oz_history_5_kolay.dart';
import 'oz_language_5_orta.dart';
import 'oz_language_5_zor.dart';
import 'oz_language_5_kolay.dart';
import 'oz_literature_5_kolay.dart';
import 'oz_literature_5_zor.dart';
import 'oz_literature_5_orta.dart';
import 'oz_mathematics_5_kolay.dart';
import 'oz_mathematics_5_orta.dart';
import 'oz_mathematics_5_zor.dart';
import 'oz_music_5_orta.dart';
import 'oz_music_5_zor.dart';
import 'oz_music_5_kolay.dart';
import 'oz_nature_5_zor.dart';
import 'oz_nature_5_orta.dart';
import 'oz_nature_5_kolay.dart';
import 'oz_physics_5_kolay.dart';
import 'oz_physics_5_zor.dart';
import 'oz_physics_5_orta.dart';
import 'oz_research_5_orta.dart';
import 'oz_research_5_kolay.dart';
import 'oz_research_5_zor.dart';
import 'oz_science_5_orta.dart';
import 'oz_science_5_zor.dart';
import 'oz_science_5_kolay.dart';
import 'oz_socialscience_5_orta.dart';
import 'oz_socialscience_5_zor.dart';
import 'oz_socialscience_5_kolay.dart';
import 'oz_sport_5_kolay.dart';
import 'oz_sport_5_orta.dart';
import 'oz_sport_5_zor.dart';
import 'oz_statistics_5_kolay.dart';
import 'oz_statistics_5_orta.dart';
import 'oz_statistics_5_zor.dart';
import 'oz_technology_5_kolay.dart';
import 'oz_technology_5_orta.dart';
import 'oz_technology_5_zor.dart';
import 'oz_science_6_orta.dart';
import 'oz_science_6_kolay.dart';
import 'oz_science_6_zor.dart';
import 'oz_science_7_kolay.dart';
import 'oz_science_7_orta.dart';
import 'oz_science_7_zor.dart';
import 'oz_science_8_orta.dart';
import 'oz_science_8_zor.dart';
import 'oz_science_8_kolay.dart';
import 'oz_science_9_kolay.dart';
import 'oz_science_9_orta.dart';
import 'oz_science_9_zor.dart';
import 'oz_science_10_kolay.dart';
import 'oz_science_10_orta.dart';
import 'oz_science_10_zor.dart';
import 'oz_science_11_orta.dart';
import 'oz_science_11_kolay.dart';
import 'oz_science_11_zor.dart';
import 'oz_science_12_kolay.dart';
import 'oz_science_12_orta.dart';
import 'oz_science_12_zor.dart';
import 'oz_science_13_kolay.dart';
import 'oz_science_13_zor.dart';
import 'oz_science_13_orta.dart';
import 'oz_science_14_kolay.dart';
import 'oz_science_14_orta.dart';
import 'oz_science_14_zor.dart';
import 'oz_history_6_kolay.dart';
import 'oz_history_6_orta.dart';
import 'oz_history_6_zor.dart';
import 'oz_history_7_orta.dart';
import 'oz_history_7_zor.dart';
import 'oz_history_7_kolay.dart';
import 'oz_history_8_kolay.dart';
import 'oz_history_8_orta.dart';
import 'oz_history_8_zor.dart';
import 'oz_history_9_zor.dart';
import 'oz_history_9_orta.dart';
import 'oz_history_9_kolay.dart';
import 'oz_history_10_kolay.dart';
import 'oz_history_10_orta.dart';
import 'oz_history_10_zor.dart';
import 'oz_history_11_orta.dart';
import 'oz_history_11_kolay.dart';
import 'oz_history_11_zor.dart';
import 'oz_history_12_orta.dart';
import 'oz_history_12_kolay.dart';
import 'oz_history_12_zor.dart';
import 'oz_history_13_kolay.dart';
import 'oz_history_13_orta.dart';
import 'oz_history_13_zor.dart';
import 'oz_history_14_kolay.dart';
import 'oz_history_14_orta.dart';
import 'oz_history_14_zor.dart';
import 'oz_geography_6_kolay.dart';
import 'oz_geography_6_orta.dart';
import 'oz_geography_6_zor.dart';
import 'oz_geography_7_orta.dart';
import 'oz_geography_7_kolay.dart';
import 'oz_geography_7_zor.dart';
import 'oz_geography_8_kolay.dart';
import 'oz_geography_8_orta.dart';
import 'oz_geography_8_zor.dart';
import 'oz_geography_9_kolay.dart';
import 'oz_geography_9_orta.dart';
import 'oz_geography_9_zor.dart';
import 'oz_geography_10_orta.dart';
import 'oz_geography_10_zor.dart';
import 'oz_geography_10_kolay.dart';
import 'oz_geography_11_kolay.dart';
import 'oz_geography_11_orta.dart';
import 'oz_geography_11_zor.dart';
import 'oz_geography_12_zor.dart';
import 'oz_geography_12_orta.dart';
import 'oz_geography_12_kolay.dart';
import 'oz_geography_13_kolay.dart';
import 'oz_geography_13_orta.dart';
import 'oz_geography_13_zor.dart';
import 'oz_geography_14_kolay.dart';
import 'oz_geography_14_orta.dart';
import 'oz_geography_14_zor.dart';
import 'oz_art_6_orta.dart';
import 'oz_art_6_zor.dart';
import 'oz_art_6_kolay.dart';
import 'oz_art_7_orta.dart';
import 'oz_art_7_kolay.dart';
import 'oz_art_7_zor.dart';
import 'oz_art_8_zor.dart';
import 'oz_art_8_kolay.dart';
import 'oz_art_8_orta.dart';
import 'oz_art_9_orta.dart';
import 'oz_art_9_zor.dart';
import 'oz_art_9_kolay.dart';
import 'oz_art_10_kolay.dart';
import 'oz_art_10_zor.dart';
import 'oz_art_10_orta.dart';
import 'oz_art_11_kolay.dart';
import 'oz_art_11_orta.dart';
import 'oz_art_11_zor.dart';
import 'oz_art_12_kolay.dart';
import 'oz_art_12_orta.dart';
import 'oz_art_12_zor.dart';
import 'oz_art_13_kolay.dart';
import 'oz_art_13_orta.dart';
import 'oz_art_13_zor.dart';
import 'oz_art_14_kolay.dart';
import 'oz_art_14_orta.dart';
import 'oz_art_14_zor.dart';
import 'oz_sport_6_orta.dart';
import 'oz_sport_6_zor.dart';
import 'oz_sport_6_kolay.dart';
import 'oz_sport_7_kolay.dart';
import 'oz_sport_7_orta.dart';
import 'oz_sport_7_zor.dart';
import 'oz_sport_8_kolay.dart';
import 'oz_sport_8_zor.dart';
import 'oz_sport_8_orta.dart';
import 'oz_sport_9_orta.dart';
import 'oz_sport_9_kolay.dart';
import 'oz_sport_9_zor.dart';
import 'oz_sport_10_kolay.dart';
import 'oz_sport_10_orta.dart';
import 'oz_sport_10_zor.dart';
import 'oz_sport_11_kolay.dart';
import 'oz_sport_11_zor.dart';
import 'oz_sport_11_orta.dart';
import 'oz_sport_12_kolay.dart';
import 'oz_sport_12_orta.dart';
import 'oz_sport_12_zor.dart';
import 'oz_sport_13_kolay.dart';
import 'oz_sport_13_orta.dart';
import 'oz_sport_13_zor.dart';
import 'oz_sport_14_kolay.dart';
import 'oz_sport_14_orta.dart';
import 'oz_sport_14_zor.dart';
import 'oz_culture_6_kolay.dart';
import 'oz_culture_6_orta.dart';
import 'oz_culture_6_zor.dart';
import 'oz_culture_7_kolay.dart';
import 'oz_culture_7_orta.dart';
import 'oz_culture_7_zor.dart';
import 'oz_culture_8_kolay.dart';
import 'oz_culture_8_orta.dart';
import 'oz_culture_8_zor.dart';
import 'oz_culture_9_kolay.dart';
import 'oz_culture_9_orta.dart';
import 'oz_culture_9_zor.dart';
import 'oz_culture_10_orta.dart';
import 'oz_culture_10_zor.dart';
import 'oz_culture_10_kolay.dart';
import 'oz_culture_11_kolay.dart';
import 'oz_culture_11_orta.dart';
import 'oz_culture_11_zor.dart';
import 'oz_culture_12_orta.dart';
import 'oz_culture_12_kolay.dart';
import 'oz_culture_12_zor.dart';
import 'oz_culture_13_orta.dart';
import 'oz_culture_13_kolay.dart';
import 'oz_culture_13_zor.dart';
import 'oz_culture_14_kolay.dart';
import 'oz_culture_14_orta.dart';
import 'oz_culture_14_zor.dart';
import 'oz_cinema_6_orta.dart';
import 'oz_cinema_6_zor.dart';
import 'oz_cinema_6_kolay.dart';
import 'oz_cinema_7_kolay.dart';
import 'oz_cinema_7_orta.dart';
import 'oz_cinema_7_zor.dart';
import 'oz_cinema_8_kolay.dart';
import 'oz_cinema_8_orta.dart';
import 'oz_cinema_8_zor.dart';
import 'oz_cinema_9_orta.dart';
import 'oz_cinema_9_kolay.dart';
import 'oz_cinema_9_zor.dart';
import 'oz_cinema_10_zor.dart';
import 'oz_cinema_10_orta.dart';
import 'oz_cinema_10_kolay.dart';
import 'oz_cinema_11_kolay.dart';
import 'oz_cinema_11_zor.dart';
import 'oz_cinema_11_orta.dart';
import 'oz_cinema_12_orta.dart';
import 'oz_cinema_12_kolay.dart';
import 'oz_cinema_12_zor.dart';
import 'oz_cinema_13_orta.dart';
import 'oz_cinema_13_zor.dart';
import 'oz_cinema_13_kolay.dart';
import 'oz_cinema_14_kolay.dart';
import 'oz_cinema_14_orta.dart';
import 'oz_cinema_14_zor.dart';
import 'oz_language_6_kolay.dart';
import 'oz_language_6_orta.dart';
import 'oz_language_6_zor.dart';
import 'oz_language_7_kolay.dart';
import 'oz_language_7_orta.dart';
import 'oz_language_7_zor.dart';
import 'oz_language_8_kolay.dart';
import 'oz_language_8_orta.dart';
import 'oz_language_8_zor.dart';
import 'oz_language_9_kolay.dart';
import 'oz_language_9_orta.dart';
import 'oz_language_9_zor.dart';
import 'oz_language_10_orta.dart';
import 'oz_language_10_kolay.dart';
import 'oz_language_10_zor.dart';
import 'oz_language_11_kolay.dart';
import 'oz_language_11_orta.dart';
import 'oz_language_11_zor.dart';
import 'oz_language_12_kolay.dart';
import 'oz_language_12_orta.dart';
import 'oz_language_12_zor.dart';
import 'oz_language_13_kolay.dart';
import 'oz_language_13_orta.dart';
import 'oz_language_13_zor.dart';
import 'oz_language_14_kolay.dart';
import 'oz_language_14_orta.dart';
import 'oz_language_14_zor.dart';
import 'oz_technology_6_orta.dart';
import 'oz_technology_6_kolay.dart';
import 'oz_technology_6_zor.dart';
import 'oz_technology_7_kolay.dart';
import 'oz_technology_7_orta.dart';
import 'oz_technology_7_zor.dart';
import 'oz_technology_8_kolay.dart';
import 'oz_technology_8_orta.dart';
import 'oz_technology_8_zor.dart';
import 'oz_technology_9_kolay.dart';
import 'oz_technology_9_orta.dart';
import 'oz_technology_9_zor.dart';
import 'oz_technology_10_kolay.dart';
import 'oz_technology_10_orta.dart';
import 'oz_technology_10_zor.dart';
import 'oz_technology_11_orta.dart';
import 'oz_technology_11_kolay.dart';
import 'oz_technology_11_zor.dart';
import 'oz_technology_12_kolay.dart';
import 'oz_technology_12_orta.dart';
import 'oz_technology_12_zor.dart';
import 'oz_technology_13_orta.dart';
import 'oz_technology_13_zor.dart';
import 'oz_technology_13_kolay.dart';
import 'oz_technology_14_kolay.dart';
import 'oz_technology_14_orta.dart';
import 'oz_technology_14_zor.dart';
import 'oz_literature_6_kolay.dart';
import 'oz_literature_6_orta.dart';
import 'oz_literature_6_zor.dart';
import 'oz_literature_7_orta.dart';
import 'oz_literature_7_zor.dart';
import 'oz_literature_7_kolay.dart';
import 'oz_literature_8_orta.dart';
import 'oz_literature_8_zor.dart';
import 'oz_literature_8_kolay.dart';
import 'oz_literature_9_orta.dart';
import 'oz_literature_9_zor.dart';
import 'oz_literature_9_kolay.dart';
import 'oz_literature_10_orta.dart';
import 'oz_literature_10_zor.dart';
import 'oz_literature_10_kolay.dart';
import 'oz_literature_11_kolay.dart';
import 'oz_literature_11_orta.dart';
import 'oz_literature_11_zor.dart';
import 'oz_literature_12_kolay.dart';
import 'oz_literature_12_orta.dart';
import 'oz_literature_12_zor.dart';
import 'oz_literature_13_kolay.dart';
import 'oz_literature_13_orta.dart';
import 'oz_literature_13_zor.dart';
import 'oz_literature_14_kolay.dart';
import 'oz_literature_14_orta.dart';
import 'oz_literature_14_zor.dart';
import 'oz_music_6_orta.dart';
import 'oz_music_6_zor.dart';
import 'oz_music_6_kolay.dart';
import 'oz_music_7_kolay.dart';
import 'oz_music_7_orta.dart';
import 'oz_music_7_zor.dart';
import 'oz_music_8_orta.dart';
import 'oz_music_8_kolay.dart';
import 'oz_music_8_zor.dart';
import 'oz_music_9_orta.dart';
import 'oz_music_9_kolay.dart';
import 'oz_music_9_zor.dart';
import 'oz_music_10_orta.dart';
import 'oz_music_10_kolay.dart';
import 'oz_music_10_zor.dart';
import 'oz_music_11_kolay.dart';
import 'oz_music_11_zor.dart';
import 'oz_music_11_orta.dart';
import 'oz_music_12_kolay.dart';
import 'oz_music_12_orta.dart';
import 'oz_music_12_zor.dart';
import 'oz_music_13_kolay.dart';
import 'oz_music_13_zor.dart';
import 'oz_music_13_orta.dart';
import 'oz_music_14_kolay.dart';
import 'oz_music_14_orta.dart';
import 'oz_music_14_zor.dart';
import 'oz_nature_6_kolay.dart';
import 'oz_nature_6_orta.dart';
import 'oz_nature_6_zor.dart';
import 'oz_nature_7_kolay.dart';
import 'oz_nature_7_orta.dart';
import 'oz_nature_7_zor.dart';
import 'oz_nature_8_kolay.dart';
import 'oz_nature_8_orta.dart';
import 'oz_nature_8_zor.dart';
import 'oz_nature_9_orta.dart';
import 'oz_nature_9_zor.dart';
import 'oz_nature_9_kolay.dart';
import 'oz_nature_10_kolay.dart';
import 'oz_nature_10_orta.dart';
import 'oz_nature_10_zor.dart';
import 'oz_nature_11_kolay.dart';
import 'oz_nature_11_orta.dart';
import 'oz_nature_11_zor.dart';
import 'oz_nature_12_orta.dart';
import 'oz_nature_12_kolay.dart';
import 'oz_nature_12_zor.dart';
import 'oz_nature_13_kolay.dart';
import 'oz_nature_13_zor.dart';
import 'oz_nature_13_orta.dart';
import 'oz_nature_14_zor.dart';
import 'oz_nature_14_kolay.dart';
import 'oz_nature_14_orta.dart';
import 'oz_exam_6_kolay.dart';
import 'oz_exam_6_orta.dart';
import 'oz_exam_6_zor.dart';
import 'oz_exam_7_orta.dart';
import 'oz_exam_7_kolay.dart';
import 'oz_exam_7_zor.dart';
import 'oz_exam_8_kolay.dart';
import 'oz_exam_8_orta.dart';
import 'oz_exam_8_zor.dart';
import 'oz_exam_9_zor.dart';
import 'oz_exam_9_orta.dart';
import 'oz_exam_9_kolay.dart';
import 'oz_exam_10_kolay.dart';
import 'oz_exam_10_orta.dart';
import 'oz_exam_10_zor.dart';
import 'oz_exam_11_orta.dart';
import 'oz_exam_11_kolay.dart';
import 'oz_exam_11_zor.dart';
import 'oz_exam_12_kolay.dart';
import 'oz_exam_12_orta.dart';
import 'oz_exam_12_zor.dart';
import 'oz_exam_13_kolay.dart';
import 'oz_exam_13_orta.dart';
import 'oz_exam_13_zor.dart';
import 'oz_exam_14_kolay.dart';
import 'oz_exam_14_orta.dart';
import 'oz_exam_14_zor.dart';
import 'oz_mathematics_6_kolay.dart';
import 'oz_mathematics_6_orta.dart';
import 'oz_mathematics_6_zor.dart';
import 'oz_mathematics_7_kolay.dart';
import 'oz_mathematics_7_orta.dart';
import 'oz_mathematics_7_zor.dart';
import 'oz_mathematics_8_kolay.dart';
import 'oz_mathematics_8_orta.dart';
import 'oz_mathematics_8_zor.dart';
import 'oz_mathematics_9_kolay.dart';
import 'oz_mathematics_9_orta.dart';
import 'oz_mathematics_9_zor.dart';
import 'oz_mathematics_10_kolay.dart';
import 'oz_mathematics_10_orta.dart';
import 'oz_mathematics_10_zor.dart';
import 'oz_mathematics_11_kolay.dart';
import 'oz_mathematics_11_orta.dart';
import 'oz_mathematics_11_zor.dart';
import 'oz_mathematics_12_kolay.dart';
import 'oz_mathematics_12_orta.dart';
import 'oz_mathematics_12_zor.dart';
import 'oz_mathematics_13_kolay.dart';
import 'oz_mathematics_13_orta.dart';
import 'oz_mathematics_13_zor.dart';
import 'oz_mathematics_14_kolay.dart';
import 'oz_mathematics_14_orta.dart';
import 'oz_mathematics_14_zor.dart';
import 'oz_physics_6_kolay.dart';
import 'oz_physics_6_orta.dart';
import 'oz_physics_6_zor.dart';
import 'oz_physics_7_kolay.dart';
import 'oz_physics_7_orta.dart';
import 'oz_physics_7_zor.dart';
import 'oz_physics_8_kolay.dart';
import 'oz_physics_8_orta.dart';
import 'oz_physics_8_zor.dart';
import 'oz_physics_9_kolay.dart';
import 'oz_physics_9_orta.dart';
import 'oz_physics_9_zor.dart';
import 'oz_physics_10_orta.dart';
import 'oz_physics_10_zor.dart';
import 'oz_physics_10_kolay.dart';
import 'oz_physics_11_kolay.dart';
import 'oz_physics_11_orta.dart';
import 'oz_physics_11_zor.dart';
import 'oz_physics_12_kolay.dart';
import 'oz_physics_12_orta.dart';
import 'oz_physics_12_zor.dart';
import 'oz_physics_13_kolay.dart';
import 'oz_physics_13_orta.dart';
import 'oz_physics_13_zor.dart';
import 'oz_physics_14_orta.dart';
import 'oz_physics_14_zor.dart';
import 'oz_physics_14_kolay.dart';
import 'oz_chemistry_6_kolay.dart';
import 'oz_chemistry_6_orta.dart';
import 'oz_chemistry_6_zor.dart';
import 'oz_chemistry_7_kolay.dart';
import 'oz_chemistry_7_orta.dart';
import 'oz_chemistry_7_zor.dart';
import 'oz_chemistry_8_kolay.dart';
import 'oz_chemistry_8_orta.dart';
import 'oz_chemistry_8_zor.dart';
import 'oz_chemistry_9_orta.dart';
import 'oz_chemistry_9_zor.dart';
import 'oz_chemistry_9_kolay.dart';
import 'oz_chemistry_10_kolay.dart';
import 'oz_chemistry_10_orta.dart';
import 'oz_chemistry_10_zor.dart';
import 'oz_chemistry_11_kolay.dart';
import 'oz_chemistry_11_orta.dart';
import 'oz_chemistry_11_zor.dart';
import 'oz_chemistry_12_kolay.dart';
import 'oz_chemistry_12_orta.dart';
import 'oz_chemistry_12_zor.dart';
import 'oz_chemistry_13_kolay.dart';
import 'oz_chemistry_13_orta.dart';
import 'oz_chemistry_13_zor.dart';
import 'oz_chemistry_14_kolay.dart';
import 'oz_chemistry_14_zor.dart';
import 'oz_chemistry_14_orta.dart';
import 'oz_biology_6_kolay.dart';
import 'oz_biology_6_orta.dart';
import 'oz_biology_6_zor.dart';
import 'oz_biology_7_kolay.dart';
import 'oz_biology_7_orta.dart';
import 'oz_biology_7_zor.dart';
import 'oz_biology_8_zor.dart';
import 'oz_biology_8_kolay.dart';
import 'oz_biology_8_orta.dart';
import 'oz_biology_9_orta.dart';
import 'oz_biology_9_kolay.dart';
import 'oz_biology_9_zor.dart';
import 'oz_biology_10_kolay.dart';
import 'oz_biology_10_orta.dart';
import 'oz_biology_10_zor.dart';
import 'oz_biology_11_kolay.dart';
import 'oz_biology_11_orta.dart';
import 'oz_biology_11_zor.dart';
import 'oz_biology_12_kolay.dart';
import 'oz_biology_12_orta.dart';
import 'oz_biology_12_zor.dart';
import 'oz_biology_13_kolay.dart';
import 'oz_biology_13_orta.dart';
import 'oz_biology_13_zor.dart';
import 'oz_biology_14_kolay.dart';
import 'oz_biology_14_orta.dart';
import 'oz_biology_14_zor.dart';
import 'oz_engineering_6_kolay.dart';
import 'oz_engineering_6_orta.dart';
import 'oz_engineering_6_zor.dart';
import 'oz_engineering_7_kolay.dart';
import 'oz_engineering_7_orta.dart';
import 'oz_engineering_7_zor.dart';
import 'oz_engineering_8_kolay.dart';
import 'oz_engineering_8_orta.dart';
import 'oz_engineering_8_zor.dart';
import 'oz_engineering_9_orta.dart';
import 'oz_engineering_9_kolay.dart';
import 'oz_engineering_9_zor.dart';
import 'oz_engineering_10_kolay.dart';
import 'oz_engineering_10_orta.dart';
import 'oz_engineering_10_zor.dart';
import 'oz_engineering_11_kolay.dart';
import 'oz_engineering_11_orta.dart';
import 'oz_engineering_11_zor.dart';
import 'oz_engineering_12_kolay.dart';
import 'oz_engineering_12_orta.dart';
import 'oz_engineering_12_zor.dart';
import 'oz_engineering_13_kolay.dart';
import 'oz_engineering_13_orta.dart';
import 'oz_engineering_13_zor.dart';
import 'oz_engineering_14_kolay.dart';
import 'oz_engineering_14_orta.dart';
import 'oz_engineering_14_zor.dart';
import 'oz_computing_6_orta.dart';
import 'oz_computing_6_kolay.dart';
import 'oz_computing_6_zor.dart';
import 'oz_computing_7_orta.dart';
import 'oz_computing_7_kolay.dart';
import 'oz_computing_7_zor.dart';
import 'oz_computing_8_kolay.dart';
import 'oz_computing_8_orta.dart';
import 'oz_computing_8_zor.dart';
import 'oz_computing_9_orta.dart';
import 'oz_computing_9_kolay.dart';
import 'oz_computing_9_zor.dart';
import 'oz_computing_10_kolay.dart';
import 'oz_computing_10_orta.dart';
import 'oz_computing_10_zor.dart';
import 'oz_computing_11_kolay.dart';
import 'oz_computing_11_orta.dart';
import 'oz_computing_11_zor.dart';
import 'oz_computing_12_kolay.dart';
import 'oz_computing_12_orta.dart';
import 'oz_computing_12_zor.dart';
import 'oz_computing_13_kolay.dart';
import 'oz_computing_13_orta.dart';
import 'oz_computing_13_zor.dart';
import 'oz_computing_14_kolay.dart';
import 'oz_computing_14_orta.dart';
import 'oz_computing_14_zor.dart';
import 'oz_statistics_6_orta.dart';
import 'oz_statistics_6_zor.dart';
import 'oz_statistics_6_kolay.dart';
import 'oz_statistics_7_orta.dart';
import 'oz_statistics_7_kolay.dart';
import 'oz_statistics_7_zor.dart';
import 'oz_statistics_8_zor.dart';
import 'oz_statistics_8_kolay.dart';
import 'oz_statistics_8_orta.dart';
import 'oz_statistics_9_kolay.dart';
import 'oz_statistics_9_orta.dart';
import 'oz_statistics_9_zor.dart';
import 'oz_statistics_10_kolay.dart';
import 'oz_statistics_10_orta.dart';
import 'oz_statistics_10_zor.dart';
import 'oz_statistics_11_orta.dart';
import 'oz_statistics_11_kolay.dart';
import 'oz_statistics_11_zor.dart';
import 'oz_statistics_12_kolay.dart';
import 'oz_statistics_12_orta.dart';
import 'oz_statistics_12_zor.dart';
import 'oz_statistics_13_kolay.dart';
import 'oz_statistics_13_orta.dart';
import 'oz_statistics_13_zor.dart';
import 'oz_statistics_14_kolay.dart';
import 'oz_statistics_14_orta.dart';
import 'oz_statistics_14_zor.dart';
import 'oz_economics_6_kolay.dart';
import 'oz_economics_6_orta.dart';
import 'oz_economics_6_zor.dart';
import 'oz_economics_7_kolay.dart';
import 'oz_economics_7_orta.dart';
import 'oz_economics_7_zor.dart';
import 'oz_economics_8_kolay.dart';
import 'oz_economics_8_orta.dart';
import 'oz_economics_8_zor.dart';
import 'oz_economics_9_kolay.dart';
import 'oz_economics_9_orta.dart';
import 'oz_economics_9_zor.dart';
import 'oz_economics_10_orta.dart';
import 'oz_economics_10_zor.dart';
import 'oz_economics_10_kolay.dart';
import 'oz_economics_11_kolay.dart';
import 'oz_economics_11_orta.dart';
import 'oz_economics_11_zor.dart';
import 'oz_economics_12_kolay.dart';
import 'oz_economics_12_zor.dart';
import 'oz_economics_12_orta.dart';
import 'oz_economics_13_kolay.dart';
import 'oz_economics_13_orta.dart';
import 'oz_economics_13_zor.dart';
import 'oz_economics_14_orta.dart';
import 'oz_economics_14_kolay.dart';
import 'oz_economics_14_zor.dart';
import 'oz_socialscience_6_orta.dart';
import 'oz_socialscience_6_zor.dart';
import 'oz_socialscience_6_kolay.dart';
import 'oz_socialscience_7_kolay.dart';
import 'oz_socialscience_7_orta.dart';
import 'oz_socialscience_7_zor.dart';
import 'oz_socialscience_8_kolay.dart';
import 'oz_socialscience_8_orta.dart';
import 'oz_socialscience_8_zor.dart';
import 'oz_socialscience_9_orta.dart';
import 'oz_socialscience_9_zor.dart';
import 'oz_socialscience_9_kolay.dart';
import 'oz_socialscience_10_kolay.dart';
import 'oz_socialscience_10_zor.dart';
import 'oz_socialscience_10_orta.dart';
import 'oz_socialscience_11_kolay.dart';
import 'oz_socialscience_11_orta.dart';
import 'oz_socialscience_11_zor.dart';
import 'oz_socialscience_12_kolay.dart';
import 'oz_socialscience_12_orta.dart';
import 'oz_socialscience_12_zor.dart';
import 'oz_socialscience_13_kolay.dart';
import 'oz_socialscience_13_orta.dart';
import 'oz_socialscience_13_zor.dart';
import 'oz_socialscience_14_kolay.dart';
import 'oz_socialscience_14_orta.dart';
import 'oz_socialscience_14_zor.dart';
import 'oz_research_6_kolay.dart';
import 'oz_research_6_orta.dart';
import 'oz_research_6_zor.dart';
import 'oz_research_7_kolay.dart';
import 'oz_research_7_orta.dart';
import 'oz_research_7_zor.dart';
import 'oz_research_8_kolay.dart';
import 'oz_research_8_zor.dart';
import 'oz_research_8_orta.dart';
import 'oz_research_9_orta.dart';
import 'oz_research_9_kolay.dart';
import 'oz_research_9_zor.dart';
import 'oz_research_10_orta.dart';
import 'oz_research_10_kolay.dart';
import 'oz_research_10_zor.dart';
import 'oz_research_11_orta.dart';
import 'oz_research_11_kolay.dart';
import 'oz_research_11_zor.dart';
import 'oz_research_12_kolay.dart';
import 'oz_research_12_orta.dart';
import 'oz_research_12_zor.dart';
import 'oz_research_13_orta.dart';
import 'oz_research_13_kolay.dart';
import 'oz_research_13_zor.dart';
import 'oz_research_14_kolay.dart';
import 'oz_research_14_orta.dart';
import 'oz_research_14_zor.dart';
import 'oz_science_15_kolay.dart';
import 'oz_science_15_orta.dart';
import 'oz_science_15_zor.dart';
import 'oz_science_16_kolay.dart';
import 'oz_science_16_orta.dart';
import 'oz_science_16_zor.dart';
import 'oz_science_17_kolay.dart';
import 'oz_science_17_orta.dart';
import 'oz_science_17_zor.dart';
import 'oz_science_18_kolay.dart';
import 'oz_science_18_orta.dart';
import 'oz_science_18_zor.dart';
import 'oz_science_19_kolay.dart';
import 'oz_science_19_orta.dart';
import 'oz_science_19_zor.dart';
import 'oz_history_15_kolay.dart';
import 'oz_history_15_orta.dart';
import 'oz_history_15_zor.dart';
import 'oz_history_16_kolay.dart';
import 'oz_history_16_orta.dart';
import 'oz_history_16_zor.dart';
import 'oz_history_17_kolay.dart';
import 'oz_history_17_orta.dart';
import 'oz_history_17_zor.dart';
import 'oz_history_18_kolay.dart';
import 'oz_history_18_orta.dart';
import 'oz_history_18_zor.dart';
import 'oz_history_19_kolay.dart';
import 'oz_history_19_orta.dart';
import 'oz_history_19_zor.dart';
import 'oz_geography_15_kolay.dart';
import 'oz_geography_15_orta.dart';
import 'oz_geography_15_zor.dart';
import 'oz_geography_16_kolay.dart';
import 'oz_geography_16_orta.dart';
import 'oz_geography_16_zor.dart';
import 'oz_geography_17_kolay.dart';
import 'oz_geography_17_orta.dart';
import 'oz_geography_17_zor.dart';
import 'oz_geography_18_kolay.dart';
import 'oz_geography_18_orta.dart';
import 'oz_geography_18_zor.dart';
import 'oz_geography_19_kolay.dart';
import 'oz_geography_19_orta.dart';
import 'oz_geography_19_zor.dart';
import 'oz_art_15_kolay.dart';
import 'oz_art_15_orta.dart';
import 'oz_art_15_zor.dart';
import 'oz_art_16_kolay.dart';
import 'oz_art_16_orta.dart';
import 'oz_art_16_zor.dart';
import 'oz_art_17_kolay.dart';
import 'oz_art_17_orta.dart';
import 'oz_art_17_zor.dart';
import 'oz_art_18_kolay.dart';
import 'oz_art_18_orta.dart';
import 'oz_art_18_zor.dart';
import 'oz_art_19_kolay.dart';
import 'oz_art_19_orta.dart';
import 'oz_art_19_zor.dart';
import 'oz_sport_15_kolay.dart';
import 'oz_sport_15_orta.dart';
import 'oz_sport_15_zor.dart';
import 'oz_sport_16_kolay.dart';
import 'oz_sport_16_orta.dart';
import 'oz_sport_16_zor.dart';
import 'oz_sport_17_kolay.dart';
import 'oz_sport_17_orta.dart';
import 'oz_sport_17_zor.dart';
import 'oz_sport_18_kolay.dart';
import 'oz_sport_18_orta.dart';
import 'oz_sport_18_zor.dart';
import 'oz_sport_19_kolay.dart';
import 'oz_sport_19_orta.dart';
import 'oz_sport_19_zor.dart';
import 'oz_culture_15_kolay.dart';
import 'oz_culture_15_orta.dart';
import 'oz_culture_15_zor.dart';
import 'oz_culture_16_kolay.dart';
import 'oz_culture_16_orta.dart';
import 'oz_culture_16_zor.dart';
import 'oz_culture_17_kolay.dart';
import 'oz_culture_17_orta.dart';
import 'oz_culture_17_zor.dart';
import 'oz_culture_18_kolay.dart';
import 'oz_culture_18_orta.dart';
import 'oz_culture_18_zor.dart';
import 'oz_culture_19_kolay.dart';
import 'oz_culture_19_orta.dart';
import 'oz_culture_19_zor.dart';
import 'oz_cinema_15_kolay.dart';
import 'oz_cinema_15_orta.dart';
import 'oz_cinema_15_zor.dart';
import 'oz_cinema_16_kolay.dart';
import 'oz_cinema_16_orta.dart';
import 'oz_cinema_16_zor.dart';
import 'oz_cinema_17_kolay.dart';
import 'oz_cinema_17_orta.dart';
import 'oz_cinema_17_zor.dart';
import 'oz_cinema_18_kolay.dart';
import 'oz_cinema_18_orta.dart';
import 'oz_cinema_18_zor.dart';
import 'oz_cinema_19_kolay.dart';
import 'oz_cinema_19_orta.dart';
import 'oz_cinema_19_zor.dart';
import 'oz_language_15_kolay.dart';
import 'oz_language_15_orta.dart';
import 'oz_language_15_zor.dart';
import 'oz_language_16_kolay.dart';
import 'oz_language_16_orta.dart';
import 'oz_language_16_zor.dart';
import 'oz_language_17_kolay.dart';
import 'oz_language_17_orta.dart';
import 'oz_language_17_zor.dart';
import 'oz_language_18_kolay.dart';
import 'oz_language_18_orta.dart';
import 'oz_language_18_zor.dart';
import 'oz_language_19_kolay.dart';
import 'oz_language_19_orta.dart';
import 'oz_language_19_zor.dart';
import 'oz_technology_15_kolay.dart';
import 'oz_technology_15_orta.dart';
import 'oz_technology_15_zor.dart';
import 'oz_technology_16_kolay.dart';
import 'oz_technology_16_orta.dart';
import 'oz_technology_16_zor.dart';
import 'oz_technology_17_kolay.dart';
import 'oz_technology_17_orta.dart';
import 'oz_technology_17_zor.dart';
import 'oz_technology_18_kolay.dart';
import 'oz_technology_18_orta.dart';
import 'oz_technology_18_zor.dart';
import 'oz_technology_19_kolay.dart';
import 'oz_technology_19_orta.dart';
import 'oz_technology_19_zor.dart';
import 'oz_literature_15_kolay.dart';
import 'oz_literature_15_orta.dart';
import 'oz_literature_15_zor.dart';
import 'oz_literature_16_kolay.dart';
import 'oz_literature_16_orta.dart';
import 'oz_literature_16_zor.dart';
import 'oz_literature_17_kolay.dart';
import 'oz_literature_17_orta.dart';
import 'oz_literature_17_zor.dart';
import 'oz_literature_18_kolay.dart';
import 'oz_literature_18_orta.dart';
import 'oz_literature_18_zor.dart';
import 'oz_literature_19_kolay.dart';
import 'oz_literature_19_orta.dart';
import 'oz_literature_19_zor.dart';
import 'oz_music_15_kolay.dart';
import 'oz_music_15_orta.dart';
import 'oz_music_15_zor.dart';
import 'oz_music_16_kolay.dart';
import 'oz_music_16_orta.dart';
import 'oz_music_16_zor.dart';
import 'oz_music_17_kolay.dart';
import 'oz_music_17_orta.dart';
import 'oz_music_17_zor.dart';
import 'oz_music_18_kolay.dart';
import 'oz_music_18_orta.dart';
import 'oz_music_18_zor.dart';
import 'oz_music_19_kolay.dart';
import 'oz_music_19_orta.dart';
import 'oz_music_19_zor.dart';
import 'oz_nature_15_kolay.dart';
import 'oz_nature_15_orta.dart';
import 'oz_nature_15_zor.dart';
import 'oz_nature_16_kolay.dart';
import 'oz_nature_16_orta.dart';
import 'oz_nature_16_zor.dart';
import 'oz_nature_17_kolay.dart';
import 'oz_nature_17_orta.dart';
import 'oz_nature_17_zor.dart';
import 'oz_nature_18_kolay.dart';
import 'oz_nature_18_orta.dart';
import 'oz_nature_18_zor.dart';
import 'oz_nature_19_kolay.dart';
import 'oz_nature_19_orta.dart';
import 'oz_nature_19_zor.dart';
import 'oz_exam_15_kolay.dart';
import 'oz_exam_15_orta.dart';
import 'oz_exam_15_zor.dart';
import 'oz_exam_16_kolay.dart';
import 'oz_exam_16_orta.dart';
import 'oz_exam_16_zor.dart';
import 'oz_exam_17_kolay.dart';
import 'oz_exam_17_orta.dart';
import 'oz_exam_17_zor.dart';
import 'oz_exam_18_kolay.dart';
import 'oz_exam_18_orta.dart';
import 'oz_exam_18_zor.dart';
import 'oz_exam_19_kolay.dart';
import 'oz_exam_19_orta.dart';
import 'oz_exam_19_zor.dart';
import 'oz_mathematics_15_kolay.dart';
import 'oz_mathematics_15_orta.dart';
import 'oz_mathematics_15_zor.dart';
import 'oz_mathematics_16_kolay.dart';
import 'oz_mathematics_16_orta.dart';
import 'oz_mathematics_16_zor.dart';
import 'oz_mathematics_17_kolay.dart';
import 'oz_mathematics_17_orta.dart';
import 'oz_mathematics_17_zor.dart';
import 'oz_mathematics_18_kolay.dart';
import 'oz_mathematics_18_orta.dart';
import 'oz_mathematics_18_zor.dart';
import 'oz_mathematics_19_kolay.dart';
import 'oz_mathematics_19_orta.dart';
import 'oz_mathematics_19_zor.dart';
import 'oz_physics_15_kolay.dart';
import 'oz_physics_15_orta.dart';
import 'oz_physics_15_zor.dart';
import 'oz_physics_16_kolay.dart';
import 'oz_physics_16_orta.dart';
import 'oz_physics_16_zor.dart';
import 'oz_physics_17_kolay.dart';
import 'oz_physics_17_orta.dart';
import 'oz_physics_17_zor.dart';
import 'oz_physics_18_kolay.dart';
import 'oz_physics_18_orta.dart';
import 'oz_physics_18_zor.dart';
import 'oz_physics_19_kolay.dart';
import 'oz_physics_19_orta.dart';
import 'oz_physics_19_zor.dart';
import 'oz_chemistry_15_kolay.dart';
import 'oz_chemistry_15_orta.dart';
import 'oz_chemistry_15_zor.dart';
import 'oz_chemistry_16_kolay.dart';
import 'oz_chemistry_16_orta.dart';
import 'oz_chemistry_16_zor.dart';
import 'oz_chemistry_17_kolay.dart';
import 'oz_chemistry_17_orta.dart';
import 'oz_chemistry_17_zor.dart';
import 'oz_chemistry_18_kolay.dart';
import 'oz_chemistry_18_orta.dart';
import 'oz_chemistry_18_zor.dart';
import 'oz_chemistry_19_kolay.dart';
import 'oz_chemistry_19_orta.dart';
import 'oz_chemistry_19_zor.dart';
import 'oz_biology_15_kolay.dart';
import 'oz_biology_15_orta.dart';
import 'oz_biology_15_zor.dart';
import 'oz_biology_16_kolay.dart';
import 'oz_biology_16_orta.dart';
import 'oz_biology_16_zor.dart';
import 'oz_biology_17_kolay.dart';
import 'oz_biology_17_orta.dart';
import 'oz_biology_17_zor.dart';
import 'oz_biology_18_kolay.dart';
import 'oz_biology_18_orta.dart';
import 'oz_biology_18_zor.dart';
import 'oz_biology_19_kolay.dart';
import 'oz_biology_19_orta.dart';
import 'oz_biology_19_zor.dart';
import 'oz_engineering_15_kolay.dart';
import 'oz_engineering_15_orta.dart';
import 'oz_engineering_15_zor.dart';
import 'oz_engineering_16_kolay.dart';
import 'oz_engineering_16_orta.dart';
import 'oz_engineering_16_zor.dart';
import 'oz_engineering_17_kolay.dart';
import 'oz_engineering_17_orta.dart';
import 'oz_engineering_17_zor.dart';
import 'oz_engineering_18_kolay.dart';
import 'oz_engineering_18_orta.dart';
import 'oz_engineering_18_zor.dart';
import 'oz_engineering_19_kolay.dart';
import 'oz_engineering_19_orta.dart';
import 'oz_engineering_19_zor.dart';
import 'oz_computing_15_kolay.dart';
import 'oz_computing_15_orta.dart';
import 'oz_computing_15_zor.dart';
import 'oz_computing_16_kolay.dart';
import 'oz_computing_16_orta.dart';
import 'oz_computing_16_zor.dart';
import 'oz_computing_17_kolay.dart';
import 'oz_computing_17_orta.dart';
import 'oz_computing_17_zor.dart';
import 'oz_computing_18_kolay.dart';
import 'oz_computing_18_orta.dart';
import 'oz_computing_18_zor.dart';
import 'oz_computing_19_kolay.dart';
import 'oz_computing_19_orta.dart';
import 'oz_computing_19_zor.dart';
import 'oz_statistics_15_kolay.dart';
import 'oz_statistics_15_orta.dart';
import 'oz_statistics_15_zor.dart';
import 'oz_statistics_16_kolay.dart';
import 'oz_statistics_16_orta.dart';
import 'oz_statistics_16_zor.dart';
import 'oz_statistics_17_kolay.dart';
import 'oz_statistics_17_orta.dart';
import 'oz_statistics_17_zor.dart';
import 'oz_statistics_18_kolay.dart';
import 'oz_statistics_18_orta.dart';
import 'oz_statistics_18_zor.dart';
import 'oz_statistics_19_kolay.dart';
import 'oz_statistics_19_orta.dart';
import 'oz_statistics_19_zor.dart';
import 'oz_economics_15_kolay.dart';
import 'oz_economics_15_orta.dart';
import 'oz_economics_15_zor.dart';
import 'oz_economics_16_kolay.dart';
import 'oz_economics_16_orta.dart';
import 'oz_economics_16_zor.dart';
import 'oz_economics_17_kolay.dart';
import 'oz_economics_17_orta.dart';
import 'oz_economics_17_zor.dart';
import 'oz_economics_18_kolay.dart';
import 'oz_economics_18_orta.dart';
import 'oz_economics_18_zor.dart';
import 'oz_economics_19_kolay.dart';
import 'oz_economics_19_orta.dart';
import 'oz_economics_19_zor.dart';
import 'oz_socialscience_15_kolay.dart';
import 'oz_socialscience_15_orta.dart';
import 'oz_socialscience_15_zor.dart';
import 'oz_socialscience_16_kolay.dart';
import 'oz_socialscience_16_orta.dart';
import 'oz_socialscience_16_zor.dart';
import 'oz_socialscience_17_kolay.dart';
import 'oz_socialscience_17_orta.dart';
import 'oz_socialscience_17_zor.dart';
import 'oz_socialscience_18_kolay.dart';
import 'oz_socialscience_18_orta.dart';
import 'oz_socialscience_18_zor.dart';
import 'oz_socialscience_19_kolay.dart';
import 'oz_socialscience_19_orta.dart';
import 'oz_socialscience_19_zor.dart';
import 'oz_research_15_kolay.dart';
import 'oz_research_15_orta.dart';
import 'oz_research_15_zor.dart';
import 'oz_research_16_kolay.dart';
import 'oz_research_16_orta.dart';
import 'oz_research_16_zor.dart';
import 'oz_research_17_kolay.dart';
import 'oz_research_17_orta.dart';
import 'oz_research_17_zor.dart';
import 'oz_research_18_kolay.dart';
import 'oz_research_18_orta.dart';
import 'oz_research_18_zor.dart';
import 'oz_research_19_kolay.dart';
import 'oz_research_19_orta.dart';
import 'oz_research_19_zor.dart';

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
  _aile('oz_art_2_orta', 'Heykel, mimarlık ve dünya mimari eserleri', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt2Orta),
  _aile('oz_art_2_kolay', 'Heykel, mimarlık ve dünya mimari eserleri', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt2Kolay),
  _aile('oz_art_2_zor', 'Heykel, mimarlık ve dünya mimari eserleri', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt2Zor),
  _aile('oz_art_3_kolay', 'Türk ve İslam sanatları', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt3Kolay),
  _aile('oz_art_3_orta', 'Türk ve İslam sanatları', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt3Orta),
  _aile('oz_art_3_zor', 'Türk ve İslam sanatları', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt3Zor),
  _aile('oz_art_4_orta', 'Sanat kavramları, teknikleri, renk ve tasarım ilkeleri; fotoğraf ve tiyatro', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt4Orta),
  _aile('oz_art_4_zor', 'Sanat kavramları, teknikleri, renk ve tasarım ilkeleri; fotoğraf ve tiyatro', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt4Zor),
  _aile('oz_art_4_kolay', 'Sanat kavramları, teknikleri, renk ve tasarım ilkeleri; fotoğraf ve tiyatro', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt4Kolay),
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
  _aile('oz_exam_4_kolay', 'Sözel mantık ve akıl yürütme', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam4Kolay),
  _aile('oz_exam_4_orta', 'Sözel mantık ve akıl yürütme', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam4Orta),
  _aile('oz_exam_4_zor', 'Sözel mantık ve akıl yürütme', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam4Zor),
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
  _aile('oz_biology_2_orta', 'Kalıtım, genetik ve evrim', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology2Orta),
  _aile('oz_biology_2_kolay', 'Kalıtım, genetik ve evrim', Topic.biology, Difficulty.easy, BloomLevel.anlama, ozBiology2Kolay),
  _aile('oz_biology_2_zor', 'Kalıtım, genetik ve evrim', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology2Zor),
  _aile('oz_biology_3_kolay', 'İnsan fizyolojisi: sistemler', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology3Kolay),
  _aile('oz_biology_3_orta', 'İnsan fizyolojisi: sistemler', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology3Orta),
  _aile('oz_biology_3_zor', 'İnsan fizyolojisi: sistemler', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology3Zor),
  _aile('oz_biology_4_kolay', 'Bitki biyolojisi, ekoloji ve canlıların sınıflandırılması', Topic.biology, Difficulty.easy, BloomLevel.anlama, ozBiology4Kolay),
  _aile('oz_biology_4_orta', 'Bitki biyolojisi, ekoloji ve canlıların sınıflandırılması', Topic.biology, Difficulty.medium, BloomLevel.analiz, ozBiology4Orta),
  _aile('oz_biology_4_zor', 'Bitki biyolojisi, ekoloji ve canlıların sınıflandırılması', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology4Zor),
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
  _aile('oz_art_5_orta', 'Genel ek sorular: Sanat kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt5Orta),
  _aile('oz_art_5_kolay', 'Genel ek sorular: Sanat kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt5Kolay),
  _aile('oz_art_5_zor', 'Genel ek sorular: Sanat kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt5Zor),
  _aile('oz_biology_5_kolay', 'Genel ek sorular: Biyoloji kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology5Kolay),
  _aile('oz_biology_5_orta', 'Genel ek sorular: Biyoloji kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology5Orta),
  _aile('oz_biology_5_zor', 'Genel ek sorular: Biyoloji kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology5Zor),
  _aile('oz_chemistry_5_zor', 'Genel ek sorular: Kimya kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry5Zor),
  _aile('oz_chemistry_5_orta', 'Genel ek sorular: Kimya kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.chemistry, Difficulty.medium, BloomLevel.hatirlama, ozChemistry5Orta),
  _aile('oz_chemistry_5_kolay', 'Genel ek sorular: Kimya kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry5Kolay),
  _aile('oz_cinema_5_kolay', 'Genel ek sorular: Sinema ve TV kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.cinema, Difficulty.easy, BloomLevel.anlama, ozCinema5Kolay),
  _aile('oz_cinema_5_orta', 'Genel ek sorular: Sinema ve TV kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema5Orta),
  _aile('oz_cinema_5_zor', 'Genel ek sorular: Sinema ve TV kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema5Zor),
  _aile('oz_computing_5_orta', 'Genel ek sorular: Bilişim ve Algoritmalar kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing5Orta),
  _aile('oz_computing_5_kolay', 'Genel ek sorular: Bilişim ve Algoritmalar kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing5Kolay),
  _aile('oz_computing_5_zor', 'Genel ek sorular: Bilişim ve Algoritmalar kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing5Zor),
  _aile('oz_culture_5_orta', 'Genel ek sorular: Genel Kültür kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture5Orta),
  _aile('oz_culture_5_kolay', 'Genel ek sorular: Genel Kültür kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture5Kolay),
  _aile('oz_culture_5_zor', 'Genel ek sorular: Genel Kültür kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.culture, Difficulty.hard, BloomLevel.anlama, ozCulture5Zor),
  _aile('oz_economics_5_kolay', 'Genel ek sorular: Ekonomi ve Finans kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics5Kolay),
  _aile('oz_economics_5_orta', 'Genel ek sorular: Ekonomi ve Finans kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics5Orta),
  _aile('oz_economics_5_zor', 'Genel ek sorular: Ekonomi ve Finans kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.economics, Difficulty.hard, BloomLevel.analiz, ozEconomics5Zor),
  _aile('oz_engineering_5_orta', 'Genel ek sorular: Mühendislik ve Tasarım kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering5Orta),
  _aile('oz_engineering_5_zor', 'Genel ek sorular: Mühendislik ve Tasarım kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering5Zor),
  _aile('oz_engineering_5_kolay', 'Genel ek sorular: Mühendislik ve Tasarım kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.engineering, Difficulty.easy, BloomLevel.anlama, ozEngineering5Kolay),
  _aile('oz_exam_5_kolay', 'Genel ek sorular: Sınav Hazırlık kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam5Kolay),
  _aile('oz_exam_5_orta', 'Genel ek sorular: Sınav Hazırlık kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam5Orta),
  _aile('oz_exam_5_zor', 'Genel ek sorular: Sınav Hazırlık kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam5Zor),
  _aile('oz_geography_5_kolay', 'Genel ek sorular: Coğrafya kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography5Kolay),
  _aile('oz_geography_5_orta', 'Genel ek sorular: Coğrafya kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography5Orta),
  _aile('oz_geography_5_zor', 'Genel ek sorular: Coğrafya kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography5Zor),
  _aile('oz_history_5_zor', 'Genel ek sorular: Tarih kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory5Zor),
  _aile('oz_history_5_orta', 'Genel ek sorular: Tarih kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory5Orta),
  _aile('oz_history_5_kolay', 'Genel ek sorular: Tarih kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory5Kolay),
  _aile('oz_language_5_orta', 'Genel ek sorular: Yabancı Dil kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage5Orta),
  _aile('oz_language_5_zor', 'Genel ek sorular: Yabancı Dil kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage5Zor),
  _aile('oz_language_5_kolay', 'Genel ek sorular: Yabancı Dil kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.language, Difficulty.easy, BloomLevel.anlama, ozLanguage5Kolay),
  _aile('oz_literature_5_kolay', 'Genel ek sorular: Edebiyat kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.literature, Difficulty.easy, BloomLevel.anlama, ozLiterature5Kolay),
  _aile('oz_literature_5_zor', 'Genel ek sorular: Edebiyat kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature5Zor),
  _aile('oz_literature_5_orta', 'Genel ek sorular: Edebiyat kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.literature, Difficulty.medium, BloomLevel.anlama, ozLiterature5Orta),
  _aile('oz_mathematics_5_kolay', 'Genel ek sorular: Matematik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics5Kolay),
  _aile('oz_mathematics_5_orta', 'Genel ek sorular: Matematik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics5Orta),
  _aile('oz_mathematics_5_zor', 'Genel ek sorular: Matematik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.mathematics, Difficulty.hard, BloomLevel.uygulama, ozMathematics5Zor),
  _aile('oz_music_5_orta', 'Genel ek sorular: Müzik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic5Orta),
  _aile('oz_music_5_zor', 'Genel ek sorular: Müzik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic5Zor),
  _aile('oz_music_5_kolay', 'Genel ek sorular: Müzik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.music, Difficulty.easy, BloomLevel.anlama, ozMusic5Kolay),
  _aile('oz_nature_5_zor', 'Genel ek sorular: Doğa kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature5Zor),
  _aile('oz_nature_5_orta', 'Genel ek sorular: Doğa kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.nature, Difficulty.medium, BloomLevel.anlama, ozNature5Orta),
  _aile('oz_nature_5_kolay', 'Genel ek sorular: Doğa kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature5Kolay),
  _aile('oz_physics_5_kolay', 'Genel ek sorular: Fizik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.physics, Difficulty.easy, BloomLevel.hatirlama, ozPhysics5Kolay),
  _aile('oz_physics_5_zor', 'Genel ek sorular: Fizik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics5Zor),
  _aile('oz_physics_5_orta', 'Genel ek sorular: Fizik kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.physics, Difficulty.medium, BloomLevel.hatirlama, ozPhysics5Orta),
  _aile('oz_research_5_orta', 'Genel ek sorular: Araştırma Yöntemleri kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.research, Difficulty.medium, BloomLevel.hatirlama, ozResearch5Orta),
  _aile('oz_research_5_kolay', 'Genel ek sorular: Araştırma Yöntemleri kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.research, Difficulty.easy, BloomLevel.hatirlama, ozResearch5Kolay),
  _aile('oz_research_5_zor', 'Genel ek sorular: Araştırma Yöntemleri kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.research, Difficulty.hard, BloomLevel.hatirlama, ozResearch5Zor),
  _aile('oz_science_5_orta', 'Genel ek sorular: Bilim kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience5Orta),
  _aile('oz_science_5_zor', 'Genel ek sorular: Bilim kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.science, Difficulty.hard, BloomLevel.hatirlama, ozScience5Zor),
  _aile('oz_science_5_kolay', 'Genel ek sorular: Bilim kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.science, Difficulty.easy, BloomLevel.anlama, ozScience5Kolay),
  _aile('oz_socialScience_5_orta', 'Genel ek sorular: Toplum ve Sosyal Bilimler kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.socialScience, Difficulty.medium, BloomLevel.hatirlama, ozSocialscience5Orta),
  _aile('oz_socialScience_5_zor', 'Genel ek sorular: Toplum ve Sosyal Bilimler kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.socialScience, Difficulty.hard, BloomLevel.anlama, ozSocialscience5Zor),
  _aile('oz_socialScience_5_kolay', 'Genel ek sorular: Toplum ve Sosyal Bilimler kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience5Kolay),
  _aile('oz_sport_5_kolay', 'Genel ek sorular: Spor kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport5Kolay),
  _aile('oz_sport_5_orta', 'Genel ek sorular: Spor kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport5Orta),
  _aile('oz_sport_5_zor', 'Genel ek sorular: Spor kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport5Zor),
  _aile('oz_statistics_5_kolay', 'Genel ek sorular: İstatistik ve Veri Bilimi kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics5Kolay),
  _aile('oz_statistics_5_orta', 'Genel ek sorular: İstatistik ve Veri Bilimi kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics5Orta),
  _aile('oz_statistics_5_zor', 'Genel ek sorular: İstatistik ve Veri Bilimi kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.statistics, Difficulty.hard, BloomLevel.uygulama, ozStatistics5Zor),
  _aile('oz_technology_5_kolay', 'Genel ek sorular: Teknoloji kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology5Kolay),
  _aile('oz_technology_5_orta', 'Genel ek sorular: Teknoloji kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.technology, Difficulty.medium, BloomLevel.hatirlama, ozTechnology5Orta),
  _aile('oz_technology_5_zor', 'Genel ek sorular: Teknoloji kategorisinde bankada henüz sorulmamış bilgi ve beceriler', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology5Zor),
  _aile('oz_science_6_orta', 'Gök cisimleri ve gözlem: takımyıldızlar, yıldız türleri, galaksiler, kozmoloji', Topic.science, Difficulty.medium, BloomLevel.hatirlama, ozScience6Orta),
  _aile('oz_science_6_kolay', 'Gök cisimleri ve gözlem: takımyıldızlar, yıldız türleri, galaksiler, kozmoloji', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience6Kolay),
  _aile('oz_science_6_zor', 'Gök cisimleri ve gözlem: takımyıldızlar, yıldız türleri, galaksiler, kozmoloji', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience6Zor),
  _aile('oz_science_7_kolay', 'Uzay araştırmaları tarihi: görevler, teleskoplar, astronotlar, uzay ajansları', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience7Kolay),
  _aile('oz_science_7_orta', 'Uzay araştırmaları tarihi: görevler, teleskoplar, astronotlar, uzay ajansları', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience7Orta),
  _aile('oz_science_7_zor', 'Uzay araştırmaları tarihi: görevler, teleskoplar, astronotlar, uzay ajansları', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience7Zor),
  _aile('oz_science_8_orta', 'Meteoroloji: hava olayları, bulutlar, rüzgâr sistemleri, hava tahmini', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience8Orta),
  _aile('oz_science_8_zor', 'Meteoroloji: hava olayları, bulutlar, rüzgâr sistemleri, hava tahmini', Topic.science, Difficulty.hard, BloomLevel.hatirlama, ozScience8Zor),
  _aile('oz_science_8_kolay', 'Meteoroloji: hava olayları, bulutlar, rüzgâr sistemleri, hava tahmini', Topic.science, Difficulty.easy, BloomLevel.anlama, ozScience8Kolay),
  _aile('oz_science_9_kolay', 'Okyanus ve su bilimi: akıntılar, gelgit, deniz canlıları ortamı, su döngüsü', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience9Kolay),
  _aile('oz_science_9_orta', 'Okyanus ve su bilimi: akıntılar, gelgit, deniz canlıları ortamı, su döngüsü', Topic.science, Difficulty.medium, BloomLevel.hatirlama, ozScience9Orta),
  _aile('oz_science_9_zor', 'Okyanus ve su bilimi: akıntılar, gelgit, deniz canlıları ortamı, su döngüsü', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience9Zor),
  _aile('oz_science_10_kolay', 'Mineraller, kayaçlar, fosiller ve jeolojik zaman', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience10Kolay),
  _aile('oz_science_10_orta', 'Mineraller, kayaçlar, fosiller ve jeolojik zaman', Topic.science, Difficulty.medium, BloomLevel.hatirlama, ozScience10Orta),
  _aile('oz_science_10_zor', 'Mineraller, kayaçlar, fosiller ve jeolojik zaman', Topic.science, Difficulty.hard, BloomLevel.hatirlama, ozScience10Zor),
  _aile('oz_science_11_orta', 'İnsan bedeni merakları: duyular, uyku, beslenme bilimi, bağışıklık', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience11Orta),
  _aile('oz_science_11_kolay', 'İnsan bedeni merakları: duyular, uyku, beslenme bilimi, bağışıklık', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience11Kolay),
  _aile('oz_science_11_zor', 'İnsan bedeni merakları: duyular, uyku, beslenme bilimi, bağışıklık', Topic.science, Difficulty.hard, BloomLevel.anlama, ozScience11Zor),
  _aile('oz_science_12_kolay', 'Ölçme ve birimler bilimi: SI, ölçü aletleri, hata, büyüklük mertebeleri', Topic.science, Difficulty.easy, BloomLevel.uygulama, ozScience12Kolay),
  _aile('oz_science_12_orta', 'Ölçme ve birimler bilimi: SI, ölçü aletleri, hata, büyüklük mertebeleri', Topic.science, Difficulty.medium, BloomLevel.uygulama, ozScience12Orta),
  _aile('oz_science_12_zor', 'Ölçme ve birimler bilimi: SI, ölçü aletleri, hata, büyüklük mertebeleri', Topic.science, Difficulty.hard, BloomLevel.uygulama, ozScience12Zor),
  _aile('oz_science_13_kolay', 'Malzemeler ve maddenin günlük halleri: plastik, cam, metal, alaşım, nanomalzeme', Topic.science, Difficulty.easy, BloomLevel.anlama, ozScience13Kolay),
  _aile('oz_science_13_zor', 'Malzemeler ve maddenin günlük halleri: plastik, cam, metal, alaşım, nanomalzeme', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience13Zor),
  _aile('oz_science_13_orta', 'Malzemeler ve maddenin günlük halleri: plastik, cam, metal, alaşım, nanomalzeme', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience13Orta),
  _aile('oz_science_14_kolay', 'Bilimsel düşünme ve yaygın yanılgılar: efsaneler, mitler, sahte bilim ayırt etme', Topic.science, Difficulty.easy, BloomLevel.anlama, ozScience14Kolay),
  _aile('oz_science_14_orta', 'Bilimsel düşünme ve yaygın yanılgılar: efsaneler, mitler, sahte bilim ayırt etme', Topic.science, Difficulty.medium, BloomLevel.degerlendirme, ozScience14Orta),
  _aile('oz_science_14_zor', 'Bilimsel düşünme ve yaygın yanılgılar: efsaneler, mitler, sahte bilim ayırt etme', Topic.science, Difficulty.hard, BloomLevel.degerlendirme, ozScience14Zor),
  _aile('oz_history_6_kolay', 'Orta Asya Türk devletleri ve göçler', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory6Kolay),
  _aile('oz_history_6_orta', 'Orta Asya Türk devletleri ve göçler', Topic.history, Difficulty.medium, BloomLevel.analiz, ozHistory6Orta),
  _aile('oz_history_6_zor', 'Orta Asya Türk devletleri ve göçler', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory6Zor),
  _aile('oz_history_7_orta', 'Avrupa tarihi: Rönesans, Reform, Coğrafi Keşifler, mutlakiyet', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory7Orta),
  _aile('oz_history_7_zor', 'Avrupa tarihi: Rönesans, Reform, Coğrafi Keşifler, mutlakiyet', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory7Zor),
  _aile('oz_history_7_kolay', 'Avrupa tarihi: Rönesans, Reform, Coğrafi Keşifler, mutlakiyet', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory7Kolay),
  _aile('oz_history_8_kolay', 'Fransız Devrimi, Napolyon ve 19. yüzyıl ulus devletleri', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory8Kolay),
  _aile('oz_history_8_orta', 'Fransız Devrimi, Napolyon ve 19. yüzyıl ulus devletleri', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory8Orta),
  _aile('oz_history_8_zor', 'Fransız Devrimi, Napolyon ve 19. yüzyıl ulus devletleri', Topic.history, Difficulty.hard, BloomLevel.analiz, ozHistory8Zor),
  _aile('oz_history_9_zor', 'Birinci Dünya Savaşı ve savaşlar arası dönem', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory9Zor),
  _aile('oz_history_9_orta', 'Birinci Dünya Savaşı ve savaşlar arası dönem', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory9Orta),
  _aile('oz_history_9_kolay', 'Birinci Dünya Savaşı ve savaşlar arası dönem', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory9Kolay),
  _aile('oz_history_10_kolay', 'İkinci Dünya Savaşı ve Soğuk Savaş', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory10Kolay),
  _aile('oz_history_10_orta', 'İkinci Dünya Savaşı ve Soğuk Savaş', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory10Orta),
  _aile('oz_history_10_zor', 'İkinci Dünya Savaşı ve Soğuk Savaş', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory10Zor),
  _aile('oz_history_11_orta', 'Asya ve Uzak Doğu tarihi: Çin hanedanları, Japonya, Hindistan, Moğollar', Topic.history, Difficulty.medium, BloomLevel.anlama, ozHistory11Orta),
  _aile('oz_history_11_kolay', 'Asya ve Uzak Doğu tarihi: Çin hanedanları, Japonya, Hindistan, Moğollar', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory11Kolay),
  _aile('oz_history_11_zor', 'Asya ve Uzak Doğu tarihi: Çin hanedanları, Japonya, Hindistan, Moğollar', Topic.history, Difficulty.hard, BloomLevel.anlama, ozHistory11Zor),
  _aile('oz_history_12_orta', 'Amerika ve Afrika tarihi: yerli uygarlıklar, sömürgecilik, bağımsızlıklar', Topic.history, Difficulty.medium, BloomLevel.analiz, ozHistory12Orta),
  _aile('oz_history_12_kolay', 'Amerika ve Afrika tarihi: yerli uygarlıklar, sömürgecilik, bağımsızlıklar', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory12Kolay),
  _aile('oz_history_12_zor', 'Amerika ve Afrika tarihi: yerli uygarlıklar, sömürgecilik, bağımsızlıklar', Topic.history, Difficulty.hard, BloomLevel.analiz, ozHistory12Zor),
  _aile('oz_history_13_kolay', 'Osmanlı kültür ve kurumları: saray, ordu, ilmiye, vakıflar, gündelik hayat', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory13Kolay),
  _aile('oz_history_13_orta', 'Osmanlı kültür ve kurumları: saray, ordu, ilmiye, vakıflar, gündelik hayat', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory13Orta),
  _aile('oz_history_13_zor', 'Osmanlı kültür ve kurumları: saray, ordu, ilmiye, vakıflar, gündelik hayat', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory13Zor),
  _aile('oz_history_14_kolay', 'Arkeoloji ve antik kentler: Anadolu ve dünyadaki kazılar, buluntular', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory14Kolay),
  _aile('oz_history_14_orta', 'Arkeoloji ve antik kentler: Anadolu ve dünyadaki kazılar, buluntular', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory14Orta),
  _aile('oz_history_14_zor', 'Arkeoloji ve antik kentler: Anadolu ve dünyadaki kazılar, buluntular', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory14Zor),
  _aile('oz_geography_6_kolay', 'Harita bilgisi, koordinatlar, projeksiyonlar ve ölçek hesapları', Topic.geography, Difficulty.easy, BloomLevel.uygulama, ozGeography6Kolay),
  _aile('oz_geography_6_orta', 'Harita bilgisi, koordinatlar, projeksiyonlar ve ölçek hesapları', Topic.geography, Difficulty.medium, BloomLevel.uygulama, ozGeography6Orta),
  _aile('oz_geography_6_zor', 'Harita bilgisi, koordinatlar, projeksiyonlar ve ölçek hesapları', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography6Zor),
  _aile('oz_geography_7_orta', 'Dünya iklim tipleri ve bitki örtüsü kuşakları', Topic.geography, Difficulty.medium, BloomLevel.analiz, ozGeography7Orta),
  _aile('oz_geography_7_kolay', 'Dünya iklim tipleri ve bitki örtüsü kuşakları', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography7Kolay),
  _aile('oz_geography_7_zor', 'Dünya iklim tipleri ve bitki örtüsü kuşakları', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography7Zor),
  _aile('oz_geography_8_kolay', 'Nüfus coğrafyası: dağılış, göç, şehirleşme', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography8Kolay),
  _aile('oz_geography_8_orta', 'Nüfus coğrafyası: dağılış, göç, şehirleşme', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography8Orta),
  _aile('oz_geography_8_zor', 'Nüfus coğrafyası: dağılış, göç, şehirleşme', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography8Zor),
  _aile('oz_geography_9_kolay', 'Ekonomik coğrafya: tarım, madenler, enerji kaynakları, ticaret yolları', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography9Kolay),
  _aile('oz_geography_9_orta', 'Ekonomik coğrafya: tarım, madenler, enerji kaynakları, ticaret yolları', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography9Orta),
  _aile('oz_geography_9_zor', 'Ekonomik coğrafya: tarım, madenler, enerji kaynakları, ticaret yolları', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography9Zor),
  _aile('oz_geography_10_orta', 'Avrupa ve Rusya bölgesel coğrafyası', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography10Orta),
  _aile('oz_geography_10_zor', 'Avrupa ve Rusya bölgesel coğrafyası', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography10Zor),
  _aile('oz_geography_10_kolay', 'Avrupa ve Rusya bölgesel coğrafyası', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography10Kolay),
  _aile('oz_geography_11_kolay', 'Asya ve Okyanusya bölgesel coğrafyası', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography11Kolay),
  _aile('oz_geography_11_orta', 'Asya ve Okyanusya bölgesel coğrafyası', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography11Orta),
  _aile('oz_geography_11_zor', 'Asya ve Okyanusya bölgesel coğrafyası', Topic.geography, Difficulty.hard, BloomLevel.anlama, ozGeography11Zor),
  _aile('oz_geography_12_zor', 'Afrika ve Amerika kıtaları bölgesel coğrafyası', Topic.geography, Difficulty.hard, BloomLevel.analiz, ozGeography12Zor),
  _aile('oz_geography_12_orta', 'Afrika ve Amerika kıtaları bölgesel coğrafyası', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography12Orta),
  _aile('oz_geography_12_kolay', 'Afrika ve Amerika kıtaları bölgesel coğrafyası', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography12Kolay),
  _aile('oz_geography_13_kolay', 'Doğal afetler ve korunma: deprem, sel, heyelan, çığ, kuraklık', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography13Kolay),
  _aile('oz_geography_13_orta', 'Doğal afetler ve korunma: deprem, sel, heyelan, çığ, kuraklık', Topic.geography, Difficulty.medium, BloomLevel.anlama, ozGeography13Orta),
  _aile('oz_geography_13_zor', 'Doğal afetler ve korunma: deprem, sel, heyelan, çığ, kuraklık', Topic.geography, Difficulty.hard, BloomLevel.uygulama, ozGeography13Zor),
  _aile('oz_geography_14_kolay', 'Türkiye bölgeleri: Karadeniz, Marmara, Ege, Akdeniz, İç, Doğu ve Güneydoğu Anadolu ayrıntıları', Topic.geography, Difficulty.easy, BloomLevel.anlama, ozGeography14Kolay),
  _aile('oz_geography_14_orta', 'Türkiye bölgeleri: Karadeniz, Marmara, Ege, Akdeniz, İç, Doğu ve Güneydoğu Anadolu ayrıntıları', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography14Orta),
  _aile('oz_geography_14_zor', 'Türkiye bölgeleri: Karadeniz, Marmara, Ege, Akdeniz, İç, Doğu ve Güneydoğu Anadolu ayrıntıları', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography14Zor),
  _aile('oz_art_6_orta', 'Rönesans ve Barok sanatı ayrıntılı', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt6Orta),
  _aile('oz_art_6_zor', 'Rönesans ve Barok sanatı ayrıntılı', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt6Zor),
  _aile('oz_art_6_kolay', 'Rönesans ve Barok sanatı ayrıntılı', Topic.art, Difficulty.easy, BloomLevel.anlama, ozArt6Kolay),
  _aile('oz_art_7_orta', '19. yüzyıl akımları: Romantizm, Realizm, İzlenimcilik, Postizlenimcilik', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt7Orta),
  _aile('oz_art_7_kolay', '19. yüzyıl akımları: Romantizm, Realizm, İzlenimcilik, Postizlenimcilik', Topic.art, Difficulty.easy, BloomLevel.analiz, ozArt7Kolay),
  _aile('oz_art_7_zor', '19. yüzyıl akımları: Romantizm, Realizm, İzlenimcilik, Postizlenimcilik', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt7Zor),
  _aile('oz_art_8_zor', '20. yüzyıl modern sanat akımları: Kübizm, Dışavurumculuk, Sürrealizm, Pop Art', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt8Zor),
  _aile('oz_art_8_kolay', '20. yüzyıl modern sanat akımları: Kübizm, Dışavurumculuk, Sürrealizm, Pop Art', Topic.art, Difficulty.easy, BloomLevel.anlama, ozArt8Kolay),
  _aile('oz_art_8_orta', '20. yüzyıl modern sanat akımları: Kübizm, Dışavurumculuk, Sürrealizm, Pop Art', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt8Orta),
  _aile('oz_art_9_orta', 'Türk resim tarihi ve Cumhuriyet dönemi sanatçıları', Topic.art, Difficulty.medium, BloomLevel.analiz, ozArt9Orta),
  _aile('oz_art_9_zor', 'Türk resim tarihi ve Cumhuriyet dönemi sanatçıları', Topic.art, Difficulty.hard, BloomLevel.analiz, ozArt9Zor),
  _aile('oz_art_9_kolay', 'Türk resim tarihi ve Cumhuriyet dönemi sanatçıları', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt9Kolay),
  _aile('oz_art_10_kolay', 'Fotoğraf sanatı ve fotoğraf tarihi', Topic.art, Difficulty.easy, BloomLevel.anlama, ozArt10Kolay),
  _aile('oz_art_10_zor', 'Fotoğraf sanatı ve fotoğraf tarihi', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt10Zor),
  _aile('oz_art_10_orta', 'Fotoğraf sanatı ve fotoğraf tarihi', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt10Orta),
  _aile('oz_art_11_kolay', 'Tiyatro ve sahne sanatları: türler, yazarlar, terimler', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt11Kolay),
  _aile('oz_art_11_orta', 'Tiyatro ve sahne sanatları: türler, yazarlar, terimler', Topic.art, Difficulty.medium, BloomLevel.anlama, ozArt11Orta),
  _aile('oz_art_11_zor', 'Tiyatro ve sahne sanatları: türler, yazarlar, terimler', Topic.art, Difficulty.hard, BloomLevel.anlama, ozArt11Zor),
  _aile('oz_art_12_kolay', 'Grafik tasarım, tipografi, afiş ve logo tasarımı', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt12Kolay),
  _aile('oz_art_12_orta', 'Grafik tasarım, tipografi, afiş ve logo tasarımı', Topic.art, Difficulty.medium, BloomLevel.anlama, ozArt12Orta),
  _aile('oz_art_12_zor', 'Grafik tasarım, tipografi, afiş ve logo tasarımı', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt12Zor),
  _aile('oz_art_13_kolay', 'Mimarlık akımları ve mimarlar', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt13Kolay),
  _aile('oz_art_13_orta', 'Mimarlık akımları ve mimarlar', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt13Orta),
  _aile('oz_art_13_zor', 'Mimarlık akımları ve mimarlar', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt13Zor),
  _aile('oz_art_14_kolay', 'Dekoratif sanatlar: seramik, cam, tekstil, mobilya, kuyumculuk', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt14Kolay),
  _aile('oz_art_14_orta', 'Dekoratif sanatlar: seramik, cam, tekstil, mobilya, kuyumculuk', Topic.art, Difficulty.medium, BloomLevel.anlama, ozArt14Orta),
  _aile('oz_art_14_zor', 'Dekoratif sanatlar: seramik, cam, tekstil, mobilya, kuyumculuk', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt14Zor),
  _aile('oz_sport_6_orta', 'Basketbol ayrıntıları: kurallar, pozisyonlar, istatistik terimleri', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport6Orta),
  _aile('oz_sport_6_zor', 'Basketbol ayrıntıları: kurallar, pozisyonlar, istatistik terimleri', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport6Zor),
  _aile('oz_sport_6_kolay', 'Basketbol ayrıntıları: kurallar, pozisyonlar, istatistik terimleri', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport6Kolay),
  _aile('oz_sport_7_kolay', 'Voleybol ve hentbol: kurallar, rotasyon, puanlama', Topic.sport, Difficulty.easy, BloomLevel.anlama, ozSport7Kolay),
  _aile('oz_sport_7_orta', 'Voleybol ve hentbol: kurallar, rotasyon, puanlama', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport7Orta),
  _aile('oz_sport_7_zor', 'Voleybol ve hentbol: kurallar, rotasyon, puanlama', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport7Zor),
  _aile('oz_sport_8_kolay', 'Tenis, masa tenisi ve badminton: kurallar ve terimler', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport8Kolay),
  _aile('oz_sport_8_zor', 'Tenis, masa tenisi ve badminton: kurallar ve terimler', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport8Zor),
  _aile('oz_sport_8_orta', 'Tenis, masa tenisi ve badminton: kurallar ve terimler', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport8Orta),
  _aile('oz_sport_9_orta', 'Güreş, judo, boks ve dövüş sporları kuralları', Topic.sport, Difficulty.medium, BloomLevel.anlama, ozSport9Orta),
  _aile('oz_sport_9_kolay', 'Güreş, judo, boks ve dövüş sporları kuralları', Topic.sport, Difficulty.easy, BloomLevel.anlama, ozSport9Kolay),
  _aile('oz_sport_9_zor', 'Güreş, judo, boks ve dövüş sporları kuralları', Topic.sport, Difficulty.hard, BloomLevel.anlama, ozSport9Zor),
  _aile('oz_sport_10_kolay', 'Yüzme, su sporları ve kış sporları', Topic.sport, Difficulty.easy, BloomLevel.anlama, ozSport10Kolay),
  _aile('oz_sport_10_orta', 'Yüzme, su sporları ve kış sporları', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport10Orta),
  _aile('oz_sport_10_zor', 'Yüzme, su sporları ve kış sporları', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport10Zor),
  _aile('oz_sport_11_kolay', 'Atletizm disiplinleri ve hesap soruları', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport11Kolay),
  _aile('oz_sport_11_zor', 'Atletizm disiplinleri ve hesap soruları', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport11Zor),
  _aile('oz_sport_11_orta', 'Atletizm disiplinleri ve hesap soruları', Topic.sport, Difficulty.medium, BloomLevel.uygulama, ozSport11Orta),
  _aile('oz_sport_12_kolay', 'Antrenman bilimi, fizyoloji, beslenme ve sakatlıklar', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport12Kolay),
  _aile('oz_sport_12_orta', 'Antrenman bilimi, fizyoloji, beslenme ve sakatlıklar', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport12Orta),
  _aile('oz_sport_12_zor', 'Antrenman bilimi, fizyoloji, beslenme ve sakatlıklar', Topic.sport, Difficulty.hard, BloomLevel.anlama, ozSport12Zor),
  _aile('oz_sport_13_kolay', 'Türk spor tarihi: kulüpler, federasyonlar, millî takımların kesinleşmiş başarıları', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport13Kolay),
  _aile('oz_sport_13_orta', 'Türk spor tarihi: kulüpler, federasyonlar, millî takımların kesinleşmiş başarıları', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport13Orta),
  _aile('oz_sport_13_zor', 'Türk spor tarihi: kulüpler, federasyonlar, millî takımların kesinleşmiş başarıları', Topic.sport, Difficulty.hard, BloomLevel.uygulama, ozSport13Zor),
  _aile('oz_sport_14_kolay', 'Geleneksel ve az bilinen sporlar: okçuluk, cirit, satranç, motor sporları, binicilik', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport14Kolay),
  _aile('oz_sport_14_orta', 'Geleneksel ve az bilinen sporlar: okçuluk, cirit, satranç, motor sporları, binicilik', Topic.sport, Difficulty.medium, BloomLevel.anlama, ozSport14Orta),
  _aile('oz_sport_14_zor', 'Geleneksel ve az bilinen sporlar: okçuluk, cirit, satranç, motor sporları, binicilik', Topic.sport, Difficulty.hard, BloomLevel.analiz, ozSport14Zor),
  _aile('oz_culture_6_kolay', 'Dünya mitolojileri: Yunan, Roma, İskandinav, Mısır, Türk mitolojisi', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture6Kolay),
  _aile('oz_culture_6_orta', 'Dünya mitolojileri: Yunan, Roma, İskandinav, Mısır, Türk mitolojisi', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture6Orta),
  _aile('oz_culture_6_zor', 'Dünya mitolojileri: Yunan, Roma, İskandinav, Mısır, Türk mitolojisi', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture6Zor),
  _aile('oz_culture_7_kolay', 'Dinler tarihi ve inanç gelenekleri', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture7Kolay),
  _aile('oz_culture_7_orta', 'Dinler tarihi ve inanç gelenekleri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture7Orta),
  _aile('oz_culture_7_zor', 'Dinler tarihi ve inanç gelenekleri', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture7Zor),
  _aile('oz_culture_8_kolay', 'Dünya mutfağı ve gastronomi terimleri', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture8Kolay),
  _aile('oz_culture_8_orta', 'Dünya mutfağı ve gastronomi terimleri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture8Orta),
  _aile('oz_culture_8_zor', 'Dünya mutfağı ve gastronomi terimleri', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture8Zor),
  _aile('oz_culture_9_kolay', 'Moda, giyim tarihi ve tekstil terimleri', Topic.culture, Difficulty.easy, BloomLevel.uygulama, ozCulture9Kolay),
  _aile('oz_culture_9_orta', 'Moda, giyim tarihi ve tekstil terimleri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture9Orta),
  _aile('oz_culture_9_zor', 'Moda, giyim tarihi ve tekstil terimleri', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture9Zor),
  _aile('oz_culture_10_orta', 'Ünlü markalar ve icatların kökeni', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture10Orta),
  _aile('oz_culture_10_zor', 'Ünlü markalar ve icatların kökeni', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture10Zor),
  _aile('oz_culture_10_kolay', 'Ünlü markalar ve icatların kökeni', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture10Kolay),
  _aile('oz_culture_11_kolay', 'Takvimler, bayramlar, özel günler ve zaman ölçme gelenekleri', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture11Kolay),
  _aile('oz_culture_11_orta', 'Takvimler, bayramlar, özel günler ve zaman ölçme gelenekleri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture11Orta),
  _aile('oz_culture_11_zor', 'Takvimler, bayramlar, özel günler ve zaman ölçme gelenekleri', Topic.culture, Difficulty.hard, BloomLevel.analiz, ozCulture11Zor),
  _aile('oz_culture_12_orta', 'Bayraklar, armalar, semboller ve millî marşlar', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture12Orta),
  _aile('oz_culture_12_kolay', 'Bayraklar, armalar, semboller ve millî marşlar', Topic.culture, Difficulty.easy, BloomLevel.anlama, ozCulture12Kolay),
  _aile('oz_culture_12_zor', 'Bayraklar, armalar, semboller ve millî marşlar', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture12Zor),
  _aile('oz_culture_13_orta', 'Görgü kuralları, iletişim kültürü ve gündelik hayat bilgisi', Topic.culture, Difficulty.medium, BloomLevel.uygulama, ozCulture13Orta),
  _aile('oz_culture_13_kolay', 'Görgü kuralları, iletişim kültürü ve gündelik hayat bilgisi', Topic.culture, Difficulty.easy, BloomLevel.anlama, ozCulture13Kolay),
  _aile('oz_culture_13_zor', 'Görgü kuralları, iletişim kültürü ve gündelik hayat bilgisi', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture13Zor),
  _aile('oz_culture_14_kolay', 'Oyunlar, bulmacalar ve eğlence kültürü tarihi', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture14Kolay),
  _aile('oz_culture_14_orta', 'Oyunlar, bulmacalar ve eğlence kültürü tarihi', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture14Orta),
  _aile('oz_culture_14_zor', 'Oyunlar, bulmacalar ve eğlence kültürü tarihi', Topic.culture, Difficulty.hard, BloomLevel.anlama, ozCulture14Zor),
  _aile('oz_cinema_6_orta', 'Hollywood klasik dönemi ve stüdyo sistemi', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema6Orta),
  _aile('oz_cinema_6_zor', 'Hollywood klasik dönemi ve stüdyo sistemi', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema6Zor),
  _aile('oz_cinema_6_kolay', 'Hollywood klasik dönemi ve stüdyo sistemi', Topic.cinema, Difficulty.easy, BloomLevel.anlama, ozCinema6Kolay),
  _aile('oz_cinema_7_kolay', 'Avrupa sinemaları: Fransız, İtalyan, Alman, İskandinav, Doğu Avrupa', Topic.cinema, Difficulty.easy, BloomLevel.anlama, ozCinema7Kolay),
  _aile('oz_cinema_7_orta', 'Avrupa sinemaları: Fransız, İtalyan, Alman, İskandinav, Doğu Avrupa', Topic.cinema, Difficulty.medium, BloomLevel.analiz, ozCinema7Orta),
  _aile('oz_cinema_7_zor', 'Avrupa sinemaları: Fransız, İtalyan, Alman, İskandinav, Doğu Avrupa', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema7Zor),
  _aile('oz_cinema_8_kolay', 'Asya sinemaları: Japon, Kore, Çin, Hint, İran', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema8Kolay),
  _aile('oz_cinema_8_orta', 'Asya sinemaları: Japon, Kore, Çin, Hint, İran', Topic.cinema, Difficulty.medium, BloomLevel.anlama, ozCinema8Orta),
  _aile('oz_cinema_8_zor', 'Asya sinemaları: Japon, Kore, Çin, Hint, İran', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema8Zor),
  _aile('oz_cinema_9_orta', 'Film türleri: western, film noir, bilimkurgu, korku, müzikal, komedi', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema9Orta),
  _aile('oz_cinema_9_kolay', 'Film türleri: western, film noir, bilimkurgu, korku, müzikal, komedi', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema9Kolay),
  _aile('oz_cinema_9_zor', 'Film türleri: western, film noir, bilimkurgu, korku, müzikal, komedi', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema9Zor),
  _aile('oz_cinema_10_zor', 'Yönetmenler ve auteur kuramı', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema10Zor),
  _aile('oz_cinema_10_orta', 'Yönetmenler ve auteur kuramı', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema10Orta),
  _aile('oz_cinema_10_kolay', 'Yönetmenler ve auteur kuramı', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema10Kolay),
  _aile('oz_cinema_11_kolay', 'Film müziği ve besteciler', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema11Kolay),
  _aile('oz_cinema_11_zor', 'Film müziği ve besteciler', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema11Zor),
  _aile('oz_cinema_11_orta', 'Film müziği ve besteciler', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema11Orta),
  _aile('oz_cinema_12_orta', 'Görsel efekt, animasyon teknikleri ve sinema teknolojisi', Topic.cinema, Difficulty.medium, BloomLevel.anlama, ozCinema12Orta),
  _aile('oz_cinema_12_kolay', 'Görsel efekt, animasyon teknikleri ve sinema teknolojisi', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema12Kolay),
  _aile('oz_cinema_12_zor', 'Görsel efekt, animasyon teknikleri ve sinema teknolojisi', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema12Zor),
  _aile('oz_cinema_13_orta', 'Televizyon dizileri tarihi ve yayıncılık terimleri', Topic.cinema, Difficulty.medium, BloomLevel.anlama, ozCinema13Orta),
  _aile('oz_cinema_13_zor', 'Televizyon dizileri tarihi ve yayıncılık terimleri', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema13Zor),
  _aile('oz_cinema_13_kolay', 'Televizyon dizileri tarihi ve yayıncılık terimleri', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema13Kolay),
  _aile('oz_cinema_14_kolay', 'Senaryo yazımı, karakter, yapı ve anlatı teknikleri', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema14Kolay),
  _aile('oz_cinema_14_orta', 'Senaryo yazımı, karakter, yapı ve anlatı teknikleri', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema14Orta),
  _aile('oz_cinema_14_zor', 'Senaryo yazımı, karakter, yapı ve anlatı teknikleri', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema14Zor),
  _aile('oz_language_6_kolay', 'İngilizce zamanlar ileri düzey ve karışık zaman kullanımı', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage6Kolay),
  _aile('oz_language_6_orta', 'İngilizce zamanlar ileri düzey ve karışık zaman kullanımı', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage6Orta),
  _aile('oz_language_6_zor', 'İngilizce zamanlar ileri düzey ve karışık zaman kullanımı', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage6Zor),
  _aile('oz_language_7_kolay', 'İngilizce bağlaçlar, edatlar ve cümle bağlantıları', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage7Kolay),
  _aile('oz_language_7_orta', 'İngilizce bağlaçlar, edatlar ve cümle bağlantıları', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage7Orta),
  _aile('oz_language_7_zor', 'İngilizce bağlaçlar, edatlar ve cümle bağlantıları', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage7Zor),
  _aile('oz_language_8_kolay', 'İngilizce kelime türetme: önek, sonek, aile sözcükleri', Topic.language, Difficulty.easy, BloomLevel.anlama, ozLanguage8Kolay),
  _aile('oz_language_8_orta', 'İngilizce kelime türetme: önek, sonek, aile sözcükleri', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage8Orta),
  _aile('oz_language_8_zor', 'İngilizce kelime türetme: önek, sonek, aile sözcükleri', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage8Zor),
  _aile('oz_language_9_kolay', 'İngilizce deyimler ve kalıp ifadeler', Topic.language, Difficulty.easy, BloomLevel.anlama, ozLanguage9Kolay),
  _aile('oz_language_9_orta', 'İngilizce deyimler ve kalıp ifadeler', Topic.language, Difficulty.medium, BloomLevel.anlama, ozLanguage9Orta),
  _aile('oz_language_9_zor', 'İngilizce deyimler ve kalıp ifadeler', Topic.language, Difficulty.hard, BloomLevel.anlama, ozLanguage9Zor),
  _aile('oz_language_10_orta', 'İngilizce diyalog tamamlama ve günlük iletişim', Topic.language, Difficulty.medium, BloomLevel.analiz, ozLanguage10Orta),
  _aile('oz_language_10_kolay', 'İngilizce diyalog tamamlama ve günlük iletişim', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage10Kolay),
  _aile('oz_language_10_zor', 'İngilizce diyalog tamamlama ve günlük iletişim', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage10Zor),
  _aile('oz_language_11_kolay', 'Almanca, Fransızca, İspanyolca temel sözcük ve ifadeler', Topic.language, Difficulty.easy, BloomLevel.hatirlama, ozLanguage11Kolay),
  _aile('oz_language_11_orta', 'Almanca, Fransızca, İspanyolca temel sözcük ve ifadeler', Topic.language, Difficulty.medium, BloomLevel.hatirlama, ozLanguage11Orta),
  _aile('oz_language_11_zor', 'Almanca, Fransızca, İspanyolca temel sözcük ve ifadeler', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage11Zor),
  _aile('oz_language_12_kolay', 'Dilbilim temel kavramları: ses bilgisi, anlam bilim, dil aileleri', Topic.language, Difficulty.easy, BloomLevel.hatirlama, ozLanguage12Kolay),
  _aile('oz_language_12_orta', 'Dilbilim temel kavramları: ses bilgisi, anlam bilim, dil aileleri', Topic.language, Difficulty.medium, BloomLevel.anlama, ozLanguage12Orta),
  _aile('oz_language_12_zor', 'Dilbilim temel kavramları: ses bilgisi, anlam bilim, dil aileleri', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage12Zor),
  _aile('oz_language_13_kolay', 'Türkçe dil bilgisi: ses olayları, yapı, sözcük türleri', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage13Kolay),
  _aile('oz_language_13_orta', 'Türkçe dil bilgisi: ses olayları, yapı, sözcük türleri', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage13Orta),
  _aile('oz_language_13_zor', 'Türkçe dil bilgisi: ses olayları, yapı, sözcük türleri', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage13Zor),
  _aile('oz_language_14_kolay', 'Türkçe yazım ve noktalama kuralları', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage14Kolay),
  _aile('oz_language_14_orta', 'Türkçe yazım ve noktalama kuralları', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage14Orta),
  _aile('oz_language_14_zor', 'Türkçe yazım ve noktalama kuralları', Topic.language, Difficulty.hard, BloomLevel.anlama, ozLanguage14Zor),
  _aile('oz_technology_6_orta', 'Mobil teknolojiler ve akıllı telefon donanımı', Topic.technology, Difficulty.medium, BloomLevel.hatirlama, ozTechnology6Orta),
  _aile('oz_technology_6_kolay', 'Mobil teknolojiler ve akıllı telefon donanımı', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology6Kolay),
  _aile('oz_technology_6_zor', 'Mobil teknolojiler ve akıllı telefon donanımı', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology6Zor),
  _aile('oz_technology_7_kolay', 'Bulut bilişim, veri merkezleri ve sanallaştırma', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology7Kolay),
  _aile('oz_technology_7_orta', 'Bulut bilişim, veri merkezleri ve sanallaştırma', Topic.technology, Difficulty.medium, BloomLevel.analiz, ozTechnology7Orta),
  _aile('oz_technology_7_zor', 'Bulut bilişim, veri merkezleri ve sanallaştırma', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology7Zor),
  _aile('oz_technology_8_kolay', 'Siber güvenlik saldırı ve savunma kavramları', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology8Kolay),
  _aile('oz_technology_8_orta', 'Siber güvenlik saldırı ve savunma kavramları', Topic.technology, Difficulty.medium, BloomLevel.hatirlama, ozTechnology8Orta),
  _aile('oz_technology_8_zor', 'Siber güvenlik saldırı ve savunma kavramları', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology8Zor),
  _aile('oz_technology_9_kolay', 'Yapay zekâ ve makine öğrenmesi kavramları', Topic.technology, Difficulty.easy, BloomLevel.anlama, ozTechnology9Kolay),
  _aile('oz_technology_9_orta', 'Yapay zekâ ve makine öğrenmesi kavramları', Topic.technology, Difficulty.medium, BloomLevel.hatirlama, ozTechnology9Orta),
  _aile('oz_technology_9_zor', 'Yapay zekâ ve makine öğrenmesi kavramları', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology9Zor),
  _aile('oz_technology_10_kolay', 'Robotik, sensörler ve otomasyon', Topic.technology, Difficulty.easy, BloomLevel.anlama, ozTechnology10Kolay),
  _aile('oz_technology_10_orta', 'Robotik, sensörler ve otomasyon', Topic.technology, Difficulty.medium, BloomLevel.hatirlama, ozTechnology10Orta),
  _aile('oz_technology_10_zor', 'Robotik, sensörler ve otomasyon', Topic.technology, Difficulty.hard, BloomLevel.hatirlama, ozTechnology10Zor),
  _aile('oz_technology_11_orta', 'Yenilenebilir enerji teknolojileri ve depolama', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology11Orta),
  _aile('oz_technology_11_kolay', 'Yenilenebilir enerji teknolojileri ve depolama', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology11Kolay),
  _aile('oz_technology_11_zor', 'Yenilenebilir enerji teknolojileri ve depolama', Topic.technology, Difficulty.hard, BloomLevel.uygulama, ozTechnology11Zor),
  _aile('oz_technology_12_kolay', 'Ulaşım teknolojileri: elektrikli araç, raylı sistem, havacılık', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology12Kolay),
  _aile('oz_technology_12_orta', 'Ulaşım teknolojileri: elektrikli araç, raylı sistem, havacılık', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology12Orta),
  _aile('oz_technology_12_zor', 'Ulaşım teknolojileri: elektrikli araç, raylı sistem, havacılık', Topic.technology, Difficulty.hard, BloomLevel.anlama, ozTechnology12Zor),
  _aile('oz_technology_13_orta', 'İletişim teknolojileri tarihi: telgraf, radyo, televizyon, uydu', Topic.technology, Difficulty.medium, BloomLevel.hatirlama, ozTechnology13Orta),
  _aile('oz_technology_13_zor', 'İletişim teknolojileri tarihi: telgraf, radyo, televizyon, uydu', Topic.technology, Difficulty.hard, BloomLevel.anlama, ozTechnology13Zor),
  _aile('oz_technology_13_kolay', 'İletişim teknolojileri tarihi: telgraf, radyo, televizyon, uydu', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology13Kolay),
  _aile('oz_technology_14_kolay', 'Tüketici elektroniği ve dijital medya formatları', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology14Kolay),
  _aile('oz_technology_14_orta', 'Tüketici elektroniği ve dijital medya formatları', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology14Orta),
  _aile('oz_technology_14_zor', 'Tüketici elektroniği ve dijital medya formatları', Topic.technology, Difficulty.hard, BloomLevel.anlama, ozTechnology14Zor),
  _aile('oz_literature_6_kolay', 'Divan edebiyatı nazım biçimleri ve şairleri ayrıntılı', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature6Kolay),
  _aile('oz_literature_6_orta', 'Divan edebiyatı nazım biçimleri ve şairleri ayrıntılı', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature6Orta),
  _aile('oz_literature_6_zor', 'Divan edebiyatı nazım biçimleri ve şairleri ayrıntılı', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature6Zor),
  _aile('oz_literature_7_orta', 'Halk edebiyatı: âşık, tekke, anonim halk edebiyatı ürünleri', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature7Orta),
  _aile('oz_literature_7_zor', 'Halk edebiyatı: âşık, tekke, anonim halk edebiyatı ürünleri', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature7Zor),
  _aile('oz_literature_7_kolay', 'Halk edebiyatı: âşık, tekke, anonim halk edebiyatı ürünleri', Topic.literature, Difficulty.easy, BloomLevel.anlama, ozLiterature7Kolay),
  _aile('oz_literature_8_orta', 'Cumhuriyet dönemi şiiri: topluluklar ve şairler', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature8Orta),
  _aile('oz_literature_8_zor', 'Cumhuriyet dönemi şiiri: topluluklar ve şairler', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature8Zor),
  _aile('oz_literature_8_kolay', 'Cumhuriyet dönemi şiiri: topluluklar ve şairler', Topic.literature, Difficulty.easy, BloomLevel.anlama, ozLiterature8Kolay),
  _aile('oz_literature_9_orta', 'Cumhuriyet dönemi roman ve hikâye', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature9Orta),
  _aile('oz_literature_9_zor', 'Cumhuriyet dönemi roman ve hikâye', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature9Zor),
  _aile('oz_literature_9_kolay', 'Cumhuriyet dönemi roman ve hikâye', Topic.literature, Difficulty.easy, BloomLevel.anlama, ozLiterature9Kolay),
  _aile('oz_literature_10_orta', 'Rus, Fransız ve İngiliz edebiyatı klasikleri', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature10Orta),
  _aile('oz_literature_10_zor', 'Rus, Fransız ve İngiliz edebiyatı klasikleri', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature10Zor),
  _aile('oz_literature_10_kolay', 'Rus, Fransız ve İngiliz edebiyatı klasikleri', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature10Kolay),
  _aile('oz_literature_11_kolay', 'Amerikan, Latin Amerika ve Alman edebiyatı', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature11Kolay),
  _aile('oz_literature_11_orta', 'Amerikan, Latin Amerika ve Alman edebiyatı', Topic.literature, Difficulty.medium, BloomLevel.anlama, ozLiterature11Orta),
  _aile('oz_literature_11_zor', 'Amerikan, Latin Amerika ve Alman edebiyatı', Topic.literature, Difficulty.hard, BloomLevel.anlama, ozLiterature11Zor),
  _aile('oz_literature_12_kolay', 'Antik ve Doğu edebiyatları: Homeros, Şehname, Hint ve Çin klasikleri', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature12Kolay),
  _aile('oz_literature_12_orta', 'Antik ve Doğu edebiyatları: Homeros, Şehname, Hint ve Çin klasikleri', Topic.literature, Difficulty.medium, BloomLevel.anlama, ozLiterature12Orta),
  _aile('oz_literature_12_zor', 'Antik ve Doğu edebiyatları: Homeros, Şehname, Hint ve Çin klasikleri', Topic.literature, Difficulty.hard, BloomLevel.anlama, ozLiterature12Zor),
  _aile('oz_literature_13_kolay', 'Çocuk edebiyatı, masallar ve gençlik klasikleri', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature13Kolay),
  _aile('oz_literature_13_orta', 'Çocuk edebiyatı, masallar ve gençlik klasikleri', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature13Orta),
  _aile('oz_literature_13_zor', 'Çocuk edebiyatı, masallar ve gençlik klasikleri', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature13Zor),
  _aile('oz_literature_14_kolay', 'Edebî terimler, anlatıcı, bakış açısı ve metin çözümleme', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature14Kolay),
  _aile('oz_literature_14_orta', 'Edebî terimler, anlatıcı, bakış açısı ve metin çözümleme', Topic.literature, Difficulty.medium, BloomLevel.uygulama, ozLiterature14Orta),
  _aile('oz_literature_14_zor', 'Edebî terimler, anlatıcı, bakış açısı ve metin çözümleme', Topic.literature, Difficulty.hard, BloomLevel.analiz, ozLiterature14Zor),
  _aile('oz_music_6_orta', 'Klasik dönem ve Romantik dönem besteciler ayrıntılı', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic6Orta),
  _aile('oz_music_6_zor', 'Klasik dönem ve Romantik dönem besteciler ayrıntılı', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic6Zor),
  _aile('oz_music_6_kolay', 'Klasik dönem ve Romantik dönem besteciler ayrıntılı', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic6Kolay),
  _aile('oz_music_7_kolay', '20. yüzyıl ve çağdaş Batı müziği', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic7Kolay),
  _aile('oz_music_7_orta', '20. yüzyıl ve çağdaş Batı müziği', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic7Orta),
  _aile('oz_music_7_zor', '20. yüzyıl ve çağdaş Batı müziği', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic7Zor),
  _aile('oz_music_8_orta', 'Caz tarihi ve terimleri', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic8Orta),
  _aile('oz_music_8_kolay', 'Caz tarihi ve terimleri', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic8Kolay),
  _aile('oz_music_8_zor', 'Caz tarihi ve terimleri', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic8Zor),
  _aile('oz_music_9_orta', 'Rock, pop ve elektronik müzik tarihi', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic9Orta),
  _aile('oz_music_9_kolay', 'Rock, pop ve elektronik müzik tarihi', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic9Kolay),
  _aile('oz_music_9_zor', 'Rock, pop ve elektronik müzik tarihi', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic9Zor),
  _aile('oz_music_10_orta', 'Türk sanat müziği besteciler ve formlar', Topic.music, Difficulty.medium, BloomLevel.analiz, ozMusic10Orta),
  _aile('oz_music_10_kolay', 'Türk sanat müziği besteciler ve formlar', Topic.music, Difficulty.easy, BloomLevel.uygulama, ozMusic10Kolay),
  _aile('oz_music_10_zor', 'Türk sanat müziği besteciler ve formlar', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic10Zor),
  _aile('oz_music_11_kolay', 'Türk halk müziği yöreler, çalgılar ve ozanlar', Topic.music, Difficulty.easy, BloomLevel.anlama, ozMusic11Kolay),
  _aile('oz_music_11_zor', 'Türk halk müziği yöreler, çalgılar ve ozanlar', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic11Zor),
  _aile('oz_music_11_orta', 'Türk halk müziği yöreler, çalgılar ve ozanlar', Topic.music, Difficulty.medium, BloomLevel.anlama, ozMusic11Orta),
  _aile('oz_music_12_kolay', 'Opera ve bale eserleri', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic12Kolay),
  _aile('oz_music_12_orta', 'Opera ve bale eserleri', Topic.music, Difficulty.medium, BloomLevel.anlama, ozMusic12Orta),
  _aile('oz_music_12_zor', 'Opera ve bale eserleri', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic12Zor),
  _aile('oz_music_13_kolay', 'Çalgı aileleri ve ses üretimi', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic13Kolay),
  _aile('oz_music_13_zor', 'Çalgı aileleri ve ses üretimi', Topic.music, Difficulty.hard, BloomLevel.analiz, ozMusic13Zor),
  _aile('oz_music_13_orta', 'Çalgı aileleri ve ses üretimi', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic13Orta),
  _aile('oz_music_14_kolay', 'Nota okuma, tempo, ölçü ve armoni hesapları', Topic.music, Difficulty.easy, BloomLevel.anlama, ozMusic14Kolay),
  _aile('oz_music_14_orta', 'Nota okuma, tempo, ölçü ve armoni hesapları', Topic.music, Difficulty.medium, BloomLevel.uygulama, ozMusic14Orta),
  _aile('oz_music_14_zor', 'Nota okuma, tempo, ölçü ve armoni hesapları', Topic.music, Difficulty.hard, BloomLevel.uygulama, ozMusic14Zor),
  _aile('oz_nature_6_kolay', 'Memeliler ayrıntılı', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature6Kolay),
  _aile('oz_nature_6_orta', 'Memeliler ayrıntılı', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature6Orta),
  _aile('oz_nature_6_zor', 'Memeliler ayrıntılı', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature6Zor),
  _aile('oz_nature_7_kolay', 'Kuşlar: göç, davranış, Türkiye kuşları', Topic.nature, Difficulty.easy, BloomLevel.anlama, ozNature7Kolay),
  _aile('oz_nature_7_orta', 'Kuşlar: göç, davranış, Türkiye kuşları', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature7Orta),
  _aile('oz_nature_7_zor', 'Kuşlar: göç, davranış, Türkiye kuşları', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature7Zor),
  _aile('oz_nature_8_kolay', 'Böcekler ve diğer omurgasızlar', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature8Kolay),
  _aile('oz_nature_8_orta', 'Böcekler ve diğer omurgasızlar', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature8Orta),
  _aile('oz_nature_8_zor', 'Böcekler ve diğer omurgasızlar', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature8Zor),
  _aile('oz_nature_9_orta', 'Deniz canlıları ve mercan resifleri', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature9Orta),
  _aile('oz_nature_9_zor', 'Deniz canlıları ve mercan resifleri', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature9Zor),
  _aile('oz_nature_9_kolay', 'Deniz canlıları ve mercan resifleri', Topic.nature, Difficulty.easy, BloomLevel.anlama, ozNature9Kolay),
  _aile('oz_nature_10_kolay', 'Sürüngenler ve amfibiler', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature10Kolay),
  _aile('oz_nature_10_orta', 'Sürüngenler ve amfibiler', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature10Orta),
  _aile('oz_nature_10_zor', 'Sürüngenler ve amfibiler', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature10Zor),
  _aile('oz_nature_11_kolay', 'Mantarlar, likenler ve mikroskobik canlılar', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature11Kolay),
  _aile('oz_nature_11_orta', 'Mantarlar, likenler ve mikroskobik canlılar', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature11Orta),
  _aile('oz_nature_11_zor', 'Mantarlar, likenler ve mikroskobik canlılar', Topic.nature, Difficulty.hard, BloomLevel.anlama, ozNature11Zor),
  _aile('oz_nature_12_orta', 'Tıbbi ve aromatik bitkiler, tarım bitkileri', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature12Orta),
  _aile('oz_nature_12_kolay', 'Tıbbi ve aromatik bitkiler, tarım bitkileri', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature12Kolay),
  _aile('oz_nature_12_zor', 'Tıbbi ve aromatik bitkiler, tarım bitkileri', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature12Zor),
  _aile('oz_nature_13_kolay', 'Koruma biyolojisi, nesli tükenen türler ve millî parklar', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature13Kolay),
  _aile('oz_nature_13_zor', 'Koruma biyolojisi, nesli tükenen türler ve millî parklar', Topic.nature, Difficulty.hard, BloomLevel.analiz, ozNature13Zor),
  _aile('oz_nature_13_orta', 'Koruma biyolojisi, nesli tükenen türler ve millî parklar', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature13Orta),
  _aile('oz_nature_14_zor', 'Doğa gözlemi, mevsimler, iz sürme ve doğada güvenlik', Topic.nature, Difficulty.hard, BloomLevel.analiz, ozNature14Zor),
  _aile('oz_nature_14_kolay', 'Doğa gözlemi, mevsimler, iz sürme ve doğada güvenlik', Topic.nature, Difficulty.easy, BloomLevel.anlama, ozNature14Kolay),
  _aile('oz_nature_14_orta', 'Doğa gözlemi, mevsimler, iz sürme ve doğada güvenlik', Topic.nature, Difficulty.medium, BloomLevel.uygulama, ozNature14Orta),
  _aile('oz_exam_6_kolay', 'TYT Türkçe: dil bilgisi', Topic.exam, Difficulty.easy, BloomLevel.analiz, ozExam6Kolay),
  _aile('oz_exam_6_orta', 'TYT Türkçe: dil bilgisi', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam6Orta),
  _aile('oz_exam_6_zor', 'TYT Türkçe: dil bilgisi', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam6Zor),
  _aile('oz_exam_7_orta', 'TYT Türkçe: yazım ve noktalama uygulamaları', Topic.exam, Difficulty.medium, BloomLevel.uygulama, ozExam7Orta),
  _aile('oz_exam_7_kolay', 'TYT Türkçe: yazım ve noktalama uygulamaları', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam7Kolay),
  _aile('oz_exam_7_zor', 'TYT Türkçe: yazım ve noktalama uygulamaları', Topic.exam, Difficulty.hard, BloomLevel.uygulama, ozExam7Zor),
  _aile('oz_exam_8_kolay', 'TYT Türkçe: anlatım bozukluğu ve cümle türleri', Topic.exam, Difficulty.easy, BloomLevel.analiz, ozExam8Kolay),
  _aile('oz_exam_8_orta', 'TYT Türkçe: anlatım bozukluğu ve cümle türleri', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam8Orta),
  _aile('oz_exam_8_zor', 'TYT Türkçe: anlatım bozukluğu ve cümle türleri', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam8Zor),
  _aile('oz_exam_9_zor', 'TYT Matematik: temel kavramlar ve sayı problemleri', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam9Zor),
  _aile('oz_exam_9_orta', 'TYT Matematik: temel kavramlar ve sayı problemleri', Topic.exam, Difficulty.medium, BloomLevel.uygulama, ozExam9Orta),
  _aile('oz_exam_9_kolay', 'TYT Matematik: temel kavramlar ve sayı problemleri', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam9Kolay),
  _aile('oz_exam_10_kolay', 'TYT Matematik: yüzde, kâr-zarar, karışım, hareket problemleri', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam10Kolay),
  _aile('oz_exam_10_orta', 'TYT Matematik: yüzde, kâr-zarar, karışım, hareket problemleri', Topic.exam, Difficulty.medium, BloomLevel.uygulama, ozExam10Orta),
  _aile('oz_exam_10_zor', 'TYT Matematik: yüzde, kâr-zarar, karışım, hareket problemleri', Topic.exam, Difficulty.hard, BloomLevel.uygulama, ozExam10Zor),
  _aile('oz_exam_11_orta', 'TYT Geometri: açılar, üçgenler, alan problemleri', Topic.exam, Difficulty.medium, BloomLevel.uygulama, ozExam11Orta),
  _aile('oz_exam_11_kolay', 'TYT Geometri: açılar, üçgenler, alan problemleri', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam11Kolay),
  _aile('oz_exam_11_zor', 'TYT Geometri: açılar, üçgenler, alan problemleri', Topic.exam, Difficulty.hard, BloomLevel.uygulama, ozExam11Zor),
  _aile('oz_exam_12_kolay', 'TYT Fen: fizik-kimya-biyoloji karma temel sorular', Topic.exam, Difficulty.easy, BloomLevel.anlama, ozExam12Kolay),
  _aile('oz_exam_12_orta', 'TYT Fen: fizik-kimya-biyoloji karma temel sorular', Topic.exam, Difficulty.medium, BloomLevel.anlama, ozExam12Orta),
  _aile('oz_exam_12_zor', 'TYT Fen: fizik-kimya-biyoloji karma temel sorular', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam12Zor),
  _aile('oz_exam_13_kolay', 'TYT Sosyal: tarih-coğrafya-felsefe karma temel sorular', Topic.exam, Difficulty.easy, BloomLevel.hatirlama, ozExam13Kolay),
  _aile('oz_exam_13_orta', 'TYT Sosyal: tarih-coğrafya-felsefe karma temel sorular', Topic.exam, Difficulty.medium, BloomLevel.anlama, ozExam13Orta),
  _aile('oz_exam_13_zor', 'TYT Sosyal: tarih-coğrafya-felsefe karma temel sorular', Topic.exam, Difficulty.hard, BloomLevel.anlama, ozExam13Zor),
  _aile('oz_exam_14_kolay', 'Mantık-muhakeme: tablo, şifre, örüntü ve sayı dizileri', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam14Kolay),
  _aile('oz_exam_14_orta', 'Mantık-muhakeme: tablo, şifre, örüntü ve sayı dizileri', Topic.exam, Difficulty.medium, BloomLevel.uygulama, ozExam14Orta),
  _aile('oz_exam_14_zor', 'Mantık-muhakeme: tablo, şifre, örüntü ve sayı dizileri', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam14Zor),
  _aile('oz_mathematics_6_kolay', 'Kümeler ve mantık', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics6Kolay),
  _aile('oz_mathematics_6_orta', 'Kümeler ve mantık', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics6Orta),
  _aile('oz_mathematics_6_zor', 'Kümeler ve mantık', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics6Zor),
  _aile('oz_mathematics_7_kolay', 'Fonksiyonlar ve grafik yorumu', Topic.mathematics, Difficulty.easy, BloomLevel.anlama, ozMathematics7Kolay),
  _aile('oz_mathematics_7_orta', 'Fonksiyonlar ve grafik yorumu', Topic.mathematics, Difficulty.medium, BloomLevel.analiz, ozMathematics7Orta),
  _aile('oz_mathematics_7_zor', 'Fonksiyonlar ve grafik yorumu', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics7Zor),
  _aile('oz_mathematics_8_kolay', 'Polinomlar ve çarpanlara ayırma', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics8Kolay),
  _aile('oz_mathematics_8_orta', 'Polinomlar ve çarpanlara ayırma', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics8Orta),
  _aile('oz_mathematics_8_zor', 'Polinomlar ve çarpanlara ayırma', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics8Zor),
  _aile('oz_mathematics_9_kolay', 'İkinci dereceden denklemler ve eşitsizlikler', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics9Kolay),
  _aile('oz_mathematics_9_orta', 'İkinci dereceden denklemler ve eşitsizlikler', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics9Orta),
  _aile('oz_mathematics_9_zor', 'İkinci dereceden denklemler ve eşitsizlikler', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics9Zor),
  _aile('oz_mathematics_10_kolay', 'Trigonometri', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics10Kolay),
  _aile('oz_mathematics_10_orta', 'Trigonometri', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics10Orta),
  _aile('oz_mathematics_10_zor', 'Trigonometri', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics10Zor),
  _aile('oz_mathematics_11_kolay', 'Analitik geometri: doğru, çember, uzaklık', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics11Kolay),
  _aile('oz_mathematics_11_orta', 'Analitik geometri: doğru, çember, uzaklık', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics11Orta),
  _aile('oz_mathematics_11_zor', 'Analitik geometri: doğru, çember, uzaklık', Topic.mathematics, Difficulty.hard, BloomLevel.uygulama, ozMathematics11Zor),
  _aile('oz_mathematics_12_kolay', 'Diziler ve seriler', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics12Kolay),
  _aile('oz_mathematics_12_orta', 'Diziler ve seriler', Topic.mathematics, Difficulty.medium, BloomLevel.analiz, ozMathematics12Orta),
  _aile('oz_mathematics_12_zor', 'Diziler ve seriler', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics12Zor),
  _aile('oz_mathematics_13_kolay', 'Limit, türev ve integrale giriş', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics13Kolay),
  _aile('oz_mathematics_13_orta', 'Limit, türev ve integrale giriş', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics13Orta),
  _aile('oz_mathematics_13_zor', 'Limit, türev ve integrale giriş', Topic.mathematics, Difficulty.hard, BloomLevel.uygulama, ozMathematics13Zor),
  _aile('oz_mathematics_14_kolay', 'Sayma, olasılık ve kombinatorik problemleri', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics14Kolay),
  _aile('oz_mathematics_14_orta', 'Sayma, olasılık ve kombinatorik problemleri', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics14Orta),
  _aile('oz_mathematics_14_zor', 'Sayma, olasılık ve kombinatorik problemleri', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics14Zor),
  _aile('oz_physics_6_kolay', 'Kinematik ve vektörler ayrıntılı', Topic.physics, Difficulty.easy, BloomLevel.uygulama, ozPhysics6Kolay),
  _aile('oz_physics_6_orta', 'Kinematik ve vektörler ayrıntılı', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics6Orta),
  _aile('oz_physics_6_zor', 'Kinematik ve vektörler ayrıntılı', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics6Zor),
  _aile('oz_physics_7_kolay', 'Dinamik, sürtünme ve dairesel hareket', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics7Kolay),
  _aile('oz_physics_7_orta', 'Dinamik, sürtünme ve dairesel hareket', Topic.physics, Difficulty.medium, BloomLevel.analiz, ozPhysics7Orta),
  _aile('oz_physics_7_zor', 'Dinamik, sürtünme ve dairesel hareket', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics7Zor),
  _aile('oz_physics_8_kolay', 'İş, enerji, güç ve momentum hesapları', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics8Kolay),
  _aile('oz_physics_8_orta', 'İş, enerji, güç ve momentum hesapları', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics8Orta),
  _aile('oz_physics_8_zor', 'İş, enerji, güç ve momentum hesapları', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics8Zor),
  _aile('oz_physics_9_kolay', 'Basınç, kaldırma kuvveti ve akışkanlar', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics9Kolay),
  _aile('oz_physics_9_orta', 'Basınç, kaldırma kuvveti ve akışkanlar', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics9Orta),
  _aile('oz_physics_9_zor', 'Basınç, kaldırma kuvveti ve akışkanlar', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics9Zor),
  _aile('oz_physics_10_orta', 'Isı ve sıcaklık, genleşme, hal değişimi', Topic.physics, Difficulty.medium, BloomLevel.analiz, ozPhysics10Orta),
  _aile('oz_physics_10_zor', 'Isı ve sıcaklık, genleşme, hal değişimi', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics10Zor),
  _aile('oz_physics_10_kolay', 'Isı ve sıcaklık, genleşme, hal değişimi', Topic.physics, Difficulty.easy, BloomLevel.uygulama, ozPhysics10Kolay),
  _aile('oz_physics_11_kolay', 'Elektrik devreleri ve elektrik enerjisi hesapları', Topic.physics, Difficulty.easy, BloomLevel.uygulama, ozPhysics11Kolay),
  _aile('oz_physics_11_orta', 'Elektrik devreleri ve elektrik enerjisi hesapları', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics11Orta),
  _aile('oz_physics_11_zor', 'Elektrik devreleri ve elektrik enerjisi hesapları', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics11Zor),
  _aile('oz_physics_12_kolay', 'Manyetizma ve elektromanyetik indüksiyon', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics12Kolay),
  _aile('oz_physics_12_orta', 'Manyetizma ve elektromanyetik indüksiyon', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics12Orta),
  _aile('oz_physics_12_zor', 'Manyetizma ve elektromanyetik indüksiyon', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics12Zor),
  _aile('oz_physics_13_kolay', 'Dalgalar, ses ve optik hesapları', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics13Kolay),
  _aile('oz_physics_13_orta', 'Dalgalar, ses ve optik hesapları', Topic.physics, Difficulty.medium, BloomLevel.anlama, ozPhysics13Orta),
  _aile('oz_physics_13_zor', 'Dalgalar, ses ve optik hesapları', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics13Zor),
  _aile('oz_physics_14_orta', 'Modern fizik: atom, çekirdek, kuantum, görelilik', Topic.physics, Difficulty.medium, BloomLevel.anlama, ozPhysics14Orta),
  _aile('oz_physics_14_zor', 'Modern fizik: atom, çekirdek, kuantum, görelilik', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics14Zor),
  _aile('oz_physics_14_kolay', 'Modern fizik: atom, çekirdek, kuantum, görelilik', Topic.physics, Difficulty.easy, BloomLevel.hatirlama, ozPhysics14Kolay),
  _aile('oz_chemistry_6_kolay', 'Atom modelleri ve elektron dizilimi', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry6Kolay),
  _aile('oz_chemistry_6_orta', 'Atom modelleri ve elektron dizilimi', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry6Orta),
  _aile('oz_chemistry_6_zor', 'Atom modelleri ve elektron dizilimi', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry6Zor),
  _aile('oz_chemistry_7_kolay', 'Periyodik özellikler ve elementler ayrıntılı', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry7Kolay),
  _aile('oz_chemistry_7_orta', 'Periyodik özellikler ve elementler ayrıntılı', Topic.chemistry, Difficulty.medium, BloomLevel.hatirlama, ozChemistry7Orta),
  _aile('oz_chemistry_7_zor', 'Periyodik özellikler ve elementler ayrıntılı', Topic.chemistry, Difficulty.hard, BloomLevel.hatirlama, ozChemistry7Zor),
  _aile('oz_chemistry_8_kolay', 'Kimyasal bağlar ve moleküller arası etkileşimler', Topic.chemistry, Difficulty.easy, BloomLevel.uygulama, ozChemistry8Kolay),
  _aile('oz_chemistry_8_orta', 'Kimyasal bağlar ve moleküller arası etkileşimler', Topic.chemistry, Difficulty.medium, BloomLevel.analiz, ozChemistry8Orta),
  _aile('oz_chemistry_8_zor', 'Kimyasal bağlar ve moleküller arası etkileşimler', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry8Zor),
  _aile('oz_chemistry_9_orta', 'Mol kavramı ve kimyasal hesaplamalar', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry9Orta),
  _aile('oz_chemistry_9_zor', 'Mol kavramı ve kimyasal hesaplamalar', Topic.chemistry, Difficulty.hard, BloomLevel.uygulama, ozChemistry9Zor),
  _aile('oz_chemistry_9_kolay', 'Mol kavramı ve kimyasal hesaplamalar', Topic.chemistry, Difficulty.easy, BloomLevel.uygulama, ozChemistry9Kolay),
  _aile('oz_chemistry_10_kolay', 'Gazlar ve gaz yasaları hesapları', Topic.chemistry, Difficulty.easy, BloomLevel.anlama, ozChemistry10Kolay),
  _aile('oz_chemistry_10_orta', 'Gazlar ve gaz yasaları hesapları', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry10Orta),
  _aile('oz_chemistry_10_zor', 'Gazlar ve gaz yasaları hesapları', Topic.chemistry, Difficulty.hard, BloomLevel.uygulama, ozChemistry10Zor),
  _aile('oz_chemistry_11_kolay', 'Çözeltiler, derişim ve koligatif özellikler', Topic.chemistry, Difficulty.easy, BloomLevel.uygulama, ozChemistry11Kolay),
  _aile('oz_chemistry_11_orta', 'Çözeltiler, derişim ve koligatif özellikler', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry11Orta),
  _aile('oz_chemistry_11_zor', 'Çözeltiler, derişim ve koligatif özellikler', Topic.chemistry, Difficulty.hard, BloomLevel.uygulama, ozChemistry11Zor),
  _aile('oz_chemistry_12_kolay', 'Asitler, bazlar, tuzlar ve pH', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry12Kolay),
  _aile('oz_chemistry_12_orta', 'Asitler, bazlar, tuzlar ve pH', Topic.chemistry, Difficulty.medium, BloomLevel.anlama, ozChemistry12Orta),
  _aile('oz_chemistry_12_zor', 'Asitler, bazlar, tuzlar ve pH', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry12Zor),
  _aile('oz_chemistry_13_kolay', 'Tepkime hızı, denge ve enerji', Topic.chemistry, Difficulty.easy, BloomLevel.uygulama, ozChemistry13Kolay),
  _aile('oz_chemistry_13_orta', 'Tepkime hızı, denge ve enerji', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry13Orta),
  _aile('oz_chemistry_13_zor', 'Tepkime hızı, denge ve enerji', Topic.chemistry, Difficulty.hard, BloomLevel.uygulama, ozChemistry13Zor),
  _aile('oz_chemistry_14_kolay', 'Organik bileşikler, fonksiyonel gruplar ve polimerler', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry14Kolay),
  _aile('oz_chemistry_14_zor', 'Organik bileşikler, fonksiyonel gruplar ve polimerler', Topic.chemistry, Difficulty.hard, BloomLevel.uygulama, ozChemistry14Zor),
  _aile('oz_chemistry_14_orta', 'Organik bileşikler, fonksiyonel gruplar ve polimerler', Topic.chemistry, Difficulty.medium, BloomLevel.hatirlama, ozChemistry14Orta),
  _aile('oz_biology_6_kolay', 'Hücre organelleri ve zar taşıma ayrıntılı', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology6Kolay),
  _aile('oz_biology_6_orta', 'Hücre organelleri ve zar taşıma ayrıntılı', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology6Orta),
  _aile('oz_biology_6_zor', 'Hücre organelleri ve zar taşıma ayrıntılı', Topic.biology, Difficulty.hard, BloomLevel.hatirlama, ozBiology6Zor),
  _aile('oz_biology_7_kolay', 'Enzimler, metabolizma, fotosentez ve solunum', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology7Kolay),
  _aile('oz_biology_7_orta', 'Enzimler, metabolizma, fotosentez ve solunum', Topic.biology, Difficulty.medium, BloomLevel.hatirlama, ozBiology7Orta),
  _aile('oz_biology_7_zor', 'Enzimler, metabolizma, fotosentez ve solunum', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology7Zor),
  _aile('oz_biology_8_zor', 'Mitoz, mayoz ve üreme', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology8Zor),
  _aile('oz_biology_8_kolay', 'Mitoz, mayoz ve üreme', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology8Kolay),
  _aile('oz_biology_8_orta', 'Mitoz, mayoz ve üreme', Topic.biology, Difficulty.medium, BloomLevel.hatirlama, ozBiology8Orta),
  _aile('oz_biology_9_orta', 'Mendel genetiği ve kalıtım problemleri', Topic.biology, Difficulty.medium, BloomLevel.uygulama, ozBiology9Orta),
  _aile('oz_biology_9_kolay', 'Mendel genetiği ve kalıtım problemleri', Topic.biology, Difficulty.easy, BloomLevel.uygulama, ozBiology9Kolay),
  _aile('oz_biology_9_zor', 'Mendel genetiği ve kalıtım problemleri', Topic.biology, Difficulty.hard, BloomLevel.uygulama, ozBiology9Zor),
  _aile('oz_biology_10_kolay', 'DNA, gen ifadesi ve biyoteknoloji', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology10Kolay),
  _aile('oz_biology_10_orta', 'DNA, gen ifadesi ve biyoteknoloji', Topic.biology, Difficulty.medium, BloomLevel.hatirlama, ozBiology10Orta),
  _aile('oz_biology_10_zor', 'DNA, gen ifadesi ve biyoteknoloji', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology10Zor),
  _aile('oz_biology_11_kolay', 'Sindirim, dolaşım ve solunum sistemleri', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology11Kolay),
  _aile('oz_biology_11_orta', 'Sindirim, dolaşım ve solunum sistemleri', Topic.biology, Difficulty.medium, BloomLevel.analiz, ozBiology11Orta),
  _aile('oz_biology_11_zor', 'Sindirim, dolaşım ve solunum sistemleri', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology11Zor),
  _aile('oz_biology_12_kolay', 'Sinir, endokrin ve duyu sistemleri', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology12Kolay),
  _aile('oz_biology_12_orta', 'Sinir, endokrin ve duyu sistemleri', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology12Orta),
  _aile('oz_biology_12_zor', 'Sinir, endokrin ve duyu sistemleri', Topic.biology, Difficulty.hard, BloomLevel.uygulama, ozBiology12Zor),
  _aile('oz_biology_13_kolay', 'Boşaltım, destek-hareket ve bağışıklık sistemleri', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology13Kolay),
  _aile('oz_biology_13_orta', 'Boşaltım, destek-hareket ve bağışıklık sistemleri', Topic.biology, Difficulty.medium, BloomLevel.analiz, ozBiology13Orta),
  _aile('oz_biology_13_zor', 'Boşaltım, destek-hareket ve bağışıklık sistemleri', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology13Zor),
  _aile('oz_biology_14_kolay', 'Ekoloji, popülasyon ve komünite', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology14Kolay),
  _aile('oz_biology_14_orta', 'Ekoloji, popülasyon ve komünite', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology14Orta),
  _aile('oz_biology_14_zor', 'Ekoloji, popülasyon ve komünite', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology14Zor),
  _aile('oz_engineering_6_kolay', 'Statik ve mukavemet temel kavramları', Topic.engineering, Difficulty.easy, BloomLevel.anlama, ozEngineering6Kolay),
  _aile('oz_engineering_6_orta', 'Statik ve mukavemet temel kavramları', Topic.engineering, Difficulty.medium, BloomLevel.uygulama, ozEngineering6Orta),
  _aile('oz_engineering_6_zor', 'Statik ve mukavemet temel kavramları', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering6Zor),
  _aile('oz_engineering_7_kolay', 'Akışkanlar mekaniği ve hidrolik', Topic.engineering, Difficulty.easy, BloomLevel.anlama, ozEngineering7Kolay),
  _aile('oz_engineering_7_orta', 'Akışkanlar mekaniği ve hidrolik', Topic.engineering, Difficulty.medium, BloomLevel.analiz, ozEngineering7Orta),
  _aile('oz_engineering_7_zor', 'Akışkanlar mekaniği ve hidrolik', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering7Zor),
  _aile('oz_engineering_8_kolay', 'Termodinamik ve ısı makineleri', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering8Kolay),
  _aile('oz_engineering_8_orta', 'Termodinamik ve ısı makineleri', Topic.engineering, Difficulty.medium, BloomLevel.hatirlama, ozEngineering8Orta),
  _aile('oz_engineering_8_zor', 'Termodinamik ve ısı makineleri', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering8Zor),
  _aile('oz_engineering_9_orta', 'Elektronik devre elemanları ve sayısal mantık', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering9Orta),
  _aile('oz_engineering_9_kolay', 'Elektronik devre elemanları ve sayısal mantık', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering9Kolay),
  _aile('oz_engineering_9_zor', 'Elektronik devre elemanları ve sayısal mantık', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering9Zor),
  _aile('oz_engineering_10_kolay', 'Malzeme bilimi ve malzeme seçimi', Topic.engineering, Difficulty.easy, BloomLevel.anlama, ozEngineering10Kolay),
  _aile('oz_engineering_10_orta', 'Malzeme bilimi ve malzeme seçimi', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering10Orta),
  _aile('oz_engineering_10_zor', 'Malzeme bilimi ve malzeme seçimi', Topic.engineering, Difficulty.hard, BloomLevel.hatirlama, ozEngineering10Zor),
  _aile('oz_engineering_11_kolay', 'Üretim yöntemleri ve imalat', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering11Kolay),
  _aile('oz_engineering_11_orta', 'Üretim yöntemleri ve imalat', Topic.engineering, Difficulty.medium, BloomLevel.hatirlama, ozEngineering11Orta),
  _aile('oz_engineering_11_zor', 'Üretim yöntemleri ve imalat', Topic.engineering, Difficulty.hard, BloomLevel.hatirlama, ozEngineering11Zor),
  _aile('oz_engineering_12_kolay', 'Kontrol sistemleri ve mekatronik', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering12Kolay),
  _aile('oz_engineering_12_orta', 'Kontrol sistemleri ve mekatronik', Topic.engineering, Difficulty.medium, BloomLevel.uygulama, ozEngineering12Orta),
  _aile('oz_engineering_12_zor', 'Kontrol sistemleri ve mekatronik', Topic.engineering, Difficulty.hard, BloomLevel.uygulama, ozEngineering12Zor),
  _aile('oz_engineering_13_kolay', 'Proje yönetimi, kalite ve güvenlik mühendisliği', Topic.engineering, Difficulty.easy, BloomLevel.anlama, ozEngineering13Kolay),
  _aile('oz_engineering_13_orta', 'Proje yönetimi, kalite ve güvenlik mühendisliği', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering13Orta),
  _aile('oz_engineering_13_zor', 'Proje yönetimi, kalite ve güvenlik mühendisliği', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering13Zor),
  _aile('oz_engineering_14_kolay', 'Ünlü mühendislik başarıları ve mühendisler', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering14Kolay),
  _aile('oz_engineering_14_orta', 'Ünlü mühendislik başarıları ve mühendisler', Topic.engineering, Difficulty.medium, BloomLevel.hatirlama, ozEngineering14Orta),
  _aile('oz_engineering_14_zor', 'Ünlü mühendislik başarıları ve mühendisler', Topic.engineering, Difficulty.hard, BloomLevel.hatirlama, ozEngineering14Zor),
  _aile('oz_computing_6_orta', 'Algoritma analizi ve karmaşıklık', Topic.computing, Difficulty.medium, BloomLevel.hatirlama, ozComputing6Orta),
  _aile('oz_computing_6_kolay', 'Algoritma analizi ve karmaşıklık', Topic.computing, Difficulty.easy, BloomLevel.uygulama, ozComputing6Kolay),
  _aile('oz_computing_6_zor', 'Algoritma analizi ve karmaşıklık', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing6Zor),
  _aile('oz_computing_7_orta', 'Sıralama ve arama algoritmaları uygulamalı', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing7Orta),
  _aile('oz_computing_7_kolay', 'Sıralama ve arama algoritmaları uygulamalı', Topic.computing, Difficulty.easy, BloomLevel.anlama, ozComputing7Kolay),
  _aile('oz_computing_7_zor', 'Sıralama ve arama algoritmaları uygulamalı', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing7Zor),
  _aile('oz_computing_8_kolay', 'Veri yapıları: yığın, kuyruk, ağaç, graf uygulamalı', Topic.computing, Difficulty.easy, BloomLevel.uygulama, ozComputing8Kolay),
  _aile('oz_computing_8_orta', 'Veri yapıları: yığın, kuyruk, ağaç, graf uygulamalı', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing8Orta),
  _aile('oz_computing_8_zor', 'Veri yapıları: yığın, kuyruk, ağaç, graf uygulamalı', Topic.computing, Difficulty.hard, BloomLevel.uygulama, ozComputing8Zor),
  _aile('oz_computing_9_orta', 'Nesne yönelimli programlama kavramları', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing9Orta),
  _aile('oz_computing_9_kolay', 'Nesne yönelimli programlama kavramları', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing9Kolay),
  _aile('oz_computing_9_zor', 'Nesne yönelimli programlama kavramları', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing9Zor),
  _aile('oz_computing_10_kolay', 'Veritabanı ve SQL sorguları', Topic.computing, Difficulty.easy, BloomLevel.uygulama, ozComputing10Kolay),
  _aile('oz_computing_10_orta', 'Veritabanı ve SQL sorguları', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing10Orta),
  _aile('oz_computing_10_zor', 'Veritabanı ve SQL sorguları', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing10Zor),
  _aile('oz_computing_11_kolay', 'Bilgisayar ağları ve protokoller', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing11Kolay),
  _aile('oz_computing_11_orta', 'Bilgisayar ağları ve protokoller', Topic.computing, Difficulty.medium, BloomLevel.hatirlama, ozComputing11Orta),
  _aile('oz_computing_11_zor', 'Bilgisayar ağları ve protokoller', Topic.computing, Difficulty.hard, BloomLevel.hatirlama, ozComputing11Zor),
  _aile('oz_computing_12_kolay', 'İşletim sistemleri kavramları', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing12Kolay),
  _aile('oz_computing_12_orta', 'İşletim sistemleri kavramları', Topic.computing, Difficulty.medium, BloomLevel.anlama, ozComputing12Orta),
  _aile('oz_computing_12_zor', 'İşletim sistemleri kavramları', Topic.computing, Difficulty.hard, BloomLevel.uygulama, ozComputing12Zor),
  _aile('oz_computing_13_kolay', 'Yazılım mühendisliği süreçleri ve test', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing13Kolay),
  _aile('oz_computing_13_orta', 'Yazılım mühendisliği süreçleri ve test', Topic.computing, Difficulty.medium, BloomLevel.hatirlama, ozComputing13Orta),
  _aile('oz_computing_13_zor', 'Yazılım mühendisliği süreçleri ve test', Topic.computing, Difficulty.hard, BloomLevel.hatirlama, ozComputing13Zor),
  _aile('oz_computing_14_kolay', 'Bilgisayar bilimi tarihi ve öncüleri', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing14Kolay),
  _aile('oz_computing_14_orta', 'Bilgisayar bilimi tarihi ve öncüleri', Topic.computing, Difficulty.medium, BloomLevel.hatirlama, ozComputing14Orta),
  _aile('oz_computing_14_zor', 'Bilgisayar bilimi tarihi ve öncüleri', Topic.computing, Difficulty.hard, BloomLevel.anlama, ozComputing14Zor),
  _aile('oz_statistics_6_orta', 'Tanımlayıcı istatistik hesapları', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics6Orta),
  _aile('oz_statistics_6_zor', 'Tanımlayıcı istatistik hesapları', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics6Zor),
  _aile('oz_statistics_6_kolay', 'Tanımlayıcı istatistik hesapları', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics6Kolay),
  _aile('oz_statistics_7_orta', 'Olasılık hesapları ve koşullu olasılık', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics7Orta),
  _aile('oz_statistics_7_kolay', 'Olasılık hesapları ve koşullu olasılık', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics7Kolay),
  _aile('oz_statistics_7_zor', 'Olasılık hesapları ve koşullu olasılık', Topic.statistics, Difficulty.hard, BloomLevel.uygulama, ozStatistics7Zor),
  _aile('oz_statistics_8_zor', 'Olasılık dağılımları: binom, normal, Poisson', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics8Zor),
  _aile('oz_statistics_8_kolay', 'Olasılık dağılımları: binom, normal, Poisson', Topic.statistics, Difficulty.easy, BloomLevel.anlama, ozStatistics8Kolay),
  _aile('oz_statistics_8_orta', 'Olasılık dağılımları: binom, normal, Poisson', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics8Orta),
  _aile('oz_statistics_9_kolay', 'Örnekleme ve tahmin, güven aralığı', Topic.statistics, Difficulty.easy, BloomLevel.anlama, ozStatistics9Kolay),
  _aile('oz_statistics_9_orta', 'Örnekleme ve tahmin, güven aralığı', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics9Orta),
  _aile('oz_statistics_9_zor', 'Örnekleme ve tahmin, güven aralığı', Topic.statistics, Difficulty.hard, BloomLevel.uygulama, ozStatistics9Zor),
  _aile('oz_statistics_10_kolay', 'Hipotez testleri kavramları', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics10Kolay),
  _aile('oz_statistics_10_orta', 'Hipotez testleri kavramları', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics10Orta),
  _aile('oz_statistics_10_zor', 'Hipotez testleri kavramları', Topic.statistics, Difficulty.hard, BloomLevel.anlama, ozStatistics10Zor),
  _aile('oz_statistics_11_orta', 'Korelasyon ve regresyon', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics11Orta),
  _aile('oz_statistics_11_kolay', 'Korelasyon ve regresyon', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics11Kolay),
  _aile('oz_statistics_11_zor', 'Korelasyon ve regresyon', Topic.statistics, Difficulty.hard, BloomLevel.uygulama, ozStatistics11Zor),
  _aile('oz_statistics_12_kolay', 'Veri görselleştirme ve grafik seçimi', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics12Kolay),
  _aile('oz_statistics_12_orta', 'Veri görselleştirme ve grafik seçimi', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics12Orta),
  _aile('oz_statistics_12_zor', 'Veri görselleştirme ve grafik seçimi', Topic.statistics, Difficulty.hard, BloomLevel.hatirlama, ozStatistics12Zor),
  _aile('oz_statistics_13_kolay', 'İstatistiksel yanılgılar ve veri okuryazarlığı', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics13Kolay),
  _aile('oz_statistics_13_orta', 'İstatistiksel yanılgılar ve veri okuryazarlığı', Topic.statistics, Difficulty.medium, BloomLevel.analiz, ozStatistics13Orta),
  _aile('oz_statistics_13_zor', 'İstatistiksel yanılgılar ve veri okuryazarlığı', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics13Zor),
  _aile('oz_statistics_14_kolay', 'Veri bilimi ve makine öğrenmesinde istatistik', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics14Kolay),
  _aile('oz_statistics_14_orta', 'Veri bilimi ve makine öğrenmesinde istatistik', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics14Orta),
  _aile('oz_statistics_14_zor', 'Veri bilimi ve makine öğrenmesinde istatistik', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics14Zor),
  _aile('oz_economics_6_kolay', 'Mikroekonomi: tüketici ve üretici kuramı', Topic.economics, Difficulty.easy, BloomLevel.uygulama, ozEconomics6Kolay),
  _aile('oz_economics_6_orta', 'Mikroekonomi: tüketici ve üretici kuramı', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics6Orta),
  _aile('oz_economics_6_zor', 'Mikroekonomi: tüketici ve üretici kuramı', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics6Zor),
  _aile('oz_economics_7_kolay', 'Piyasa yapıları ve rekabet', Topic.economics, Difficulty.easy, BloomLevel.anlama, ozEconomics7Kolay),
  _aile('oz_economics_7_orta', 'Piyasa yapıları ve rekabet', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics7Orta),
  _aile('oz_economics_7_zor', 'Piyasa yapıları ve rekabet', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics7Zor),
  _aile('oz_economics_8_kolay', 'Makroekonomi: milli gelir, büyüme, işsizlik', Topic.economics, Difficulty.easy, BloomLevel.anlama, ozEconomics8Kolay),
  _aile('oz_economics_8_orta', 'Makroekonomi: milli gelir, büyüme, işsizlik', Topic.economics, Difficulty.medium, BloomLevel.analiz, ozEconomics8Orta),
  _aile('oz_economics_8_zor', 'Makroekonomi: milli gelir, büyüme, işsizlik', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics8Zor),
  _aile('oz_economics_9_kolay', 'Para politikası ve maliye politikası', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics9Kolay),
  _aile('oz_economics_9_orta', 'Para politikası ve maliye politikası', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics9Orta),
  _aile('oz_economics_9_zor', 'Para politikası ve maliye politikası', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics9Zor),
  _aile('oz_economics_10_orta', 'Uluslararası ticaret ve döviz', Topic.economics, Difficulty.medium, BloomLevel.hatirlama, ozEconomics10Orta),
  _aile('oz_economics_10_zor', 'Uluslararası ticaret ve döviz', Topic.economics, Difficulty.hard, BloomLevel.anlama, ozEconomics10Zor),
  _aile('oz_economics_10_kolay', 'Uluslararası ticaret ve döviz', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics10Kolay),
  _aile('oz_economics_11_kolay', 'Finansal piyasalar ve yatırım araçları', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics11Kolay),
  _aile('oz_economics_11_orta', 'Finansal piyasalar ve yatırım araçları', Topic.economics, Difficulty.medium, BloomLevel.hatirlama, ozEconomics11Orta),
  _aile('oz_economics_11_zor', 'Finansal piyasalar ve yatırım araçları', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics11Zor),
  _aile('oz_economics_12_kolay', 'Kişisel finans hesapları: faiz, bütçe, kredi', Topic.economics, Difficulty.easy, BloomLevel.anlama, ozEconomics12Kolay),
  _aile('oz_economics_12_zor', 'Kişisel finans hesapları: faiz, bütçe, kredi', Topic.economics, Difficulty.hard, BloomLevel.uygulama, ozEconomics12Zor),
  _aile('oz_economics_12_orta', 'Kişisel finans hesapları: faiz, bütçe, kredi', Topic.economics, Difficulty.medium, BloomLevel.degerlendirme, ozEconomics12Orta),
  _aile('oz_economics_13_kolay', 'İşletme yönetimi ve pazarlama', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics13Kolay),
  _aile('oz_economics_13_orta', 'İşletme yönetimi ve pazarlama', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics13Orta),
  _aile('oz_economics_13_zor', 'İşletme yönetimi ve pazarlama', Topic.economics, Difficulty.hard, BloomLevel.anlama, ozEconomics13Zor),
  _aile('oz_economics_14_orta', 'İktisat düşüncesi tarihi ve iktisatçılar', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics14Orta),
  _aile('oz_economics_14_kolay', 'İktisat düşüncesi tarihi ve iktisatçılar', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics14Kolay),
  _aile('oz_economics_14_zor', 'İktisat düşüncesi tarihi ve iktisatçılar', Topic.economics, Difficulty.hard, BloomLevel.anlama, ozEconomics14Zor),
  _aile('oz_socialScience_6_orta', 'Sosyoloji kuramları ve sosyologlar', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience6Orta),
  _aile('oz_socialScience_6_zor', 'Sosyoloji kuramları ve sosyologlar', Topic.socialScience, Difficulty.hard, BloomLevel.hatirlama, ozSocialscience6Zor),
  _aile('oz_socialScience_6_kolay', 'Sosyoloji kuramları ve sosyologlar', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience6Kolay),
  _aile('oz_socialScience_7_kolay', 'Toplumsal yapı, tabakalaşma ve değişme', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience7Kolay),
  _aile('oz_socialScience_7_orta', 'Toplumsal yapı, tabakalaşma ve değişme', Topic.socialScience, Difficulty.medium, BloomLevel.analiz, ozSocialscience7Orta),
  _aile('oz_socialScience_7_zor', 'Toplumsal yapı, tabakalaşma ve değişme', Topic.socialScience, Difficulty.hard, BloomLevel.hatirlama, ozSocialscience7Zor),
  _aile('oz_socialScience_8_kolay', 'Gelişim psikolojisi ve öğrenme', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience8Kolay),
  _aile('oz_socialScience_8_orta', 'Gelişim psikolojisi ve öğrenme', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience8Orta),
  _aile('oz_socialScience_8_zor', 'Gelişim psikolojisi ve öğrenme', Topic.socialScience, Difficulty.hard, BloomLevel.hatirlama, ozSocialscience8Zor),
  _aile('oz_socialScience_9_orta', 'Bilişsel psikoloji, bellek ve algı', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience9Orta),
  _aile('oz_socialScience_9_zor', 'Bilişsel psikoloji, bellek ve algı', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience9Zor),
  _aile('oz_socialScience_9_kolay', 'Bilişsel psikoloji, bellek ve algı', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience9Kolay),
  _aile('oz_socialScience_10_kolay', 'Sosyal psikoloji', Topic.socialScience, Difficulty.easy, BloomLevel.uygulama, ozSocialscience10Kolay),
  _aile('oz_socialScience_10_zor', 'Sosyal psikoloji', Topic.socialScience, Difficulty.hard, BloomLevel.hatirlama, ozSocialscience10Zor),
  _aile('oz_socialScience_10_orta', 'Sosyal psikoloji', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience10Orta),
  _aile('oz_socialScience_11_kolay', 'Felsefe tarihi: İlk Çağ ve Orta Çağ', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience11Kolay),
  _aile('oz_socialScience_11_orta', 'Felsefe tarihi: İlk Çağ ve Orta Çağ', Topic.socialScience, Difficulty.medium, BloomLevel.hatirlama, ozSocialscience11Orta),
  _aile('oz_socialScience_11_zor', 'Felsefe tarihi: İlk Çağ ve Orta Çağ', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience11Zor),
  _aile('oz_socialScience_12_kolay', 'Felsefe tarihi: Yeni Çağ ve çağdaş felsefe', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience12Kolay),
  _aile('oz_socialScience_12_orta', 'Felsefe tarihi: Yeni Çağ ve çağdaş felsefe', Topic.socialScience, Difficulty.medium, BloomLevel.hatirlama, ozSocialscience12Orta),
  _aile('oz_socialScience_12_zor', 'Felsefe tarihi: Yeni Çağ ve çağdaş felsefe', Topic.socialScience, Difficulty.hard, BloomLevel.anlama, ozSocialscience12Zor),
  _aile('oz_socialScience_13_kolay', 'Mantık: önermeler, çıkarımlar, safsatalar', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience13Kolay),
  _aile('oz_socialScience_13_orta', 'Mantık: önermeler, çıkarımlar, safsatalar', Topic.socialScience, Difficulty.medium, BloomLevel.uygulama, ozSocialscience13Orta),
  _aile('oz_socialScience_13_zor', 'Mantık: önermeler, çıkarımlar, safsatalar', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience13Zor),
  _aile('oz_socialScience_14_kolay', 'Anayasa, devlet yapısı ve vatandaşlık bilgisi', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience14Kolay),
  _aile('oz_socialScience_14_orta', 'Anayasa, devlet yapısı ve vatandaşlık bilgisi', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience14Orta),
  _aile('oz_socialScience_14_zor', 'Anayasa, devlet yapısı ve vatandaşlık bilgisi', Topic.socialScience, Difficulty.hard, BloomLevel.anlama, ozSocialscience14Zor),
  _aile('oz_research_6_kolay', 'Araştırma soruları ve hipotez kurma uygulamaları', Topic.research, Difficulty.easy, BloomLevel.uygulama, ozResearch6Kolay),
  _aile('oz_research_6_orta', 'Araştırma soruları ve hipotez kurma uygulamaları', Topic.research, Difficulty.medium, BloomLevel.uygulama, ozResearch6Orta),
  _aile('oz_research_6_zor', 'Araştırma soruları ve hipotez kurma uygulamaları', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch6Zor),
  _aile('oz_research_7_kolay', 'Deney tasarımı ve kontrol grupları uygulamaları', Topic.research, Difficulty.easy, BloomLevel.hatirlama, ozResearch7Kolay),
  _aile('oz_research_7_orta', 'Deney tasarımı ve kontrol grupları uygulamaları', Topic.research, Difficulty.medium, BloomLevel.analiz, ozResearch7Orta),
  _aile('oz_research_7_zor', 'Deney tasarımı ve kontrol grupları uygulamaları', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch7Zor),
  _aile('oz_research_8_kolay', 'Nitel araştırma yöntemleri', Topic.research, Difficulty.easy, BloomLevel.anlama, ozResearch8Kolay),
  _aile('oz_research_8_zor', 'Nitel araştırma yöntemleri', Topic.research, Difficulty.hard, BloomLevel.hatirlama, ozResearch8Zor),
  _aile('oz_research_8_orta', 'Nitel araştırma yöntemleri', Topic.research, Difficulty.medium, BloomLevel.hatirlama, ozResearch8Orta),
  _aile('oz_research_9_orta', 'Nicel araştırma ve ölçme araçları', Topic.research, Difficulty.medium, BloomLevel.uygulama, ozResearch9Orta),
  _aile('oz_research_9_kolay', 'Nicel araştırma ve ölçme araçları', Topic.research, Difficulty.easy, BloomLevel.uygulama, ozResearch9Kolay),
  _aile('oz_research_9_zor', 'Nicel araştırma ve ölçme araçları', Topic.research, Difficulty.hard, BloomLevel.uygulama, ozResearch9Zor),
  _aile('oz_research_10_orta', 'Geçerlik, güvenirlik ve yanlılık türleri', Topic.research, Difficulty.medium, BloomLevel.analiz, ozResearch10Orta),
  _aile('oz_research_10_kolay', 'Geçerlik, güvenirlik ve yanlılık türleri', Topic.research, Difficulty.easy, BloomLevel.anlama, ozResearch10Kolay),
  _aile('oz_research_10_zor', 'Geçerlik, güvenirlik ve yanlılık türleri', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch10Zor),
  _aile('oz_research_11_orta', 'Araştırma etiği ve akademik dürüstlük', Topic.research, Difficulty.medium, BloomLevel.degerlendirme, ozResearch11Orta),
  _aile('oz_research_11_kolay', 'Araştırma etiği ve akademik dürüstlük', Topic.research, Difficulty.easy, BloomLevel.uygulama, ozResearch11Kolay),
  _aile('oz_research_11_zor', 'Araştırma etiği ve akademik dürüstlük', Topic.research, Difficulty.hard, BloomLevel.hatirlama, ozResearch11Zor),
  _aile('oz_research_12_kolay', 'Kaynakça, alıntı ve akademik yazım', Topic.research, Difficulty.easy, BloomLevel.hatirlama, ozResearch12Kolay),
  _aile('oz_research_12_orta', 'Kaynakça, alıntı ve akademik yazım', Topic.research, Difficulty.medium, BloomLevel.uygulama, ozResearch12Orta),
  _aile('oz_research_12_zor', 'Kaynakça, alıntı ve akademik yazım', Topic.research, Difficulty.hard, BloomLevel.hatirlama, ozResearch12Zor),
  _aile('oz_research_13_orta', 'Bilgi okuryazarlığı ve doğrulama', Topic.research, Difficulty.medium, BloomLevel.anlama, ozResearch13Orta),
  _aile('oz_research_13_kolay', 'Bilgi okuryazarlığı ve doğrulama', Topic.research, Difficulty.easy, BloomLevel.anlama, ozResearch13Kolay),
  _aile('oz_research_13_zor', 'Bilgi okuryazarlığı ve doğrulama', Topic.research, Difficulty.hard, BloomLevel.hatirlama, ozResearch13Zor),
  _aile('oz_research_14_kolay', 'Proje tabanlı araştırma ve rapor yazımı', Topic.research, Difficulty.easy, BloomLevel.uygulama, ozResearch14Kolay),
  _aile('oz_research_14_orta', 'Proje tabanlı araştırma ve rapor yazımı', Topic.research, Difficulty.medium, BloomLevel.uygulama, ozResearch14Orta),
  _aile('oz_research_14_zor', 'Proje tabanlı araştırma ve rapor yazımı', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch14Zor),
  _aile('oz_science_15_kolay', 'Tıp tarihi, aşılar, salgınlarla mücadele ve sağlık buluşları', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience15Kolay),
  _aile('oz_science_15_orta', 'Tıp tarihi, aşılar, salgınlarla mücadele ve sağlık buluşları', Topic.science, Difficulty.medium, BloomLevel.hatirlama, ozScience15Orta),
  _aile('oz_science_15_zor', 'Tıp tarihi, aşılar, salgınlarla mücadele ve sağlık buluşları', Topic.science, Difficulty.hard, BloomLevel.hatirlama, ozScience15Zor),
  _aile('oz_science_16_kolay', 'Tarım bilimi, toprak bilimi, gıda koruma ve fermantasyon bilimi', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience16Kolay),
  _aile('oz_science_16_orta', 'Tarım bilimi, toprak bilimi, gıda koruma ve fermantasyon bilimi', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience16Orta),
  _aile('oz_science_16_zor', 'Tarım bilimi, toprak bilimi, gıda koruma ve fermantasyon bilimi', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience16Zor),
  _aile('oz_science_17_kolay', 'Buzullar, kutup bölgeleri, çöller ve ekstrem yer ortamları bilimi', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience17Kolay),
  _aile('oz_science_17_orta', 'Buzullar, kutup bölgeleri, çöller ve ekstrem yer ortamları bilimi', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience17Orta),
  _aile('oz_science_17_zor', 'Buzullar, kutup bölgeleri, çöller ve ekstrem yer ortamları bilimi', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience17Zor),
  _aile('oz_science_18_kolay', 'Adli bilimler, arkeometri ve bilimsel tarihleme yöntemleri', Topic.science, Difficulty.easy, BloomLevel.hatirlama, ozScience18Kolay),
  _aile('oz_science_18_orta', 'Adli bilimler, arkeometri ve bilimsel tarihleme yöntemleri', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience18Orta),
  _aile('oz_science_18_zor', 'Adli bilimler, arkeometri ve bilimsel tarihleme yöntemleri', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience18Zor),
  _aile('oz_science_19_kolay', 'Biyomimetik, atmosferik optik olaylar ve akustik merakları', Topic.science, Difficulty.easy, BloomLevel.anlama, ozScience19Kolay),
  _aile('oz_science_19_orta', 'Biyomimetik, atmosferik optik olaylar ve akustik merakları', Topic.science, Difficulty.medium, BloomLevel.anlama, ozScience19Orta),
  _aile('oz_science_19_zor', 'Biyomimetik, atmosferik optik olaylar ve akustik merakları', Topic.science, Difficulty.hard, BloomLevel.analiz, ozScience19Zor),
  _aile('oz_history_15_kolay', 'Anadolu uygarlıkları, Anadolu beylikleri ve Türkiye Selçuklu şehir-ticaret hayatı', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory15Kolay),
  _aile('oz_history_15_orta', 'Anadolu uygarlıkları, Anadolu beylikleri ve Türkiye Selçuklu şehir-ticaret hayatı', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory15Orta),
  _aile('oz_history_15_zor', 'Anadolu uygarlıkları, Anadolu beylikleri ve Türkiye Selçuklu şehir-ticaret hayatı', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory15Zor),
  _aile('oz_history_16_kolay', 'Denizcilik tarihi, boğazlar, kanallar, ünlü denizciler ve deniz muharebeleri', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory16Kolay),
  _aile('oz_history_16_orta', 'Denizcilik tarihi, boğazlar, kanallar, ünlü denizciler ve deniz muharebeleri', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory16Orta),
  _aile('oz_history_16_zor', 'Denizcilik tarihi, boğazlar, kanallar, ünlü denizciler ve deniz muharebeleri', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory16Zor),
  _aile('oz_history_17_kolay', 'Yazı, kâğıt, matbaa, kütüphaneler, medreseler ve üniversiteler tarihi', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory17Kolay),
  _aile('oz_history_17_orta', 'Yazı, kâğıt, matbaa, kütüphaneler, medreseler ve üniversiteler tarihi', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory17Orta),
  _aile('oz_history_17_zor', 'Yazı, kâğıt, matbaa, kütüphaneler, medreseler ve üniversiteler tarihi', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory17Zor),
  _aile('oz_history_18_kolay', 'Diplomasi tarihi: antlaşmalar, kongreler, ittifaklar ve uluslararası kuruluşların doğuşu', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory18Kolay),
  _aile('oz_history_18_orta', 'Diplomasi tarihi: antlaşmalar, kongreler, ittifaklar ve uluslararası kuruluşların doğuşu', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory18Orta),
  _aile('oz_history_18_zor', 'Diplomasi tarihi: antlaşmalar, kongreler, ittifaklar ve uluslararası kuruluşların doğuşu', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory18Zor),
  _aile('oz_history_19_kolay', 'Dünya ticaret yolları, para tarihi ve Sanayi Devrimi\'nin toplumsal dönüşümü', Topic.history, Difficulty.easy, BloomLevel.hatirlama, ozHistory19Kolay),
  _aile('oz_history_19_orta', 'Dünya ticaret yolları, para tarihi ve Sanayi Devrimi\'nin toplumsal dönüşümü', Topic.history, Difficulty.medium, BloomLevel.hatirlama, ozHistory19Orta),
  _aile('oz_history_19_zor', 'Dünya ticaret yolları, para tarihi ve Sanayi Devrimi\'nin toplumsal dönüşümü', Topic.history, Difficulty.hard, BloomLevel.hatirlama, ozHistory19Zor),
  _aile('oz_geography_15_kolay', 'Dünya boğazları, kanalları, körfezleri, yarımadaları, adaları ve kenar denizleri', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography15Kolay),
  _aile('oz_geography_15_orta', 'Dünya boğazları, kanalları, körfezleri, yarımadaları, adaları ve kenar denizleri', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography15Orta),
  _aile('oz_geography_15_zor', 'Dünya boğazları, kanalları, körfezleri, yarımadaları, adaları ve kenar denizleri', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography15Zor),
  _aile('oz_geography_16_kolay', 'Dünya nehirleri, gölleri, deltaları, su havzaları ve baraj coğrafyası', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography16Kolay),
  _aile('oz_geography_16_orta', 'Dünya nehirleri, gölleri, deltaları, su havzaları ve baraj coğrafyası', Topic.geography, Difficulty.medium, BloomLevel.hatirlama, ozGeography16Orta),
  _aile('oz_geography_16_zor', 'Dünya nehirleri, gölleri, deltaları, su havzaları ve baraj coğrafyası', Topic.geography, Difficulty.hard, BloomLevel.hatirlama, ozGeography16Zor),
  _aile('oz_geography_17_kolay', 'Toprak tipleri, kayaç döngüsü ve karstik-buzul-rüzgâr-kıyı yer şekilleri', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography17Kolay),
  _aile('oz_geography_17_orta', 'Toprak tipleri, kayaç döngüsü ve karstik-buzul-rüzgâr-kıyı yer şekilleri', Topic.geography, Difficulty.medium, BloomLevel.analiz, ozGeography17Orta),
  _aile('oz_geography_17_zor', 'Toprak tipleri, kayaç döngüsü ve karstik-buzul-rüzgâr-kıyı yer şekilleri', Topic.geography, Difficulty.hard, BloomLevel.analiz, ozGeography17Zor),
  _aile('oz_geography_18_kolay', 'Türkiye\'nin sınır kapıları, ulaşım koridorları, UNESCO miras alanları ve coğrafi işaretli yöreleri', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography18Kolay),
  _aile('oz_geography_18_orta', 'Türkiye\'nin sınır kapıları, ulaşım koridorları, UNESCO miras alanları ve coğrafi işaretli yöreleri', Topic.geography, Difficulty.medium, BloomLevel.anlama, ozGeography18Orta),
  _aile('oz_geography_18_zor', 'Türkiye\'nin sınır kapıları, ulaşım koridorları, UNESCO miras alanları ve coğrafi işaretli yöreleri', Topic.geography, Difficulty.hard, BloomLevel.analiz, ozGeography18Zor),
  _aile('oz_geography_19_kolay', 'Sürdürülebilirlik, uluslararası çevre sözleşmeleri ve küresel enerji-çevre coğrafyası', Topic.geography, Difficulty.easy, BloomLevel.hatirlama, ozGeography19Kolay),
  _aile('oz_geography_19_orta', 'Sürdürülebilirlik, uluslararası çevre sözleşmeleri ve küresel enerji-çevre coğrafyası', Topic.geography, Difficulty.medium, BloomLevel.anlama, ozGeography19Orta),
  _aile('oz_geography_19_zor', 'Sürdürülebilirlik, uluslararası çevre sözleşmeleri ve küresel enerji-çevre coğrafyası', Topic.geography, Difficulty.hard, BloomLevel.analiz, ozGeography19Zor),
  _aile('oz_art_15_kolay', 'Dünya ve Türkiye müzeleri, sanat galerileri, bienaller ve müzecilik kavramları', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt15Kolay),
  _aile('oz_art_15_orta', 'Dünya ve Türkiye müzeleri, sanat galerileri, bienaller ve müzecilik kavramları', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt15Orta),
  _aile('oz_art_15_zor', 'Dünya ve Türkiye müzeleri, sanat galerileri, bienaller ve müzecilik kavramları', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt15Zor),
  _aile('oz_art_16_kolay', 'Baskı resim, gravür, litografi, illüstrasyon, karikatür ve çizgi roman sanatı', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt16Kolay),
  _aile('oz_art_16_orta', 'Baskı resim, gravür, litografi, illüstrasyon, karikatür ve çizgi roman sanatı', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt16Orta),
  _aile('oz_art_16_zor', 'Baskı resim, gravür, litografi, illüstrasyon, karikatür ve çizgi roman sanatı', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt16Zor),
  _aile('oz_art_17_kolay', 'Antik Çağ ve Orta Çağ görsel sanatları: Mezopotamya, Mısır, Yunan, Roma ve Bizans', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt17Kolay),
  _aile('oz_art_17_orta', 'Antik Çağ ve Orta Çağ görsel sanatları: Mezopotamya, Mısır, Yunan, Roma ve Bizans', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt17Orta),
  _aile('oz_art_17_zor', 'Antik Çağ ve Orta Çağ görsel sanatları: Mezopotamya, Mısır, Yunan, Roma ve Bizans', Topic.art, Difficulty.hard, BloomLevel.analiz, ozArt17Zor),
  _aile('oz_art_18_kolay', 'Resim-heykel malzemeleri, boya teknikleri, pigmentler ve sanat eseri restorasyonu', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt18Kolay),
  _aile('oz_art_18_orta', 'Resim-heykel malzemeleri, boya teknikleri, pigmentler ve sanat eseri restorasyonu', Topic.art, Difficulty.medium, BloomLevel.hatirlama, ozArt18Orta),
  _aile('oz_art_18_zor', 'Resim-heykel malzemeleri, boya teknikleri, pigmentler ve sanat eseri restorasyonu', Topic.art, Difficulty.hard, BloomLevel.analiz, ozArt18Zor),
  _aile('oz_art_19_kolay', 'Geleneksel seyirlik sanatlar, kukla, gölge oyunu ve sahne-kostüm tasarımı', Topic.art, Difficulty.easy, BloomLevel.hatirlama, ozArt19Kolay),
  _aile('oz_art_19_orta', 'Geleneksel seyirlik sanatlar, kukla, gölge oyunu ve sahne-kostüm tasarımı', Topic.art, Difficulty.medium, BloomLevel.anlama, ozArt19Orta),
  _aile('oz_art_19_zor', 'Geleneksel seyirlik sanatlar, kukla, gölge oyunu ve sahne-kostüm tasarımı', Topic.art, Difficulty.hard, BloomLevel.hatirlama, ozArt19Zor),
  _aile('oz_sport_15_kolay', 'Bisiklet, yelken, kürek, kano ve triatlon kuralları ve terimleri', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport15Kolay),
  _aile('oz_sport_15_orta', 'Bisiklet, yelken, kürek, kano ve triatlon kuralları ve terimleri', Topic.sport, Difficulty.medium, BloomLevel.hatirlama, ozSport15Orta),
  _aile('oz_sport_15_zor', 'Bisiklet, yelken, kürek, kano ve triatlon kuralları ve terimleri', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport15Zor),
  _aile('oz_sport_16_kolay', 'Cimnastik, eskrim, okçuluk ve atıcılık disiplinleri', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport16Kolay),
  _aile('oz_sport_16_orta', 'Cimnastik, eskrim, okçuluk ve atıcılık disiplinleri', Topic.sport, Difficulty.medium, BloomLevel.anlama, ozSport16Orta),
  _aile('oz_sport_16_zor', 'Cimnastik, eskrim, okçuluk ve atıcılık disiplinleri', Topic.sport, Difficulty.hard, BloomLevel.hatirlama, ozSport16Zor),
  _aile('oz_sport_17_kolay', 'Kış sporları ayrıntıları: alp disiplini, biatlon, kayakla atlama, buz pateni, körling ve buz hokeyi', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport17Kolay),
  _aile('oz_sport_17_orta', 'Kış sporları ayrıntıları: alp disiplini, biatlon, kayakla atlama, buz pateni, körling ve buz hokeyi', Topic.sport, Difficulty.medium, BloomLevel.anlama, ozSport17Orta),
  _aile('oz_sport_17_zor', 'Kış sporları ayrıntıları: alp disiplini, biatlon, kayakla atlama, buz pateni, körling ve buz hokeyi', Topic.sport, Difficulty.hard, BloomLevel.analiz, ozSport17Zor),
  _aile('oz_sport_18_kolay', 'Paralimpik oyunlar, engelli spor branşları, fair-play tarihi ve spor etiği', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport18Kolay),
  _aile('oz_sport_18_orta', 'Paralimpik oyunlar, engelli spor branşları, fair-play tarihi ve spor etiği', Topic.sport, Difficulty.medium, BloomLevel.anlama, ozSport18Orta),
  _aile('oz_sport_18_zor', 'Paralimpik oyunlar, engelli spor branşları, fair-play tarihi ve spor etiği', Topic.sport, Difficulty.hard, BloomLevel.analiz, ozSport18Zor),
  _aile('oz_sport_19_kolay', 'Spor sahaları, standart ekipman ölçüleri, hakem kararları ve turnuva sistemleri', Topic.sport, Difficulty.easy, BloomLevel.hatirlama, ozSport19Kolay),
  _aile('oz_sport_19_orta', 'Spor sahaları, standart ekipman ölçüleri, hakem kararları ve turnuva sistemleri', Topic.sport, Difficulty.medium, BloomLevel.anlama, ozSport19Orta),
  _aile('oz_sport_19_zor', 'Spor sahaları, standart ekipman ölçüleri, hakem kararları ve turnuva sistemleri', Topic.sport, Difficulty.hard, BloomLevel.anlama, ozSport19Zor),
  _aile('oz_culture_15_kolay', 'Anadolu mutfak mirası, yöresel yemekler, coğrafi işaretli lezzetler ve içecek kültürü tarihi', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture15Kolay),
  _aile('oz_culture_15_orta', 'Anadolu mutfak mirası, yöresel yemekler, coğrafi işaretli lezzetler ve içecek kültürü tarihi', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture15Orta),
  _aile('oz_culture_15_zor', 'Anadolu mutfak mirası, yöresel yemekler, coğrafi işaretli lezzetler ve içecek kültürü tarihi', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture15Zor),
  _aile('oz_culture_16_kolay', 'Geleneksel el sanatları, somut olmayan kültürel miras ve unutulmaya yüz tutmuş meslekler', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture16Kolay),
  _aile('oz_culture_16_orta', 'Geleneksel el sanatları, somut olmayan kültürel miras ve unutulmaya yüz tutmuş meslekler', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture16Orta),
  _aile('oz_culture_16_zor', 'Geleneksel el sanatları, somut olmayan kültürel miras ve unutulmaya yüz tutmuş meslekler', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture16Zor),
  _aile('oz_culture_17_kolay', 'Uluslararası ödüller, evrensel kodlamalar ve işaret sistemleri', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture17Kolay),
  _aile('oz_culture_17_orta', 'Uluslararası ödüller, evrensel kodlamalar ve işaret sistemleri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture17Orta),
  _aile('oz_culture_17_zor', 'Uluslararası ödüller, evrensel kodlamalar ve işaret sistemleri', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture17Zor),
  _aile('oz_culture_18_kolay', 'Kitap, kütüphanecilik, basın-yayın tarihi, filateli ve nümismatik kültürü', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture18Kolay),
  _aile('oz_culture_18_orta', 'Kitap, kütüphanecilik, basın-yayın tarihi, filateli ve nümismatik kültürü', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture18Orta),
  _aile('oz_culture_18_zor', 'Kitap, kütüphanecilik, basın-yayın tarihi, filateli ve nümismatik kültürü', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture18Zor),
  _aile('oz_culture_19_kolay', 'Denizcilik, havacılık, demiryolu ve seyahat kültürü terimleri', Topic.culture, Difficulty.easy, BloomLevel.hatirlama, ozCulture19Kolay),
  _aile('oz_culture_19_orta', 'Denizcilik, havacılık, demiryolu ve seyahat kültürü terimleri', Topic.culture, Difficulty.medium, BloomLevel.hatirlama, ozCulture19Orta),
  _aile('oz_culture_19_zor', 'Denizcilik, havacılık, demiryolu ve seyahat kültürü terimleri', Topic.culture, Difficulty.hard, BloomLevel.hatirlama, ozCulture19Zor),
  _aile('oz_cinema_15_kolay', 'Görüntü yönetimi, kamera hareketleri, mercekler, aydınlatma ve renk düzenleme', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema15Kolay),
  _aile('oz_cinema_15_orta', 'Görüntü yönetimi, kamera hareketleri, mercekler, aydınlatma ve renk düzenleme', Topic.cinema, Difficulty.medium, BloomLevel.analiz, ozCinema15Orta),
  _aile('oz_cinema_15_zor', 'Görüntü yönetimi, kamera hareketleri, mercekler, aydınlatma ve renk düzenleme', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema15Zor),
  _aile('oz_cinema_16_kolay', 'Kurgu kuramları, ses tasarımı, foley, dublaj ve post-prodüksiyon', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema16Kolay),
  _aile('oz_cinema_16_orta', 'Kurgu kuramları, ses tasarımı, foley, dublaj ve post-prodüksiyon', Topic.cinema, Difficulty.medium, BloomLevel.anlama, ozCinema16Orta),
  _aile('oz_cinema_16_zor', 'Kurgu kuramları, ses tasarımı, foley, dublaj ve post-prodüksiyon', Topic.cinema, Difficulty.hard, BloomLevel.analiz, ozCinema16Zor),
  _aile('oz_cinema_17_kolay', 'Belgesel sinema tarihi, belgesel türleri ve gerçeklik anlatımı', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema17Kolay),
  _aile('oz_cinema_17_orta', 'Belgesel sinema tarihi, belgesel türleri ve gerçeklik anlatımı', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema17Orta),
  _aile('oz_cinema_17_zor', 'Belgesel sinema tarihi, belgesel türleri ve gerçeklik anlatımı', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema17Zor),
  _aile('oz_cinema_18_kolay', 'Uluslararası ve ulusal film festivalleri, ödül tarihi ve sinema kurumları', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema18Kolay),
  _aile('oz_cinema_18_orta', 'Uluslararası ve ulusal film festivalleri, ödül tarihi ve sinema kurumları', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema18Orta),
  _aile('oz_cinema_18_zor', 'Uluslararası ve ulusal film festivalleri, ödül tarihi ve sinema kurumları', Topic.cinema, Difficulty.hard, BloomLevel.hatirlama, ozCinema18Zor),
  _aile('oz_cinema_19_kolay', 'Oyunculuk yaklaşımları, kostüm-makyaj ve film seti ekibi görevleri', Topic.cinema, Difficulty.easy, BloomLevel.hatirlama, ozCinema19Kolay),
  _aile('oz_cinema_19_orta', 'Oyunculuk yaklaşımları, kostüm-makyaj ve film seti ekibi görevleri', Topic.cinema, Difficulty.medium, BloomLevel.hatirlama, ozCinema19Orta),
  _aile('oz_cinema_19_zor', 'Oyunculuk yaklaşımları, kostüm-makyaj ve film seti ekibi görevleri', Topic.cinema, Difficulty.hard, BloomLevel.analiz, ozCinema19Zor),
  _aile('oz_language_15_kolay', 'İngilizce edilgen çatı, dolaylı anlatım, koşul cümleleri ve ettirgen yapılar', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage15Kolay),
  _aile('oz_language_15_orta', 'İngilizce edilgen çatı, dolaylı anlatım, koşul cümleleri ve ettirgen yapılar', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage15Orta),
  _aile('oz_language_15_zor', 'İngilizce edilgen çatı, dolaylı anlatım, koşul cümleleri ve ettirgen yapılar', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage15Zor),
  _aile('oz_language_16_kolay', 'İngilizce sıfat-isim-zarf cümlecikleri ve fiilimsiler', Topic.language, Difficulty.easy, BloomLevel.uygulama, ozLanguage16Kolay),
  _aile('oz_language_16_orta', 'İngilizce sıfat-isim-zarf cümlecikleri ve fiilimsiler', Topic.language, Difficulty.medium, BloomLevel.uygulama, ozLanguage16Orta),
  _aile('oz_language_16_zor', 'İngilizce sıfat-isim-zarf cümlecikleri ve fiilimsiler', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage16Zor),
  _aile('oz_language_17_kolay', 'Akademik ve bilimsel İngilizce söz varlığı: bağlamdan sözcük ve anlam çıkarma', Topic.language, Difficulty.easy, BloomLevel.hatirlama, ozLanguage17Kolay),
  _aile('oz_language_17_orta', 'Akademik ve bilimsel İngilizce söz varlığı: bağlamdan sözcük ve anlam çıkarma', Topic.language, Difficulty.medium, BloomLevel.anlama, ozLanguage17Orta),
  _aile('oz_language_17_zor', 'Akademik ve bilimsel İngilizce söz varlığı: bağlamdan sözcük ve anlam çıkarma', Topic.language, Difficulty.hard, BloomLevel.analiz, ozLanguage17Zor),
  _aile('oz_language_18_kolay', 'Dünya alfabeleri, yazı sistemleri tarihi, etimoloji ve çeviri bilimi', Topic.language, Difficulty.easy, BloomLevel.hatirlama, ozLanguage18Kolay),
  _aile('oz_language_18_orta', 'Dünya alfabeleri, yazı sistemleri tarihi, etimoloji ve çeviri bilimi', Topic.language, Difficulty.medium, BloomLevel.hatirlama, ozLanguage18Orta),
  _aile('oz_language_18_zor', 'Dünya alfabeleri, yazı sistemleri tarihi, etimoloji ve çeviri bilimi', Topic.language, Difficulty.hard, BloomLevel.hatirlama, ozLanguage18Zor),
  _aile('oz_language_19_kolay', 'Bilim, hukuk, müzik ve kültürde yerleşik Latince, İtalyanca, Fransızca ve Yunanca kökenli uluslararası terimler ve ifadeler', Topic.language, Difficulty.easy, BloomLevel.hatirlama, ozLanguage19Kolay),
  _aile('oz_language_19_orta', 'Bilim, hukuk, müzik ve kültürde yerleşik Latince, İtalyanca, Fransızca ve Yunanca kökenli uluslararası terimler ve ifadeler', Topic.language, Difficulty.medium, BloomLevel.anlama, ozLanguage19Orta),
  _aile('oz_language_19_zor', 'Bilim, hukuk, müzik ve kültürde yerleşik Latince, İtalyanca, Fransızca ve Yunanca kökenli uluslararası terimler ve ifadeler', Topic.language, Difficulty.hard, BloomLevel.anlama, ozLanguage19Zor),
  _aile('oz_technology_15_kolay', 'Yarı iletkenler, işlemci mimarisi, bellek hiyerarşisi ve çip üretimi', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology15Kolay),
  _aile('oz_technology_15_orta', 'Yarı iletkenler, işlemci mimarisi, bellek hiyerarşisi ve çip üretimi', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology15Orta),
  _aile('oz_technology_15_zor', 'Yarı iletkenler, işlemci mimarisi, bellek hiyerarşisi ve çip üretimi', Topic.technology, Difficulty.hard, BloomLevel.analiz, ozTechnology15Zor),
  _aile('oz_technology_16_kolay', 'Ekran, görüntüleme, dijital ses, optik ve veri sıkıştırma teknolojileri', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology16Kolay),
  _aile('oz_technology_16_orta', 'Ekran, görüntüleme, dijital ses, optik ve veri sıkıştırma teknolojileri', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology16Orta),
  _aile('oz_technology_16_zor', 'Ekran, görüntüleme, dijital ses, optik ve veri sıkıştırma teknolojileri', Topic.technology, Difficulty.hard, BloomLevel.analiz, ozTechnology16Zor),
  _aile('oz_technology_17_kolay', 'Biyomedikal cihazlar, tıbbi görüntüleme, giyilebilir teknoloji ve sağlık bilişimi', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology17Kolay),
  _aile('oz_technology_17_orta', 'Biyomedikal cihazlar, tıbbi görüntüleme, giyilebilir teknoloji ve sağlık bilişimi', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology17Orta),
  _aile('oz_technology_17_zor', 'Biyomedikal cihazlar, tıbbi görüntüleme, giyilebilir teknoloji ve sağlık bilişimi', Topic.technology, Difficulty.hard, BloomLevel.analiz, ozTechnology17Zor),
  _aile('oz_technology_18_kolay', 'Uydu konumlama', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology18Kolay),
  _aile('oz_technology_18_orta', 'Uydu konumlama', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology18Orta),
  _aile('oz_technology_18_zor', 'Uydu konumlama', Topic.technology, Difficulty.hard, BloomLevel.analiz, ozTechnology18Zor),
  _aile('oz_technology_19_kolay', 'Web standartları, açık kaynak lisansları, sürüm kontrolü, karakter kodlama ve dijital erişilebilirlik', Topic.technology, Difficulty.easy, BloomLevel.hatirlama, ozTechnology19Kolay),
  _aile('oz_technology_19_orta', 'Web standartları, açık kaynak lisansları, sürüm kontrolü, karakter kodlama ve dijital erişilebilirlik', Topic.technology, Difficulty.medium, BloomLevel.anlama, ozTechnology19Orta),
  _aile('oz_technology_19_zor', 'Web standartları, açık kaynak lisansları, sürüm kontrolü, karakter kodlama ve dijital erişilebilirlik', Topic.technology, Difficulty.hard, BloomLevel.anlama, ozTechnology19Zor),
  _aile('oz_literature_15_kolay', 'Tanzimat, Servetifünun, Fecriati ve Millî Edebiyat dönemleri: roman kahramanları, dergiler, eleştiriler ve edebî tartışmalar', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature15Kolay),
  _aile('oz_literature_15_orta', 'Tanzimat, Servetifünun, Fecriati ve Millî Edebiyat dönemleri: roman kahramanları, dergiler, eleştiriler ve edebî tartışmalar', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature15Orta),
  _aile('oz_literature_15_zor', 'Tanzimat, Servetifünun, Fecriati ve Millî Edebiyat dönemleri: roman kahramanları, dergiler, eleştiriler ve edebî tartışmalar', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature15Zor),
  _aile('oz_literature_16_kolay', 'Türk ve dünya tiyatro edebiyatı: trajedi, komedi, dram ve çağdaş oyun yazarları', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature16Kolay),
  _aile('oz_literature_16_orta', 'Türk ve dünya tiyatro edebiyatı: trajedi, komedi, dram ve çağdaş oyun yazarları', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature16Orta),
  _aile('oz_literature_16_zor', 'Türk ve dünya tiyatro edebiyatı: trajedi, komedi, dram ve çağdaş oyun yazarları', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature16Zor),
  _aile('oz_literature_17_kolay', 'Öğretici ve kişisel hayatı konu alan metinler: deneme, gezi yazısı, anı, biyografi, mektup ve günlük klasikleri', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature17Kolay),
  _aile('oz_literature_17_orta', 'Öğretici ve kişisel hayatı konu alan metinler: deneme, gezi yazısı, anı, biyografi, mektup ve günlük klasikleri', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature17Orta),
  _aile('oz_literature_17_zor', 'Öğretici ve kişisel hayatı konu alan metinler: deneme, gezi yazısı, anı, biyografi, mektup ve günlük klasikleri', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature17Zor),
  _aile('oz_literature_18_kolay', 'İtalyan, İspanyol, İskandinav, Balkan ve Türk dünyası edebiyatı klasikleri', Topic.literature, Difficulty.easy, BloomLevel.hatirlama, ozLiterature18Kolay),
  _aile('oz_literature_18_orta', 'İtalyan, İspanyol, İskandinav, Balkan ve Türk dünyası edebiyatı klasikleri', Topic.literature, Difficulty.medium, BloomLevel.hatirlama, ozLiterature18Orta),
  _aile('oz_literature_18_zor', 'İtalyan, İspanyol, İskandinav, Balkan ve Türk dünyası edebiyatı klasikleri', Topic.literature, Difficulty.hard, BloomLevel.hatirlama, ozLiterature18Zor),
  _aile('oz_literature_19_kolay', 'Uygulamalı şiir bilgisi ve söz sanatları çözümleme', Topic.literature, Difficulty.easy, BloomLevel.uygulama, ozLiterature19Kolay),
  _aile('oz_literature_19_orta', 'Uygulamalı şiir bilgisi ve söz sanatları çözümleme', Topic.literature, Difficulty.medium, BloomLevel.analiz, ozLiterature19Orta),
  _aile('oz_literature_19_zor', 'Uygulamalı şiir bilgisi ve söz sanatları çözümleme', Topic.literature, Difficulty.hard, BloomLevel.analiz, ozLiterature19Zor),
  _aile('oz_music_15_kolay', 'Orta Çağ, Rönesans ve Barok müziği: formlar, çalgılar ve besteciler', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic15Kolay),
  _aile('oz_music_15_orta', 'Orta Çağ, Rönesans ve Barok müziği: formlar, çalgılar ve besteciler', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic15Orta),
  _aile('oz_music_15_zor', 'Orta Çağ, Rönesans ve Barok müziği: formlar, çalgılar ve besteciler', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic15Zor),
  _aile('oz_music_16_kolay', 'Çoksesli Türk müziği tarihi, Türk Beşleri, konservatuvarlar ve yorumcular', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic16Kolay),
  _aile('oz_music_16_orta', 'Çoksesli Türk müziği tarihi, Türk Beşleri, konservatuvarlar ve yorumcular', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic16Orta),
  _aile('oz_music_16_zor', 'Çoksesli Türk müziği tarihi, Türk Beşleri, konservatuvarlar ve yorumcular', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic16Zor),
  _aile('oz_music_17_kolay', 'Dünya geleneksel müzikleri ve etnomüzikoloji', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic17Kolay),
  _aile('oz_music_17_orta', 'Dünya geleneksel müzikleri ve etnomüzikoloji', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic17Orta),
  _aile('oz_music_17_zor', 'Dünya geleneksel müzikleri ve etnomüzikoloji', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic17Zor),
  _aile('oz_music_18_kolay', 'Ses kayıt tarihi, mikrofon türleri, stüdyo prodüksiyonu ve salon akustiği', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic18Kolay),
  _aile('oz_music_18_orta', 'Ses kayıt tarihi, mikrofon türleri, stüdyo prodüksiyonu ve salon akustiği', Topic.music, Difficulty.medium, BloomLevel.anlama, ozMusic18Orta),
  _aile('oz_music_18_zor', 'Ses kayıt tarihi, mikrofon türleri, stüdyo prodüksiyonu ve salon akustiği', Topic.music, Difficulty.hard, BloomLevel.analiz, ozMusic18Zor),
  _aile('oz_music_19_kolay', 'İnsan sesi grupları, koro, şeflik, oda müziği toplulukları ve klasik müzik formları', Topic.music, Difficulty.easy, BloomLevel.hatirlama, ozMusic19Kolay),
  _aile('oz_music_19_orta', 'İnsan sesi grupları, koro, şeflik, oda müziği toplulukları ve klasik müzik formları', Topic.music, Difficulty.medium, BloomLevel.hatirlama, ozMusic19Orta),
  _aile('oz_music_19_zor', 'İnsan sesi grupları, koro, şeflik, oda müziği toplulukları ve klasik müzik formları', Topic.music, Difficulty.hard, BloomLevel.hatirlama, ozMusic19Zor),
  _aile('oz_nature_15_kolay', 'Ağaç türleri, orman kuşakları, tohum yayılma yolları ve bitki uyumları', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature15Kolay),
  _aile('oz_nature_15_orta', 'Ağaç türleri, orman kuşakları, tohum yayılma yolları ve bitki uyumları', Topic.nature, Difficulty.medium, BloomLevel.analiz, ozNature15Orta),
  _aile('oz_nature_15_zor', 'Ağaç türleri, orman kuşakları, tohum yayılma yolları ve bitki uyumları', Topic.nature, Difficulty.hard, BloomLevel.analiz, ozNature15Zor),
  _aile('oz_nature_16_kolay', 'Tatlı su ve sulak alan ekosistemleri: göller, akarsular, deltalar, sazlıklar ve canlıları', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature16Kolay),
  _aile('oz_nature_16_orta', 'Tatlı su ve sulak alan ekosistemleri: göller, akarsular, deltalar, sazlıklar ve canlıları', Topic.nature, Difficulty.medium, BloomLevel.anlama, ozNature16Orta),
  _aile('oz_nature_16_zor', 'Tatlı su ve sulak alan ekosistemleri: göller, akarsular, deltalar, sazlıklar ve canlıları', Topic.nature, Difficulty.hard, BloomLevel.analiz, ozNature16Zor),
  _aile('oz_nature_17_kolay', 'Toprak ekosistemi, ayrıştırıcılar, tozlaşma', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature17Kolay),
  _aile('oz_nature_17_orta', 'Toprak ekosistemi, ayrıştırıcılar, tozlaşma', Topic.nature, Difficulty.medium, BloomLevel.anlama, ozNature17Orta),
  _aile('oz_nature_17_zor', 'Toprak ekosistemi, ayrıştırıcılar, tozlaşma', Topic.nature, Difficulty.hard, BloomLevel.analiz, ozNature17Zor),
  _aile('oz_nature_18_kolay', 'Hayvanlarda iletişim, yön bulma, göç, kış-yaz uykusu, kamuflaj ve mimikri stratejileri', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature18Kolay),
  _aile('oz_nature_18_orta', 'Hayvanlarda iletişim, yön bulma, göç, kış-yaz uykusu, kamuflaj ve mimikri stratejileri', Topic.nature, Difficulty.medium, BloomLevel.anlama, ozNature18Orta),
  _aile('oz_nature_18_zor', 'Hayvanlarda iletişim, yön bulma, göç, kış-yaz uykusu, kamuflaj ve mimikri stratejileri', Topic.nature, Difficulty.hard, BloomLevel.analiz, ozNature18Zor),
  _aile('oz_nature_19_kolay', 'Türkiye\'nin doğal mirasları: kanyonlar, şelaleler, mağaralar, travertenler, biyosfer rezervleri ve jeoparklar', Topic.nature, Difficulty.easy, BloomLevel.hatirlama, ozNature19Kolay),
  _aile('oz_nature_19_orta', 'Türkiye\'nin doğal mirasları: kanyonlar, şelaleler, mağaralar, travertenler, biyosfer rezervleri ve jeoparklar', Topic.nature, Difficulty.medium, BloomLevel.hatirlama, ozNature19Orta),
  _aile('oz_nature_19_zor', 'Türkiye\'nin doğal mirasları: kanyonlar, şelaleler, mağaralar, travertenler, biyosfer rezervleri ve jeoparklar', Topic.nature, Difficulty.hard, BloomLevel.hatirlama, ozNature19Zor),
  _aile('oz_exam_15_kolay', 'TYT-AYT Türkçe: düşünceyi geliştirme yolları, anlatım biçimleri, akışı bozan cümle ve paragraf tamamlama', Topic.exam, Difficulty.easy, BloomLevel.anlama, ozExam15Kolay),
  _aile('oz_exam_15_orta', 'TYT-AYT Türkçe: düşünceyi geliştirme yolları, anlatım biçimleri, akışı bozan cümle ve paragraf tamamlama', Topic.exam, Difficulty.medium, BloomLevel.anlama, ozExam15Orta),
  _aile('oz_exam_15_zor', 'TYT-AYT Türkçe: düşünceyi geliştirme yolları, anlatım biçimleri, akışı bozan cümle ve paragraf tamamlama', Topic.exam, Difficulty.hard, BloomLevel.degerlendirme, ozExam15Zor),
  _aile('oz_exam_16_kolay', 'TYT Matematik: günlük yaşam modelleme, kademeli tarife, nöbet-periyot, kuyruk, terazi ve rutin olmayan sayısal problemler', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam16Kolay),
  _aile('oz_exam_16_orta', 'TYT Matematik: günlük yaşam modelleme, kademeli tarife, nöbet-periyot, kuyruk, terazi ve rutin olmayan sayısal problemler', Topic.exam, Difficulty.medium, BloomLevel.uygulama, ozExam16Orta),
  _aile('oz_exam_16_zor', 'TYT Matematik: günlük yaşam modelleme, kademeli tarife, nöbet-periyot, kuyruk, terazi ve rutin olmayan sayısal problemler', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam16Zor),
  _aile('oz_exam_17_kolay', 'AYT Sosyal-1 karma: edebiyat dönem karşılaştırması, tarihsel kanıt yorumlama ve coğrafi nedensellik soruları', Topic.exam, Difficulty.easy, BloomLevel.hatirlama, ozExam17Kolay),
  _aile('oz_exam_17_orta', 'AYT Sosyal-1 karma: edebiyat dönem karşılaştırması, tarihsel kanıt yorumlama ve coğrafi nedensellik soruları', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam17Orta),
  _aile('oz_exam_17_zor', 'AYT Sosyal-1 karma: edebiyat dönem karşılaştırması, tarihsel kanıt yorumlama ve coğrafi nedensellik soruları', Topic.exam, Difficulty.hard, BloomLevel.degerlendirme, ozExam17Zor),
  _aile('oz_exam_18_kolay', 'TYT-AYT Felsefe: bilgi, varlık, ahlak, sanat, siyaset ve bilim felsefesi özgün metinli çıkarım soruları', Topic.exam, Difficulty.easy, BloomLevel.anlama, ozExam18Kolay),
  _aile('oz_exam_18_orta', 'TYT-AYT Felsefe: bilgi, varlık, ahlak, sanat, siyaset ve bilim felsefesi özgün metinli çıkarım soruları', Topic.exam, Difficulty.medium, BloomLevel.anlama, ozExam18Orta),
  _aile('oz_exam_18_zor', 'TYT-AYT Felsefe: bilgi, varlık, ahlak, sanat, siyaset ve bilim felsefesi özgün metinli çıkarım soruları', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam18Zor),
  _aile('oz_exam_19_kolay', 'Sözel ve sayısal akıl yürütme: takvim-saat, yön-rota, turnuva-puan, raf-koltuk dizilimi ve kurallı şifre kurguları', Topic.exam, Difficulty.easy, BloomLevel.uygulama, ozExam19Kolay),
  _aile('oz_exam_19_orta', 'Sözel ve sayısal akıl yürütme: takvim-saat, yön-rota, turnuva-puan, raf-koltuk dizilimi ve kurallı şifre kurguları', Topic.exam, Difficulty.medium, BloomLevel.analiz, ozExam19Orta),
  _aile('oz_exam_19_zor', 'Sözel ve sayısal akıl yürütme: takvim-saat, yön-rota, turnuva-puan, raf-koltuk dizilimi ve kurallı şifre kurguları', Topic.exam, Difficulty.hard, BloomLevel.analiz, ozExam19Zor),
  _aile('oz_mathematics_15_kolay', 'Üçgenlerde açı, kenar-açı bağıntıları, eşlik-benzerlik ve üçgenin yardımcı elemanları-merkezleri', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics15Kolay),
  _aile('oz_mathematics_15_orta', 'Üçgenlerde açı, kenar-açı bağıntıları, eşlik-benzerlik ve üçgenin yardımcı elemanları-merkezleri', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics15Orta),
  _aile('oz_mathematics_15_zor', 'Üçgenlerde açı, kenar-açı bağıntıları, eşlik-benzerlik ve üçgenin yardımcı elemanları-merkezleri', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics15Zor),
  _aile('oz_mathematics_16_kolay', 'Çokgenler, özel dörtgenler ve çemberde açı-kiriş-teğet-kuvvet özellikleri', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics16Kolay),
  _aile('oz_mathematics_16_orta', 'Çokgenler, özel dörtgenler ve çemberde açı-kiriş-teğet-kuvvet özellikleri', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics16Orta),
  _aile('oz_mathematics_16_zor', 'Çokgenler, özel dörtgenler ve çemberde açı-kiriş-teğet-kuvvet özellikleri', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics16Zor),
  _aile('oz_mathematics_17_kolay', 'Katı cisimler ve uzay geometrisi: prizma, piramit, silindir, koni, küre, kesit ve açınım problemleri', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics17Kolay),
  _aile('oz_mathematics_17_orta', 'Katı cisimler ve uzay geometrisi: prizma, piramit, silindir, koni, küre, kesit ve açınım problemleri', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics17Orta),
  _aile('oz_mathematics_17_zor', 'Katı cisimler ve uzay geometrisi: prizma, piramit, silindir, koni, küre, kesit ve açınım problemleri', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics17Zor),
  _aile('oz_mathematics_18_kolay', 'Logaritma modelleri, üstel büyüme-bozunma, modüler aritmetik ve sayı kuramı uygulamaları', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics18Kolay),
  _aile('oz_mathematics_18_orta', 'Logaritma modelleri, üstel büyüme-bozunma, modüler aritmetik ve sayı kuramı uygulamaları', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics18Orta),
  _aile('oz_mathematics_18_zor', 'Logaritma modelleri, üstel büyüme-bozunma, modüler aritmetik ve sayı kuramı uygulamaları', Topic.mathematics, Difficulty.hard, BloomLevel.analiz, ozMathematics18Zor),
  _aile('oz_mathematics_19_kolay', 'Türev ve integral uygulamaları: teğet eğimi, ekstremum, maksimum-minimum optimizasyon, eğri altı alan ve değişim hızı', Topic.mathematics, Difficulty.easy, BloomLevel.uygulama, ozMathematics19Kolay),
  _aile('oz_mathematics_19_orta', 'Türev ve integral uygulamaları: teğet eğimi, ekstremum, maksimum-minimum optimizasyon, eğri altı alan ve değişim hızı', Topic.mathematics, Difficulty.medium, BloomLevel.uygulama, ozMathematics19Orta),
  _aile('oz_mathematics_19_zor', 'Türev ve integral uygulamaları: teğet eğimi, ekstremum, maksimum-minimum optimizasyon, eğri altı alan ve değişim hızı', Topic.mathematics, Difficulty.hard, BloomLevel.uygulama, ozMathematics19Zor),
  _aile('oz_physics_15_kolay', 'Basit makineler, tork, kütle merkezi ve statik denge sistemleri', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics15Kolay),
  _aile('oz_physics_15_orta', 'Basit makineler, tork, kütle merkezi ve statik denge sistemleri', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics15Orta),
  _aile('oz_physics_15_zor', 'Basit makineler, tork, kütle merkezi ve statik denge sistemleri', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics15Zor),
  _aile('oz_physics_16_kolay', 'Basit harmonik hareket, evrensel kütleçekim, Kepler yasaları ve uydu yörüngeleri', Topic.physics, Difficulty.easy, BloomLevel.anlama, ozPhysics16Kolay),
  _aile('oz_physics_16_orta', 'Basit harmonik hareket, evrensel kütleçekim, Kepler yasaları ve uydu yörüngeleri', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics16Orta),
  _aile('oz_physics_16_zor', 'Basit harmonik hareket, evrensel kütleçekim, Kepler yasaları ve uydu yörüngeleri', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics16Zor),
  _aile('oz_physics_17_kolay', 'Sığaçlar', Topic.physics, Difficulty.easy, BloomLevel.hatirlama, ozPhysics17Kolay),
  _aile('oz_physics_17_orta', 'Sığaçlar', Topic.physics, Difficulty.medium, BloomLevel.uygulama, ozPhysics17Orta),
  _aile('oz_physics_17_zor', 'Sığaçlar', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics17Zor),
  _aile('oz_physics_18_kolay', 'Geometrik optik ve dalga optiği: aynalar, mercekler, tam yansıma, çift yarık girişimi, tek yarık kırınımı, kutuplanma ve renk', Topic.physics, Difficulty.easy, BloomLevel.hatirlama, ozPhysics18Kolay),
  _aile('oz_physics_18_orta', 'Geometrik optik ve dalga optiği: aynalar, mercekler, tam yansıma, çift yarık girişimi, tek yarık kırınımı, kutuplanma ve renk', Topic.physics, Difficulty.medium, BloomLevel.anlama, ozPhysics18Orta),
  _aile('oz_physics_18_zor', 'Geometrik optik ve dalga optiği: aynalar, mercekler, tam yansıma, çift yarık girişimi, tek yarık kırınımı, kutuplanma ve renk', Topic.physics, Difficulty.hard, BloomLevel.uygulama, ozPhysics18Zor),
  _aile('oz_physics_19_kolay', 'Astrofizik: yıldızların yaşam döngüsü, HR diyagramı, tayf analizi, Doppler kırmızıya kayma ve ötegezegen keşif yöntemleri', Topic.physics, Difficulty.easy, BloomLevel.hatirlama, ozPhysics19Kolay),
  _aile('oz_physics_19_orta', 'Astrofizik: yıldızların yaşam döngüsü, HR diyagramı, tayf analizi, Doppler kırmızıya kayma ve ötegezegen keşif yöntemleri', Topic.physics, Difficulty.medium, BloomLevel.anlama, ozPhysics19Orta),
  _aile('oz_physics_19_zor', 'Astrofizik: yıldızların yaşam döngüsü, HR diyagramı, tayf analizi, Doppler kırmızıya kayma ve ötegezegen keşif yöntemleri', Topic.physics, Difficulty.hard, BloomLevel.analiz, ozPhysics19Zor),
  _aile('oz_chemistry_15_kolay', 'Elektrokimya: redoks tepkimeleri, aktiflik, galvanik piller, Nernst mantığı, elektroliz, Faraday yasaları ve korozyondan korunma', Topic.chemistry, Difficulty.easy, BloomLevel.anlama, ozChemistry15Kolay),
  _aile('oz_chemistry_15_orta', 'Elektrokimya: redoks tepkimeleri, aktiflik, galvanik piller, Nernst mantığı, elektroliz, Faraday yasaları ve korozyondan korunma', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry15Orta),
  _aile('oz_chemistry_15_zor', 'Elektrokimya: redoks tepkimeleri, aktiflik, galvanik piller, Nernst mantığı, elektroliz, Faraday yasaları ve korozyondan korunma', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry15Zor),
  _aile('oz_chemistry_16_kolay', 'Kimyasal enerji', Topic.chemistry, Difficulty.easy, BloomLevel.uygulama, ozChemistry16Kolay),
  _aile('oz_chemistry_16_orta', 'Kimyasal enerji', Topic.chemistry, Difficulty.medium, BloomLevel.uygulama, ozChemistry16Orta),
  _aile('oz_chemistry_16_zor', 'Kimyasal enerji', Topic.chemistry, Difficulty.hard, BloomLevel.uygulama, ozChemistry16Zor),
  _aile('oz_chemistry_17_kolay', 'Laboratuvar güvenliği, cam araç-gereçler, ayırma-saflaştırma yöntemleri ve titrasyon-nitel analiz uygulamaları', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry17Kolay),
  _aile('oz_chemistry_17_orta', 'Laboratuvar güvenliği, cam araç-gereçler, ayırma-saflaştırma yöntemleri ve titrasyon-nitel analiz uygulamaları', Topic.chemistry, Difficulty.medium, BloomLevel.anlama, ozChemistry17Orta),
  _aile('oz_chemistry_17_zor', 'Laboratuvar güvenliği, cam araç-gereçler, ayırma-saflaştırma yöntemleri ve titrasyon-nitel analiz uygulamaları', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry17Zor),
  _aile('oz_chemistry_18_kolay', 'Su ve çevre kimyası, sert su, asit yağmurları, atmosfer kirleticileri, geri dönüşüm ve yeşil kimya ilkeleri', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry18Kolay),
  _aile('oz_chemistry_18_orta', 'Su ve çevre kimyası, sert su, asit yağmurları, atmosfer kirleticileri, geri dönüşüm ve yeşil kimya ilkeleri', Topic.chemistry, Difficulty.medium, BloomLevel.anlama, ozChemistry18Orta),
  _aile('oz_chemistry_18_zor', 'Su ve çevre kimyası, sert su, asit yağmurları, atmosfer kirleticileri, geri dönüşüm ve yeşil kimya ilkeleri', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry18Zor),
  _aile('oz_chemistry_19_kolay', 'Metalürji, alaşımlar, seramikler, cam, çimento, yarı iletkenler ve kompozit malzemelerin kimyası', Topic.chemistry, Difficulty.easy, BloomLevel.hatirlama, ozChemistry19Kolay),
  _aile('oz_chemistry_19_orta', 'Metalürji, alaşımlar, seramikler, cam, çimento, yarı iletkenler ve kompozit malzemelerin kimyası', Topic.chemistry, Difficulty.medium, BloomLevel.anlama, ozChemistry19Orta),
  _aile('oz_chemistry_19_zor', 'Metalürji, alaşımlar, seramikler, cam, çimento, yarı iletkenler ve kompozit malzemelerin kimyası', Topic.chemistry, Difficulty.hard, BloomLevel.analiz, ozChemistry19Zor),
  _aile('oz_biology_15_kolay', 'Bitki biyolojisi ayrıntıları: bitkisel dokular, hormonlar, ksilem-floem taşıması, stoma mekanizması, tropizma-nasti ve fotoperiyodizm', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology15Kolay),
  _aile('oz_biology_15_orta', 'Bitki biyolojisi ayrıntıları: bitkisel dokular, hormonlar, ksilem-floem taşıması, stoma mekanizması, tropizma-nasti ve fotoperiyodizm', Topic.biology, Difficulty.medium, BloomLevel.analiz, ozBiology15Orta),
  _aile('oz_biology_15_zor', 'Bitki biyolojisi ayrıntıları: bitkisel dokular, hormonlar, ksilem-floem taşıması, stoma mekanizması, tropizma-nasti ve fotoperiyodizm', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology15Zor),
  _aile('oz_biology_16_kolay', 'Mikrobiyoloji ve sınıflandırma: bakteriler, arkeler, protistler, mantarlar, virüs döngüleri ve ikili adlandırma kuralları', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology16Kolay),
  _aile('oz_biology_16_orta', 'Mikrobiyoloji ve sınıflandırma: bakteriler, arkeler, protistler, mantarlar, virüs döngüleri ve ikili adlandırma kuralları', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology16Orta),
  _aile('oz_biology_16_zor', 'Mikrobiyoloji ve sınıflandırma: bakteriler, arkeler, protistler, mantarlar, virüs döngüleri ve ikili adlandırma kuralları', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology16Zor),
  _aile('oz_biology_17_kolay', 'Evrimsel biyoloji ve popülasyon genetiği: doğal seçilim biçimleri, Hardy-Weinberg dengesi, genetik sürüklenme ve türleşme mekanizmaları', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology17Kolay),
  _aile('oz_biology_17_orta', 'Evrimsel biyoloji ve popülasyon genetiği: doğal seçilim biçimleri, Hardy-Weinberg dengesi, genetik sürüklenme ve türleşme mekanizmaları', Topic.biology, Difficulty.medium, BloomLevel.uygulama, ozBiology17Orta),
  _aile('oz_biology_17_zor', 'Evrimsel biyoloji ve popülasyon genetiği: doğal seçilim biçimleri, Hardy-Weinberg dengesi, genetik sürüklenme ve türleşme mekanizmaları', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology17Zor),
  _aile('oz_biology_18_kolay', 'İnsan embriyonik gelişimi, kök hücre türleri, doku-organ farklılaşması ve kalıtsal hastalıkların genetik danışmanlığı', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology18Kolay),
  _aile('oz_biology_18_orta', 'İnsan embriyonik gelişimi, kök hücre türleri, doku-organ farklılaşması ve kalıtsal hastalıkların genetik danışmanlığı', Topic.biology, Difficulty.medium, BloomLevel.anlama, ozBiology18Orta),
  _aile('oz_biology_18_zor', 'İnsan embriyonik gelişimi, kök hücre türleri, doku-organ farklılaşması ve kalıtsal hastalıkların genetik danışmanlığı', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology18Zor),
  _aile('oz_biology_19_kolay', 'Canlıların temel bileşenleri ayrıntılı: karbonhidratlar, lipitler, protein yapısı, vitaminler, mineraller, ATP ve nükleik asit biyokimyası', Topic.biology, Difficulty.easy, BloomLevel.hatirlama, ozBiology19Kolay),
  _aile('oz_biology_19_orta', 'Canlıların temel bileşenleri ayrıntılı: karbonhidratlar, lipitler, protein yapısı, vitaminler, mineraller, ATP ve nükleik asit biyokimyası', Topic.biology, Difficulty.medium, BloomLevel.hatirlama, ozBiology19Orta),
  _aile('oz_biology_19_zor', 'Canlıların temel bileşenleri ayrıntılı: karbonhidratlar, lipitler, protein yapısı, vitaminler, mineraller, ATP ve nükleik asit biyokimyası', Topic.biology, Difficulty.hard, BloomLevel.analiz, ozBiology19Zor),
  _aile('oz_engineering_15_kolay', 'Deprem mühendisliği, zemin mekaniği, temel türleri, köprü, tünel ve baraj yapıları', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering15Kolay),
  _aile('oz_engineering_15_orta', 'Deprem mühendisliği, zemin mekaniği, temel türleri, köprü, tünel ve baraj yapıları', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering15Orta),
  _aile('oz_engineering_15_zor', 'Deprem mühendisliği, zemin mekaniği, temel türleri, köprü, tünel ve baraj yapıları', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering15Zor),
  _aile('oz_engineering_16_kolay', 'Teknik resim, görünüş çıkarma, tolerans, hassas ölçüm aletleri', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering16Kolay),
  _aile('oz_engineering_16_orta', 'Teknik resim, görünüş çıkarma, tolerans, hassas ölçüm aletleri', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering16Orta),
  _aile('oz_engineering_16_zor', 'Teknik resim, görünüş çıkarma, tolerans, hassas ölçüm aletleri', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering16Zor),
  _aile('oz_engineering_17_kolay', 'Enerji sistemleri mühendisliği: güç santrali çevrimleri, kojenerasyon, ısı pompaları, ısıl yalıtım', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering17Kolay),
  _aile('oz_engineering_17_orta', 'Enerji sistemleri mühendisliği: güç santrali çevrimleri, kojenerasyon, ısı pompaları, ısıl yalıtım', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering17Orta),
  _aile('oz_engineering_17_zor', 'Enerji sistemleri mühendisliği: güç santrali çevrimleri, kojenerasyon, ısı pompaları, ısıl yalıtım', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering17Zor),
  _aile('oz_engineering_18_kolay', 'Endüstri mühendisliği, süreç iyileştirme, yalın üretim, tedarik zinciri, kritik yol', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering18Kolay),
  _aile('oz_engineering_18_orta', 'Endüstri mühendisliği, süreç iyileştirme, yalın üretim, tedarik zinciri, kritik yol', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering18Orta),
  _aile('oz_engineering_18_zor', 'Endüstri mühendisliği, süreç iyileştirme, yalın üretim, tedarik zinciri, kritik yol', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering18Zor),
  _aile('oz_engineering_19_kolay', 'Çevre ve su mühendisliği: içme suyu ve atık su arıtma basamakları, katı atık yönetimi, biyogaz ve baca gazı arıtımı', Topic.engineering, Difficulty.easy, BloomLevel.hatirlama, ozEngineering19Kolay),
  _aile('oz_engineering_19_orta', 'Çevre ve su mühendisliği: içme suyu ve atık su arıtma basamakları, katı atık yönetimi, biyogaz ve baca gazı arıtımı', Topic.engineering, Difficulty.medium, BloomLevel.anlama, ozEngineering19Orta),
  _aile('oz_engineering_19_zor', 'Çevre ve su mühendisliği: içme suyu ve atık su arıtma basamakları, katı atık yönetimi, biyogaz ve baca gazı arıtımı', Topic.engineering, Difficulty.hard, BloomLevel.analiz, ozEngineering19Zor),
  _aile('oz_computing_15_kolay', 'Kriptografi, özet fonksiyonları', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing15Kolay),
  _aile('oz_computing_15_orta', 'Kriptografi, özet fonksiyonları', Topic.computing, Difficulty.medium, BloomLevel.anlama, ozComputing15Orta),
  _aile('oz_computing_15_zor', 'Kriptografi, özet fonksiyonları', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing15Zor),
  _aile('oz_computing_16_kolay', 'Düzenli ifadeler', Topic.computing, Difficulty.easy, BloomLevel.uygulama, ozComputing16Kolay),
  _aile('oz_computing_16_orta', 'Düzenli ifadeler', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing16Orta),
  _aile('oz_computing_16_zor', 'Düzenli ifadeler', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing16Zor),
  _aile('oz_computing_17_kolay', 'Graf kuramı uygulamaları, BFS/DFS, en kısa yol, en küçük kapsayan ağaç, açgözlü', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing17Kolay),
  _aile('oz_computing_17_orta', 'Graf kuramı uygulamaları, BFS/DFS, en kısa yol, en küçük kapsayan ağaç, açgözlü', Topic.computing, Difficulty.medium, BloomLevel.uygulama, ozComputing17Orta),
  _aile('oz_computing_17_zor', 'Graf kuramı uygulamaları, BFS/DFS, en kısa yol, en küçük kapsayan ağaç, açgözlü', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing17Zor),
  _aile('oz_computing_18_kolay', 'Eşzamanlılık', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing18Kolay),
  _aile('oz_computing_18_orta', 'Eşzamanlılık', Topic.computing, Difficulty.medium, BloomLevel.anlama, ozComputing18Orta),
  _aile('oz_computing_18_zor', 'Eşzamanlılık', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing18Zor),
  _aile('oz_computing_19_kolay', 'İnsan-bilgisayar etkileşimi', Topic.computing, Difficulty.easy, BloomLevel.hatirlama, ozComputing19Kolay),
  _aile('oz_computing_19_orta', 'İnsan-bilgisayar etkileşimi', Topic.computing, Difficulty.medium, BloomLevel.anlama, ozComputing19Orta),
  _aile('oz_computing_19_zor', 'İnsan-bilgisayar etkileşimi', Topic.computing, Difficulty.hard, BloomLevel.analiz, ozComputing19Zor),
  _aile('oz_statistics_15_kolay', 'Bayes çıkarımı, tanı testleri', Topic.statistics, Difficulty.easy, BloomLevel.uygulama, ozStatistics15Kolay),
  _aile('oz_statistics_15_orta', 'Bayes çıkarımı, tanı testleri', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics15Orta),
  _aile('oz_statistics_15_zor', 'Bayes çıkarımı, tanı testleri', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics15Zor),
  _aile('oz_statistics_16_kolay', 'Zaman serileri, endeks sayılar, baz yılı, hareketli ortalamalar, mevsimsel düzeltme ve demografik oran hesapları', Topic.statistics, Difficulty.easy, BloomLevel.hatirlama, ozStatistics16Kolay),
  _aile('oz_statistics_16_orta', 'Zaman serileri, endeks sayılar, baz yılı, hareketli ortalamalar, mevsimsel düzeltme ve demografik oran hesapları', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics16Orta),
  _aile('oz_statistics_16_zor', 'Zaman serileri, endeks sayılar, baz yılı, hareketli ortalamalar, mevsimsel düzeltme ve demografik oran hesapları', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics16Zor),
  _aile('oz_statistics_17_kolay', 'A/B testleri, istatistiksel güç, etki büyüklüğü, çoklu karşılaştırma yanılgısı, karıştırıcı değişkenler ve Simpson paradoksu', Topic.statistics, Difficulty.easy, BloomLevel.hatirlama, ozStatistics17Kolay),
  _aile('oz_statistics_17_orta', 'A/B testleri, istatistiksel güç, etki büyüklüğü, çoklu karşılaştırma yanılgısı, karıştırıcı değişkenler ve Simpson paradoksu', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics17Orta),
  _aile('oz_statistics_17_zor', 'A/B testleri, istatistiksel güç, etki büyüklüğü, çoklu karşılaştırma yanılgısı, karıştırıcı değişkenler ve Simpson paradoksu', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics17Zor),
  _aile('oz_statistics_18_kolay', 'Sıra istatistikleri, çeyreklikler', Topic.statistics, Difficulty.easy, BloomLevel.hatirlama, ozStatistics18Kolay),
  _aile('oz_statistics_18_orta', 'Sıra istatistikleri, çeyreklikler', Topic.statistics, Difficulty.medium, BloomLevel.uygulama, ozStatistics18Orta),
  _aile('oz_statistics_18_zor', 'Sıra istatistikleri, çeyreklikler', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics18Zor),
  _aile('oz_statistics_19_kolay', 'Veri ön işleme, eksik veri türleri, ölçekleme, karışıklık matrisi', Topic.statistics, Difficulty.easy, BloomLevel.hatirlama, ozStatistics19Kolay),
  _aile('oz_statistics_19_orta', 'Veri ön işleme, eksik veri türleri, ölçekleme, karışıklık matrisi', Topic.statistics, Difficulty.medium, BloomLevel.anlama, ozStatistics19Orta),
  _aile('oz_statistics_19_zor', 'Veri ön işleme, eksik veri türleri, ölçekleme, karışıklık matrisi', Topic.statistics, Difficulty.hard, BloomLevel.analiz, ozStatistics19Zor),
  _aile('oz_economics_15_kolay', 'Davranışsal iktisat, oyun kuramı', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics15Kolay),
  _aile('oz_economics_15_orta', 'Davranışsal iktisat, oyun kuramı', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics15Orta),
  _aile('oz_economics_15_zor', 'Davranışsal iktisat, oyun kuramı', Topic.economics, Difficulty.hard, BloomLevel.analiz, ozEconomics15Zor),
  _aile('oz_economics_16_kolay', 'Kamu ekonomisi: dışsallıklar, tam kamusal mallar, bedavacılık sorunu, Pigou vergisi, vergi tarifeleri ve gelir dağılımı', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics16Kolay),
  _aile('oz_economics_16_orta', 'Kamu ekonomisi: dışsallıklar, tam kamusal mallar, bedavacılık sorunu, Pigou vergisi, vergi tarifeleri ve gelir dağılımı', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics16Orta),
  _aile('oz_economics_16_zor', 'Kamu ekonomisi: dışsallıklar, tam kamusal mallar, bedavacılık sorunu, Pigou vergisi, vergi tarifeleri ve gelir dağılımı', Topic.economics, Difficulty.hard, BloomLevel.analiz, ozEconomics16Zor),
  _aile('oz_economics_17_kolay', 'Kalkınma ekonomisi, beşerî sermaye, İnsani Gelişme Endeksi, döngüsel ekonomi, karbon fiyatlama ve sürdürülebilir kalkınma', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics17Kolay),
  _aile('oz_economics_17_orta', 'Kalkınma ekonomisi, beşerî sermaye, İnsani Gelişme Endeksi, döngüsel ekonomi, karbon fiyatlama ve sürdürülebilir kalkınma', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics17Orta),
  _aile('oz_economics_17_zor', 'Kalkınma ekonomisi, beşerî sermaye, İnsani Gelişme Endeksi, döngüsel ekonomi, karbon fiyatlama ve sürdürülebilir kalkınma', Topic.economics, Difficulty.hard, BloomLevel.analiz, ozEconomics17Zor),
  _aile('oz_economics_18_kolay', 'Temel muhasebe ve finansal tablo analizi: bilanço eşitliği, gelir tablosu, cari oran, kârlılık marjları, amortisman ve başabaş noktası', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics18Kolay),
  _aile('oz_economics_18_orta', 'Temel muhasebe ve finansal tablo analizi: bilanço eşitliği, gelir tablosu, cari oran, kârlılık marjları, amortisman ve başabaş noktası', Topic.economics, Difficulty.medium, BloomLevel.anlama, ozEconomics18Orta),
  _aile('oz_economics_18_zor', 'Temel muhasebe ve finansal tablo analizi: bilanço eşitliği, gelir tablosu, cari oran, kârlılık marjları, amortisman ve başabaş noktası', Topic.economics, Difficulty.hard, BloomLevel.analiz, ozEconomics18Zor),
  _aile('oz_economics_19_kolay', 'Türkiye iktisat tarihi ve iktisadi kurumlar', Topic.economics, Difficulty.easy, BloomLevel.hatirlama, ozEconomics19Kolay),
  _aile('oz_economics_19_orta', 'Türkiye iktisat tarihi ve iktisadi kurumlar', Topic.economics, Difficulty.medium, BloomLevel.hatirlama, ozEconomics19Orta),
  _aile('oz_economics_19_zor', 'Türkiye iktisat tarihi ve iktisadi kurumlar', Topic.economics, Difficulty.hard, BloomLevel.hatirlama, ozEconomics19Zor),
  _aile('oz_socialScience_15_kolay', 'Kültürel antropoloji ve etnografya: kültürel görelilik, etnosantrizm, geçiş ritüelleri, akrabalık, sözlü ve maddi kültür', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience15Kolay),
  _aile('oz_socialScience_15_orta', 'Kültürel antropoloji ve etnografya: kültürel görelilik, etnosantrizm, geçiş ritüelleri, akrabalık, sözlü ve maddi kültür', Topic.socialScience, Difficulty.medium, BloomLevel.hatirlama, ozSocialscience15Orta),
  _aile('oz_socialScience_15_zor', 'Kültürel antropoloji ve etnografya: kültürel görelilik, etnosantrizm, geçiş ritüelleri, akrabalık, sözlü ve maddi kültür', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience15Zor),
  _aile('oz_socialScience_16_kolay', 'İletişim bilimleri, medya kuramları ve medya okuryazarlığı', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience16Kolay),
  _aile('oz_socialScience_16_orta', 'İletişim bilimleri, medya kuramları ve medya okuryazarlığı', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience16Orta),
  _aile('oz_socialScience_16_zor', 'İletişim bilimleri, medya kuramları ve medya okuryazarlığı', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience16Zor),
  _aile('oz_socialScience_17_kolay', 'Eğitim bilimleri ve öğrenme psikolojisi uygulamaları', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience17Kolay),
  _aile('oz_socialScience_17_orta', 'Eğitim bilimleri ve öğrenme psikolojisi uygulamaları', Topic.socialScience, Difficulty.medium, BloomLevel.uygulama, ozSocialscience17Orta),
  _aile('oz_socialScience_17_zor', 'Eğitim bilimleri ve öğrenme psikolojisi uygulamaları', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience17Zor),
  _aile('oz_socialScience_18_kolay', 'Kent sosyolojisi, göç kuramları, demografik dönüşüm ve çalışma sosyolojisi', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience18Kolay),
  _aile('oz_socialScience_18_orta', 'Kent sosyolojisi, göç kuramları, demografik dönüşüm ve çalışma sosyolojisi', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience18Orta),
  _aile('oz_socialScience_18_zor', 'Kent sosyolojisi, göç kuramları, demografik dönüşüm ve çalışma sosyolojisi', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience18Zor),
  _aile('oz_socialScience_19_kolay', 'Hukukun temel dalları, yargı ilkeleri ve insan hakları belgeleri tarihi', Topic.socialScience, Difficulty.easy, BloomLevel.hatirlama, ozSocialscience19Kolay),
  _aile('oz_socialScience_19_orta', 'Hukukun temel dalları, yargı ilkeleri ve insan hakları belgeleri tarihi', Topic.socialScience, Difficulty.medium, BloomLevel.anlama, ozSocialscience19Orta),
  _aile('oz_socialScience_19_zor', 'Hukukun temel dalları, yargı ilkeleri ve insan hakları belgeleri tarihi', Topic.socialScience, Difficulty.hard, BloomLevel.analiz, ozSocialscience19Zor),
  _aile('oz_research_15_kolay', 'Sistematik derleme, meta-analiz, kanıt piramidi ve bilimsel hakemlik süreci', Topic.research, Difficulty.easy, BloomLevel.hatirlama, ozResearch15Kolay),
  _aile('oz_research_15_orta', 'Sistematik derleme, meta-analiz, kanıt piramidi ve bilimsel hakemlik süreci', Topic.research, Difficulty.medium, BloomLevel.anlama, ozResearch15Orta),
  _aile('oz_research_15_zor', 'Sistematik derleme, meta-analiz, kanıt piramidi ve bilimsel hakemlik süreci', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch15Zor),
  _aile('oz_research_16_kolay', 'Anket ve ölçek tasarımı: soru yazım hataları, çift namlulu ve yönlendirici sorular, sosyal beğenilirlik, tavan-taban etkisi ve güvenirlik', Topic.research, Difficulty.easy, BloomLevel.hatirlama, ozResearch16Kolay),
  _aile('oz_research_16_orta', 'Anket ve ölçek tasarımı: soru yazım hataları, çift namlulu ve yönlendirici sorular, sosyal beğenilirlik, tavan-taban etkisi ve güvenirlik', Topic.research, Difficulty.medium, BloomLevel.analiz, ozResearch16Orta),
  _aile('oz_research_16_zor', 'Anket ve ölçek tasarımı: soru yazım hataları, çift namlulu ve yönlendirici sorular, sosyal beğenilirlik, tavan-taban etkisi ve güvenirlik', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch16Zor),
  _aile('oz_research_17_kolay', 'Boylamsal, kesitsel, kohort, vaka-kontrol ve saha araştırması desenleri', Topic.research, Difficulty.easy, BloomLevel.hatirlama, ozResearch17Kolay),
  _aile('oz_research_17_orta', 'Boylamsal, kesitsel, kohort, vaka-kontrol ve saha araştırması desenleri', Topic.research, Difficulty.medium, BloomLevel.analiz, ozResearch17Orta),
  _aile('oz_research_17_zor', 'Boylamsal, kesitsel, kohort, vaka-kontrol ve saha araştırması desenleri', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch17Zor),
  _aile('oz_research_18_kolay', 'Açık bilim, tekrarlanabilirlik, ön kayıt', Topic.research, Difficulty.easy, BloomLevel.hatirlama, ozResearch18Kolay),
  _aile('oz_research_18_orta', 'Açık bilim, tekrarlanabilirlik, ön kayıt', Topic.research, Difficulty.medium, BloomLevel.anlama, ozResearch18Orta),
  _aile('oz_research_18_zor', 'Açık bilim, tekrarlanabilirlik, ön kayıt', Topic.research, Difficulty.hard, BloomLevel.analiz, ozResearch18Zor),
  _aile('oz_research_19_kolay', 'Bilim iletişimi ve medya okuryazarlığı: abartılı manşetleri, yanıltıcı grafikleri, mutlak-göreli risk farkını ve örneklem tuzaklarını saptama', Topic.research, Difficulty.easy, BloomLevel.anlama, ozResearch19Kolay),
  _aile('oz_research_19_orta', 'Bilim iletişimi ve medya okuryazarlığı: abartılı manşetleri, yanıltıcı grafikleri, mutlak-göreli risk farkını ve örneklem tuzaklarını saptama', Topic.research, Difficulty.medium, BloomLevel.analiz, ozResearch19Orta),
  _aile('oz_research_19_zor', 'Bilim iletişimi ve medya okuryazarlığı: abartılı manşetleri, yanıltıcı grafikleri, mutlak-göreli risk farkını ve örneklem tuzaklarını saptama', Topic.research, Difficulty.hard, BloomLevel.degerlendirme, ozResearch19Zor),
];

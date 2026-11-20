/// Verified YouTube descriptions, 18 November 2026. This is a dated selection.
class VoiceProjectCatalog {
  static const entries = [
    (name: 'Romantic Alexa', views: 2333192, video: 'https://www.youtube.com/watch?v=AWvsXxDtEkU', repo: 'https://github.com/ProgrammingHero1/romantic-alexa'),
    (name: 'Jarvis AI', views: 1441650, video: 'https://www.youtube.com/watch?v=s_8b5iq4Rvk', repo: 'https://github.com/CodeWithHarry/JarvisAI-YouTube'),
    (name: 'Whisplay AI Chatbot', views: 705081, video: 'https://www.youtube.com/watch?v=kFmhSTh167U', repo: 'https://github.com/PiSugar/whisplay-ai-chatbot'),
    (name: 'Xiaozhi Desk Buddy', views: 561292, video: 'https://www.youtube.com/watch?v=aDaSp6zaqWM', repo: 'https://github.com/TechTalkies/Xiaozhi-for-XiaoESP32S3'),
    (name: 'Jarvis for Windows', views: 495091, video: 'https://www.youtube.com/watch?v=RAKpMYOlttA', repo: 'https://github.com/crackallcode/AI-Assistant-'),
  ];

  static String describe() => [
    '18 Kasım 2026’da incelenen ve açıklamasında kaynak kod içeren GitHub depo bağlantısı bulunan videolar:',
    for (final (i, project) in entries.indexed)
      '${i + 1}. ${project.name} — ${project.views} izlenme',
    'Örneğin “ikinci Jarvis projesinin kodunu aç” diyebilirsin.',
  ].join('\n');
}

package com.mehmetderin.kitapbul_flutter;

import android.app.Activity;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.speech.RecognitionListener;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;
import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Türkçe konuşma tanıma (SpeechRecognizer) ve sesli okuma (Edge Neural TTS
 * tr-TR-AhmetNeural varsayılan + çevrimdışı Android TextToSpeech yedek)
 * için yerel Android köprüsü ("kitapbul/voice").
 */
final class VoiceAssistantBridge {
    private static final Locale TR = Locale.forLanguageTag("tr-TR");

    private final Activity activity;
    private final MethodChannel channel;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService ttsExecutor = Executors.newSingleThreadExecutor();

    private SpeechRecognizer recognizer;
    private TextToSpeech tts;
    private MediaPlayer ttsPlayer;
    private boolean ttsReady = false;
    private boolean listening = false;
    private volatile String currentVoice = EdgeTtsSynthesizer.DEFAULT_VOICE;
    private volatile int speakToken = 0;

    VoiceAssistantBridge(Activity activity, MethodChannel channel) {
        this.activity = activity;
        this.channel = channel;
        initTts();
    }

    private void initTts() {
        try {
            tts = new TextToSpeech(activity.getApplicationContext(), status -> {
                if (status == TextToSpeech.SUCCESS && tts != null) {
                    int res = tts.setLanguage(TR);
                    ttsReady = (res != TextToSpeech.LANG_MISSING_DATA
                            && res != TextToSpeech.LANG_NOT_SUPPORTED);
                    if (!ttsReady) {
                        // Türkçe ses paketi eksikse varsayılan sistem diline düş
                        tts.setLanguage(Locale.getDefault());
                        ttsReady = true;
                    }
                    tts.setOnUtteranceProgressListener(new UtteranceProgressListener() {
                        @Override
                        public void onStart(String utteranceId) {
                            sendEvent("ttsStart", utteranceId, 0f);
                        }

                        @Override
                        public void onDone(String utteranceId) {
                            sendEvent("ttsDone", utteranceId, 0f);
                        }

                        @Override
                        public void onError(String utteranceId) {
                            sendEvent("ttsError", utteranceId, 0f);
                        }
                    });
                }
            });
        } catch (Exception ignored) {
            ttsReady = false;
        }
    }

    Map<String, Object> status(boolean micPermissionGranted) {
        Map<String, Object> out = new HashMap<>();
        out.put("micPermission", micPermissionGranted);
        out.put("speechAvailable", SpeechRecognizer.isRecognitionAvailable(activity));
        out.put("ttsReady", true);
        out.put("ttsVoice", currentVoice);
        out.put("listening", listening);
        return out;
    }

    void setVoice(String voice, MethodChannel.Result result) {
        currentVoice = EdgeTtsSynthesizer.resolveVoice(voice);
        result.success(currentVoice);
    }

    void startListening(String localeTag, MethodChannel.Result result) {
        main.post(() -> {
            try {
                stopSpeakingInternal();
                ensureRecognizer();
                if (recognizer == null) {
                    result.error("unavailable", "Bu cihazda ses tanıma servisi bulunamadı", null);
                    return;
                }
                Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
                intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
                String lang = (localeTag == null || localeTag.trim().isEmpty()) ? "tr-TR" : localeTag.trim();
                intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang);
                intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, lang);
                intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true);
                intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3);
                listening = true;
                recognizer.startListening(intent);
                result.success(true);
            } catch (Exception e) {
                listening = false;
                result.error("listen_error", "Mikrofon başlatılamadı: " + e.getMessage(), null);
            }
        });
    }

    void stopListening(MethodChannel.Result result) {
        main.post(() -> {
            try {
                if (recognizer != null && listening) {
                    recognizer.stopListening();
                }
                listening = false;
                result.success(true);
            } catch (Exception e) {
                listening = false;
                result.success(false);
            }
        });
    }

    void cancelListening(MethodChannel.Result result) {
        main.post(() -> {
            try {
                if (recognizer != null) {
                    recognizer.cancel();
                }
                listening = false;
                result.success(true);
            } catch (Exception e) {
                listening = false;
                result.success(false);
            }
        });
    }

    void speak(String text, double rate, double pitch, String voice, MethodChannel.Result result) {
        main.post(() -> {
            if (text == null || text.trim().isEmpty()) {
                result.success(false);
                return;
            }
            stopSpeakingInternal();
            final int token = ++speakToken;
            if (voice != null && !voice.trim().isEmpty()) {
                currentVoice = EdgeTtsSynthesizer.resolveVoice(voice);
            }
            final String resolvedVoice = EdgeTtsSynthesizer.resolveVoice(currentVoice);
            final String id = "utt-" + UUID.randomUUID();
            final String clean = text.length() > 3600 ? text.substring(0, 3600) : text;

            if (!EdgeTtsSynthesizer.SYSTEM_VOICE.equalsIgnoreCase(resolvedVoice)) {
                result.success(true);
                sendEvent("ttsStart", id, 0f);
                final File cacheDir = activity.getCacheDir();
                ttsExecutor.execute(() -> {
                    if (token != speakToken) return;
                    File mp3File = EdgeTtsSynthesizer.synthesizeToFile(
                            cacheDir, clean, resolvedVoice, rate, pitch);
                    if (token != speakToken) return;
                    if (mp3File != null && mp3File.exists() && mp3File.length() > 128L) {
                        main.post(() -> {
                            if (token != speakToken) return;
                            if (!playMp3File(mp3File, token, id)) {
                                speakWithSystemTts(clean, rate, pitch, id);
                            }
                        });
                    } else {
                        main.post(() -> {
                            if (token != speakToken) return;
                            speakWithSystemTts(clean, rate, pitch, id);
                        });
                    }
                });
                return;
            }

            boolean ok = speakWithSystemTts(clean, rate, pitch, id);
            result.success(ok);
        });
    }

    private boolean playMp3File(File mp3File, final int token, final String utteranceId) {
        try {
            stopMediaPlayerOnly();
            MediaPlayer mp = new MediaPlayer();
            mp.setAudioAttributes(
                    new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build());
            mp.setDataSource(mp3File.getAbsolutePath());
            mp.setOnCompletionListener(player -> {
                try {
                    player.release();
                } catch (Exception ignored) {
                }
                if (ttsPlayer == player) {
                    ttsPlayer = null;
                }
                if (token == speakToken) {
                    sendEvent("ttsDone", utteranceId, 0f);
                }
            });
            mp.setOnErrorListener((player, what, extra) -> {
                try {
                    player.release();
                } catch (Exception ignored) {
                }
                if (ttsPlayer == player) {
                    ttsPlayer = null;
                }
                if (token == speakToken) {
                    sendEvent("ttsError", utteranceId, 0f);
                }
                return true;
            });
            mp.prepare();
            ttsPlayer = mp;
            mp.start();
            return true;
        } catch (Exception e) {
            stopMediaPlayerOnly();
            return false;
        }
    }

    private boolean speakWithSystemTts(String clean, double rate, double pitch, String id) {
        if (tts == null || !ttsReady) {
            initTts();
            sendEvent("ttsError", id, 0f);
            return false;
        }
        try {
            float safeRate = (float) Math.max(0.5, Math.min(2.0, rate <= 0 ? 1.0 : rate));
            float safePitch = (float) Math.max(0.6, Math.min(1.6, pitch <= 0 ? 1.0 : pitch));
            tts.setSpeechRate(safeRate);
            tts.setPitch(safePitch);
            tts.speak(clean, TextToSpeech.QUEUE_FLUSH, null, id);
            return true;
        } catch (Exception e) {
            sendEvent("ttsError", id, 0f);
            return false;
        }
    }

    void stopSpeaking(MethodChannel.Result result) {
        main.post(() -> {
            stopSpeakingInternal();
            result.success(true);
        });
    }

    private void stopMediaPlayerOnly() {
        try {
            if (ttsPlayer != null) {
                if (ttsPlayer.isPlaying()) {
                    ttsPlayer.stop();
                }
                ttsPlayer.release();
            }
        } catch (Exception ignored) {
        } finally {
            ttsPlayer = null;
        }
    }

    private void stopSpeakingInternal() {
        speakToken++;
        stopMediaPlayerOnly();
        try {
            if (tts != null) {
                tts.stop();
            }
        } catch (Exception ignored) {
        }
    }

    private void ensureRecognizer() {
        if (recognizer != null) {
            try {
                recognizer.cancel();
            } catch (Exception ignored) {
            }
            return;
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            return;
        }
        recognizer = SpeechRecognizer.createSpeechRecognizer(activity);
        recognizer.setRecognitionListener(new RecognitionListener() {
            @Override
            public void onReadyForSpeech(Bundle params) {
                sendEvent("ready", "", 0f);
            }

            @Override
            public void onBeginningOfSpeech() {
                sendEvent("speechStart", "", 0f);
            }

            @Override
            public void onRmsChanged(float rmsdB) {
                sendEvent("rms", "", rmsdB);
            }

            @Override
            public void onBufferReceived(byte[] buffer) {}

            @Override
            public void onEndOfSpeech() {
                listening = false;
                sendEvent("speechEnd", "", 0f);
            }

            @Override
            public void onError(int error) {
                listening = false;
                sendEvent("error", errorMessageTr(error), (float) error);
            }

            @Override
            public void onResults(Bundle results) {
                listening = false;
                String best = firstMatch(results);
                sendEvent("final", best, 1f);
            }

            @Override
            public void onPartialResults(Bundle partialResults) {
                String part = firstMatch(partialResults);
                if (!part.isEmpty()) {
                    sendEvent("partial", part, 0.5f);
                }
            }

            @Override
            public void onEvent(int eventType, Bundle params) {}
        });
    }

    private static String firstMatch(Bundle b) {
        if (b == null) return "";
        ArrayList<String> list = b.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION);
        if (list == null || list.isEmpty()) return "";
        String s = list.get(0);
        return s == null ? "" : s.trim();
    }

    private static String errorMessageTr(int code) {
        switch (code) {
            case SpeechRecognizer.ERROR_AUDIO:
                return "Ses kaydı hatası oluştu.";
            case SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS:
                return "Mikrofon izni verilmedi.";
            case SpeechRecognizer.ERROR_NETWORK:
            case SpeechRecognizer.ERROR_NETWORK_TIMEOUT:
                return "Ses tanıma ağ bağlantısı zaman aşımına uğradı.";
            case SpeechRecognizer.ERROR_NO_MATCH:
                return "Konuşma anlaşılamadı, tekrar söyleyin.";
            case SpeechRecognizer.ERROR_RECOGNIZER_BUSY:
                return "Ses tanıma meşgul, lütfen bekleyin.";
            case SpeechRecognizer.ERROR_SPEECH_TIMEOUT:
                return "Ses algılanmadı.";
            default:
                return "Ses tanıma tamamlanamadı (kod: " + code + ").";
        }
    }

    private void sendEvent(String type, String text, float value) {
        main.post(() -> {
            try {
                Map<String, Object> payload = new HashMap<>();
                payload.put("type", type);
                payload.put("text", text == null ? "" : text);
                payload.put("value", (double) value);
                channel.invokeMethod("onVoiceEvent", payload);
            } catch (Exception ignored) {
            }
        });
    }

    void destroy() {
        main.post(() -> {
            speakToken++;
            stopMediaPlayerOnly();
            try {
                ttsExecutor.shutdownNow();
            } catch (Exception ignored) {
            }
            try {
                if (recognizer != null) {
                    recognizer.destroy();
                    recognizer = null;
                }
            } catch (Exception ignored) {
            }
            try {
                if (tts != null) {
                    tts.stop();
                    tts.shutdown();
                    tts = null;
                }
            } catch (Exception ignored) {
            }
        });
    }
}

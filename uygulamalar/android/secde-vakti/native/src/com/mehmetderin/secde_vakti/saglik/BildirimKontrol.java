package com.mehmetderin.secde_vakti.saglik;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlarmManager;
import android.app.AlertDialog;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.SystemClock;
import android.provider.Settings;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Bildirimlerin telefona ulaşmasını engelleyen sistem ayarlarını denetler.
 *
 * Uygulamanın Dart tarafı vakit bildirimlerini doğru kuruyor; bildirimler çoğunlukla
 * kapalı izin, kapatılmış ezan kanalı, tam zamanlı alarm izni ya da pil kısıtlaması
 * yüzünden gelmiyor. Ana ekran her öne geldiğinde çağrılır, sorunu bulursa Türkçe bir
 * uyarıyla kullanıcıyı ilgili ayar sayfasına götürür.
 */
public final class BildirimKontrol {

    private static final String ANAHTAR_SON_UYARI = "son_uyari_ms";
    private static final String ANAHTAR_TANITILAN_SURUM = "tanitilan_surum";
    static final String ANAHTAR_PIL_SORMA = "pil_sorma";
    private static final int BU_SURUM = 5;
    /** Bildirimi tamamen engelleyen sorunlarda en fazla 12 saatte bir uyarı. */
    private static final long UYARI_ARALIGI_MS = 12L * 60 * 60 * 1000;
    /** Yalnızca pil optimizasyonu açıksa en fazla haftada bir uyarı. */
    private static final long PIL_UYARI_ARALIGI_MS = 7L * 24 * 60 * 60 * 1000;

    static final int SORUN_IZIN = 1;
    static final int SORUN_KANAL = 2;
    static final int SORUN_TAM_ALARM = 3;
    static final int SORUN_PIL = 4;
    static final int SORUN_ARKA_PLAN = 5;

    private static boolean diyalogAcik = false;

    private BildirimKontrol() {}

    static final class Sorun {
        final int tur;
        final String baslik;
        final String aciklama;
        final String kanalId;

        Sorun(int tur, String baslik, String aciklama, String kanalId) {
            this.tur = tur;
            this.baslik = baslik;
            this.aciklama = aciklama;
            this.kanalId = kanalId;
        }
    }

    /** Ana ekran öne gelince çağrılır. Hiçbir zaman istisna fırlatmaz. */
    public static void kontrolEt(final Activity aktivite) {
        try {
            // Flutter kendi izin isteğini gösterebilsin diye kısa bir gecikme.
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                try {
                    kontrolEtSimdi(aktivite);
                } catch (Throwable ignored) {
                }
            }, 1800);
        } catch (Throwable ignored) {
        }
    }

    private static void kontrolEtSimdi(final Activity aktivite) {
        if (diyalogAcik || aktivite.isFinishing() || aktivite.isDestroyed()) return;
        // Üstünde başka bir ekran (ör. ana menü) varsa uyarıyı o ekran gösterir
        if (!aktivite.hasWindowFocus()) return;
        // İlk kurulum ekranı bitmeden araya girme; izinleri orada Flutter istiyor.
        if (!kurulumTamam(aktivite)) return;

        final SharedPreferences tercih = Tercihler.sp(aktivite);
        final List<Sorun> sorunlar = sorunlariBul(aktivite, tercih.getBoolean(ANAHTAR_PIL_SORMA, false));
        final boolean tanitilmadi = tercih.getInt(ANAHTAR_TANITILAN_SURUM, 0) < BU_SURUM;

        if (sorunlar.isEmpty()) {
            if (tanitilmadi) {
                tercih.edit().putInt(ANAHTAR_TANITILAN_SURUM, BU_SURUM).apply();
                hazirDiyalogu(aktivite);
            }
            return;
        }

        long simdi = System.currentTimeMillis();
        long son = tercih.getLong(ANAHTAR_SON_UYARI, 0);
        long aralik = yalnizPil(sorunlar) ? PIL_UYARI_ARALIGI_MS : UYARI_ARALIGI_MS;
        if (!tanitilmadi && simdi - son < aralik && simdi >= son) return;
        tercih.edit()
                .putLong(ANAHTAR_SON_UYARI, simdi)
                .putInt(ANAHTAR_TANITILAN_SURUM, BU_SURUM)
                .apply();
        sorunDiyalogu(aktivite, sorunlar);
    }

    static boolean kurulumTamam(Context c) {
        try {
            // Flutter shared_preferences anahtarları "flutter." önekiyle saklar.
            Object v = c.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getAll().get("flutter.settings.onboarded");
            return v instanceof Boolean && (Boolean) v;
        } catch (Throwable t) {
            return false;
        }
    }

    static boolean yalnizPil(List<Sorun> sorunlar) {
        for (Sorun s : sorunlar) if (s.tur != SORUN_PIL) return false;
        return !sorunlar.isEmpty();
    }

    static List<Sorun> sorunlariBul(Context c, boolean pilSorma) {
        List<Sorun> liste = new ArrayList<>();
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);

        if (nm != null && !nm.areNotificationsEnabled()) {
            liste.add(new Sorun(SORUN_IZIN, "Bildirim izni kapalı",
                    "Secde Vakti'nin bildirim göstermesine izin verilmemiş. Ezan ve vakit uyarıları bu yüzden hiç gelmez.",
                    null));
        } else if (nm != null && Build.VERSION.SDK_INT >= 26) {
            try {
                for (NotificationChannel kanal : nm.getNotificationChannels()) {
                    String id = kanal.getId();
                    boolean onemli = id.startsWith("sekine_alarm_") || id.equals("sekine_channel_default");
                    if (onemli && kanal.getImportance() == NotificationManager.IMPORTANCE_NONE) {
                        liste.add(new Sorun(SORUN_KANAL, "\"" + kanal.getName() + "\" kanalı kapalı",
                                "Vakit bildirimleri bu kanaldan gönderiliyor ama kanal telefon ayarlarından kapatılmış.",
                                id));
                        break;
                    }
                }
            } catch (Throwable ignored) {
            }
        }

        if (Build.VERSION.SDK_INT >= 31) {
            AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
            if (am != null && !am.canScheduleExactAlarms()) {
                liste.add(new Sorun(SORUN_TAM_ALARM, "Alarmlar ve hatırlatıcılar izni kapalı",
                        "Bu izin olmadan Android ezan bildirimini dakikalarca geciktirebilir.",
                        null));
            }
        }

        if (Build.VERSION.SDK_INT >= 28) {
            ActivityManager acm = (ActivityManager) c.getSystemService(Context.ACTIVITY_SERVICE);
            if (acm != null && acm.isBackgroundRestricted()) {
                liste.add(new Sorun(SORUN_ARKA_PLAN, "Pil kullanımı \"Kısıtlanmış\"",
                        "Android uygulamayı arka planda tamamen durduruyor. Alarmlar ve günlük yenileme çalışmaz.",
                        null));
            }
        }

        if (!pilSorma && !pilMuaf(c)) {
            liste.add(new Sorun(SORUN_PIL, "Pil optimizasyonu açık",
                    "Telefon uzun süre kilitliyken bildirimler gecikebilir ya da hiç gelmeyebilir. Secde Vakti'yi pil optimizasyonundan çıkarın.",
                    null));
        }
        return liste;
    }

    static boolean pilMuaf(Context c) {
        PowerManager pm = (PowerManager) c.getSystemService(Context.POWER_SERVICE);
        return pm == null || pm.isIgnoringBatteryOptimizations(c.getPackageName());
    }

    private static AlertDialog.Builder diyalog(Activity a) {
        return new AlertDialog.Builder(a);
    }

    private static void goster(AlertDialog.Builder b) {
        AlertDialog d = b.create();
        d.setOnDismissListener(x -> diyalogAcik = false);
        diyalogAcik = true;
        d.show();
    }

    private static void hazirDiyalogu(final Activity a) {
        StringBuilder metin = new StringBuilder();
        metin.append("✓ Bildirim izni açık\n");
        metin.append("✓ Ezan kanalları açık\n");
        if (Build.VERSION.SDK_INT >= 31) metin.append("✓ Tam zamanlı alarm izni var\n");
        metin.append(pilMuaf(a) ? "✓ Pil optimizasyonu kapalı\n" : "– Pil optimizasyonu açık (sormamamı istediniz)\n");
        Vakit sonraki = VakitDeposu.sonrakiVakit(a);
        if (sonraki != null) {
            metin.append("\nSonraki vakit: ").append(sonraki.kisaAd()).append(" · ")
                    .append(Metinler.gunVeSaat(sonraki.zaman)).append('\n');
        }
        metin.append("\nYeni: Mihrap teması, sade ana ekran, \"Vakitler\" ekranı, vakit sayacı ve vakitte titreşim. ")
                .append("Uygulama simgesine uzun basarak da açabilirsiniz.");
        goster(diyalog(a)
                .setTitle("Bildirimler hazır")
                .setMessage(metin.toString())
                .setPositiveButton("Vakitler", (d, w) -> durumEkraniniAc(a))
                .setNeutralButton("Test bildirimi", (d, w) -> testPlanla(a))
                .setNegativeButton("Tamam", null));
    }

    private static void sorunDiyalogu(final Activity a, final List<Sorun> sorunlar) {
        StringBuilder metin = new StringBuilder();
        for (Sorun s : sorunlar) {
            metin.append("✗ ").append(s.baslik).append("\n").append(s.aciklama).append("\n\n");
        }
        String uretici = ureticiNotu();
        if (uretici != null) metin.append(uretici).append("\n\n");
        metin.append("\"Düzelt\" ilgili ayar sayfasını açar. Döndüğünüzde kalan sorunlar yeniden denetlenir.");

        String baslik = sorunlar.size() == 1 ? "Bildirimler gelmeyebilir"
                : "Bildirimler gelmeyebilir (" + sorunlar.size() + " sorun)";
        final Sorun ilk = sorunlar.get(0);
        AlertDialog.Builder b = diyalog(a)
                .setTitle(baslik)
                .setMessage(metin.toString().trim())
                .setPositiveButton("Düzelt", (d, w) -> {
                    // Ayardan dönünce hemen yeniden denetle.
                    Tercihler.sp(a).edit().putLong(ANAHTAR_SON_UYARI, 0).apply();
                    duzelt(a, ilk);
                })
                .setNegativeButton("Sonra", null);
        if (yalnizPil(sorunlar)) {
            b.setNeutralButton("Bir daha sorma", (d, w) ->
                    Tercihler.sp(a).edit().putBoolean(ANAHTAR_PIL_SORMA, true).apply());
        } else {
            b.setNeutralButton("Ayrıntı", (d, w) -> durumEkraniniAc(a));
        }
        goster(b);
    }

    static void durumEkraniniAc(Context c) {
        try {
            c.startActivity(new Intent(c, DurumAktivitesi.class).setAction(Intent.ACTION_VIEW)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Throwable ignored) {
        }
    }

    static String tamEkranNotu(Context c) {
        if (Build.VERSION.SDK_INT < 34) return null;
        try {
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null && !nm.canUseFullScreenIntent()) {
                return "Tam ekran ezan alarmı izni kapalı. Ezan yine bildirim olarak gelir; kilit ekranında tam ekran açılmaz.";
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    static boolean tamEkranAyariVar() {
        return Build.VERSION.SDK_INT >= 34;
    }

    static void tamEkranAyariniAc(Activity a) {
        List<Intent> adaylar = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 34) {
            adaylar.add(new Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:" + a.getPackageName())));
        }
        adaylar.add(uygulamaAyrintilari(a));
        ilkAcilaniBaslat(a, adaylar);
    }

    static String ureticiAdi() {
        String m = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        if (m.contains("xiaomi") || m.contains("redmi") || m.contains("poco")) return "xiaomi";
        if (m.contains("huawei") || m.contains("honor")) return "huawei";
        if (m.contains("oppo") || m.contains("realme") || m.contains("oneplus")) return "oppo";
        if (m.contains("vivo")) return "vivo";
        if (m.contains("samsung")) return "samsung";
        return null;
    }

    static String ureticiNotu() {
        String u = ureticiAdi();
        if (u == null) return null;
        switch (u) {
            case "xiaomi":
                return "Xiaomi/Redmi/POCO telefonlarda ayrıca \"Otomatik başlatma\" izni açılmalı ve Pil tasarrufu \"Kısıtlama yok\" seçilmeli.";
            case "huawei":
                return "Huawei/Honor telefonlarda Uygulama başlatma ayarında Secde Vakti için \"Manuel yönet\" seçip üç seçeneği de açın.";
            case "oppo":
                return "OPPO/realme/OnePlus telefonlarda \"Otomatik başlatma\" ve \"Arka planda çalışmaya izin ver\" açılmalı.";
            case "vivo":
                return "vivo telefonlarda \"Otomatik başlatma\" ve \"Arka planda yüksek güç tüketimi\" izni açılmalı.";
            case "samsung":
                return "Samsung telefonlarda Secde Vakti \"Uyuyan uygulamalar\" ya da \"Derin uyuyan uygulamalar\" listesinde olmamalı (Ayarlar › Pil › Arka plan kullanım sınırları).";
            default:
                return null;
        }
    }

    static void ureticiAyariniAc(Activity a) {
        String u = ureticiAdi();
        List<Intent> adaylar = new ArrayList<>();
        if ("xiaomi".equals(u)) {
            adaylar.add(new Intent().setComponent(new ComponentName("com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity")));
        } else if ("huawei".equals(u)) {
            adaylar.add(new Intent().setComponent(new ComponentName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")));
            adaylar.add(new Intent().setComponent(new ComponentName("com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity")));
        } else if ("oppo".equals(u)) {
            adaylar.add(new Intent().setComponent(new ComponentName("com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity")));
            adaylar.add(new Intent().setComponent(new ComponentName("com.oplus.safecenter",
                    "com.oplus.safecenter.permission.startup.StartupAppListActivity")));
        } else if ("vivo".equals(u)) {
            adaylar.add(new Intent().setComponent(new ComponentName("com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")));
        } else if ("samsung".equals(u)) {
            adaylar.add(new Intent().setComponent(new ComponentName("com.samsung.android.lool",
                    "com.samsung.android.sm.battery.ui.BatteryActivity")));
        }
        adaylar.add(uygulamaAyrintilari(a));
        ilkAcilaniBaslat(a, adaylar);
    }

    static Intent uygulamaAyrintilari(Context c) {
        return new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + c.getPackageName()));
    }

    static Intent bildirimAyarlari(Context c) {
        if (Build.VERSION.SDK_INT >= 26) {
            return new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, c.getPackageName());
        }
        return uygulamaAyrintilari(c);
    }

    static void ilkAcilaniBaslat(Activity a, List<Intent> adaylar) {
        for (Intent i : adaylar) {
            try {
                a.startActivity(i);
                return;
            } catch (Throwable ignored) {
            }
        }
        Toast.makeText(a, "Ayar sayfası açılamadı. Ayarlar › Uygulamalar › Secde Vakti bölümüne gidin.",
                Toast.LENGTH_LONG).show();
    }

    static void duzelt(Activity a, Sorun s) {
        String paket = a.getPackageName();
        List<Intent> adaylar = new ArrayList<>();
        switch (s.tur) {
            case SORUN_IZIN:
                adaylar.add(bildirimAyarlari(a));
                break;
            case SORUN_KANAL:
                if (Build.VERSION.SDK_INT >= 26) {
                    adaylar.add(new Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, paket)
                            .putExtra(Settings.EXTRA_CHANNEL_ID, s.kanalId));
                }
                adaylar.add(bildirimAyarlari(a));
                break;
            case SORUN_TAM_ALARM:
                if (Build.VERSION.SDK_INT >= 31) {
                    adaylar.add(new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:" + paket)));
                }
                break;
            case SORUN_PIL:
                adaylar.add(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:" + paket)));
                adaylar.add(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
                break;
            case SORUN_ARKA_PLAN:
            default:
                break;
        }
        adaylar.add(uygulamaAyrintilari(a));
        ilkAcilaniBaslat(a, adaylar);
    }

    /** 60 saniye sonrasına, vakit bildirimleriyle aynı yoldan (AlarmManager) bir test bildirimi kurar. */
    static void testPlanla(Context a) {
        try {
            AlarmManager am = (AlarmManager) a.getSystemService(Context.ALARM_SERVICE);
            Intent i = new Intent(a, TestAlarmAlici.class).setAction(TestAlarmAlici.EYLEM);
            PendingIntent pi = PendingIntent.getBroadcast(a, 0x5ecde, i, Kanallar.bayrak());
            long zaman = SystemClock.elapsedRealtime() + 60_000L;
            boolean tam = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms();
            if (tam) {
                am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, zaman, pi);
            } else {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, zaman, pi);
            }
            Tercihler.sp(a).edit().putLong("son_test_kurulan_ms", System.currentTimeMillis()).apply();
            Toast.makeText(a, "Test bildirimi 1 dakika sonra gelecek. Telefonu kilitleyebilirsiniz.",
                    Toast.LENGTH_LONG).show();
        } catch (Throwable t) {
            Toast.makeText(a, "Test kurulamadı: " + t.getMessage(), Toast.LENGTH_LONG).show();
        }
    }
}
